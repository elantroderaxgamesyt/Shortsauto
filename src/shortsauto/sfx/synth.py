"""Efectos de sonido sintetizados (sin archivos externos)."""
import numpy as np
from scipy.signal import butter, sosfilt

SR = 44100


def _t(seconds: float) -> np.ndarray:
    return np.arange(int(seconds * SR)) / SR


def _bandpass_sweep(noise: np.ndarray, f0: float, f1: float, chunks: int = 40) -> np.ndarray:
    out = np.zeros_like(noise)
    size = len(noise) // chunks
    for i in range(chunks):
        f = f0 + (f1 - f0) * i / (chunks - 1)
        sos = butter(2, [f * 0.7, min(f * 1.4, SR / 2.1)], btype="band", fs=SR, output="sos")
        seg = slice(i * size, (i + 1) * size if i < chunks - 1 else len(noise))
        out[seg] = sosfilt(sos, noise[seg])
    return out


def whoosh(rng) -> np.ndarray:
    t = _t(0.55)
    env = np.sin(np.pi * t / t[-1]) ** 2
    return _bandpass_sweep(rng.standard_normal(len(t)), 300, 4000) * env * 1.6


def riser(rng) -> np.ndarray:
    t = _t(1.2)
    env = (t / t[-1]) ** 2
    tone = np.sin(2 * np.pi * np.cumsum(200 + 900 * (t / t[-1]) ** 2) / SR)
    return (0.5 * _bandpass_sweep(rng.standard_normal(len(t)), 400, 6000) + 0.4 * tone) * env


def pop(rng) -> np.ndarray:
    t = _t(0.12)
    f = 900 * np.exp(-t * 25) + 300
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 35)


def impacto(rng) -> np.ndarray:
    t = _t(1.0)
    boom = np.sin(2 * np.pi * np.cumsum(40 + 80 * np.exp(-t * 12)) / SR) * np.exp(-t * 4)
    crack = rng.standard_normal(len(t)) * np.exp(-t * 30) * 0.4
    return boom + crack


def click(rng) -> np.ndarray:
    t = _t(0.03)
    return rng.standard_normal(len(t)) * np.exp(-t * 300) * 0.8


SOUNDS = {"whoosh": whoosh, "riser": riser, "pop": pop, "impacto": impacto, "click": click}


def build_track(events: list[tuple[float, str]], duration: float, seed: int = 0) -> np.ndarray:
    """events: (segundo, nombre). Los whoosh/riser se adelantan para culminar en el corte."""
    rng = np.random.default_rng(seed)
    track = np.zeros(int(duration * SR) + SR, np.float32)
    for at, name in events:
        if name not in SOUNDS:
            continue
        s = SOUNDS[name](rng).astype(np.float32)
        lead = {"whoosh": 0.3, "riser": 1.1}.get(name, 0.0)
        i = max(0, int((at - lead) * SR))
        end = min(len(track), i + len(s))
        track[i:end] += s[: end - i]
    track = track[: int(duration * SR)]
    peak = np.abs(track).max()
    return track / peak * 0.8 if peak > 0 else track
