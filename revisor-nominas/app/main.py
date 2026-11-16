"""Servidor web del revisor de nóminas."""
from __future__ import annotations

import logging
from pathlib import Path

import anthropic
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from . import ia
from .comprobaciones import para_plan
from .planes import resolver_plan

log = logging.getLogger("nominas")
MAX_BYTES = 10 * 1024 * 1024
STATIC = Path(__file__).parent.parent / "static"

app = FastAPI(title="Revisor de nóminas")
app.mount("/static", StaticFiles(directory=STATIC), name="static")


def _plan(plan: str, codigo: str | None):
    try:
        return resolver_plan(plan, codigo)
    except PermissionError as e:
        raise HTTPException(403, str(e))


@app.get("/")
def inicio():
    return FileResponse(STATIC / "index.html")


@app.get("/api/estado")
def estado():
    return {"demo": not ia.hay_credenciales()}


@app.post("/api/analizar")
async def analizar(archivo: UploadFile = File(...), plan: str = Form("free"), codigo: str = Form("")):
    p = _plan(plan, codigo)
    datos = await archivo.read(MAX_BYTES + 1)
    if len(datos) > MAX_BYTES:
        raise HTTPException(413, "El archivo supera 10 MB.")
    if not datos:
        raise HTTPException(400, "El archivo está vacío.")
    tipo = (archivo.content_type or "").lower()
    if tipo == "image/jpg":
        tipo = "image/jpeg"
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

    return {
        "plan": p.nombre,
        "demo": not ia.hay_credenciales(),
        "informe": informe.model_dump(),
        "calculos": [c.model_dump() for c in para_plan(p.comprobaciones, informe.datos)],
        "preguntas_chat": p.preguntas_chat,
    }


class PeticionChat(BaseModel):
    plan: str = "free"
    codigo: str = ""
    informe: dict
    historial: list[dict]


@app.post("/api/chat")
def chat(req: PeticionChat):
    p = _plan(req.plan, req.codigo)
    preguntas = sum(1 for m in req.historial if m.get("role") == "user")
    if p.preguntas_chat and preguntas > p.preguntas_chat:
        raise HTTPException(402, f"La versión gratuita incluye {p.preguntas_chat} preguntas por nómina. "
                                 "Pásate a Pro para preguntas ilimitadas.")
    if not req.historial or req.historial[-1].get("role") != "user":
        raise HTTPException(400, "Falta la pregunta.")

    def gen():
        try:
            yield from ia.chat(req.informe, req.historial, p)
        except anthropic.APIError as e:
            log.error("Error en el chat: %s", e)
            yield "\n\n(Se ha producido un error con la IA. Inténtalo de nuevo.)"

    return StreamingResponse(gen(), media_type="text/plain; charset=utf-8")
