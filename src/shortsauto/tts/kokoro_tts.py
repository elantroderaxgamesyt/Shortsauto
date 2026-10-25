"""Narración con Kokoro (ONNX, CPU o GPU) y tiempos por palabra."""
import functools
import re
from dataclasses import dataclass

import numpy as np
import soundfile as sf

from ..config import MODELS
from ..script.schema import Script

SR = 24000
VOICES = {"ef_dora": "Dora (mujer)", "em_alex": "Álex (hombre)", "em_santa": "Santa (hombre)"}


@dataclass
class Word:
    text: str
    start: float
    end: float
    scene: int          # -1 gancho, -2 CTA, 0..n escenas
    keyword: bool = False


@dataclass
class Narration:
    words: list[Word]
    scene_starts: list[float]   # inicio de cada bloque narrado (gancho, escenas, CTA)
    duration: float


@functools.cache
def _engine():
    from kokoro_onnx import Kokoro
    return Kokoro(str(MODELS / "tts/kokoro-v1.0.onnx"), str(MODELS / "tts/voices-v1.0.bin"))


def _sentences(text: str) -> list[str]:
    return [s for s in re.split(r"(?<=[.!?…])\s+", text.strip()) if s]


def _trim(audio: np.ndarray, threshold: float = 0.01) -> np.ndarray:
    loud = np.flatnonzero(np.abs(audio) > threshold)
    if loud.size == 0:
        return audio
    pad = int(0.03 * SR)
    return audio[max(0, loud[0] - pad): loud[-1] + pad]


def _syllables(word: str) -> float:
    n = len(re.findall(r"[aeiouáéíóúü]+", word.lower())) or 1
    if word[-1:] in ",;:":
        n += 0.8                     # pausa corta tras coma
    return n


def _norm(word: str) -> str:
    return re.sub(r"[^\w]", "", word.lower())


def synthesize(script: Script, voice: str, speed: float, gap: float, out_wav) -> Narration:
    engine = _engine()
    chunks, words, starts = [], [], []
    t = 0.0
    silence = np.zeros(int(gap * SR), dtype=np.float32)
    segments = script.segments()
    for i, (text, scene) in enumerate(segments):
        scene_idx = -1 if i == 0 else (-2 if scene is None else i - 1)
        keyword = _norm(scene.palabra_clave) if scene else ""
        starts.append(t)
        for sentence in _sentences(text):
            audio, _ = engine.create(sentence, voice=voice, speed=speed, lang="es")
            audio = _trim(np.asarray(audio, dtype=np.float32))
            dur = len(audio) / SR
            tokens = sentence.split()
            weights = np.array([_syllables(w) for w in tokens])
            edges = t + np.concatenate([[0], np.cumsum(weights)]) / weights.sum() * dur
            for w, a, b in zip(tokens, edges[:-1], edges[1:]):
                words.append(Word(w, float(a), float(b), scene_idx,
                                  keyword=bool(keyword) and _norm(w) == keyword))
            chunks += [audio, silence]
            t += dur + gap
        # Pausa algo mayor entre bloques.
        chunks.append(silence)
        t += gap
    audio = np.concatenate(chunks)
    sf.write(out_wav, audio, SR)
    return Narration(words, starts, len(audio) / SR)
