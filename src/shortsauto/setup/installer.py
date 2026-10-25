"""Lo que hace el asistente de primer arranque: decidir e instalar lo que falta."""
import importlib.util
import logging
import subprocess
import sys
from dataclasses import dataclass
from typing import Callable

from . import hardware, models

log = logging.getLogger(__name__)

TORCH_INDEX = "https://download.pytorch.org/whl/cu124"
GPU_PACKAGES = ["diffusers>=0.31", "transformers>=4.46", "accelerate", "safetensors",
                "huggingface_hub", "peft"]


@dataclass
class Step:
    key: str
    label: str
    size_gb: float
    done: bool
    optional: bool = False      # si falla, la app sigue funcionando en modo ligero


def plan(hw: hardware.Hardware | None = None) -> tuple[hardware.Hardware, dict, list[Step]]:
    hw = hw or hardware.detect()
    profile = hardware.choose_profile(hw)
    llm = models.REGISTRY[profile["llm"]]
    steps = [
        Step("kokoro", "Voz neuronal (Kokoro)", 0.35, models.REGISTRY["kokoro"].installed()),
        Step("llama-server", "Motor de texto (llama.cpp)", 0.2 if not hw.has_cuda else 0.6,
             models.llama_server_path().exists()),
        Step(llm.key, llm.label, llm.size_gb, llm.installed()),
    ]
    if profile["image"] != "procedural":
        from ..visuals import diffusion
        steps.append(Step("torch", "PyTorch con CUDA", 2.8, importlib.util.find_spec("torch") is not None
                          and importlib.util.find_spec("diffusers") is not None, optional=True))
        steps.append(Step(profile["image"], f"Imágenes con IA ({profile['image']})",
                          diffusion.SPECS[profile["image"]]["gb"],
                          _diffusion_installed(profile["image"]), optional=True))
    return hw, profile, steps


def _diffusion_installed(model: str) -> bool:
    from ..config import MODELS
    flag = MODELS / "hf" / f".{model}.ok"
    return flag.exists()


def run_step(step: Step, hw: hardware.Hardware, progress: Callable[[str, float], None]) -> None:
    def cb(name, done, total):
        progress(f"{step.label}: {name}", done / total if total else 0)

    if step.key == "llama-server":
        models.ensure_llama_server(hw.has_cuda, cb)
    elif step.key in models.REGISTRY:
        models.ensure(step.key, cb)
    elif step.key == "torch":
        progress(f"{step.label}: instalando (puede tardar varios minutos)…", 0)
        _pip(["torch", "--index-url", TORCH_INDEX])
        _pip(GPU_PACKAGES)
    else:
        from ..config import MODELS
        from ..visuals import diffusion
        progress(f"{step.label}: descargando…", 0)
        diffusion.download(step.key)
        (MODELS / "hf" / f".{step.key}.ok").touch()
    progress(step.label, 1.0)


def _pip(args: list[str]) -> None:
    proc = subprocess.run([sys.executable, "-m", "pip", "install", "--no-warn-script-location", *args],
                          capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError("pip falló:\n" + proc.stderr[-1500:])
