import os

for v in ("ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_PROFILE", "GOOGLE_PLAY_CREDENCIALES"):
    os.environ.pop(v, None)
os.environ["NOMINAS_PAGOS_PRUEBA"] = "1"

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402

from app import cuentas  # noqa: E402
from app.comprobaciones import basicas, completas  # noqa: E402
from app.main import app  # noqa: E402
from app.modelos import DatosNomina  # noqa: E402

c = TestClient(app)
PDF = ("nomina.pdf", b"%PDF-1.4 demo", "application/pdf")
U1 = {"X-Usuario": "usuario-de-prueba-0001"}
U2 = {"X-Usuario": "usuario-de-prueba-0002"}


@pytest.fixture(autouse=True)
def base_limpia(tmp_path):
    cuentas.reiniciar(str(tmp_path / "t.db"))


def analizar(plan, h=U1, archivo=PDF):
    return c.post("/api/analizar", files={"archivo": archivo}, data={"plan": plan}, headers=h)


def comprar(producto, token, h=U1):
    return c.post("/api/compras/google", json={"producto": producto, "token": token}, headers=h)


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


# ---- Revisiones ----

def test_free_demo():
    j = analizar("free").json()
    assert j["demo"] and j["plan"] == "free" and len(j["informe"]["puntos"]) <= 5
    assert len(j["calculos"]) == 3 and j["id"]


def test_free_limite_diario():
    for _ in range(3):
        assert analizar("free").status_code == 200
    assert analizar("free").status_code == 402
    assert analizar("free", U2).status_code == 200


def test_formato_no_soportado():
    assert analizar("free", archivo=("a.txt", b"hola", "text/plain")).status_code == 415


def test_formato_por_extension():
    assert analizar("free", archivo=("n.pdf", b"%PDF", "application/octet-stream")).status_code == 200


def test_sin_cabecera_usuario():
    assert c.post("/api/analizar", files={"archivo": PDF}).status_code == 422
    assert c.get("/api/cuenta", headers={"X-Usuario": "corto"}).status_code == 400


# ---- Pro y pagos ----

def test_pro_sin_saldo():
    assert analizar("pro").status_code == 402


def test_revision_pro_consume_credito():
    assert comprar("revision_pro", "prueba-1").json()["creditos"] == 1
    j = analizar("pro").json()
    assert any(x["estado"] == "error" and "MEI" in x["concepto"] for x in j["calculos"])
    assert j["cuenta"]["creditos"] == 0
    assert analizar("pro").status_code == 402


def test_token_no_se_aplica_dos_veces():
    comprar("revision_pro", "prueba-x")
    assert comprar("revision_pro", "prueba-x").json()["creditos"] == 1
    assert comprar("revision_pro", "prueba-x", U2).json()["creditos"] == 0


def test_error_de_analisis_no_cobra(monkeypatch):
    from app import ia
    comprar("revision_pro", "prueba-2")

    def falla(*a):
        raise ia.RechazoIA("x")
    monkeypatch.setattr(ia, "analizar", falla)
    assert analizar("pro").status_code == 422
    assert c.get("/api/cuenta", headers=U1).json()["creditos"] == 1


def test_suscripcion_mensual():
    r = comprar("pro_mensual", "prueba-sub").json()
    assert r["suscripcion_activa"] and r["mensual_restantes"] == 30
    assert analizar("pro").status_code == 200
    assert c.get("/api/cuenta", headers=U1).json()["mensual_restantes"] == 29


def test_suscripcion_se_restaura_en_otro_dispositivo():
    comprar("pro_mensual", "prueba-sub")
    assert comprar("pro_mensual", "prueba-sub", U2).json()["suscripcion_activa"]
    assert not c.get("/api/cuenta", headers=U1).json()["suscripcion_activa"]


def test_token_falso_sin_google():
    assert comprar("revision_pro", "token-inventado").status_code == 400


def test_codigo_canje():
    cod = cuentas.crear_codigo(creditos=2)
    assert c.post("/api/canjear", json={"codigo": cod.lower()}, headers=U1).json()["creditos"] == 2
    assert c.post("/api/canjear", json={"codigo": cod}, headers=U2).status_code == 400


# ---- Chat ----

def test_limite_chat_free():
    rid = analizar("free").json()["id"]
    h = [{"role": "user", "content": "q"}]
    for _ in range(3):
        assert c.post("/api/chat", json={"revision": rid, "historial": h}, headers=U1).status_code == 200
    assert c.post("/api/chat", json={"revision": rid, "historial": h}, headers=U1).status_code == 402


def test_chat_revision_ajena():
    rid = analizar("free").json()["id"]
    r = c.post("/api/chat", json={"revision": rid, "historial": [{"role": "user", "content": "q"}]}, headers=U2)
    assert r.status_code == 404
