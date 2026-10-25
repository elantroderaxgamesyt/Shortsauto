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
    files: dict[str, list[str]]     # ruta relativa en /models -> URLs (la primera que funcione)
    size_gb: float
    extra: dict = field(default_factory=dict)

    def paths(self) -> list[Path]:
        return [MODELS / rel for rel in self.files]

    def installed(self) -> bool:
        return all(p.exists() for p in self.paths())


def _qwen(size: str, quant: str) -> list[str]:
    """Repositorio oficial de Qwen y dos espejos conocidos por si cambia el nombre."""
    return [f"{HF}/Qwen/Qwen3-{size}-GGUF/resolve/main/Qwen3-{size}-{quant}.gguf",
            f"{HF}/unsloth/Qwen3-{size}-GGUF/resolve/main/Qwen3-{size}-{quant}.gguf",
            f"{HF}/bartowski/Qwen_Qwen3-{size}-GGUF/resolve/main/Qwen_Qwen3-{size}-{quant}.gguf"]


REGISTRY: dict[str, ModelSpec] = {
    "kokoro": ModelSpec(
        "kokoro", "Kokoro-82M (voz)", "Apache-2.0",
        {"tts/kokoro-v1.0.onnx": [f"{KOKORO}/kokoro-v1.0.onnx"],
         "tts/voices-v1.0.bin": [f"{KOKORO}/voices-v1.0.bin"]},
        0.35,
    ),
    "qwen3-1.7b": ModelSpec("qwen3-1.7b", "Qwen3 1.7B (guion)", "Apache-2.0",
                            {"llm/Qwen3-1.7B-Q8_0.gguf": _qwen("1.7B", "Q8_0")}, 1.8),
    "qwen3-4b": ModelSpec("qwen3-4b", "Qwen3 4B (guion)", "Apache-2.0",
                          {"llm/Qwen3-4B-Q4_K_M.gguf": _qwen("4B", "Q4_K_M")}, 2.5),
    "qwen3-8b": ModelSpec("qwen3-8b", "Qwen3 8B (guion)", "Apache-2.0",
                          {"llm/Qwen3-8B-Q4_K_M.gguf": _qwen("8B", "Q4_K_M")}, 5.0),
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
    for rel, urls in spec.files.items():
        dest = MODELS / rel
        if dest.exists():
            continue
        errors = []
        for url in urls:
            log.info("Descargando %s -> %s", url, dest)
            try:
                download(url, dest, (lambda d, t, rel=rel: progress(rel, d, t)) if progress else None)
                break
            except requests.HTTPError as e:      # 404 u otro: probamos el siguiente espejo
                errors.append(f"{url}: {e}")
                dest.with_suffix(dest.suffix + ".part").unlink(missing_ok=True)
        else:
            raise RuntimeError(f"No se pudo descargar {rel}:\n" + "\n".join(errors))
    return spec


# --- llama.cpp (llama-server) ---------------------------------------------

def llama_server_path() -> Path:
    name = "llama-server.exe" if platform.system() == "Windows" else "llama-server"
    for p in [BIN / "llama" / name, BIN / name]:
        if p.exists():
            return p
    return BIN / "llama" / name


def _pick_asset(assets: list[dict], cuda: bool) -> list[dict]:
    """Elige el zip de llama.cpp para este sistema (y las DLL de CUDA en Windows)."""
    import re
    names = {a["name"]: a for a in assets}
    system = platform.system()
    if system == "Windows":
        if cuda:
            builds = sorted(n for n in names if re.search(r"^llama-.*-bin-win-cuda-[\d.]+-x64\.zip$", n))
            if builds:
                version = re.search(r"cuda-([\d.]+)-x64", builds[0]).group(1)
                cudart = [n for n in names if n.startswith("cudart-") and f"cuda-{version}-x64" in n]
                return [names[builds[0]]] + [names[n] for n in cudart[:1]]
        pattern = r"^llama-.*-bin-win-(cpu-)?x64\.zip$"
    elif system == "Linux":
        pattern = r"^llama-.*-bin-ubuntu-x64\.(zip|tar\.gz)$"
    else:
        pattern = r"^llama-.*-bin-macos-arm64\.(zip|tar\.gz)$"
    found = [n for n in names if re.search(pattern, n)]
    if not found:
        raise RuntimeError("No encontré llama.cpp para este sistema entre: " + ", ".join(names))
    return [names[found[0]]]


def ensure_llama_server(cuda: bool, progress=None) -> Path:
    """Descarga la última versión precompilada de llama.cpp desde GitHub."""
    exe = llama_server_path()
    if exe.exists():
        return exe
    import tarfile
    import zipfile

    with urllib.request.urlopen(
        "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest", timeout=30
    ) as r:
        release = json.load(r)
    target = BIN / "llama"
    target.mkdir(parents=True, exist_ok=True)
    for asset in _pick_asset(release["assets"], cuda):
        archive = BIN / asset["name"]
        download(asset["browser_download_url"], archive,
                 (lambda d, t, n=asset["name"]: progress(n, d, t)) if progress else None)
        # Los paquetes traen a veces una carpeta build/bin/; aplanamos.
        if archive.name.endswith(".zip"):
            with zipfile.ZipFile(archive) as z:
                for m in z.infolist():
                    if not m.is_dir():
                        (target / Path(m.filename).name).write_bytes(z.read(m))
        else:
            with tarfile.open(archive) as t:
                for m in t.getmembers():
                    if m.isfile():
                        (target / Path(m.name).name).write_bytes(t.extractfile(m).read())
        archive.unlink()
    if platform.system() != "Windows":
        for f in target.iterdir():
            f.chmod(0o755)
    if not exe.exists():
        raise RuntimeError(f"El paquete de llama.cpp no contenía {exe.name}")
    return exe
