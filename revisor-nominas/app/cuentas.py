"""Cuentas anónimas, saldo Pro, compras y revisiones guardadas (SQLite).

Cada instalación de la app genera un identificador aleatorio y lo envía en la
cabecera X-Usuario. No se guarda la nómina: sólo el informe, para el chat.
"""
from __future__ import annotations

import json
import os
import secrets
import sqlite3
import threading
from datetime import datetime, timedelta, timezone

from .planes import FREE_POR_DIA, MENSUAL_POR_MES

_lock = threading.Lock()
_con: sqlite3.Connection | None = None

ESQUEMA = """
CREATE TABLE IF NOT EXISTS usuarios (
    id TEXT PRIMARY KEY,
    creditos INTEGER NOT NULL DEFAULT 0,
    suscripcion_hasta TEXT,
    creado TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS compras (
    token TEXT PRIMARY KEY,
    usuario TEXT NOT NULL,
    producto TEXT NOT NULL,
    origen TEXT NOT NULL,
    fecha TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS revisiones (
    id TEXT PRIMARY KEY,
    usuario TEXT NOT NULL,
    plan TEXT NOT NULL,
    pagada_con TEXT,
    informe TEXT NOT NULL,
    preguntas INTEGER NOT NULL DEFAULT 0,
    fecha TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS rev_usuario ON revisiones(usuario, fecha);
CREATE TABLE IF NOT EXISTS codigos (
    codigo TEXT PRIMARY KEY,
    creditos INTEGER NOT NULL DEFAULT 0,
    dias_pro INTEGER NOT NULL DEFAULT 0,
    usado_por TEXT
);
"""


def ahora() -> datetime:
    return datetime.now(timezone.utc)


def db() -> sqlite3.Connection:
    global _con
    if _con is None:
        _con = sqlite3.connect(os.getenv("NOMINAS_DB", "nominas.db"), check_same_thread=False,
                               isolation_level=None)
        _con.row_factory = sqlite3.Row
        _con.executescript(ESQUEMA)
    return _con


def reiniciar(ruta: str) -> None:
    """Para tests: abre otra base de datos."""
    global _con
    os.environ["NOMINAS_DB"] = ruta
    _con = None


def usuario(uid: str) -> sqlite3.Row:
    with _lock:
        db().execute("INSERT OR IGNORE INTO usuarios(id, creado) VALUES (?, ?)", (uid, ahora().isoformat()))
        return db().execute("SELECT * FROM usuarios WHERE id = ?", (uid,)).fetchone()


def suscripcion_activa(u: sqlite3.Row) -> bool:
    return bool(u["suscripcion_hasta"]) and datetime.fromisoformat(u["suscripcion_hasta"]) > ahora()


def _contar(uid: str, plan: str, desde: datetime, pagada_con: str | None = None) -> int:
    q = "SELECT COUNT(*) FROM revisiones WHERE usuario = ? AND plan = ? AND fecha >= ?"
    args: list = [uid, plan, desde.isoformat()]
    if pagada_con:
        q += " AND pagada_con = ?"
        args.append(pagada_con)
    return db().execute(q, args).fetchone()[0]


def resumen(uid: str) -> dict:
    u = usuario(uid)
    activa = suscripcion_activa(u)
    hoy = ahora().replace(hour=0, minute=0, second=0, microsecond=0)
    return {
        "creditos": u["creditos"],
        "suscripcion_activa": activa,
        "suscripcion_hasta": u["suscripcion_hasta"] if activa else None,
        "free_restantes_hoy": max(0, FREE_POR_DIA - _contar(uid, "free", hoy)),
        "mensual_restantes": (max(0, MENSUAL_POR_MES - _contar(uid, "pro", ahora() - timedelta(days=30), "suscripcion"))
                              if activa else 0),
    }


class SinSaldo(Exception):
    pass


def reservar(uid: str, plan: str) -> str | None:
    """Comprueba si el usuario puede hacer la revisión. Devuelve con qué se paga."""
    r = resumen(uid)
    if plan == "free":
        if r["free_restantes_hoy"] <= 0:
            raise SinSaldo(f"Has usado las {FREE_POR_DIA} revisiones gratis de hoy. Vuelve mañana o pásate a Pro.")
        return None
    if r["suscripcion_activa"] and r["mensual_restantes"] > 0:
        return "suscripcion"
    if r["creditos"] > 0:
        return "credito"
    raise SinSaldo("Necesitas una revisión Pro (2,99 €) o la suscripción mensual (9,99 €).")


def guardar_revision(uid: str, plan: str, pagada_con: str | None, informe: dict) -> str:
    """Guarda el informe y descuenta el crédito si se pagó con uno. Atómico."""
    rid = secrets.token_urlsafe(16)
    with _lock:
        c = db()
        c.execute("BEGIN IMMEDIATE")
        try:
            if pagada_con == "credito":
                cur = c.execute("UPDATE usuarios SET creditos = creditos - 1 WHERE id = ? AND creditos > 0", (uid,))
                if cur.rowcount == 0:
                    raise SinSaldo("No te quedan revisiones Pro.")
            c.execute("INSERT INTO revisiones(id, usuario, plan, pagada_con, informe, fecha) VALUES (?,?,?,?,?,?)",
                      (rid, uid, plan, pagada_con, json.dumps(informe, ensure_ascii=False), ahora().isoformat()))
            c.execute("COMMIT")
        except Exception:
            c.execute("ROLLBACK")
            raise
    return rid


def revision(uid: str, rid: str) -> sqlite3.Row | None:
    return db().execute("SELECT * FROM revisiones WHERE id = ? AND usuario = ?", (rid, uid)).fetchone()


def sumar_pregunta(rid: str) -> None:
    with _lock:
        db().execute("UPDATE revisiones SET preguntas = preguntas + 1 WHERE id = ?", (rid,))


def registrar_compra(uid: str, token: str, producto: str, origen: str,
                     creditos: int = 0, hasta: datetime | None = None) -> bool:
    """Aplica una compra una sola vez (el token es único). Devuelve False si ya estaba aplicada."""
    usuario(uid)
    with _lock:
        c = db()
        c.execute("BEGIN IMMEDIATE")
        try:
            dueno = c.execute("SELECT usuario FROM compras WHERE token = ?", (token,)).fetchone()
            if dueno:
                c.execute("ROLLBACK")
                # Una suscripción puede restaurarse en otro dispositivo: se mueve al nuevo usuario.
                if hasta is not None and dueno["usuario"] != uid:
                    _transferir_suscripcion(dueno["usuario"], uid, token, hasta)
                elif hasta is not None:
                    db().execute("UPDATE usuarios SET suscripcion_hasta = ? WHERE id = ?", (hasta.isoformat(), uid))
                return False
            c.execute("INSERT INTO compras(token, usuario, producto, origen, fecha) VALUES (?,?,?,?,?)",
                      (token, uid, producto, origen, ahora().isoformat()))
            if creditos:
                c.execute("UPDATE usuarios SET creditos = creditos + ? WHERE id = ?", (creditos, uid))
            if hasta is not None:
                c.execute("UPDATE usuarios SET suscripcion_hasta = ? WHERE id = ?", (hasta.isoformat(), uid))
            c.execute("COMMIT")
            return True
        except Exception:
            c.execute("ROLLBACK")
            raise


def _transferir_suscripcion(anterior: str, nuevo: str, token: str, hasta: datetime) -> None:
    c = db()
    c.execute("UPDATE usuarios SET suscripcion_hasta = NULL WHERE id = ?", (anterior,))
    c.execute("UPDATE usuarios SET suscripcion_hasta = ? WHERE id = ?", (hasta.isoformat(), nuevo))
    c.execute("UPDATE compras SET usuario = ? WHERE token = ?", (nuevo, token))


# ---- Códigos de canje (promociones y, de momento, Pro en Windows) ----

def crear_codigo(creditos: int = 0, dias_pro: int = 0) -> str:
    codigo = "-".join(secrets.token_hex(2).upper() for _ in range(3))
    db().execute("INSERT INTO codigos(codigo, creditos, dias_pro) VALUES (?,?,?)", (codigo, creditos, dias_pro))
    return codigo


def canjear(uid: str, codigo: str) -> None:
    codigo = codigo.strip().upper()
    usuario(uid)
    with _lock:
        c = db()
        c.execute("BEGIN IMMEDIATE")
        try:
            fila = c.execute("SELECT * FROM codigos WHERE codigo = ? AND usado_por IS NULL", (codigo,)).fetchone()
            if not fila:
                raise ValueError("Código no válido o ya usado.")
            c.execute("UPDATE codigos SET usado_por = ? WHERE codigo = ?", (uid, codigo))
            if fila["creditos"]:
                c.execute("UPDATE usuarios SET creditos = creditos + ? WHERE id = ?", (fila["creditos"], uid))
            if fila["dias_pro"]:
                u = c.execute("SELECT suscripcion_hasta FROM usuarios WHERE id = ?", (uid,)).fetchone()
                base = max(ahora(), datetime.fromisoformat(u[0])) if u[0] else ahora()
                c.execute("UPDATE usuarios SET suscripcion_hasta = ? WHERE id = ?",
                          ((base + timedelta(days=fila["dias_pro"])).isoformat(), uid))
            c.execute("COMMIT")
        except Exception:
            c.execute("ROLLBACK")
            raise
