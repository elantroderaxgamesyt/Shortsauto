"""Estructura del guion y validación."""
import re
from dataclasses import asdict, dataclass, field

MOODS = ["epico", "misterio", "alegre", "tranquilo", "tenso", "inspirador"]
SFX = ["ninguno", "whoosh", "pop", "impacto", "riser", "click"]

JSON_SCHEMA = {
    "type": "object",
    "properties": {
        "titulo": {"type": "string"},
        "gancho": {"type": "string"},
        "escenas": {
            "type": "array", "minItems": 3, "maxItems": 8,
            "items": {
                "type": "object",
                "properties": {
                    "texto": {"type": "string"},
                    "visual": {"type": "string"},
                    "palabra_clave": {"type": "string"},
                    "sfx": {"enum": SFX},
                },
                "required": ["texto", "visual", "palabra_clave", "sfx"],
            },
        },
        "cta": {"type": "string"},
        "mood": {"enum": MOODS},
        "descripcion": {"type": "string"},
        "hashtags": {"type": "array", "items": {"type": "string"}, "maxItems": 8},
    },
    "required": ["titulo", "gancho", "escenas", "cta", "mood", "descripcion", "hashtags"],
}


@dataclass
class Scene:
    texto: str
    visual: str = ""
    palabra_clave: str = ""
    sfx: str = "whoosh"


@dataclass
class Script:
    titulo: str
    gancho: str
    escenas: list[Scene]
    cta: str
    mood: str = "inspirador"
    descripcion: str = ""
    hashtags: list[str] = field(default_factory=list)

    def segments(self) -> list[tuple[str, Scene | None]]:
        """Bloques narrados en orden: gancho, escenas, CTA."""
        out = [(self.gancho, None)]
        out += [(s.texto, s) for s in self.escenas]
        if self.cta:
            out.append((self.cta, None))
        return out

    def word_count(self) -> int:
        return sum(len(t.split()) for t, _ in self.segments())

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict) -> "Script":
        escenas = [Scene(**{k: v for k, v in e.items() if k in Scene.__dataclass_fields__})
                   for e in d["escenas"]]
        mood = d.get("mood") if d.get("mood") in MOODS else "inspirador"
        for e in escenas:
            if e.sfx not in SFX:
                e.sfx = "whoosh"
        tags = [("#" + t.lstrip("#").replace(" ", "")) for t in d.get("hashtags", []) if t.strip()]
        return cls(d["titulo"].strip(), d["gancho"].strip(), escenas, d.get("cta", "").strip(),
                   mood, d.get("descripcion", "").strip(), tags)

    @classmethod
    def from_text(cls, text: str, titulo: str = "") -> "Script":
        """Guion escrito por el usuario en texto plano: un párrafo o frase por escena."""
        parts = [p.strip() for p in re.split(r"\n\s*\n", text.strip()) if p.strip()]
        if len(parts) < 2:
            parts = [s.strip() for s in re.split(r"(?<=[.!?])\s+", text.strip()) if s.strip()]
        gancho, rest = parts[0], parts[1:]
        escenas = [Scene(p, visual=p, palabra_clave=_longest_word(p)) for p in rest]
        return cls(titulo or gancho[:60], gancho, escenas, "")


def _longest_word(text: str) -> str:
    words = re.findall(r"\w+", text)
    return max(words, key=len) if words else ""
