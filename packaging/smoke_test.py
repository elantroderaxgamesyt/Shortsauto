"""Prueba completa en una instalación limpia: asistente de modelos + un vídeo con guion del LLM.

Uso: python packaging/smoke_test.py <carpeta de la app>
Los errores se publican como anotaciones de GitHub Actions (visibles sin descargar los logs).
"""
import os
import subprocess
import sys
import time
import traceback
from pathlib import Path

app = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(app / "src"))


def annotate(title: str, text: str) -> None:
    text = text[-6000:].replace("%", "%25").replace("\r", "").replace("\n", "%0A")
    print(f"::error title={title}::{text}", flush=True)


def tail(path: Path, n: int = 40) -> str:
    if not path.exists():
        return f"(no existe {path.name})"
    return "\n".join(path.read_text("utf-8", errors="replace").splitlines()[-n:])


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    from shortsauto.setup import installer

    hw, profile, steps = installer.plan()
    print(f"Hardware: {hw}\nPerfil: {profile}", flush=True)
    last = [0.0]

    def progress(text: str, frac: float) -> None:
        if time.time() - last[0] > 10 or frac >= 1:
            print(f"  {text}: {frac:.0%}", flush=True)
            last[0] = time.time()

    for step in steps:
        if not step.done:
            print(f"Instalando {step.label}…", flush=True)
            try:
                installer.run_step(step, hw, progress)
            except Exception:
                annotate(f"Asistente: {step.label}", traceback.format_exc())
                return 1

    env = dict(os.environ, PYTHONIOENCODING="utf-8")
    result = subprocess.run([sys.executable, str(app / "main.py"), "--tema",
                             "tres datos curiosos sobre los pulpos", "--duracion", "30"],
                            cwd=app, capture_output=True, text=True, encoding="utf-8",
                            errors="replace", env=env)
    print(result.stdout, result.stderr, flush=True)
    videos = list((app / "output").glob("*/video.mp4"))
    print("Vídeos:", videos)
    if result.returncode or not videos:
        annotate("Generación de vídeo", result.stdout[-2500:] + "\n" + result.stderr[-2500:])
        annotate("shortsauto.log", tail(app / "logs" / "shortsauto.log"))
        annotate("llama-server.log", tail(app / "logs" / "llama-server.log", 25))
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        annotate("Prueba", traceback.format_exc())
        sys.exit(1)
