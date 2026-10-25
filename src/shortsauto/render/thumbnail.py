"""Miniatura 1080x1920 con el título sobre el fondo del vídeo."""
import textwrap

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from ..config import FONTS


def make(background: np.ndarray, title: str, keyword: str, size: tuple[int, int], path) -> None:
    W, H = size
    img = Image.fromarray(background).resize(size, Image.LANCZOS).filter(ImageFilter.GaussianBlur(3))
    img = Image.blend(img, Image.new("RGB", size, (0, 0, 0)), 0.25)
    draw = ImageDraw.Draw(img)
    font = ImageFont.truetype(str(FONTS / "Anton-Regular.ttf"), 150)
    lines = textwrap.wrap(title.upper(), width=12)[:5]
    line_h = 175
    y = (H - line_h * len(lines)) // 2 - 100
    kw = keyword.upper()
    for line in lines:
        tw = draw.textlength(line, font=font)
        x = (W - tw) / 2
        for word in line.split(" "):
            color = (255, 225, 0) if kw and kw in word else (255, 255, 255)
            draw.text((x, y), word, font=font, fill=color, stroke_width=10, stroke_fill=(0, 0, 0))
            x += draw.textlength(word + " ", font=font)
        y += line_h
    img.save(path, quality=92)
