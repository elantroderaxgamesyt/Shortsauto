"""API del revisor de nóminas. La usan la app de Android y la de Windows."""
from __future__ import annotations

import json
import logging
import re

import anthropic
from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, Request, UploadFile
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from . import admob_ssv, almacen, google_play, ia
from .comprobaciones import para_plan
from .planes import MAX_PREGUNTAS_ANUNCIO, PLANES, VERIFICACION_ANUNCIOS

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


def _preguntas_disponibles(rev) -> int | None:
    """Preguntas que le quedan: las incluidas en el plan + 1 por cada anuncio visto - las hechas."""
    incluidas = PLANES[rev["plan"]].preguntas_chat
    if incluidas is None:
        return None
    return max(0, incluidas + rev["preguntas_extra"] - rev["preguntas"])


def _revision_json(rev) -> dict:
    contenido = json.loads(rev["informe"])
    return {
        "id": rev["id"],
        "plan": rev["plan"],
        "fecha": rev["fecha"],
        "demo": contenido.get("demo", False),
        "informe": contenido["informe"],
        "calculos": contenido["calculos"],
        "preguntas_ilimitadas": PLANES[rev["plan"]].preguntas_chat is None,
        "preguntas_disponibles": _preguntas_disponibles(rev),
        "preguntas_por_anuncio": rev["preguntas_extra"] < MAX_PREGUNTAS_ANUNCIO,
        "pdf_pagado": rev["compra_pdf"] is not None,
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
    if _preguntas_disponibles(rev) == 0:
        if rev["preguntas_extra"] >= MAX_PREGUNTAS_ANUNCIO:
            raise HTTPException(429, "Has llegado al máximo de preguntas para esta revisión.")
        raise HTTPException(402, "Mira un anuncio corto para hacer otra pregunta a Nora.")
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


# ---------------------------------------------------------------- anuncios con recompensa

@app.post("/api/revisiones/{rid}/recompensa")
def recompensa(rid: str, disp: str = Depends(dispositivo)):
    """La app avisa de que el usuario ha visto un anuncio con recompensa.

    Con NOMINAS_VERIFICACION_ANUNCIOS=app se suma la pregunta aquí (sólo para pruebas).
    Con "ssv" la suma Google llamando a /api/admob/recompensa, y esto sólo devuelve cuántas hay.
    """
    rev = almacen.revision(disp, rid)
    if not rev:
        raise HTTPException(404, "Revisión no encontrada.")
    if VERIFICACION_ANUNCIOS != "ssv" and not almacen.sumar_pregunta_extra(rid, MAX_PREGUNTAS_ANUNCIO):
        raise HTTPException(429, f"Has llegado al máximo de {MAX_PREGUNTAS_ANUNCIO} preguntas con anuncios "
                                 "en esta revisión.")
    return {"preguntas_disponibles": _preguntas_disponibles(almacen.revision(disp, rid))}


@app.get("/api/admob/recompensa")
def admob_recompensa(request: Request):
    """Aviso de AdMob (verificación en el servidor) de que se ha visto un anuncio con recompensa.
    La app pone el id del dispositivo en user_id y el de la revisión en custom_data."""
    try:
        p = admob_ssv.verificar(request.url.query)
    except admob_ssv.FirmaNoValida as e:
        raise HTTPException(400, str(e))
    rev = almacen.revision(p.get("user_id", ""), p.get("custom_data", ""))
    if rev:
        almacen.sumar_pregunta_extra(rev["id"], MAX_PREGUNTAS_ANUNCIO, transaccion=p.get("transaction_id"))
    return {"ok": True}  # AdMob sólo necesita un 200


# ---------------------------------------------------------------- informe en PDF (0,50 €)

class PeticionPdf(BaseModel):
    compra: str


@app.post("/api/revisiones/{rid}/pdf")
def comprar_pdf(rid: str, req: PeticionPdf, disp: str = Depends(dispositivo)):
    """Registra el pago del PDF de una revisión completa. Se paga una vez por informe;
    la app genera el PDF en el móvil cuando el servidor confirma el pago."""
    rev = almacen.revision(disp, rid)
    if not rev:
        raise HTTPException(404, "Revisión no encontrada.")
    if rev["plan"] != "pro":
        raise HTTPException(400, "El informe en PDF es de la revisión completa.")
    if rev["compra_pdf"] is not None:
        return {"pdf_pagado": True}
    if almacen.compra_usada(req.compra):
        raise HTTPException(409, "Esta compra ya se ha usado.")
    try:
        google_play.verificar_pdf(req.compra)
    except google_play.CompraNoValida as e:
        raise HTTPException(402, str(e))
    try:
        almacen.marcar_pdf_pagado(rid, req.compra)
    except almacen.CompraUsada as e:
        raise HTTPException(409, str(e))
    return {"pdf_pagado": True}
