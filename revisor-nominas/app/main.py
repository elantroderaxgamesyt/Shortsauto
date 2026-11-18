"""API del revisor de nóminas. La usan la app de Android y la de Windows."""
from __future__ import annotations

import json
import logging
import re

import anthropic
from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from . import almacen, google_play, ia
from .comprobaciones import para_plan
from .planes import PLANES

log = logging.getLogger("nominas")
MAX_BYTES = 10 * 1024 * 1024
VERSION_API = 3

app = FastAPI(title="Revisor de nóminas")


def dispositivo(x_dispositivo: str = Header(...)) -> str:
    """Identificador anónimo de la instalación (no es una cuenta)."""
    if not re.fullmatch(r"[A-Za-z0-9-]{16,64}", x_dispositivo):
        raise HTTPException(400, "Identificador de dispositivo no válido.")
    return x_dispositivo


@app.get("/")
def raiz():
    return {"servicio": "revisor-nominas", "version_api": VERSION_API}


@app.get("/api/estado")
def estado():
    return {"demo": not ia.hay_credenciales(), "version_api": VERSION_API}


@app.get("/api/limites")
def limites(disp: str = Depends(dispositivo)):
    return {"free_restantes_hoy": almacen.free_restantes_hoy(disp)}


@app.post("/api/analizar")
async def analizar(archivo: UploadFile = File(...), plan: str = Form("free"), compra: str = Form(""),
                   disp: str = Depends(dispositivo)):
    """Revisión gratis, o completa pagada con una compra de Google Play (token en `compra`)."""
    if plan not in PLANES:
        raise HTTPException(400, "Plan no válido.")
    p = PLANES[plan]
    if plan == "free":
        try:
            almacen.comprobar_free(disp)
        except almacen.SinSaldo as e:
            raise HTTPException(402, str(e))
        compra = ""
    else:
        if not compra:
            raise HTTPException(402, "La revisión completa cuesta 2,99 €. Falta el pago.")
        if almacen.compra_usada(compra):
            raise HTTPException(409, "Esta compra ya se ha usado para otra revisión.")
        try:
            google_play.verificar_revision(compra)
        except google_play.CompraNoValida as e:
            raise HTTPException(402, str(e))

    datos = await archivo.read(MAX_BYTES + 1)
    if len(datos) > MAX_BYTES:
        raise HTTPException(413, "El archivo supera 10 MB.")
    if not datos:
        raise HTTPException(400, "El archivo está vacío.")
    tipo = (archivo.content_type or "").lower()
    tipo = {"image/jpg": "image/jpeg"}.get(tipo, tipo)
    if tipo in ("", "application/octet-stream"):
        nombre = (archivo.filename or "").lower()
        tipo = next((t for ext, t in ((".pdf", "application/pdf"), (".png", "image/png"), (".jpg", "image/jpeg"),
                                      (".jpeg", "image/jpeg"), (".webp", "image/webp")) if nombre.endswith(ext)), tipo)
    try:
        ia.bloque_documento(b"", tipo)  # valida el formato antes de llamar a la IA
        informe = ia.analizar(datos, tipo, p)
    except ValueError as e:
        raise HTTPException(415, str(e))
    except ia.RechazoIA as e:
        raise HTTPException(422, str(e))
    except anthropic.RateLimitError:
        raise HTTPException(429, "Hay mucha demanda ahora mismo. Inténtalo en un minuto.")
    except anthropic.APIConnectionError:
        raise HTTPException(503, "No se ha podido conectar con la IA.")
    except anthropic.APIStatusError as e:
        log.error("Error de la API (%s): %s", e.status_code, e.message)
        raise HTTPException(502, "La IA ha devuelto un error. Inténtalo de nuevo.")

    calculos = [c.model_dump() for c in para_plan(p.comprobaciones, informe.datos)]
    contenido = {"informe": informe.model_dump(), "calculos": calculos, "demo": not ia.hay_credenciales()}
    try:
        # La compra sólo queda "gastada" si el análisis ha salido bien.
        rid = almacen.guardar_revision(disp, plan, compra or None, contenido)
    except almacen.CompraUsada as e:
        raise HTTPException(409, str(e))

    return _revision_json(almacen.revision(disp, rid))


def _revision_json(rev) -> dict:
    contenido = json.loads(rev["informe"])
    return {
        "id": rev["id"],
        "plan": rev["plan"],
        "fecha": rev["fecha"],
        "demo": contenido.get("demo", False),
        "informe": contenido["informe"],
        "calculos": contenido["calculos"],
        "preguntas_chat": PLANES[rev["plan"]].preguntas_chat,
        "preguntas_usadas": rev["preguntas"],
    }


@app.get("/api/revisiones")
def revisiones(disp: str = Depends(dispositivo)):
    """Historial: lo justo para pintar la lista."""
    out = []
    for r in almacen.listar_revisiones(disp):
        inf = json.loads(r["informe"])["informe"]
        d = inf["datos"]
        out.append({"id": r["id"], "plan": r["plan"], "fecha": r["fecha"], "veredicto": inf["veredicto"],
                    "periodo": d.get("periodo"), "empresa": d.get("empresa"), "liquido": d.get("liquido")})
    return out


@app.get("/api/revisiones/{rid}")
def revision(rid: str, disp: str = Depends(dispositivo)):
    rev = almacen.revision(disp, rid)
    if not rev:
        raise HTTPException(404, "Revisión no encontrada.")
    return _revision_json(rev)


class Mensaje(BaseModel):
    role: str
    content: str


class PeticionChat(BaseModel):
    revision: str
    historial: list[Mensaje]


@app.post("/api/chat")
def chat(req: PeticionChat, disp: str = Depends(dispositivo)):
    rev = almacen.revision(disp, req.revision)
    if not rev:
        raise HTTPException(404, "Revisión no encontrada.")
    p = PLANES[rev["plan"]]
    if p.preguntas_chat and rev["preguntas"] >= p.preguntas_chat:
        raise HTTPException(402, f"La versión gratuita incluye {p.preguntas_chat} preguntas por nómina. "
                                 "Con la revisión completa las preguntas son ilimitadas.")
    if not req.historial or req.historial[-1].role != "user":
        raise HTTPException(400, "Falta la pregunta.")
    almacen.sumar_pregunta(rev["id"])

    contexto = json.loads(rev["informe"])
    historial = [m.model_dump() for m in req.historial][-40:]

    def gen():
        try:
            yield from ia.chat(contexto, historial, p)
        except anthropic.APIError as e:
            log.error("Error en el chat: %s", e)
            yield "\n\n(Se ha producido un error con la IA. Inténtalo de nuevo.)"

    return StreamingResponse(gen(), media_type="text/plain; charset=utf-8")
