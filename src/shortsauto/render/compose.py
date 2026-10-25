"""Montaje final: fondo + subtítulos + voz + música con ducking + SFX, normalizado."""
import shutil
import subprocess
from pathlib import Path
from typing import Callable, Iterator

import numpy as np

from ..config import FONTS
from .ffmpeg import ffmpeg, video_encoder


def render(job: Path, frames: Iterator[np.ndarray], frame_size: tuple[int, int], cfg: dict,
           duration: float, total_frames: int, progress: Callable[[float], None] | None = None,
           out_name: str = "video.mp4") -> Path:
    v, mus, sfx, audio = cfg["video"], cfg["musica"], cfg["sfx"], cfg["audio"]
    w, h = frame_size
    # libass necesita la carpeta de fuentes; usamos rutas relativas al job para
    # evitar el escapado de "C:\" en los filtros de FFmpeg en Windows.
    fonts = job / "_fonts"
    shutil.copytree(FONTS, fonts, dirs_exist_ok=True, ignore=shutil.ignore_patterns("*.txt"))

    music_vol = mus["volumen"] if (job / "music.wav").exists() else 0
    sfx_vol = sfx["volumen"] if sfx["activado"] and (job / "sfx.wav").exists() else 0
    duck = ("[m][sc]sidechaincompress=threshold=0.02:ratio=10:attack=15:release=350:makeup=1[md]"
            if mus.get("ducking", True) else "[m]anull[md];[sc]anullsink")
    graph = ";".join([
        f"[0:v]scale={v['ancho']}:{v['alto']}:flags=lanczos,ass=subs.ass:fontsdir=_fonts,format=yuv420p[v]",
        "[1:a]aresample=44100,aformat=channel_layouts=stereo,apad,asplit=2[voice][sc]",
        f"[2:a]aresample=44100,aformat=channel_layouts=stereo,volume={music_vol}[m]",
        duck,
        f"[3:a]aresample=44100,aformat=channel_layouts=stereo,volume={sfx_vol}[s]",
        "[voice][md][s]amix=inputs=3:normalize=0:duration=first,"
        f"loudnorm=I={audio['loudness_lufs']}:TP=-1.5:LRA=11,aresample=48000[a]",
    ])

    def audio_input(name: str) -> list[str]:
        p = job / name
        if p.exists():
            return ["-i", name]
        return ["-f", "lavfi", "-t", str(duration), "-i", "anullsrc=r=44100:cl=stereo"]

    cmd = [ffmpeg(), "-hide_banner", "-loglevel", "error", "-y",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{w}x{h}", "-r", str(v["fps"]), "-i", "-",
           "-i", "voice.wav", *audio_input("music.wav"), *audio_input("sfx.wav"),
           "-filter_complex", graph, "-map", "[v]", "-map", "[a]",
           *video_encoder(), "-r", str(v["fps"]), "-c:a", "aac", "-b:a", "192k",
           "-t", f"{duration:.3f}", "-movflags", "+faststart", out_name]
    proc = subprocess.Popen(cmd, cwd=job, stdin=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        for i, frame in enumerate(frames):
            proc.stdin.write(frame.tobytes())
            if progress and i and i % 15 == 0:
                progress(i / total_frames)
        proc.stdin.close()
    except BrokenPipeError:
        pass
    err = proc.stderr.read().decode(errors="replace")
    if proc.wait() != 0:
        raise RuntimeError("FFmpeg falló al montar el vídeo:\n" + err[-2000:])
    shutil.rmtree(fonts, ignore_errors=True)
    return job / out_name
