import os

for v in ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_PROFILE", "GOOGLE_PLAY_CREDENCIALES"):
    os.environ.pop(v, None)
os.environ["NOMINAS_PAGOS_PRUEBA"] = "1"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app import almacen  # noqa: E402
from app.comprobaciones import basicas, completas  # noqa: E402
from app.main import app  # noqa: E402
from app.modelos import DatosNomina  # noqa: E402

c = TestClient(app)
PDF = ("nomina.pdf", b"%PDF-1.4 demo", "application/pdf")
U1 = {"X-Dispositivo": "dispositivo-prueba-0001"}
U2 = {"X-Dispositivo": "dispositivo-prueba-0002"}


@pytest.fixture(autouse=True)
def base_limpia(tmp_path):
    almacen.reiniciar(str(tmp_path / "t.db"))


def analizar(plan, h=U1, archivo=PDF, compra=""):
    return c.post("/api/analizar", files={"archivo": archivo}, data={"plan": plan, "compra": compra}, headers=h)


def datos(**cambios):
    base = dict(empresa=None, trabajador=None, categoria=None, convenio=None, periodo=None,
                tipo_contrato="temporal",
                devengos=[{"concepto": "Base", "importe": 2000}],
                deducciones=[{"concepto": "CC", "tipo": "contingencias_comunes", "porcentaje": 4.7, "base": 2000, "importe": 94},
                             {"concepto": "Desempleo", "tipo": "desempleo", "porcentaje": None, "base": None, "importe": 31}],
                total_devengado=2000, total_deducciones=125, liquido=1875,
                base_cc=2000, base_cp=2000, base_irpf=None, pct_irpf=None)
    base.update(cambios)
    return DatosNomina.model_validate(base)


# ---- Cálculos ----

def test_sumas_correctas():
    assert all(x.estado == "ok" for x in basicas(datos()))


def test_liquido_mal():
    r = {x.concepto: x for x in basicas(datos(liquido=1900))}
    assert r["Líquido a percibir"].estado == "error"


def test_desempleo_temporal_usa_1_60():
    r = [x for x in completas(datos()) if x.concepto.startswith("Desempleo")]
    assert r[0].importe_esperado == 32.0 and r[0].estado == "error"


# ---- Revisiones gratis ----

def test_free_demo():
    j = analizar("free").json()
    assert j["demo"] and j["plan"] == "free" and len(j["informe"]["puntos"]) <= 5
    assert len(j["calculos"]) == 3 and j["id"]


def test_free_limite_diario():
    for _ in range(3):
        assert analizar("free").status_code == 200
    assert analizar("free").status_code == 402
    assert c.get("/api/limites", headers=U1).json()["free_restantes_hoy"] == 0
    assert analizar("free", U2).status_code == 200


def test_formato_no_soportado():
    assert analizar("free", archivo=("a.txt", b"hola", "text/plain")).status_code == 415


def test_formato_por_extension():
    assert analizar("free", archivo=("n.pdf", b"%PDF", "application/octet-stream")).status_code == 200


def test_sin_cabecera_dispositivo():
    assert c.post("/api/analizar", files={"archivo": PDF}).status_code == 422
    assert c.get("/api/limites", headers={"X-Dispositivo": "corto"}).status_code == 400


def test_ya_no_hay_cuentas_ni_suscripcion():
    assert c.get("/api/cuenta", headers=U1).status_code == 404
    assert c.post("/api/compras/google", json={}, headers=U1).status_code == 404
    assert c.post("/api/canjear", json={}, headers=U1).status_code == 404


# ---- Revisión completa: pago por revisión ----

def test_pro_sin_pago():
    assert analizar("pro").status_code == 402


def test_pro_con_compra():
    r = analizar("pro", compra="prueba-1")
    assert r.status_code == 200
    j = r.json()
    assert j["plan"] == "pro"
    assert any(x["estado"] == "error" and "MEI" in x["concepto"] for x in j["calculos"])
    assert j["informe"]["reclamacion"]["procede"]


def test_compra_no_se_reutiliza():
    assert analizar("pro", compra="prueba-2").status_code == 200
    assert analizar("pro", compra="prueba-2").status_code == 409
    assert analizar("pro", U2, compra="prueba-2").status_code == 409


def test_compra_falsa():
    assert analizar("pro", compra="token-inventado").status_code == 402


def test_error_de_analisis_no_gasta_la_compra(monkeypatch):
    from app import ia

    def falla(*a):
        raise ia.RechazoIA("x")
    monkeypatch.setattr(ia, "analizar", falla)
    assert analizar("pro", compra="prueba-3").status_code == 422
    monkeypatch.undo()
    assert analizar("pro", compra="prueba-3").status_code == 200  # se puede reintentar


def test_pro_no_gasta_revisiones_gratis():
    analizar("pro", compra="prueba-4")
    assert c.get("/api/limites", headers=U1).json()["free_restantes_hoy"] == 3


# ---- Historial ----

def test_historial():
    a = analizar("free").json()
    b = analizar("pro", compra="prueba-h").json()
    lista = c.get("/api/revisiones", headers=U1).json()
    assert [x["id"] for x in lista] == [b["id"], a["id"]]
    assert lista[0]["plan"] == "pro" and lista[0]["veredicto"] == "revisar" and lista[0]["liquido"] == 1997.23
    r = c.get(f"/api/revisiones/{a['id']}", headers=U1).json()
    assert r["informe"] == a["informe"] and r["preguntas_chat"] == 1
    assert c.get(f"/api/revisiones/{a['id']}", headers=U2).status_code == 404
    assert c.get("/api/revisiones", headers=U2).json() == []


# ---- Chat ----

def test_limite_chat_free():
    rid = analizar("free").json()["id"]
    h = [{"role": "user", "content": "q"}]
    assert c.post("/api/chat", json={"revision": rid, "historial": h}, headers=U1).status_code == 200
    assert c.post("/api/chat", json={"revision": rid, "historial": h}, headers=U1).status_code == 402


def test_pro_chat_ilimitado():
    rid = analizar("pro", compra="prueba-chat").json()["id"]
    h = [{"role": "user", "content": "q"}]
    for _ in range(5):
        assert c.post("/api/chat", json={"revision": rid, "historial": h}, headers=U1).status_code == 200


def test_chat_revision_ajena():
    rid = analizar("free").json()["id"]
    r = c.post("/api/chat", json={"revision": rid, "historial": [{"role": "user", "content": "q"}]}, headers=U2)
    assert r.status_code == 404


# ---- Modelos ----

def test_modelos_por_plan():
    from app.ia import _respaldo
    from app.planes import PLANES
    assert PLANES["free"].modelo == "claude-haiku-5-5"
    assert PLANES["pro"].modelo == "claude-opus-5-5"
    assert _respaldo("claude-haiku-5-5") == {}  # Haiku no admite modelo de respaldo
    assert _respaldo("claude-opus-5-5")["fallbacks"] == "default"
