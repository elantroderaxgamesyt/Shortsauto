"""Llamadas a Claude: análisis de la nómina y chat de dudas."""
from __future__ import annotations

import base64
import json
import os
from pathlib import Path
from typing import Iterator

import anthropic

from .comprobaciones import REFERENCIA
from .modelos import InformeFree, InformePro
from .planes import MODELO, Plan

BETAS = ["server-side-fallback-2026-07-01"]
TIPOS_IMAGEN = {"image/png", "image/jpeg", "image/webp", "image/gif"}

PERSONA = """Eres "Nora", asesora laboral especializada en nóminas españolas. Hablas en español \
de España, de tú, con frases cortas y sin jerga innecesaria; cuando uses un término técnico \
(base de cotización, MEI, prorrata...) lo explicas en una línea. Eres honesta: si algo no se \
puede saber sólo con la nómina (por ejemplo, el salario que fija el convenio), lo dices y \
explicas cómo comprobarlo. No inventes cifras de convenios. No eres abogada: para reclamaciones \
importantes recomiendas consultar con un graduado social, sindicato o abogado laboralista.

Privacidad: nunca repitas completos DNI/NIE, número de la Seguridad Social, IBAN ni dirección. \
Enmascáralos (p. ej. "12***78Z"). Puedes usar el nombre de pila del trabajador.

Tipos de referencia que usa la app (revísalos si el periodo de la nómina es de otro año):
""" + json.dumps(REFERENCIA, ensure_ascii=False)

INSTRUCCIONES_FREE = """Revisa esta nómina y da un informe SENCILLO:
- veredicto: correcta / revisar / incorrecta (o ilegible si no se puede leer).
- resumen: 2-3 frases para alguien sin conocimientos.
- puntos: como máximo {max_puntos}, los más importantes (lo que está bien y lo que falla).
- datos: extrae los importes de la nómina tal cual aparecen (usa null si no aparece un dato). \
En deducciones, clasifica cada línea con su tipo."""

INSTRUCCIONES_PRO = """Haz una revisión COMPLETA de esta nómina, como lo haría una asesora laboral:
- Comprueba cada concepto: salario base, complementos, pagas extra o prorrata, horas extra, \
pluses, bases de cotización (incluida la prorrata de pagas extra en la base), cada cotización \
del trabajador (contingencias comunes, desempleo según contrato, formación, MEI), IRPF \
(si el % parece razonable para el salario), periodo y días cotizados, datos obligatorios \
del recibo (Orden ESS/2098/2014).
- comprobaciones: una por concepto revisado, con importe en nómina, importe esperado (si se puede \
calcular), explicación y qué hacer.
- explicacion_conceptos: explica en lenguaje llano qué significa cada línea de la nómina.
- recomendaciones y preguntas_para_rrhh: concretas y accionables.
- borrador_reclamacion: si hay errores, un texto breve y educado para enviar a la empresa; si no, null.
- confianza y limitaciones: qué no has podido comprobar y por qué.
- datos: extrae los importes tal cual aparecen (null si falta). Clasifica cada deducción con su tipo."""


def hay_credenciales() -> bool:
    return bool(os.getenv("ANTHROPIC_API_KEY") or os.getenv("ANTHROPIC_AUTH_TOKEN")
                or os.getenv("ANTHROPIC_PROFILE"))


_cliente: anthropic.Anthropic | None = None


def cliente() -> anthropic.Anthropic:
    global _cliente
    if _cliente is None:
        _cliente = anthropic.Anthropic(max_retries=3)
    return _cliente


class RechazoIA(Exception):
    pass


def bloque_documento(datos: bytes, media_type: str) -> dict:
    b64 = base64.standard_b64encode(datos).decode()
    if media_type == "application/pdf":
        return {"type": "document", "source": {"type": "base64", "media_type": media_type, "data": b64}}
    if media_type in TIPOS_IMAGEN:
        return {"type": "image", "source": {"type": "base64", "media_type": media_type, "data": b64}}
    raise ValueError("Formato no soportado. Sube un PDF o una foto (PNG, JPG, WEBP).")


def analizar(datos: bytes, media_type: str, plan: Plan) -> InformeFree | InformePro:
    if not hay_credenciales():
        return informe_demo(plan)

    if plan.nombre == "pro":
        esquema, instrucciones = InformePro, INSTRUCCIONES_PRO
    else:
        esquema, instrucciones = InformeFree, INSTRUCCIONES_FREE.format(max_puntos=plan.max_puntos)

    with cliente().beta.messages.stream(
        model=MODELO,
        max_tokens=32000,
        betas=BETAS,
        fallbacks="default",
        system=[{"type": "text", "text": PERSONA, "cache_control": {"type": "ephemeral"}}],
        output_config={"effort": plan.esfuerzo},
        output_format=esquema,
        messages=[{"role": "user", "content": [bloque_documento(datos, media_type),
                                               {"type": "text", "text": instrucciones}]}],
    ) as stream:
        msg = stream.get_final_message()

    if msg.stop_reason == "refusal":
        raise RechazoIA("La IA no ha podido analizar este documento.")
    if msg.stop_reason == "max_tokens" or msg.parsed_output is None:
        raise RechazoIA("El análisis se ha cortado. Prueba de nuevo.")
    informe = msg.parsed_output
    if plan.max_puntos and hasattr(informe, "puntos"):
        informe.puntos = informe.puntos[: plan.max_puntos]
    return informe


def chat(informe: dict, historial: list[dict], plan: Plan) -> Iterator[str]:
    """Responde dudas sobre la nómina ya analizada. Devuelve el texto en trozos."""
    if not hay_credenciales():
        yield ("(Modo demo, sin clave de API) En la versión real te respondería Nora usando los "
               "datos de tu nómina. Configura ANTHROPIC_API_KEY para activarlo.")
        return

    contexto = ("Este es el análisis de la nómina del usuario (JSON). Responde a sus dudas basándote "
                "en él; si te pregunta algo que no está en la nómina, dilo.\n\n"
                + json.dumps(informe, ensure_ascii=False))
    if plan.nombre == "free":
        contexto += ("\n\nVersión gratuita: responde en 3-5 frases. Si la duda requiere un cálculo "
                     "detallado o una reclamación, indica que la versión Pro lo incluye.")

    mensajes = [{"role": m["role"], "content": m["content"]} for m in historial
                if m.get("role") in ("user", "assistant") and m.get("content")]

    with cliente().beta.messages.stream(
        model=MODELO,
        max_tokens=8000 if plan.nombre == "free" else 32000,
        betas=BETAS,
        fallbacks="default",
        system=[{"type": "text", "text": PERSONA},
                {"type": "text", "text": contexto, "cache_control": {"type": "ephemeral"}}],
        output_config={"effort": "low" if plan.nombre == "free" else "medium"},
        messages=mensajes,
    ) as stream:
        for texto in stream.text_stream:
            yield texto
        final = stream.get_final_message()
    if final.stop_reason == "refusal":
        yield "\n\n(No puedo responder a esa pregunta.)"


def informe_demo(plan: Plan) -> InformeFree | InformePro:
    """Informe de ejemplo para probar la app sin clave de API."""
    ruta = Path(__file__).parent.parent / "ejemplos" / f"informe_demo_{plan.nombre}.json"
    datos = json.loads(ruta.read_text("utf-8"))
    return (InformePro if plan.nombre == "pro" else InformeFree).model_validate(datos)
