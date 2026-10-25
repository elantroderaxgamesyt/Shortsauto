"""Fondos animados generados por código (modo ligero, sin modelos).

Capas: degradado animado, manchas de color, figura geométrica girando,
palabra clave gigante (tipografía cinética), partículas y viñeta.
"""
import math
import random
from dataclasses import dataclass

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from ..config import FONTS

PALETTES = {
    "epico":      [("#0b0f2e", "#5b1a8c", "#ff7a18"), ("#120c1f", "#a11d33", "#ffcc33")],
    "misterio":   [("#05060f", "#1b2a4a", "#3ae0c5"), ("#0a0614", "#3a1457", "#8f6bff")],
    "alegre":     [("#ff6f91", "#ffc75f", "#ffffff"), ("#00c9a7", "#845ec2", "#fff3a0")],
    "tranquilo":  [("#0f2027", "#2c5364", "#a8e6cf"), ("#1d2b3a", "#4b7a8c", "#f6d5a8")],
    "tenso":      [("#0d0d0d", "#5c0a0a", "#ff3b3b"), ("#101418", "#3d1f00", "#ff8c1a")],
    "inspirador": [("#141e30", "#243b55", "#ffd56b"), ("#2b1055", "#7597de", "#ffffff")],
}


def _rgb(h: str) -> np.ndarray:
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)], dtype=np.float32)


@dataclass
class SceneVisual:
    start: float
    keyword: str


class ProceduralBackground:
    def __init__(self, w: int, h: int, fps: int, mood: str, scenes: list[SceneVisual], seed=None):
        self.w, self.h, self.fps = w, h, fps
        self.scenes = scenes
        rng = random.Random(seed)
        base = PALETTES.get(mood, PALETTES["inspirador"])
        # Una paleta por escena, alternando variantes y rotando ligeramente el tono.
        self.palettes = [[_rgb(c) for c in base[i % len(base)]] for i in range(len(scenes))]
        self.shapes = [rng.choice(["ring", "triangle", "square", "hexagon"]) for _ in scenes]
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        self.xx, self.yy = xx / w, yy / h
        d = np.sqrt((self.xx - 0.5) ** 2 + ((self.yy - 0.5) * h / w) ** 2)
        self.vignette = np.clip(1.15 - d * 0.9, 0.35, 1.0)[..., None]
        self.blobs = [(rng.random() * 6.28, rng.uniform(0.15, 0.35), rng.uniform(0.1, 0.25))
                      for _ in range(4)]
        self.particles = [[rng.random(), rng.random(), rng.uniform(0.02, 0.08), rng.uniform(1, 3.5)]
                          for _ in range(70)]
        self.font = ImageFont.truetype(str(FONTS / "Anton-Regular.ttf"), int(w * 0.3))

    def _scene_at(self, t: float) -> int:
        idx = 0
        for i, s in enumerate(self.scenes):
            if t >= s.start:
                idx = i
        return idx

    def _palette(self, t: float) -> tuple[list[np.ndarray], int, float]:
        i = self._scene_at(t)
        since = t - self.scenes[i].start
        mix = min(1.0, since / 0.5)
        if i == 0 or mix >= 1:
            return self.palettes[i], i, since
        prev, cur = self.palettes[i - 1], self.palettes[i]
        return [p * (1 - mix) + c * mix for p, c in zip(prev, cur)], i, since

    def frame(self, t: float) -> np.ndarray:
        (c1, c2, accent), idx, since = self._palette(t)
        ang = t * 0.15
        g = np.clip((self.xx - 0.5) * math.sin(ang) + (self.yy - 0.5) * math.cos(ang) + 0.5, 0, 1)
        img = c1 * (1 - g[..., None]) + c2 * g[..., None]

        for phase, radius, speed in self.blobs:
            cx = 0.5 + 0.35 * math.sin(t * speed * 2 + phase)
            cy = 0.5 + 0.30 * math.cos(t * speed * 1.3 + phase * 1.7)
            d2 = (self.xx - cx) ** 2 + ((self.yy - cy) * self.h / self.w) ** 2
            img += (accent - img) * (np.exp(-d2 / (radius ** 2)) * 0.35)[..., None]

        img = np.clip(img * self.vignette, 0, 255).astype(np.uint8)
        pil = Image.fromarray(img, "RGB")
        overlay = Image.new("RGBA", pil.size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(overlay)
        ac = tuple(int(v) for v in accent)
        self._shape(draw, self.shapes[idx], t, ac)
        self._keyword(overlay, self.scenes[idx].keyword, since, ac)
        self._particles(draw, t, ac)
        pil = Image.alpha_composite(pil.convert("RGBA"), overlay)

        if since < 0.25 and idx > 0:            # destello en el cambio de escena
            a = int(150 * (1 - since / 0.25))
            pil = Image.alpha_composite(pil, Image.new("RGBA", pil.size, (255, 255, 255, a)))
        return np.asarray(pil.convert("RGB"))

    def _shape(self, draw, kind, t, color):
        cx, cy = self.w / 2, self.h * 0.42
        r = self.w * (0.38 + 0.03 * math.sin(t * 1.4))
        width = max(2, self.w // 90)
        rgba = (*color, 70)
        if kind == "ring":
            draw.ellipse([cx - r, cy - r, cx + r, cy + r], outline=rgba, width=width)
            r2 = r * 0.7
            draw.ellipse([cx - r2, cy - r2, cx + r2, cy + r2], outline=(*color, 40), width=width)
            return
        sides = {"triangle": 3, "square": 4, "hexagon": 6}[kind]
        rot = t * 0.4
        pts = [(cx + r * math.cos(rot + k * 2 * math.pi / sides),
                cy + r * math.sin(rot + k * 2 * math.pi / sides)) for k in range(sides)]
        draw.polygon(pts, outline=rgba, width=width)

    def _keyword(self, overlay, word, since, color):
        if not word:
            return
        word = word.upper()
        scale = 1.0 + 0.04 * since                       # zoom lento
        alpha = int(min(1.0, since / 0.4) * 55)
        bbox = self.font.getbbox(word)
        tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
        layer = Image.new("RGBA", (tw + 20, th + 20), (0, 0, 0, 0))
        ImageDraw.Draw(layer).text((10 - bbox[0], 10 - bbox[1]), word, font=self.font,
                                   fill=(*color, alpha))
        fit = min(scale * self.w * 0.92 / layer.width, 1.6 * scale)
        layer = layer.resize((max(1, int(layer.width * fit)), max(1, int(layer.height * fit))),
                             Image.BILINEAR).filter(ImageFilter.GaussianBlur(1))
        overlay.alpha_composite(layer, ((self.w - layer.width) // 2,
                                        int(self.h * 0.30 - layer.height / 2)))

    def _particles(self, draw, t, color):
        for x0, y0, speed, size in self.particles:
            y = (y0 - t * speed) % 1.0
            x = x0 + 0.02 * math.sin(t + y0 * 10)
            px, py = x * self.w, y * self.h
            a = int(120 * (0.5 + 0.5 * math.sin(t * 2 + x0 * 20)))
            draw.ellipse([px - size, py - size, px + size, py + size], fill=(*color, a))

    def frames(self, duration: float):
        n = int(math.ceil(duration * self.fps))
        for i in range(n):
            yield self.frame(i / self.fps)
