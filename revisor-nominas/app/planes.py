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
    preguntas_chat: int | None  # preguntas incluidas por revisión (None = ilimitadas)
    comprobaciones: str    # "basicas" (sumas) o "completas" (sumas + cotizaciones + IRPF)


PLANES = {
    "free": Plan("free", modelo=MODELO_FREE, esfuerzo="medium", max_puntos=5, preguntas_chat=int(os.getenv("NOMINAS_PREGUNTAS_GRATIS", "0")),
                 comprobaciones="basicas"),
    "pro": Plan("pro", modelo=MODELO_PRO, esfuerzo="high", max_puntos=0, preguntas_chat=int(os.getenv("NOMINAS_PREGUNTAS_COMPLETA", "3")),
                comprobaciones="completas"),
}

# Producto de Google Play (créalo con este mismo id en Play Console).
PRODUCTO_REVISION = "revision_pro"   # consumible, 2,99 €: una revisión completa
PRODUCTO_PDF = "informe_pdf"         # consumible, 0,50 €: el PDF de una revisión completa

# Preguntas a Nora: las incluidas en cada plan (gratis 0, completa 3) y después 1 por cada
# anuncio con recompensa visto, como mucho este número por revisión (cada pregunta cuesta IA).
MAX_PREGUNTAS_ANUNCIO = int(os.getenv("NOMINAS_MAX_PREGUNTAS_ANUNCIO", "5"))

# Cómo se comprueba que el anuncio se ha visto:
#   "app" -> el servidor se fía de la app (sólo mientras se usan los anuncios de PRUEBA).
#   "ssv" -> verificación en el servidor de AdMob (Google llama a /api/admob/recompensa
#            con una firma). Es la que hay que usar con anuncios reales.
VERIFICACION_ANUNCIOS = os.getenv("NOMINAS_VERIFICACION_ANUNCIOS", "app")

# Uso justo: cada revisión gratis cuesta dinero en IA.
FREE_POR_DIA = int(os.getenv("NOMINAS_FREE_POR_DIA", "3"))
