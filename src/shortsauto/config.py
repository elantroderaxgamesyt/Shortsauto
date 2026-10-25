"""Rutas de la aplicación y carga de config.yaml."""
import copy
import sys
from pathlib import Path

import yaml


def app_root() -> Path:
    # Empaquetada: junto al ejecutable. En desarrollo: raíz del repositorio.
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parents[2]


ROOT = app_root()
MODELS = ROOT / "models"
ASSETS = ROOT / "assets"
FONTS = ASSETS / "fonts"
BIN = ROOT / "bin"
LOGS = ROOT / "logs"


def load_config(path: Path | None = None) -> dict:
    path = path or ROOT / "config.yaml"
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def merge(base: dict, overrides: dict) -> dict:
    """Mezcla recursiva; los valores None de overrides se ignoran."""
    out = copy.deepcopy(base)
    for key, value in overrides.items():
        if value is None:
            continue
        if isinstance(value, dict) and isinstance(out.get(key), dict):
            out[key] = merge(out[key], value)
        else:
            out[key] = value
    return out
