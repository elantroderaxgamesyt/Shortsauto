"""API del revisor de nóminas. La usan la app de Android y la de Windows."""
from __future__ import annotations

import json
import logging
import re

import anthropic
from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from . import cuentas, google_play, ia
from .comprobaciones import para_plan
from .planes import PLANES

log = logging.getLogger("nominas")
MAX_BYTES = 10 * 1024 * 1024
VERSION_API = 2

app = FastAPI(title="Revisor de nóminas")


def usuario_id(x_usuario: str = Header(...)) -> str:
    if not re.fullmatch(r"[A-Za-z0-9-]{16,64}", x_usuario):
        raise HTTPException(400, "Identificador de usuario no válido.")
    return x_usuario


@app.get("/")
def raiz():
    return {"servicio": "revisor-nominas", "version_api": VERSION_API}


@app.get("/api/estado")
def estado():
    return {"demo": not ia.hay_credenciales(), "version_api": VERSION_API}


@app.get("/api/cuenta")
def cuenta(uid: str = Depends(usuario_id)):
    return cuentas.resumen(uid)


@app.post("/api/analizar")
async def analizar(archivo: UploadFile = File(...), plan: str = Form("free"), uid: str = Depends(usuario_id)):
    if plan not in PLANES:
        raise HTTPException(400, "Plan no válido.")
    p = PLANES[plan]
    try:
        pago = cuentas.reservar(uid, plan)
    except cuentas.SinSaldo as e:
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
    contenido = {"informe": informe.model_dump(), "calculos": calculos}
    try:
        # El crédito sólo se descuenta si el análisis ha salido bien.
        rid = cuentas.guardar_revision(uid, plan, pago, contenido)
    except cuentas.SinSaldo as e:
        raise HTTPException(402, str(e))

    return {
        "id": rid,
        "plan": p.nombre,
        "demo": not ia.hay_credenciales(),
        **contenido,
        "preguntas_chat": p.preguntas_chat,
        "cuenta": cuentas.resumen(uid),
    }


class Mensaje(BaseModel):
    role: str
    content: str


class PeticionChat(BaseModel):
    revision: str
    historial: list[Mensaje]


@app.post("/api/chat")
def chat(req: PeticionChat, uid: str = Depends(usuario_id)):
    rev = cuentas.revision(uid, req.revision)
    if not rev:
        raise HTTPException(404, "Revisión no encontrada.")
    p = PLANES[rev["plan"]]
    if p.preguntas_chat and rev["preguntas"] >= p.preguntas_chat:
        raise HTTPException(402, f"La versión gratuita incluye {p.preguntas_chat} preguntas por nómina. "
                                 "Pásate a Pro para preguntas ilimitadas.")
    if not req.historial or req.historial[-1].role != "user":
        raise HTTPException(400, "Falta la pregunta.")
    cuentas.sumar_pregunta(rev["id"])

    contexto = json.loads(rev["informe"])
    historial = [m.model_dump() for m in req.historial][-40:]

    def gen():
        try:
            yield from ia.chat(contexto, historial, p)
        except anthropic.APIError as e:
            log.error("Error en el chat: %s", e)
            yield "\n\n(Se ha producido un error con la IA. Inténtalo de nuevo.)"

    return StreamingResponse(gen(), media_type="text/plain; charset=utf-8")


class PeticionCompra(BaseModel):
    producto: str
    token: str


@app.post("/api/compras/google")
def compra_google(req: PeticionCompra, uid: str = Depends(usuario_id)):
    try:
        v = google_play.verificar(req.producto, req.token)
    except google_play.CompraNoValida as e:
        raise HTTPException(400, str(e))
    cuentas.registrar_compra(uid, req.token, v.producto, "google_play", creditos=v.creditos, hasta=v.hasta)
    return cuentas.resumen(uid)


class PeticionCanje(BaseModel):
    codigo: str


@app.post("/api/canjear")
def canjear(req: PeticionCanje, uid: str = Depends(usuario_id)):
    try:
        cuentas.canjear(uid, req.codigo)
    except ValueError as e:
        raise HTTPException(400, str(e))
    return cuentas.resumen(uid)
