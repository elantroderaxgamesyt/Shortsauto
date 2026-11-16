"""Verificación de compras de Google Play en el servidor.

Nunca te fíes de lo que diga la app: el servidor pregunta a Google si el token
de compra es real antes de dar saldo.

Configuración:
  GOOGLE_PLAY_PAQUETE        id de la app (p. ej. es.revisornominas.app)
  GOOGLE_PLAY_CREDENCIALES   ruta al JSON de la cuenta de servicio con acceso
                             a la API "Google Play Android Developer"
  NOMINAS_PAGOS_PRUEBA=1     sólo desarrollo: acepta tokens "prueba-..." sin Google
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import datetime, timedelta

from .cuentas import ahora
from .planes import PRODUCTO_MENSUAL, PRODUCTO_REVISION

API = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications"


class CompraNoValida(Exception):
    pass


@dataclass
class Verificada:
    producto: str
    creditos: int = 0
    hasta: datetime | None = None


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


def _get(url: str) -> dict:
    r = _http().get(url, timeout=20)
    if r.status_code in (400, 404, 410):
        raise CompraNoValida("Google no reconoce esta compra.")
    r.raise_for_status()
    return r.json()


def verificar(producto: str, token: str) -> Verificada:
    if os.getenv("NOMINAS_PAGOS_PRUEBA") == "1" and token.startswith("prueba-"):
        if producto == PRODUCTO_REVISION:
            return Verificada(producto, creditos=1)
        if producto == PRODUCTO_MENSUAL:
            return Verificada(producto, hasta=ahora() + timedelta(days=30))

    paquete = os.getenv("GOOGLE_PLAY_PAQUETE", "es.revisornominas.app")

    if producto == PRODUCTO_REVISION:
        d = _get(f"{API}/{paquete}/purchases/products/{producto}/tokens/{token}")
        if d.get("purchaseState") != 0:  # 0 = comprado, 1 = cancelado, 2 = pendiente
            raise CompraNoValida("La compra no está completada.")
        return Verificada(producto, creditos=1)

    if producto == PRODUCTO_MENSUAL:
        d = _get(f"{API}/{paquete}/purchases/subscriptionsv2/tokens/{token}")
        if d.get("subscriptionState") not in ("SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"):
            raise CompraNoValida("La suscripción no está activa.")
        fechas = [li["expiryTime"] for li in d.get("lineItems", []) if li.get("productId") == producto]
        if not fechas:
            raise CompraNoValida("La suscripción no corresponde a este producto.")
        hasta = max(datetime.fromisoformat(f.replace("Z", "+00:00")) for f in fechas)
        return Verificada(producto, hasta=hasta)

    raise CompraNoValida("Producto desconocido.")
