"""Verificación en el servidor de los anuncios con recompensa de AdMob (SSV).

Cuando alguien termina de ver un anuncio con recompensa, Google llama a nuestra URL
(GET /api/admob/recompensa?...&key_id=..&signature=..). La firma demuestra que la
llamada viene de Google y no de alguien que quiere preguntas gratis.

Configuración en AdMob: bloque "Recompensa" → Verificación en el servidor → URL de
devolución de llamada = https://TU-SERVIDOR/api/admob/recompensa
"""
from __future__ import annotations

import base64
import time
from urllib.parse import parse_qsl

URL_CLAVES = "https://www.gstatic.com/admob/reward/verifier-keys.json"
_claves: dict[str, bytes] = {}
_claves_hasta = 0.0


class FirmaNoValida(Exception):
    pass


def _cargar_claves() -> dict[str, bytes]:
    """Claves públicas de Google (se renuevan cada día)."""
    global _claves, _claves_hasta
    if not _claves or time.time() > _claves_hasta:
        import requests
        r = requests.get(URL_CLAVES, timeout=10)
        r.raise_for_status()
        _claves = {str(k["keyId"]): k["pem"].encode() for k in r.json()["keys"]}
        _claves_hasta = time.time() + 24 * 3600
    return _claves


def verificar(query: str) -> dict[str, str]:
    """Comprueba la firma de la query de AdMob y devuelve sus parámetros."""
    from cryptography.exceptions import InvalidSignature
    from cryptography.hazmat.primitives import hashes
    from cryptography.hazmat.primitives.asymmetric import ec
    from cryptography.hazmat.primitives.serialization import load_pem_public_key

    if "&signature=" not in query:
        raise FirmaNoValida("Falta la firma.")
    mensaje = query[: query.index("&signature=")]  # se firma todo lo anterior a signature
    params = dict(parse_qsl(query, keep_blank_values=True))
    pem = _cargar_claves().get(params.get("key_id", ""))
    if pem is None:
        raise FirmaNoValida("Clave desconocida.")
    firma = params.get("signature", "")
    try:
        firma_bytes = base64.urlsafe_b64decode(firma + "=" * (-len(firma) % 4))
        load_pem_public_key(pem).verify(firma_bytes, mensaje.encode(), ec.ECDSA(hashes.SHA256()))
    except (InvalidSignature, ValueError):
        raise FirmaNoValida("Firma incorrecta.")
    return params
