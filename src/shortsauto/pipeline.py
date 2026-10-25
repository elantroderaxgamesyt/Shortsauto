"""Orquestador: ejecuta las etapas, guarda el estado y permite reintentar."""
import json
import logging
import re
import time
import unicodedata
from dataclasses import asdict
from datetime import datetime
from pathlib import Path
from typing import Callable

import numpy as np
import soundfile as sf

from .config import ROOT
from .music import procedural as music
from .render import compose, thumbnail
from .script import llm
from .script.schema import Script
from .setup import hardware
from .sfx import synth
from .subtitles import ass
from .tts import kokoro_tts
from .tts.kokoro_tts import Narration, Word
from .visuals import diffusion
from .visuals.kenburns import KenBurns
from .visuals.procedural import ProceduralBackground, SceneVisual

log = logging.getLogger(__name__)

STAGES = ["guion", "voz", "subtitulos", "visuales", "musica", "sfx", "video", "extras"]
STAGE_LABELS = {"guion": "Escribiendo guion", "voz": "Generando voz",
                "subtitulos": "Creando subtítulos", "visuales": "Generando imágenes", "musica": "Componiendo música",
                "sfx": "Sintetizando efectos", "video": "Renderizando vídeo",
                "extras": "Miniatura y metadatos"}

Progress = Callable[[str, float], None]


class StageError(RuntimeError):
    def __init__(self, stage: str, cause: Exception):
        super().__init__(f"Falló la etapa «{STAGE_LABELS[stage]}»: {cause}")
        self.stage = stage


def slug(text: str) -> str:
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    s = re.sub(r"[^\w\s-]", "", text.lower()).strip()
    return re.sub(r"[\s_-]+", "_", s)[:40] or "short"


class Job:
    def __init__(self, folder: Path):
        self.dir = folder
        self.dir.mkdir(parents=True, exist_ok=True)
        self.state_file = folder / "estado.json"
        self.state = json.loads(self.state_file.read_text("utf-8")) if self.state_file.exists() else {}

    def done(self, stage: str) -> bool:
        return stage in self.state.get("completadas", [])

    def mark(self, stage: str) -> None:
        self.state.setdefault("completadas", []).append(stage)
        self.save()

    def save(self) -> None:
        self.state_file.write_text(json.dumps(self.state, ensure_ascii=False, indent=2), "utf-8")


class Pipeline:
    def __init__(self, cfg: dict, progress: Progress | None = None):
        self.cfg = cfg
        self.progress = progress or (lambda stage, f: None)
        self.hw = hardware.detect()
        self.profile = hardware.choose_profile(self.hw)
        self._llm: llm.LlamaServer | None = None

    def llm_server(self) -> llm.LlamaServer:
        if self._llm is None:
            g = self.cfg["guion"]
            self._llm = llm.LlamaServer(self.profile["llm"], g["puerto"], g["contexto"], self.hw.has_cuda)
        return self._llm

    def close(self) -> None:
        if self._llm:
            self._llm.stop()

    def new_job(self, tema: str) -> Job:
        out = Path(self.cfg["salida"]["carpeta"])
        out = out if out.is_absolute() else ROOT / out
        stamp = datetime.now().strftime("%Y-%m-%d_%H%M%S")
        job = Job(out / f"{stamp}_{slug(tema)}")
        job.state.setdefault("tema", tema)
        job.save()
        return job

    def run(self, job: Job, script: Script | None = None) -> Path:
        """Ejecuta las etapas pendientes. Si se pasa `script`, se usa en lugar del LLM."""
        if script is not None and not job.done("guion"):
            self._save_script(job, script)
            job.mark("guion")
        for stage in STAGES:
            if job.done(stage):
                continue
            self.progress(stage, 0.0)
            t0 = time.time()
            try:
                getattr(self, f"_stage_{stage}")(job)
            except Exception as e:     # se informa la etapa exacta y se puede reintentar
                log.exception("Etapa %s", stage)
                raise StageError(stage, e) from e
            job.mark(stage)
            log.info("%s: %.1fs", stage, time.time() - t0)
            self.progress(stage, 1.0)
        return job.dir / "video.mp4"

    # --- etapas ------------------------------------------------------------

    def _save_script(self, job: Job, script: Script) -> None:
        (job.dir / "guion.json").write_text(
            json.dumps(script.to_dict(), ensure_ascii=False, indent=2), "utf-8")

    def _script(self, job: Job) -> Script:
        return Script.from_dict(json.loads((job.dir / "guion.json").read_text("utf-8")))

    def _narration(self, job: Job) -> Narration:
        d = json.loads((job.dir / "narracion.json").read_text("utf-8"))
        return Narration([Word(**w) for w in d["words"]], d["scene_starts"], d["duration"])

    def _stage_guion(self, job: Job) -> None:
        tema = job.state["tema"]
        script = llm.generate(self.llm_server(), tema, self.cfg["video"]["duracion_objetivo"],
                              self.cfg["guion"])
        self._save_script(job, script)

    def _stage_voz(self, job: Job) -> None:
        v = self.cfg["voz"]
        narr = kokoro_tts.synthesize(self._script(job), v["voz"], v["velocidad"],
                                     v["pausa_entre_frases"], job.dir / "voice.wav")
        (job.dir / "narracion.json").write_text(json.dumps(asdict(narr), ensure_ascii=False), "utf-8")

    def _stage_subtitulos(self, job: Job) -> None:
        narr, script = self._narration(job), self._script(job)
        ass.write_ass(narr, self.cfg["subtitulos"], self.cfg["video"], script.gancho, job.dir / "subs.ass")
        ass.write_srt(narr, job.dir / "subtitulos.srt")

    def _duration(self, job: Job) -> float:
        return self._narration(job).duration + 0.8

    def _seed(self, job: Job) -> int:
        return abs(hash(job.dir.name)) % (2**31)

    def image_model(self) -> str | None:
        """Modelo de imagen a usar, o None para fondos procedurales."""
        mode = self.cfg["visuales"]["modo"]
        if mode == "procedural" or not diffusion.available():
            return None
        model = self.profile["image"]
        if model == "procedural":
            return "sd15-lcm" if mode == "difusion" else None
        return model

    def _stage_visuales(self, job: Job) -> None:
        model = self.image_model()
        job.state["visual_mode"] = "procedural"
        if model is None:
            return
        narr, script = self._narration(job), self._script(job)
        segs = script.segments()
        ends = narr.scene_starts[1:] + [self._duration(job)]
        prompts = [scene.visual if scene else "" for _, scene in segs]
        # Gancho y CTA reutilizan la descripción de la escena más cercana.
        prompts[0] = prompts[0] or (script.escenas[0].visual if script.escenas else script.titulo)
        prompts[-1] = prompts[-1] or prompts[-2]
        plan = []
        for i, (start, end) in enumerate(zip(narr.scene_starts, ends)):
            n = min(3, max(1, round((end - start) / 5)))
            step = (end - start) / n
            plan += [(start + k * step, start + (k + 1) * step, prompts[i]) for k in range(n)]
        gen = None
        try:
            gen = diffusion.ImageGenerator(model, self.hw.vram_gb)
            images = []
            for k, (a, b, prompt) in enumerate(plan):
                path = job.dir / f"img_{k:02d}.png"
                if not path.exists():
                    gen.generate(prompt, self.cfg["visuales"]["estilo"], path, self._seed(job) + k)
                images.append([a, b, path.name])
                self.progress("visuales", (k + 1) / len(plan))
            job.state["visual_mode"] = model
            job.state["images"] = images
        except Exception as e:
            if not diffusion.is_oom(e):
                raise
            log.warning("Sin memoria de GPU para %s; uso fondos procedurales", model)
        finally:
            if gen:
                gen.close()
            job.save()

    def _stage_musica(self, job: Job) -> None:
        mood = self.cfg["musica"].get("forzar_mood") or self._script(job).mood
        audio = music.compose(mood, self._duration(job), self._seed(job))
        sf.write(job.dir / "music.wav", audio, music.SR)

    def _stage_sfx(self, job: Job) -> None:
        if not self.cfg["sfx"]["activado"]:
            return
        narr, script = self._narration(job), self._script(job)
        events = [(0.0, "impacto")]
        for start, (_, scene) in zip(narr.scene_starts[1:], script.segments()[1:]):
            events.append((start, scene.sfx if scene else "riser"))
        events += [(w.start, "pop") for w in narr.words if w.keyword]
        sf.write(job.dir / "sfx.wav", synth.build_track(events, self._duration(job), self._seed(job)),
                 synth.SR)

    def _background(self, job: Job) -> ProceduralBackground:
        v, narr, script = self.cfg["video"], self._narration(job), self._script(job)
        s = v["escala_render"]
        keywords = [""] + [sc.palabra_clave for sc in script.escenas] + ([""] if script.cta else [])
        scenes = [SceneVisual(t, k) for t, k in zip(narr.scene_starts, keywords)]
        return ProceduralBackground(v["ancho"] // s, v["alto"] // s, v["fps"], script.mood, scenes,
                                    seed=self._seed(job))

    def _visual(self, job: Job):
        if job.state.get("visual_mode", "procedural") == "procedural":
            return self._background(job)
        v = self.cfg["video"]
        images = [(a, b, str(job.dir / name)) for a, b, name in job.state["images"]]
        return KenBurns(images, (v["ancho"], v["alto"]), v["fps"], seed=self._seed(job))

    def _stage_video(self, job: Job) -> None:
        bg, dur, fps = self._visual(job), self._duration(job), self.cfg["video"]["fps"]
        compose.render(job.dir, bg.frames(dur), (bg.w, bg.h), self.cfg, dur, int(dur * fps),
                       progress=lambda f: self.progress("video", f))

    def _stage_extras(self, job: Job) -> None:
        script, bg = self._script(job), self._visual(job)
        kw = script.escenas[0].palabra_clave if script.escenas else ""
        thumbnail.make(bg.frame(1.5), script.titulo, kw,
                       (self.cfg["video"]["ancho"], self.cfg["video"]["alto"]), job.dir / "miniatura.jpg")
        meta = [f"TÍTULO:\n{script.titulo}", "", f"DESCRIPCIÓN:\n{script.descripcion}", "",
                "HASHTAGS:\n" + " ".join(script.hashtags), "", "GUION:",
                *[t for t, _ in script.segments()]]
        (job.dir / "metadatos.txt").write_text("\n".join(meta), "utf-8")


def music_preview(mood: str, seconds: float = 20) -> np.ndarray:
    return music.compose(mood, seconds)
