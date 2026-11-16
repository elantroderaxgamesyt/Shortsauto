"""Diferencias entre la versión Free y la Pro. Cambia aquí los límites."""
import os
from dataclasses import dataclass

MODELO = os.getenv("NOMINAS_MODELO", "claude-opus-5-5")


@dataclass(frozen=True)
class Plan:
    nombre: str
    esfuerzo: str          # output_config.effort de Claude
    max_puntos: int        # puntos del informe
    preguntas_chat: int    # 0 = ilimitadas
    comprobaciones: str    # "basicas" (sumas) o "completas" (sumas + cotizaciones + IRPF)


PLANES = {
    "free": Plan("free", esfuerzo="low", max_puntos=5, preguntas_chat=3, comprobaciones="basicas"),
    "pro": Plan("pro", esfuerzo="high", max_puntos=0, preguntas_chat=0, comprobaciones="completas"),
}


def codigos_pro() -> set[str]:
    """Códigos de acceso Pro (NOMINAS_CODIGOS_PRO="abc,def"). Vacío = Pro abierto (prototipo)."""
    return {c.strip() for c in os.getenv("NOMINAS_CODIGOS_PRO", "").split(",") if c.strip()}


def resolver_plan(plan: str, codigo: str | None) -> Plan:
    if plan == "pro":
        codigos = codigos_pro()
        if codigos and (codigo or "") not in codigos:
            raise PermissionError("Código Pro no válido")
        return PLANES["pro"]
    return PLANES["free"]
