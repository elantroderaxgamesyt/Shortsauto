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
    assert r["informe"] == a["informe"] and r["preguntas_disponibles"] == 0 and r["preguntas_por_anuncio"]
    assert c.get(f"/api/revisiones/{a['id']}", headers=U2).status_code == 404
    assert c.get("/api/revisiones", headers=U2).json() == []


# ---- Chat ----

def chat(rid, h=U1):
    return c.post("/api/chat", json={"revision": rid, "historial": [{"role": "user", "content": "q"}]}, headers=h)


def anuncio(rid, h=U1):
    return c.post(f"/api/revisiones/{rid}/recompensa", headers=h)


def test_free_una_pregunta_por_anuncio():
    rid = analizar("free").json()["id"]
    assert chat(rid).status_code == 402               # sin anuncio, no hay pregunta
    assert anuncio(rid).json()["preguntas_disponibles"] == 1
    assert chat(rid).status_code == 200
    assert chat(rid).status_code == 402               # gastada
    anuncio(rid)
    anuncio(rid)
    assert chat(rid).status_code == 200 and chat(rid).status_code == 200


def test_maximo_preguntas_por_anuncio():
    rid = analizar("free").json()["id"]
    for _ in range(5):
        assert anuncio(rid).status_code == 200
    assert anuncio(rid).status_code == 429
    for _ in range(5):
        assert chat(rid).status_code == 200
    assert chat(rid).status_code == 429              # tope: ni con anuncios


def test_anuncio_en_revision_ajena():
    rid = analizar("free").json()["id"]
    assert anuncio(rid, U2).status_code == 404


def test_completa_3_preguntas_y_luego_anuncios():
    pro = analizar("pro", compra="prueba-anuncio").json()
    rid = pro["id"]
    assert not pro["preguntas_ilimitadas"] and pro["preguntas_disponibles"] == 3
    for _ in range(3):
        assert chat(rid).status_code == 200      # 3 sin anuncios
    assert chat(rid).status_code == 402
    assert anuncio(rid).json()["preguntas_disponibles"] == 1
    assert chat(rid).status_code == 200


def test_modo_ssv_no_se_fia_de_la_app(monkeypatch):
    from app import main
    monkeypatch.setattr(main, "VERIFICACION_ANUNCIOS", "ssv")
    rid = analizar("free").json()["id"]
    assert anuncio(rid).json()["preguntas_disponibles"] == 0


def test_ssv_de_admob(monkeypatch):
    """Simula la llamada firmada de Google con una clave de prueba."""
    import base64
    from urllib.parse import quote

    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec

    from app import admob_ssv
    clave = ec.generate_private_key(ec.SECP256R1())
    pem = clave.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
    monkeypatch.setattr(admob_ssv, "_cargar_claves", lambda: {"123": pem})

    rid = analizar("free").json()["id"]

    def llamada(transaccion, firmar=True):
        q = (f"ad_network=5450213213286189855&ad_unit=1234&custom_data={quote(rid)}&reward_amount=1"
             f"&reward_item=pregunta&timestamp=1700000000000&transaction_id={transaccion}"
             f"&user_id={U1['X-Dispositivo']}")
        firma = clave.sign(q.encode(), ec.ECDSA(hashes.SHA256())) if firmar else b"falsa"
        f = base64.urlsafe_b64encode(firma).decode().rstrip("=")
        return c.get(f"/api/admob/recompensa?{q}&signature={f}&key_id=123")

    assert llamada("t1").status_code == 200
    assert llamada("t1").status_code == 200           # repetida: no suma otra vez
    assert llamada("t2", firmar=False).status_code == 400
    r = c.get(f"/api/revisiones/{rid}", headers=U1).json()
    assert r["preguntas_disponibles"] == 1




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


# ---- Informe en PDF (0,50 €) ----

def pdf(rid, compra, h=U1):
    return c.post(f"/api/revisiones/{rid}/pdf", json={"compra": compra}, headers=h)


def test_pdf_se_paga_una_vez_por_informe():
    j = analizar("pro", compra="prueba-rev").json()
    assert j["pdf_pagado"] is False
    assert pdf(j["id"], "token-falso").status_code == 402
    assert pdf(j["id"], "prueba-pdf").json()["pdf_pagado"]
    assert c.get(f"/api/revisiones/{j['id']}", headers=U1).json()["pdf_pagado"]
    assert pdf(j["id"], "prueba-otro").json()["pdf_pagado"]  # ya pagado: no cobra otra vez


def test_pdf_compra_no_se_reutiliza():
    a = analizar("pro", compra="prueba-a").json()["id"]
    b = analizar("pro", compra="prueba-b").json()["id"]
    assert pdf(a, "prueba-pdf1").status_code == 200
    assert pdf(b, "prueba-pdf1").status_code == 409
    assert pdf(b, "prueba-a").status_code == 409             # el token de la revisión tampoco vale


def test_pdf_solo_en_completa_y_propia():
    f = analizar("free").json()["id"]
    assert pdf(f, "prueba-x").status_code == 400
    p = analizar("pro", compra="prueba-c").json()["id"]
    assert pdf(p, "prueba-y", U2).status_code == 404

