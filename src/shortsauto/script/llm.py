"""Generación del guion con un LLM local (llama.cpp / llama-server)."""
import atexit
import json
import logging
import random
import subprocess
import time

import requests

from ..config import LOGS
from ..setup import models
from .schema import JSON_SCHEMA, MOODS, Script

log = logging.getLogger(__name__)

SYSTEM = """Eres un guionista experto en vídeos cortos virales (YouTube Shorts, TikTok, Reels).
Escribes en {idioma} natural, frases cortas y fáciles de leer en voz alta.
Reglas:
- "gancho": una frase de máximo 12 palabras que obligue a seguir mirando (pregunta, dato chocante o promesa).
- "escenas": cada una 1-2 frases, con un dato concreto y correcto. No inventes cifras si no estás seguro.
- "visual": descripción EN INGLÉS de una imagen para esa escena (sujeto, entorno, luz, encuadre vertical).
- "palabra_clave": la palabra más importante de la escena (se resaltará).
- "sfx": efecto de sonido para la transición.
- "cta": cierre corto invitando a seguir o comentar.
- "mood": uno de {moods}.
- "hashtags": 5-8 hashtags relevantes.
Escribe números y siglas como se pronuncian ("mil quinientos", no "1.500")."""

USER = """Tema: {tema}
Duración objetivo: {segundos} segundos de narración (unas {palabras} palabras en total).
Responde solo con el JSON."""

SURPRISE_TOPICS = [
    "datos curiosos del espacio", "animales con habilidades increíbles", "misterios de la historia",
    "inventos que cambiaron el mundo", "curiosidades del cuerpo humano", "lugares extraños del planeta",
    "trucos de psicología", "récords de la naturaleza", "civilizaciones antiguas", "el océano profundo",
]


class LlamaServer:
    """Arranca llama-server una vez y lo reutiliza para varios vídeos."""

    def __init__(self, model_key: str, port: int, ctx: int, gpu: bool):
        self.model = models.llm_file(model_key)
        self.port, self.ctx, self.gpu = port, ctx, gpu
        self.proc: subprocess.Popen | None = None

    @property
    def url(self) -> str:
        return f"http://127.0.0.1:{self.port}"

    def start(self) -> None:
        if self.proc and self.proc.poll() is None:
            return
        exe = models.llama_server_path()
        if not exe.exists():
            raise RuntimeError("Falta llama-server. Ejecuta el asistente de instalación.")
        if not self.model.exists():
            raise RuntimeError(f"Falta el modelo de guion {self.model.name}. Ejecuta el asistente.")
        LOGS.mkdir(exist_ok=True)
        args = [str(exe), "-m", str(self.model), "--port", str(self.port), "-c", str(self.ctx),
                "--host", "127.0.0.1", "-ngl", "99" if self.gpu else "0"]
        flags = subprocess.CREATE_NO_WINDOW if hasattr(subprocess, "CREATE_NO_WINDOW") else 0
        self.proc = subprocess.Popen(args, stdout=open(LOGS / "llama-server.log", "w"),
                                     stderr=subprocess.STDOUT, creationflags=flags)
        atexit.register(self.stop)
        deadline = time.time() + 180
        while time.time() < deadline:
            if self.proc.poll() is not None:
                raise RuntimeError("llama-server se cerró al arrancar; mira logs/llama-server.log")
            try:
                if requests.get(self.url + "/health", timeout=2).status_code == 200:
                    return
            except requests.RequestException:
                pass
            time.sleep(1)
        raise RuntimeError("llama-server no respondió en 3 minutos")

    def stop(self) -> None:
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()
            try:
                self.proc.wait(10)
            except subprocess.TimeoutExpired:
                self.proc.kill()

    def chat_json(self, system: str, user: str, temperature: float) -> dict:
        self.start()
        body = {
            "messages": [{"role": "system", "content": system},
                         {"role": "user", "content": user + " /no_think"}],
            "temperature": temperature,
            "max_tokens": 1500,
            "response_format": {"type": "json_schema",
                                "json_schema": {"name": "guion", "schema": JSON_SCHEMA}},
            "chat_template_kwargs": {"enable_thinking": False},
        }
        r = requests.post(self.url + "/v1/chat/completions", json=body, timeout=600)
        r.raise_for_status()
        content = r.json()["choices"][0]["message"]["content"]
        content = content.split("</think>")[-1].strip()
        return json.loads(content)


def surprise_topic() -> str:
    return random.choice(SURPRISE_TOPICS)


def generate(server: LlamaServer, tema: str, segundos: int, cfg: dict) -> Script:
    palabras = int(segundos * 2.4)
    system = SYSTEM.format(idioma=cfg["idioma"], moods=", ".join(MOODS))
    user = USER.format(tema=tema, segundos=segundos, palabras=palabras)
    last_error = None
    for intento in range(3):
        try:
            script = Script.from_dict(server.chat_json(system, user, cfg["temperatura"]))
            n = script.word_count()
            # Reintenta si se aleja mucho de la duración pedida.
            if 0.6 * palabras <= n <= 1.5 * palabras or intento == 2:
                return script
            user += f"\nTu versión anterior tenía {n} palabras; ajústala a unas {palabras}."
        except (ValueError, KeyError, TypeError) as e:
            last_error = e
            log.warning("Guion inválido (intento %d): %s", intento + 1, e)
    raise RuntimeError(f"El modelo no generó un guion válido: {last_error}")


def topics(server: LlamaServer, nicho: str, n: int) -> list[str]:
    """Ideas de temas distintos dentro de un nicho, para el modo lote."""
    schema = {"type": "object", "properties": {"temas": {
        "type": "array", "items": {"type": "string"}, "minItems": n, "maxItems": n}},
        "required": ["temas"]}
    server.start()
    body = {
        "messages": [{"role": "user", "content":
                      f"Dame {n} temas concretos y distintos para vídeos cortos virales sobre "
                      f"«{nicho}». Cada tema en una línea breve. /no_think"}],
        "temperature": 0.9, "max_tokens": 800,
        "response_format": {"type": "json_schema", "json_schema": {"name": "t", "schema": schema}},
        "chat_template_kwargs": {"enable_thinking": False},
    }
    r = requests.post(server.url + "/v1/chat/completions", json=body, timeout=300)
    r.raise_for_status()
    content = r.json()["choices"][0]["message"]["content"].split("</think>")[-1]
    return [t.strip() for t in json.loads(content)["temas"] if t.strip()][:n]
