"""Animación Ken Burns (zoom y paneo suaves) sobre imágenes, con fundidos entre escenas."""
import math
import random

import numpy as np
from PIL import Image


class KenBurns:
    def __init__(self, images: list[tuple[float, float, str]], size: tuple[int, int], fps: int,
                 seed: int = 0):
        """images: (inicio, fin, ruta) en segundos."""
        self.w, self.h = size
        self.fps = fps
        self.items = []
        rng = random.Random(seed)
        for start, end, path in images:
            img = Image.open(path).convert("RGB")
            # Base algo mayor que la salida para poder hacer zoom sin pixelar.
            scale = max(self.w / img.width, self.h / img.height) * 1.25
            img = img.resize((int(img.width * scale), int(img.height * scale)), Image.LANCZOS)
            zoom_in = rng.random() < 0.6
            pan = (rng.uniform(-1, 1), rng.uniform(-1, 1))
            self.items.append((start, end, img, zoom_in, pan))
        # Degradado oscuro abajo para que se lean los subtítulos.
        y = np.linspace(0, 1, self.h, dtype=np.float32)[:, None]
        alpha = 255 * 0.55 * np.clip((y - 0.45) / 0.55, 0, 1) ** 1.5
        self.mask = Image.fromarray(np.repeat(alpha, self.w, axis=1).astype(np.uint8), "L")
        self.black = Image.new("RGB", (self.w, self.h))

    def _render(self, item, t: float) -> Image.Image:
        start, end, img, zoom_in, (px, py) = item
        p = min(1.0, max(0.0, (t - start) / max(0.1, end - start)))
        p = p * p * (3 - 2 * p)                     # suavizado
        z = 1.0 + 0.18 * (p if zoom_in else 1 - p)  # 1.0 = encuadre completo
        cw, ch = img.width / z / 1.0, img.height / z
        cw, ch = min(cw, img.width), min(ch, img.height)
        # Recorte con la proporción de salida.
        ratio = self.w / self.h
        if cw / ch > ratio:
            cw = ch * ratio
        else:
            ch = cw / ratio
        cx = img.width / 2 + px * (img.width - cw) / 2 * (p - 0.5)
        cy = img.height / 2 + py * (img.height - ch) / 2 * (p - 0.5)
        box = (cx - cw / 2, cy - ch / 2, cx + cw / 2, cy + ch / 2)
        return img.resize((self.w, self.h), Image.BILINEAR, box=box)

    def frame(self, t: float) -> np.ndarray:
        idx = max([i for i, it in enumerate(self.items) if t >= it[0]] or [0])
        cur = self._render(self.items[idx], t)
        since = t - self.items[idx][0]
        if idx > 0 and since < 0.3:                 # fundido cruzado
            a = since / 0.3
            cur = Image.blend(self._render(self.items[idx - 1], t), cur, a)
        return np.asarray(Image.composite(self.black, cur, self.mask))

    def frames(self, duration: float):
        for i in range(int(math.ceil(duration * self.fps))):
            yield self.frame(i / self.fps)
