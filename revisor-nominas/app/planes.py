"""Diferencias entre la versión Free y la Pro, productos de pago y límites de uso."""
import os
from dataclasses import dataclass

# Modelos de Claude. Se pueden cambiar con variables de entorno sin tocar código.
# Revisión gratis y chat con Haiku (mucho más barato); revisión completa (de pago) con Opus.
MODELO_FREE = os.getenv("NOMINAS_MODELO_FREE", "claude-haiku-5-5")
MODELO_PRO = os.getenv("NOMINAS_MODELO_PRO", "claude-opus-5-5")
MODELO_CHAT = os.getenv("NOMINAS_MODELO_CHAT", "claude-haiku-5-5")


@dataclass(frozen=True)
class Plan:
    nombre: str
    modelo: str            # modelo de Claude para el análisis
    esfuerzo: str          # output_config.effort de Claude
    max_puntos: int        # puntos del informe (0 = sin límite)
    preguntas_chat: int    # preguntas por revisión (0 = ilimitadas)
    comprobaciones: str    # "basicas" (sumas) o "completas" (sumas + cotizaciones + IRPF)


PLANES = {
    "free": Plan("free", modelo=MODELO_FREE, esfuerzo="medium", max_puntos=5, preguntas_chat=1, comprobaciones="basicas"),
    "pro": Plan("pro", modelo=MODELO_PRO, esfuerzo="high", max_puntos=0, preguntas_chat=0, comprobaciones="completas"),
}

# Productos de Google Play (créalos con estos mismos IDs en Play Console).
PRODUCTO_REVISION = "revision_pro"   # consumible, 2,99 €: +1 revisión Pro
PRODUCTO_MENSUAL = "pro_mensual"     # suscripción, 9,99 €/mes

# Uso justo: cada revisión cuesta dinero en IA.
FREE_POR_DIA = int(os.getenv("NOMINAS_FREE_POR_DIA", "3"))
MENSUAL_POR_MES = int(os.getenv("NOMINAS_MENSUAL_POR_MES", "30"))
