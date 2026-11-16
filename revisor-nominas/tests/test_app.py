import os

os.environ.pop("ANTHROPIC_API_KEY", None)
os.environ.pop("ANTHROPIC_AUTH_TOKEN", None)
os.environ.pop("ANTHROPIC_PROFILE", None)

from fastapi.testclient import TestClient  # noqa: E402

from app.comprobaciones import basicas, completas  # noqa: E402
from app.main import app  # noqa: E402
from app.modelos import DatosNomina  # noqa: E402

c = TestClient(app)
PDF = ("nomina.pdf", b"%PDF-1.4 demo", "application/pdf")


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


def test_sumas_correctas():
    assert all(x.estado == "ok" for x in basicas(datos()))


def test_liquido_mal():
    r = {x.concepto: x for x in basicas(datos(liquido=1900))}
    assert r["Líquido a percibir"].estado == "error"


def test_desempleo_temporal_usa_1_60():
    r = [x for x in completas(datos()) if x.concepto.startswith("Desempleo")]
    assert r[0].importe_esperado == 32.0 and r[0].estado == "error"


def test_free_demo():
    j = c.post("/api/analizar", files={"archivo": PDF}, data={"plan": "free"}).json()
    assert j["demo"] and j["plan"] == "free" and len(j["informe"]["puntos"]) <= 5
    assert len(j["calculos"]) == 3


def test_pro_demo_detecta_mei():
    j = c.post("/api/analizar", files={"archivo": PDF}, data={"plan": "pro"}).json()
    assert any(x["estado"] == "error" and "MEI" in x["concepto"] for x in j["calculos"])


def test_formato_no_soportado():
    r = c.post("/api/analizar", files={"archivo": ("a.txt", b"hola", "text/plain")})
    assert r.status_code == 415


def test_codigo_pro(monkeypatch):
    monkeypatch.setenv("NOMINAS_CODIGOS_PRO", "secreto")
    assert c.post("/api/analizar", files={"archivo": PDF}, data={"plan": "pro"}).status_code == 403
    assert c.post("/api/analizar", files={"archivo": PDF}, data={"plan": "pro", "codigo": "secreto"}).status_code == 200


def test_limite_chat_free():
    h = [{"role": "user", "content": "q"}, {"role": "assistant", "content": "a"}] * 3 + [{"role": "user", "content": "q4"}]
    r = c.post("/api/chat", json={"plan": "free", "informe": {}, "historial": h})
    assert r.status_code == 402
    r = c.post("/api/chat", json={"plan": "pro", "informe": {}, "historial": h})
    assert r.status_code == 200
