"""Prueba completa en una instalación limpia: asistente de modelos + un vídeo con guion del LLM.

Uso: python packaging/smoke_test.py <carpeta de la app>
"""
import subprocess
import sys
import time
from pathlib import Path

app = Path(sys.argv[1]).resolve()
sys.path.insert(0, str(app / "src"))

from shortsauto.setup import installer  # noqa: E402

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
        installer.run_step(step, hw, progress)

result = subprocess.run([sys.executable, str(app / "main.py"), "--tema",
                         "tres datos curiosos sobre los pulpos", "--duracion", "30"], cwd=app)
videos = list((app / "output").glob("*/video.mp4"))
print("Vídeos:", videos)
sys.exit(result.returncode or (0 if videos else 1))
