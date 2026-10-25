"""Subtítulos karaoke (.ass, quemados con libass) y .srt."""
from ..tts.kokoro_tts import Narration, Word


def _ts(t: float) -> str:
    cs = int(round(t * 100))
    h, cs = divmod(cs, 360000)
    m, cs = divmod(cs, 6000)
    s, cs = divmod(cs, 100)
    return f"{h}:{m:02d}:{s:02d}.{cs:02d}"


def _srt_ts(t: float) -> str:
    ms = int(round(t * 1000))
    h, ms = divmod(ms, 3600000)
    m, ms = divmod(ms, 60000)
    s, ms = divmod(ms, 1000)
    return f"{h:02d}:{m:02d}:{s:02d},{ms:03d}"


def _clean(text: str) -> str:
    return text.replace("{", "(").replace("}", ")").upper()


def group_words(words: list[Word], size: int) -> list[list[Word]]:
    """Grupos de hasta `size` palabras; cortamos en puntuación y entre bloques."""
    groups, cur = [], []
    for w in words:
        if cur and (len(cur) >= size or w.scene != cur[-1].scene):
            groups.append(cur)
            cur = []
        cur.append(w)
        if w.text[-1:] in ".!?,;:…":
            groups.append(cur)
            cur = []
    if cur:
        groups.append(cur)
    return groups


def write_ass(narr: Narration, cfg: dict, video: dict, title: str, path) -> None:
    W, H = video["ancho"], video["alto"]
    y = int(H * cfg["posicion_y"])
    size, border = cfg["tamano"], cfg["borde"]
    base, active = cfg["color"], cfg["color_activo"]
    lines = [
        "[Script Info]", "ScriptType: v4.00+", f"PlayResX: {W}", f"PlayResY: {H}",
        "WrapStyle: 0", "ScaledBorderAndShadow: yes", "",
        "[V4+ Styles]",
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, "
        "BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, "
        "BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
        f"Style: Sub,{cfg['fuente']},{size},{base},{base},&H00000000,&H80000000,"
        f"0,0,0,0,100,100,2,0,1,{border},4,5,60,60,0,1",
        f"Style: Title,{cfg['fuente']},{int(size * 0.8)},&H00FFFFFF,&H00FFFFFF,&H00000000,"
        f"&HA0000000,0,0,0,0,100,100,1,0,3,18,0,8,70,70,{int(H * 0.12)},1",
        "", "[Events]",
        "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text",
    ]
    # Título del gancho arriba durante los primeros segundos (caja opaca).
    hook_end = narr.scene_starts[1] if len(narr.scene_starts) > 1 else 3.0
    lines.append(f"Dialogue: 1,{_ts(0)},{_ts(min(hook_end, 4.0))},Title,,0,0,0,,"
                 f"{{\\fad(150,250)}}{_clean(title)}")

    for group in group_words(narr.words, cfg["palabras_por_grupo"]):
        start = group[0].start
        end = group[-1].end + 0.05
        pos = f"\\an5\\pos({W // 2},{y})"
        if cfg["estilo"] == "simple":
            text = " ".join(_clean(w.text) for w in group)
            lines.append(f"Dialogue: 0,{_ts(start)},{_ts(end)},Sub,,0,0,0,,{{{pos}}}{text}")
            continue
        # Una línea por palabra activa: la palabra que suena va en color y algo más grande.
        for i, w in enumerate(group):
            parts = []
            for j, other in enumerate(group):
                word = _clean(other.text)
                if j == i:
                    color = "&H004CFF5A" if other.keyword else active
                    parts.append(f"{{\\c{color}\\fscx112\\fscy112}}{word}{{\\c{base}\\fscx100\\fscy100}}")
                else:
                    parts.append(word)
            pop = "\\fscx92\\fscy92\\t(0,80,\\fscx100\\fscy100)" if i == 0 else ""
            w_end = group[i + 1].start if i + 1 < len(group) else end
            lines.append(f"Dialogue: 0,{_ts(w.start)},{_ts(w_end)},Sub,,0,0,0,,"
                         f"{{{pos}{pop}}}" + " ".join(parts))
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def write_srt(narr: Narration, path, size: int = 6) -> None:
    out = []
    for n, g in enumerate(group_words(narr.words, size), 1):
        out += [str(n), f"{_srt_ts(g[0].start)} --> {_srt_ts(g[-1].end)}",
                " ".join(w.text for w in g), ""]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out))
