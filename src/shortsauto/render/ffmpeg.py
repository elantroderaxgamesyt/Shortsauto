"""Localiza FFmpeg y elige el codificador de vídeo."""
import functools
import platform
import shutil
import subprocess
from pathlib import Path

from ..config import BIN


@functools.cache
def ffmpeg() -> str:
    name = "ffmpeg.exe" if platform.system() == "Windows" else "ffmpeg"
    local = BIN / name
    if local.exists():
        return str(local)
    found = shutil.which("ffmpeg")
    if found:
        return found
    raise RuntimeError("No se encontró FFmpeg. Reinstala la aplicación.")


@functools.cache
def video_encoder() -> list[str]:
    """NVENC si funciona de verdad (no basta con que esté compilado), si no x264."""
    test = [ffmpeg(), "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i",
            "color=c=black:s=256x256:d=0.2", "-c:v", "h264_nvenc", "-f", "null", "-"]
    try:
        if subprocess.run(test, capture_output=True, timeout=30).returncode == 0:
            return ["-c:v", "h264_nvenc", "-preset", "p5", "-cq", "21", "-b:v", "0"]
    except (subprocess.SubprocessError, OSError):
        pass
    return ["-c:v", "libx264", "-preset", "veryfast", "-crf", "20"]


def run(args: list[str], cwd: Path | None = None, input_bytes=None) -> None:
    proc = subprocess.run([ffmpeg(), "-hide_banner", "-loglevel", "error", "-y", *args],
                          cwd=cwd, input=input_bytes, capture_output=True)
    if proc.returncode != 0:
        raise RuntimeError("FFmpeg falló:\n" + proc.stderr.decode(errors="replace")[-2000:])
