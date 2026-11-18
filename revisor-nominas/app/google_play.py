"""Verificación en el servidor de las compras de Google Play.

Nunca te fíes de lo que diga la app: antes de hacer una revisión completa, el servidor
pregunta a Google si el token de compra es real.

Configuración:
  GOOGLE_PLAY_PAQUETE        id de la app (p. ej. es.revisornominas.app)
  GOOGLE_PLAY_CREDENCIALES   ruta al JSON de la cuenta de servicio con acceso
                             a la API "Google Play Android Developer"
  NOMINAS_PAGOS_PRUEBA=1     sólo desarrollo: acepta tokens "prueba-..." sin Google
"""
from __future__ import annotations

import os

from .planes import PRODUCTO_PDF, PRODUCTO_REVISION

API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"


class CompraNoValida(Exception):
    pass


_sesion = None


def _http():
    global _sesion
    if _sesion is None:
        ruta = os.getenv("GOOGLE_PLAY_CREDENCIALES")
        if not ruta:
            raise CompraNoValida("El servidor no tiene configurada la verificación de Google Play.")
        from google.auth.transport.requests import AuthorizedSession
        from google.oauth2 import service_account
        cred = service_account.Credentials.from_service_account_file(
            ruta, scopes=["https://www.googleapis.com/auth/androidpublisher"])
        _sesion = AuthorizedSession(cred)
    return _sesion


def verificar_revision(token: str) -> None:
    """Comprueba que el token corresponde a una compra pagada de la revisión completa."""
    _verificar(PRODUCTO_REVISION, token)


def verificar_pdf(token: str) -> None:
    """Comprueba que el token corresponde a una compra pagada del informe en PDF."""
    _verificar(PRODUCTO_PDF, token)


def _verificar(producto: str, token: str) -> None:
    if os.getenv("NOMINAS_PAGOS_PRUEBA") == "1" and token.startswith("prueba-"):
        return
    paquete = os.getenv("GOOGLE_PLAY_PAQUETE", "es.revisornominas.app")
    r = _http().get(f"{API}/{paquete}/purchases/products/{producto}/tokens/{token}", timeout=20)
    if r.status_code in (400, 404, 410):
        raise CompraNoValida("Google no reconoce esta compra.")
    r.raise_for_status()
    if r.json().get("purchaseState") != 0:  # 0 = pagada, 1 = cancelada, 2 = pendiente
        raise CompraNoValida("El pago no está completado.")
