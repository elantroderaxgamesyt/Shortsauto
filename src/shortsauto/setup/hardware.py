"""Detección de hardware y elección del perfil de modelos."""
import shutil
import subprocess
from dataclasses import dataclass

import psutil


@dataclass
class Hardware:
    cpu_cores: int
    ram_gb: float
    gpu_name: str | None
    vram_gb: float

    @property
    def has_cuda(self) -> bool:
        return self.gpu_name is not None and self.vram_gb >= 3.5


def _nvidia_gpu() -> tuple[str | None, float]:
    exe = shutil.which("nvidia-smi")
    if not exe:
        return None, 0.0
    try:
        out = subprocess.run(
            [exe, "--query-gpu=name,memory.total", "--format=csv,noheader,nounits"],
            capture_output=True, text=True, timeout=10, check=True,
        ).stdout.strip().splitlines()
    except (subprocess.SubprocessError, OSError):
        return None, 0.0
    if not out:
        return None, 0.0
    # Si hay varias GPU, la de más memoria.
    best = max((line.rsplit(",", 1) for line in out), key=lambda p: float(p[1]))
    return best[0].strip(), float(best[1]) / 1024


def detect() -> Hardware:
    name, vram = _nvidia_gpu()
    return Hardware(
        cpu_cores=psutil.cpu_count(logical=False) or psutil.cpu_count() or 1,
        ram_gb=psutil.virtual_memory().total / 1024**3,
        gpu_name=name,
        vram_gb=vram,
    )


def choose_profile(hw: Hardware) -> dict:
    """Devuelve qué modelo usar en cada etapa según el hardware."""
    if hw.vram_gb >= 10:
        llm, image, music = "qwen3-8b", "sdxl-lightning", "procedural"
    elif hw.vram_gb >= 6:
        llm, image, music = "qwen3-4b", "sdxl-lightning", "procedural"
    elif hw.vram_gb >= 3.5:
        llm, image, music = "qwen3-4b", "sd15-lcm", "procedural"
    else:
        llm = "qwen3-4b" if hw.ram_gb >= 12 else "qwen3-1.7b"
        image, music = "procedural", "procedural"
    return {"llm": llm, "tts": "kokoro", "image": image, "music": music}
