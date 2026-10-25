"""ShortsAuto: crea Shorts verticales 100% en local.

Sin argumentos abre la interfaz gráfica. Ejemplos de línea de comandos:
  python main.py --tema "datos curiosos de Marte" --duracion 45
  python main.py --sorprendeme
  python main.py --guion mi_guion.txt
  python main.py --lote temas.txt
  python main.py --reanudar output/2026-10-25_120000_marte
"""
import argparse
import json
import logging
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "src"))

from shortsauto.config import LOGS, load_config, merge  # noqa: E402


def setup_logging() -> None:
    LOGS.mkdir(exist_ok=True)
    logging.basicConfig(
        level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s",
        handlers=[logging.FileHandler(LOGS / "shortsauto.log", encoding="utf-8"),
                  logging.StreamHandler()])


def main() -> int:
    ap = argparse.ArgumentParser(description="Generador de Shorts 100% local")
    ap.add_argument("--tema")
    ap.add_argument("--sorprendeme", action="store_true")
    ap.add_argument("--guion", type=Path, help="Guion propio (.txt o .json); no usa el LLM")
    ap.add_argument("--lote", type=Path, help="Archivo con un tema por línea")
    ap.add_argument("--reanudar", type=Path, help="Carpeta de un trabajo que falló")
    ap.add_argument("--duracion", type=int)
    ap.add_argument("--voz", choices=["ef_dora", "em_alex", "em_santa"])
    ap.add_argument("--mood", help="Fuerza el mood de la música")
    args = ap.parse_args()

    if not any([args.tema, args.sorprendeme, args.guion, args.lote, args.reanudar]):
        from shortsauto.gui.app import run_gui
        return run_gui()

    setup_logging()
    from shortsauto.pipeline import Job, Pipeline, StageError
    from shortsauto.script import llm
    from shortsauto.script.schema import Script

    cfg = merge(load_config(), {"video": {"duracion_objetivo": args.duracion},
                                "voz": {"voz": args.voz}})
    pipe = Pipeline(cfg, progress=lambda s, f: f == 0 and print(f"→ {s}…", flush=True))
    try:
        if args.reanudar:
            jobs = [(Job(args.reanudar), None)]
        elif args.guion:
            raw = args.guion.read_text("utf-8")
            script = (Script.from_dict(json.loads(raw)) if args.guion.suffix == ".json"
                      else Script.from_text(raw))
            if args.mood:
                script.mood = args.mood
            jobs = [(pipe.new_job(script.titulo), script)]
        else:
            temas = ([t.strip() for t in args.lote.read_text("utf-8").splitlines() if t.strip()]
                     if args.lote else [args.tema or llm.surprise_topic()])
            jobs = [(pipe.new_job(t), None) for t in temas]
        failed = 0
        for job, script in jobs:
            try:
                print("✔ Listo:", pipe.run(job, script))
            except StageError as e:
                failed += 1
                print(f"✘ {e}\n  Reintenta con: python main.py --reanudar \"{job.dir}\"")
        return 1 if failed else 0
    finally:
        pipe.close()


if __name__ == "__main__":
    sys.exit(main())
