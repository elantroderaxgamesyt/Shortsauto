"""Lo que guarda el servidor (SQLite). No hay cuentas de usuario.

Cada instalación de la app manda un identificador anónimo y aleatorio en la cabecera
X-Dispositivo. Sólo sirve para el límite de revisiones gratis al día, para el historial
"Mis revisiones", para las preguntas ganadas con anuncios y para que nadie pueda leer
el chat de otro. No se guarda la nómina,
sólo el informe.

Las revisiones completas se pagan una a una (2,99 € en Google Play): cada compra se
usa para una sola revisión y queda registrada para que no se pueda reutilizar.
"""
from __future__ import annotations

import json
import os
import secrets
import sqlite3
import threading
from datetime import datetime, timezone

from .planes import FREE_POR_DIA

_lock = threading.Lock()
_con: sqlite3.Connection | None = None

ESQUEMA = """
CREATE TABLE IF NOT EXISTS revisiones (
    id TEXT PRIMARY KEY,
    dispositivo TEXT NOT NULL,
    plan TEXT NOT NULL,
    compra TEXT UNIQUE,          -- token de Google Play con el que se pagó (NULL si es gratis)
    informe TEXT NOT NULL,
    preguntas INTEGER NOT NULL DEFAULT 0,
    preguntas_extra INTEGER NOT NULL DEFAULT 0,  -- ganadas viendo anuncios
    fecha TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS rev_dispositivo ON revisiones(dispositivo, fecha);
CREATE TABLE IF NOT EXISTS recompensas (
    transaccion TEXT PRIMARY KEY,   -- id de AdMob: cada anuncio visto cuenta una sola vez
    revision TEXT NOT NULL,
    fecha TEXT NOT NULL
);
"""


class SinSaldo(Exception):
    pass


class CompraUsada(Exception):
    pass


def ahora() -> datetime:
    return datetime.now(timezone.utc)


def db() -> sqlite3.Connection:
    global _con
    if _con is None:
        _con = sqlite3.connect(os.getenv("NOMINAS_DB", "nominas.db"), check_same_thread=False,
                               isolation_level=None)
        _con.row_factory = sqlite3.Row
        _con.executescript(ESQUEMA)
        columnas = {c[1] for c in _con.execute("PRAGMA table_info(revisiones)")}
        if "preguntas_extra" not in columnas:  # bases de datos creadas antes de este cambio
            _con.execute("ALTER TABLE revisiones ADD COLUMN preguntas_extra INTEGER NOT NULL DEFAULT 0")
    return _con


def reiniciar(ruta: str) -> None:
    """Para tests: abre otra base de datos."""
    global _con
    os.environ["NOMINAS_DB"] = ruta
    _con = None


def free_restantes_hoy(disp: str) -> int:
    hoy = ahora().replace(hour=0, minute=0, second=0, microsecond=0)
    usadas = db().execute("SELECT COUNT(*) FROM revisiones WHERE dispositivo = ? AND plan = 'free' AND fecha >= ?",
                          (disp, hoy.isoformat())).fetchone()[0]
    return max(0, FREE_POR_DIA - usadas)


def comprobar_free(disp: str) -> None:
    if free_restantes_hoy(disp) <= 0:
        raise SinSaldo(f"Has usado las {FREE_POR_DIA} revisiones gratis de hoy. Vuelve mañana o haz una revisión completa.")


def compra_usada(token: str) -> bool:
    return db().execute("SELECT 1 FROM revisiones WHERE compra = ?", (token,)).fetchone() is not None


def guardar_revision(disp: str, plan: str, compra: str | None, contenido: dict) -> str:
    rid = secrets.token_urlsafe(16)
    with _lock:
        try:
            db().execute("INSERT INTO revisiones(id, dispositivo, plan, compra, informe, fecha) VALUES (?,?,?,?,?,?)",
                         (rid, disp, plan, compra, json.dumps(contenido, ensure_ascii=False), ahora().isoformat()))
        except sqlite3.IntegrityError:
            raise CompraUsada("Esta compra ya se ha usado para otra revisión.")
    return rid


def revision(disp: str, rid: str) -> sqlite3.Row | None:
    return db().execute("SELECT * FROM revisiones WHERE id = ? AND dispositivo = ?", (rid, disp)).fetchone()


def listar_revisiones(disp: str, limite: int = 50) -> list[sqlite3.Row]:
    return db().execute("SELECT id, plan, informe, fecha FROM revisiones WHERE dispositivo = ? "
                        "ORDER BY fecha DESC LIMIT ?", (disp, limite)).fetchall()


def sumar_pregunta(rid: str) -> None:
    with _lock:
        db().execute("UPDATE revisiones SET preguntas = preguntas + 1 WHERE id = ?", (rid,))


def sumar_pregunta_extra(rid: str, maximo: int, transaccion: str | None = None) -> bool:
    """Suma una pregunta ganada con un anuncio. False si se ha llegado al máximo o la
    transacción de AdMob ya se había contado."""
    with _lock:
        c = db()
        c.execute("BEGIN IMMEDIATE")
        try:
            if transaccion:
                try:
                    c.execute("INSERT INTO recompensas(transaccion, revision, fecha) VALUES (?,?,?)",
                              (transaccion, rid, ahora().isoformat()))
                except sqlite3.IntegrityError:
                    c.execute("ROLLBACK")
                    return False
            cur = c.execute("UPDATE revisiones SET preguntas_extra = preguntas_extra + 1 "
                            "WHERE id = ? AND preguntas_extra < ?", (rid, maximo))
            if cur.rowcount == 0:
                c.execute("ROLLBACK")
                return False
            c.execute("COMMIT")
            return True
        except Exception:
            c.execute("ROLLBACK")
            raise
