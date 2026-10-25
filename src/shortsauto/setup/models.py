"""Registro de modelos y descargas reanudables."""
import json
import logging
import platform
import urllib.request
from dataclasses import dataclass, field
from pathlib import Path
from typing import Callable

import requests

from ..config import BIN, MODELS

log = logging.getLogger(__name__)

HF = "https://huggingface.co"
KOKORO = "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0"


@dataclass
class ModelSpec:
    key: str
    label: str
    license: str
    files: dict[str, str]           # ruta relativa en /models -> URL
    size_gb: float
    extra: dict = field(default_factory=dict)

    def paths(self) -> list[Path]:
        return [MODELS / rel for rel in self.files]

    def installed(self) -> bool:
        return all(p.exists() for p in self.paths())


REGISTRY: dict[str, ModelSpec] = {
    "kokoro": ModelSpec(
        "kokoro", "Kokoro-82M (voz)", "Apache-2.0",
        {"tts/kokoro-v1.0.onnx": f"{KOKORO}/kokoro-v1.0.onnx",
         "tts/voices-v1.0.bin": f"{KOKORO}/voices-v1.0.bin"},
        0.35,
    ),
    "qwen3-1.7b": ModelSpec(
        "qwen3-1.7b", "Qwen3 1.7B (guion)", "Apache-2.0",
        {"llm/Qwen3-1.7B-Q8_0.gguf": f"{HF}/Qwen/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q8_0.gguf"},
        1.8,
    ),
    "qwen3-4b": ModelSpec(
        "qwen3-4b", "Qwen3 4B (guion)", "Apache-2.0",
        {"llm/Qwen3-4B-Q4_K_M.gguf": f"{HF}/Qwen/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf"},
        2.5,
    ),
    "qwen3-8b": ModelSpec(
        "qwen3-8b", "Qwen3 8B (guion)", "Apache-2.0",
        {"llm/Qwen3-8B-Q4_K_M.gguf": f"{HF}/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf"},
        5.0,
    ),
}


def llm_file(key: str) -> Path:
    return REGISTRY[key].paths()[0]


def download(url: str, dest: Path, progress: Callable[[int, int], None] | None = None) -> None:
    """Descarga con reanudación: escribe en .part y continúa con Range si se cortó."""
    dest.parent.mkdir(parents=True, exist_ok=True)
    part = dest.with_suffix(dest.suffix + ".part")
    done = part.stat().st_size if part.exists() else 0
    headers = {"Range": f"bytes={done}-"} if done else {}
    with requests.get(url, headers=headers, stream=True, timeout=60) as r:
        if r.status_code == 416:            # ya estaba completo
            part.replace(dest)
            return
        r.raise_for_status()
        if done and r.status_code != 206:   # el servidor no admite Range
            done = 0
        total = int(r.headers.get("Content-Length", 0)) + done
        with open(part, "ab" if done else "wb") as f:
            for chunk in r.iter_content(chunk_size=1 << 20):
                f.write(chunk)
                done += len(chunk)
                if progress:
                    progress(done, total)
    part.replace(dest)


def ensure(key: str, progress: Callable[[str, int, int], None] | None = None) -> ModelSpec:
    spec = REGISTRY[key]
    for rel, url in spec.files.items():
        dest = MODELS / rel
        if dest.exists():
            continue
        log.info("Descargando %s -> %s", url, dest)
        download(url, dest, (lambda d, t, rel=rel: progress(rel, d, t)) if progress else None)
    return spec


# --- llama.cpp (llama-server) ---------------------------------------------

def llama_server_path() -> Path:
    name = "llama-server.exe" if platform.system() == "Windows" else "llama-server"
    for p in [BIN / "llama" / name, BIN / name]:
        if p.exists():
            return p
    return BIN / "llama" / name


def llama_asset_suffix(cuda: bool) -> str:
    system = platform.system()
    if system == "Windows":
        return "bin-win-cuda-12.4-x64.zip" if cuda else "bin-win-cpu-x64.zip"
    if system == "Linux":
        return "bin-ubuntu-vulkan-x64.zip" if cuda else "bin-ubuntu-x64.zip"
    return "bin-macos-arm64.zip"


def ensure_llama_server(cuda: bool, progress=None) -> Path:
    """Descarga la última versión precompilada de llama.cpp desde GitHub."""
    exe = llama_server_path()
    if exe.exists():
        return exe
    import zipfile

    with urllib.request.urlopen(
        "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest", timeout=30
    ) as r:
        release = json.load(r)
    wanted = [llama_asset_suffix(cuda)]
    if cuda and platform.system() == "Windows":
        wanted.append("cudart-llama-bin-win-cuda-12.4-x64.zip")   # DLLs de CUDA
    target = BIN / "llama"
    for suffix in wanted:
        asset = next(a for a in release["assets"] if a["name"].endswith(suffix)
                     and (suffix.startswith("cudart") or not a["name"].startswith("cudart")))
        zpath = BIN / asset["name"]
        download(asset["browser_download_url"], zpath,
                 (lambda d, t, n=asset["name"]: progress(n, d, t)) if progress else None)
        with zipfile.ZipFile(zpath) as z:
            for member in z.infolist():
                if member.is_dir():
                    continue
                # Los zips traen a veces una carpeta build/bin/; aplanamos.
                out = target / Path(member.filename).name
                out.parent.mkdir(parents=True, exist_ok=True)
                out.write_bytes(z.read(member))
        zpath.unlink()
    if platform.system() != "Windows":
        for f in target.iterdir():
            f.chmod(0o755)
    return exe
