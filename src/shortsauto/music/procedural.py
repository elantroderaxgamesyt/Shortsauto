"""Compositor procedural: genera música original según el mood (sin modelos)."""
import math

import numpy as np
from scipy.signal import butter, fftconvolve, sosfilt

SR = 44100

# mood -> bpm, tónica (MIDI), escala, progresión (grados), patrón de batería, brillo del pad
MOODS = {
    "epico":      dict(bpm=120, root=50, scale="minor", prog=[0, 5, 2, 6], drums="driving", cutoff=2600),
    "misterio":   dict(bpm=90,  root=45, scale="minor", prog=[0, 5, 0, 4], drums="sparse",  cutoff=1400),
    "alegre":     dict(bpm=118, root=55, scale="major", prog=[0, 4, 5, 3], drums="four",    cutoff=3500),
    "tranquilo":  dict(bpm=80,  root=53, scale="major", prog=[0, 5, 3, 4], drums="none",    cutoff=1800),
    "tenso":      dict(bpm=128, root=47, scale="minor", prog=[0, 1, 0, 6], drums="driving", cutoff=2000),
    "inspirador": dict(bpm=100, root=52, scale="major", prog=[3, 4, 0, 5], drums="four",    cutoff=3000),
}
SCALES = {"major": [0, 2, 4, 5, 7, 9, 11], "minor": [0, 2, 3, 5, 7, 8, 10]}


def _hz(midi: float) -> float:
    return 440.0 * 2 ** ((midi - 69) / 12)


def _chord(root: int, scale: list[int], degree: int) -> list[int]:
    notes = []
    for k in (0, 2, 4):
        d = degree + k
        notes.append(root + scale[d % 7] + 12 * (d // 7))
    return notes


def _saw(freq: float, n: int, harmonics: int = 12) -> np.ndarray:
    t = np.arange(n) / SR
    out = np.zeros(n, dtype=np.float32)
    for k in range(1, harmonics + 1):
        if freq * k > SR / 2.2:
            break
        out += (np.sin(2 * np.pi * freq * k * t) / k).astype(np.float32)
    return out


def _env(n: int, attack: float, release: float) -> np.ndarray:
    a, r = max(1, int(attack * SR)), max(1, int(release * SR))
    e = np.ones(n, dtype=np.float32)
    e[:a] = np.linspace(0, 1, min(a, n))
    e[-r:] *= np.linspace(1, 0, min(r, n))
    return e


def _lowpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    return sosfilt(butter(2, cutoff, fs=SR, output="sos"), x).astype(np.float32)


def _highpass(x: np.ndarray, cutoff: float) -> np.ndarray:
    return sosfilt(butter(2, cutoff, btype="high", fs=SR, output="sos"), x).astype(np.float32)


def _kick(rng) -> np.ndarray:
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    freq = 45 + 110 * np.exp(-t * 30)
    return (np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t * 9)).astype(np.float32)


def _snare(rng) -> np.ndarray:
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    noise = _highpass(rng.standard_normal(n).astype(np.float32), 1500) * np.exp(-t * 18)
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25)
    return (0.6 * noise + 0.4 * body).astype(np.float32)


def _hat(rng) -> np.ndarray:
    n = int(0.06 * SR)
    t = np.arange(n) / SR
    return (_highpass(rng.standard_normal(n).astype(np.float32), 7000) * np.exp(-t * 70)).astype(np.float32)


def _place(track: np.ndarray, sample: np.ndarray, at: int, gain: float) -> None:
    if at >= len(track):
        return
    end = min(len(track), at + len(sample))
    track[at:end] += sample[: end - at] * gain


def _reverb(x: np.ndarray, rng, seconds=1.8, wet=0.3) -> np.ndarray:
    n = int(seconds * SR)
    ir = rng.standard_normal(n).astype(np.float32) * np.exp(-np.arange(n) / SR * 4)
    ir = _lowpass(ir, 5000)
    tail = fftconvolve(x, ir)[: len(x)]
    tail /= (np.abs(tail).max() + 1e-9)
    return x * (1 - wet) + tail * wet * np.abs(x).max()


def compose(mood: str, duration: float, seed: int = 0) -> np.ndarray:
    """Devuelve audio estéreo float32 (n, 2) a 44.1 kHz."""
    p = MOODS.get(mood, MOODS["inspirador"])
    rng = np.random.default_rng(seed)
    scale = SCALES[p["scale"]]
    beat = 60 / p["bpm"]
    bar = 4 * beat
    total = int((duration + 2) * SR)
    n_bars = math.ceil((duration + 2) / bar)
    pad = np.zeros(total, np.float32)
    bass = np.zeros(total, np.float32)
    arp_l = np.zeros(total, np.float32)
    arp_r = np.zeros(total, np.float32)
    drums = np.zeros(total, np.float32)
    kick, snare, hat = _kick(rng), _snare(rng), _hat(rng)

    # Patrón de arpegio aleatorio pero fijo para todo el tema (memorable).
    arp_pattern = rng.choice([0, 1, 2, 3, 2, 1], size=8)
    for b in range(n_bars):
        chord = _chord(p["root"], scale, p["prog"][b % len(p["prog"])])
        start = int(b * bar * SR)
        n = min(int(bar * SR), total - start)
        if n <= 0:
            break
        # Pad: tres voces de sierra desafinadas, filtradas.
        seg = np.zeros(n, np.float32)
        for note in chord:
            for detune in (-0.08, 0.08):
                seg += _saw(_hz(note + 12 + detune), n, 8)
        pad[start:start + n] += _lowpass(seg, p["cutoff"]) * _env(n, 0.3, 0.3) * 0.08
        # Bajo en corcheas (o negras si es tranquilo).
        step = beat / 2 if p["drums"] in ("driving", "four") else beat
        steps = int(round(bar / step))
        for s in range(steps):
            at = start + int(s * step * SR)
            ln = int(step * SR * 0.9)
            t = np.arange(ln) / SR
            f = _hz(chord[0] - 12)
            note = (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t)) * np.exp(-t * 3)
            _place(bass, (note * _env(ln, 0.005, 0.03)).astype(np.float32), at, 0.28)
        # Arpegio en semicorcheas a partir del compás 2.
        if b >= 1:
            notes = chord + [chord[0] + 12]
            for s in range(16):
                at = start + int(s * beat / 4 * SR)
                ln = int(beat / 4 * SR * 1.8)
                t = np.arange(ln) / SR
                f = _hz(notes[arp_pattern[s % 8]] + 24)
                tone = (2 / np.pi * np.arcsin(np.sin(2 * np.pi * f * t))) * np.exp(-t * 14)
                _place(arp_l if s % 2 == 0 else arp_r, tone.astype(np.float32), at, 0.07)
        # Batería (entra en el compás 2 para dejar una intro).
        if b >= 2 and p["drums"] != "none":
            for q in range(4):
                at = start + int(q * beat * SR)
                if p["drums"] == "four" or (p["drums"] == "driving" and q in (0, 2)) \
                        or (p["drums"] == "sparse" and q == 0):
                    _place(drums, kick, at, 0.55)
                if q in (1, 3) and p["drums"] != "sparse":
                    _place(drums, snare, at, 0.30)
                for e in (0, 0.5):
                    _place(drums, hat, at + int(e * beat * SR), 0.12 if e else 0.07)

    pad = _reverb(pad, rng, wet=0.35)
    arp_l, arp_r = _reverb(arp_l, rng, wet=0.3), _reverb(arp_r, rng, wet=0.3)
    left = pad + bass + drums + arp_l * 1.0 + arp_r * 0.45
    right = pad + bass + drums + arp_r * 1.0 + arp_l * 0.45
    mix = np.stack([left, right], axis=1)[: int(duration * SR)]
    fade = int(1.5 * SR)
    mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
    mix[: int(0.3 * SR)] *= np.linspace(0, 1, int(0.3 * SR))[:, None]
    return (mix / (np.abs(mix).max() + 1e-9) * 0.89).astype(np.float32)
