"""Interfaz gráfica (PySide6)."""
import logging
import os
import shutil
import subprocess
import sys
import traceback
from pathlib import Path

from PySide6.QtCore import QObject, Qt, QThread, QUrl, Signal
from PySide6.QtGui import QFont
from PySide6.QtWidgets import (
    QApplication, QCheckBox, QComboBox, QDialog, QFileDialog, QFormLayout, QHBoxLayout, QLabel, QLineEdit,
    QListWidget, QListWidgetItem, QMainWindow, QMessageBox, QPlainTextEdit, QProgressBar,
    QPushButton, QSlider, QSpinBox, QTabWidget, QVBoxLayout, QWidget,
)

from ..config import LOGS, MODELS, ROOT, load_config, merge
from ..music.procedural import MOODS
from ..setup import installer
from ..tts.kokoro_tts import VOICES

log = logging.getLogger(__name__)

STYLE = """
QWidget { background: #14161c; color: #e8e8ee; font-size: 14px; }
QLineEdit, QComboBox, QPlainTextEdit, QSpinBox, QListWidget {
    background: #1e2129; border: 1px solid #2c303b; border-radius: 8px; padding: 6px; }
QPushButton { background: #2a2e39; border: none; border-radius: 8px; padding: 9px 16px; }
QPushButton:hover { background: #353a47; }
QPushButton#primary { background: #ff3d6e; font-weight: bold; font-size: 16px; padding: 12px; }
QPushButton#primary:hover { background: #ff5a84; }
QPushButton:disabled { background: #22252d; color: #666; }
QProgressBar { background: #1e2129; border: none; border-radius: 5px; height: 10px; text-align: center; }
QProgressBar::chunk { background: #ff3d6e; border-radius: 5px; }
QTabWidget::pane { border: none; }
QTabBar::tab { background: #1e2129; padding: 8px 18px; border-radius: 8px; margin-right: 4px; }
QTabBar::tab:selected { background: #ff3d6e; }
QLabel#h1 { font-size: 22px; font-weight: bold; }
QLabel#muted { color: #8a8f9c; }
"""


# --- Trabajo en segundo plano ---------------------------------------------

class Worker(QObject):
    stage = Signal(str, float)
    job_started = Signal(int, int, str)
    job_done = Signal(str)
    failed = Signal(str, str)          # mensaje, carpeta del trabajo para reintentar
    finished = Signal()

    def __init__(self, cfg: dict, temas: list[str], nicho: str | None = None, n: int = 0,
                 resume: Path | None = None, script_text: str | None = None):
        super().__init__()
        self.cfg, self.temas, self.nicho, self.n, self.resume = cfg, temas, nicho, n, resume
        self.script_text = script_text
        self.cancelled = False

    def run(self) -> None:
        from ..pipeline import Job, Pipeline, StageError
        from ..script import llm
        from ..script.schema import Script

        pipe = Pipeline(self.cfg, progress=self.stage.emit)
        try:
            script = Script.from_text(self.script_text) if self.script_text else None
            if self.resume:
                jobs = [Job(self.resume)]
            elif script:
                jobs = [pipe.new_job(script.titulo)]
            else:
                temas = self.temas
                if self.nicho:
                    self.stage.emit("guion", 0.0)
                    temas = llm.topics(pipe.llm_server(), self.nicho, self.n)
                jobs = [pipe.new_job(t) for t in temas]
            for i, job in enumerate(jobs):
                if self.cancelled:
                    break
                self.job_started.emit(i + 1, len(jobs), job.state.get("tema", ""))
                try:
                    self.job_done.emit(str(pipe.run(job, script)))
                except StageError as e:
                    self.failed.emit(str(e), str(job.dir))
        except Exception as e:
            log.exception("Error general")
            self.failed.emit(f"{e}\n\n{traceback.format_exc(limit=3)}", "")
        finally:
            pipe.close()
            self.finished.emit()


class SetupWorker(QObject):
    progress = Signal(str, float)
    done = Signal(bool, str)      # ok, mensaje (error o aviso)

    def __init__(self, hw, steps):
        super().__init__()
        self.hw, self.steps = hw, steps

    def run(self) -> None:
        warnings = []
        for step in self.steps:
            if step.done:
                continue
            try:
                installer.run_step(step, self.hw, self.progress.emit)
                step.done = True
            except Exception as e:
                log.exception("Instalación de %s", step.key)
                detail = f"{step.label}: {type(e).__name__}: {e}"
                if not step.optional:
                    self.done.emit(False, detail + "\n\n(Más detalles en logs/shortsauto.log)")
                    return
                warnings.append(detail)
                break   # las imágenes dependen de PyTorch: no seguimos con ellas
        self.done.emit(True, "\n".join(warnings))


def start_thread(owner, worker: QObject, finished_signal) -> QThread:
    thread = QThread(owner)
    worker.moveToThread(thread)
    thread.started.connect(worker.run)
    finished_signal.connect(thread.quit)
    thread.start()
    return thread


# --- Asistente de primer arranque -----------------------------------------

class SetupWizard(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Preparando ShortsAuto")
        self.setMinimumWidth(560)
        self.hw, self.profile, self.steps = installer.plan()
        lay = QVBoxLayout(self)
        title = QLabel("Bienvenido a ShortsAuto")
        title.setObjectName("h1")
        lay.addWidget(title)
        gpu = (f"{self.hw.gpu_name} ({self.hw.vram_gb:.0f} GB)" if self.hw.gpu_name
               else "No detectada → modo ligero")
        info = QLabel(f"<b>Tu equipo:</b> {self.hw.cpu_cores} núcleos · {self.hw.ram_gb:.0f} GB de RAM · "
                      f"GPU: {gpu}<br><br>Voy a descargar los modelos de IA que funcionan mejor en tu PC. "
                      "Solo se hace una vez; después todo funciona sin internet.")
        info.setWordWrap(True)
        lay.addWidget(info)
        self.list = QListWidget()
        for s in self.steps:
            mark = "✔" if s.done else "⬇"
            extra = "  (opcional)" if s.optional else ""
            QListWidgetItem(f"{mark}  {s.label}  —  {s.size_gb:.1f} GB{extra}", self.list)
        lay.addWidget(self.list)
        self.with_images = QCheckBox("Instalar también las imágenes con IA (opcional)")
        self.with_images.setToolTip("Usa la GPU. Si falla, la app funciona igual con fondos animados.")
        self.with_images.setChecked(True)
        self.with_images.toggled.connect(self.update_total)
        if any(s.optional and not s.done for s in self.steps):
            lay.addWidget(self.with_images)
        self.total = QLabel()
        lay.addWidget(self.total)
        self.update_total()
        self.status = QLabel("")
        self.status.setObjectName("muted")
        self.bar = QProgressBar()
        lay.addWidget(self.status)
        lay.addWidget(self.bar)
        self.button = QPushButton("Instalar y empezar")
        self.button.setObjectName("primary")
        self.button.clicked.connect(self.start)
        lay.addWidget(self.button)

    def selected_steps(self) -> list:
        return [s for s in self.steps if not s.optional or self.with_images.isChecked()]

    def update_total(self) -> None:
        pending = sum(s.size_gb for s in self.selected_steps() if not s.done)
        self.total.setText(f"Descarga total: <b>{pending:.1f} GB</b>")

    def start(self) -> None:
        self.button.setEnabled(False)
        self.with_images.setEnabled(False)
        self.worker = SetupWorker(self.hw, self.selected_steps())
        self.worker.progress.connect(self.on_progress)
        self.worker.done.connect(self.on_done)
        self.thread = start_thread(self, self.worker, self.worker.done)

    def on_progress(self, text: str, frac: float) -> None:
        self.status.setText(text)
        self.bar.setValue(int(frac * 100))

    def on_done(self, ok: bool, error: str) -> None:
        if ok:
            if error:
                QMessageBox.information(
                    self, "Imágenes con IA no instaladas",
                    "La app ya funciona (con fondos animados), pero no se pudieron instalar las "
                    "imágenes con IA. Puedes reintentarlo desde Ajustes.\n\n" + error)
            self.accept()
            return
        self.button.setEnabled(True)
        self.with_images.setEnabled(True)
        self.button.setText("Reintentar (continúa donde se quedó)")
        QMessageBox.warning(self, "No se pudo completar", error)


# --- Ajustes ----------------------------------------------------------------

class SettingsDialog(QDialog):
    def __init__(self, cfg: dict, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Ajustes")
        self.cfg = cfg
        form = QFormLayout(self)
        self.mode = QComboBox()
        self.mode.addItems(["auto", "procedural", "difusion"])
        self.mode.setCurrentText(cfg["visuales"]["modo"])
        form.addRow("Visuales (calidad/velocidad):", self.mode)
        self.out = QLineEdit(cfg["salida"]["carpeta"])
        browse = QPushButton("…")
        browse.clicked.connect(self.pick_folder)
        row = QHBoxLayout()
        row.addWidget(self.out)
        row.addWidget(browse)
        form.addRow("Carpeta de salida:", row)
        self.models = QListWidget()
        self.refresh_models()
        form.addRow("Modelos instalados:", self.models)
        delete = QPushButton("Borrar modelo seleccionado")
        delete.clicked.connect(self.delete_model)
        form.addRow("", delete)
        install = QPushButton("Instalar modelos que faltan…")
        install.clicked.connect(lambda: (SetupWizard(self).exec(), self.refresh_models()))
        form.addRow("", install)
        ok = QPushButton("Guardar")
        ok.setObjectName("primary")
        ok.clicked.connect(self.accept)
        form.addRow(ok)

    def pick_folder(self) -> None:
        d = QFileDialog.getExistingDirectory(self, "Carpeta de salida")
        if d:
            self.out.setText(d)

    def refresh_models(self) -> None:
        self.models.clear()
        for path in sorted(MODELS.glob("*/*")) if MODELS.exists() else []:
            size = (sum(f.stat().st_size for f in path.rglob("*") if f.is_file())
                    if path.is_dir() else path.stat().st_size)
            item = QListWidgetItem(f"{path.parent.name}/{path.name}  ({size / 1024**3:.2f} GB)")
            item.setData(Qt.UserRole, str(path))
            self.models.addItem(item)

    def delete_model(self) -> None:
        item = self.models.currentItem()
        if not item:
            return
        path = Path(item.data(Qt.UserRole))
        if QMessageBox.question(self, "Borrar", f"¿Borrar {path.name}? Se volverá a descargar "
                                "si hace falta.") != QMessageBox.Yes:
            return
        shutil.rmtree(path) if path.is_dir() else path.unlink()
        self.refresh_models()

    def values(self) -> dict:
        return {"visuales": {"modo": self.mode.currentText()}, "salida": {"carpeta": self.out.text()}}


# --- Ventana principal ----------------------------------------------------

class MainWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        from ..pipeline import STAGE_LABELS, STAGES
        self.STAGES, self.LABELS = STAGES, STAGE_LABELS
        self.cfg = load_config()
        self.overrides: dict = {}
        self.last_video: str | None = None
        self.retry_dir: str | None = None
        self.setWindowTitle("ShortsAuto — Shorts automáticos 100% locales")
        self.resize(1100, 760)

        root = QWidget()
        main = QHBoxLayout(root)
        main.addLayout(self._build_left(), 4)
        main.addLayout(self._build_right(), 5)
        self.setCentralWidget(root)

    def _build_left(self) -> QVBoxLayout:
        left = QVBoxLayout()
        title = QLabel("ShortsAuto")
        title.setObjectName("h1")
        left.addWidget(title)
        tabs = QTabWidget()

        single = QWidget()
        f = QFormLayout(single)
        self.tema = QLineEdit()
        self.tema.setPlaceholderText("Ej: 3 datos curiosos sobre los pulpos")
        surprise = QPushButton("🎲 Sorpréndeme")
        surprise.clicked.connect(self.surprise)
        row = QHBoxLayout()
        row.addWidget(self.tema)
        row.addWidget(surprise)
        f.addRow("Tema:", row)
        tabs.addTab(single, "Un vídeo")

        batch = QWidget()
        b = QVBoxLayout(batch)
        b.addWidget(QLabel("Un tema por línea:"))
        self.lote = QPlainTextEdit()
        b.addWidget(self.lote)
        nrow = QHBoxLayout()
        self.nicho = QLineEdit()
        self.nicho.setPlaceholderText("…o escribe un nicho (ej: historia de Roma)")
        self.n_videos = QSpinBox()
        self.n_videos.setRange(1, 50)
        self.n_videos.setValue(5)
        nrow.addWidget(self.nicho)
        nrow.addWidget(QLabel("nº vídeos:"))
        nrow.addWidget(self.n_videos)
        b.addLayout(nrow)
        tabs.addTab(batch, "Lote")

        own = QWidget()
        o = QVBoxLayout(own)
        o.addWidget(QLabel("Pega tu guion. La primera frase o párrafo es el gancho; "
                           "cada párrafo siguiente es una escena."))
        self.own_script = QPlainTextEdit()
        o.addWidget(self.own_script)
        tabs.addTab(own, "Mi guion")
        self.tabs = tabs
        left.addWidget(tabs)

        opts = QFormLayout()
        self.voz = QComboBox()
        for key, label in VOICES.items():
            self.voz.addItem(label, key)
        self.voz.setCurrentIndex(list(VOICES).index(self.cfg["voz"]["voz"]))
        opts.addRow("Voz:", self.voz)
        self.dur = QSlider(Qt.Horizontal)
        self.dur.setRange(30, 60)
        self.dur.setValue(self.cfg["video"]["duracion_objetivo"])
        self.dur_label = QLabel()
        self.dur.valueChanged.connect(lambda v: self.dur_label.setText(f"{v} s"))
        self.dur_label.setText(f"{self.dur.value()} s")
        drow = QHBoxLayout()
        drow.addWidget(self.dur)
        drow.addWidget(self.dur_label)
        opts.addRow("Duración:", drow)
        self.estilo = QComboBox()
        self.estilo.addItems(["realista", "anime", "minimalista", "3d"])
        self.estilo.setCurrentText(self.cfg["visuales"]["estilo"])
        opts.addRow("Estilo visual:", self.estilo)
        self.subs = QComboBox()
        self.subs.addItems(["karaoke", "simple"])
        opts.addRow("Subtítulos:", self.subs)
        self.mood = QComboBox()
        self.mood.addItems(["automático"] + list(MOODS))
        opts.addRow("Música:", self.mood)
        left.addLayout(opts)

        self.go = QPushButton("Generar")
        self.go.setObjectName("primary")
        self.go.clicked.connect(self.generate)
        left.addWidget(self.go)
        brow = QHBoxLayout()
        settings = QPushButton("⚙ Ajustes")
        settings.clicked.connect(self.open_settings)
        self.retry = QPushButton("↻ Reintentar")
        self.retry.setEnabled(False)
        self.retry.clicked.connect(self.retry_job)
        brow.addWidget(settings)
        brow.addWidget(self.retry)
        left.addLayout(brow)
        left.addStretch()
        return left

    def _build_right(self) -> QVBoxLayout:
        right = QVBoxLayout()
        self.job_label = QLabel("Listo para generar")
        self.job_label.setObjectName("muted")
        right.addWidget(self.job_label)
        self.bars = {}
        grid = QFormLayout()
        for s in self.STAGES:
            bar = QProgressBar()
            bar.setTextVisible(False)
            self.bars[s] = bar
            grid.addRow(self.LABELS[s], bar)
        right.addLayout(grid)
        self.preview = self._make_preview()
        right.addWidget(self.preview, 1)
        prow = QHBoxLayout()
        self.open_btn = QPushButton("📂 Abrir carpeta")
        self.open_btn.setEnabled(False)
        self.open_btn.clicked.connect(self.open_folder)
        self.play_btn = QPushButton("▶ Reproducir")
        self.play_btn.setEnabled(False)
        self.play_btn.clicked.connect(self.play)
        prow.addWidget(self.play_btn)
        prow.addWidget(self.open_btn)
        right.addLayout(prow)
        return right

    def _make_preview(self) -> QWidget:
        try:
            from PySide6.QtMultimedia import QAudioOutput, QMediaPlayer
            from PySide6.QtMultimediaWidgets import QVideoWidget
            video = QVideoWidget()
            video.setMinimumHeight(360)
            self.player = QMediaPlayer(self)
            self.audio = QAudioOutput(self)
            self.player.setAudioOutput(self.audio)
            self.player.setVideoOutput(video)
            return video
        except Exception:      # sin backend multimedia: se abre con el reproductor del sistema
            self.player = None
            label = QLabel("La vista previa se abrirá en tu reproductor.")
            label.setAlignment(Qt.AlignCenter)
            return label

    # --- acciones --------------------------------------------------------

    def current_cfg(self) -> dict:
        mood = self.mood.currentText()
        return merge(self.cfg, merge(self.overrides, {
            "voz": {"voz": self.voz.currentData()},
            "video": {"duracion_objetivo": self.dur.value()},
            "visuales": {"estilo": self.estilo.currentText()},
            "subtitulos": {"estilo": self.subs.currentText()},
            "musica": {"forzar_mood": None if mood == "automático" else mood},
        }))

    def surprise(self) -> None:
        from ..script.llm import surprise_topic
        self.tema.setText(surprise_topic())

    def generate(self) -> None:
        nicho, temas = None, []
        if self.tabs.currentIndex() == 2:
            text = self.own_script.toPlainText().strip()
            if not text:
                QMessageBox.information(self, "Mi guion", "Escribe o pega un guion.")
                return
            self._launch(Worker(self.current_cfg(), [], script_text=text))
            return
        if self.tabs.currentIndex() == 0:
            if not self.tema.text().strip():
                self.surprise()
            temas = [self.tema.text().strip()]
        else:
            temas = [t.strip() for t in self.lote.toPlainText().splitlines() if t.strip()]
            if not temas and self.nicho.text().strip():
                nicho = self.nicho.text().strip()
            if not temas and not nicho:
                QMessageBox.information(self, "Lote", "Escribe temas o un nicho.")
                return
        self._launch(Worker(self.current_cfg(), temas, nicho, self.n_videos.value()))

    def retry_job(self) -> None:
        if self.retry_dir:
            self._launch(Worker(self.current_cfg(), [], resume=Path(self.retry_dir)))

    def _launch(self, worker: Worker) -> None:
        self.go.setEnabled(False)
        self.retry.setEnabled(False)
        for bar in self.bars.values():
            bar.setValue(0)
        self.worker = worker
        worker.stage.connect(self.on_stage)
        worker.job_started.connect(self.on_job_started)
        worker.job_done.connect(self.on_job_done)
        worker.failed.connect(self.on_failed)
        worker.finished.connect(lambda: self.go.setEnabled(True))
        self.thread = start_thread(self, worker, worker.finished)

    def on_stage(self, stage: str, frac: float) -> None:
        if stage in self.bars:
            self.bars[stage].setValue(int(frac * 100))
        self.job_label.setText(f"{self.LABELS.get(stage, stage)}…")

    def on_job_started(self, i: int, n: int, tema: str) -> None:
        for bar in self.bars.values():
            bar.setValue(0)
        self.job_label.setText(f"Vídeo {i}/{n}: {tema}")

    def on_job_done(self, path: str) -> None:
        self.last_video = path
        self.open_btn.setEnabled(True)
        self.play_btn.setEnabled(True)
        self.job_label.setText(f"✔ Terminado: {Path(path).parent.name}")
        self.play()

    def on_failed(self, msg: str, folder: str) -> None:
        self.retry_dir = folder or None
        self.retry.setEnabled(bool(folder))
        QMessageBox.warning(self, "Algo falló", msg + ("\n\nPulsa «Reintentar» para continuar desde "
                                                       "esa etapa." if folder else ""))

    def play(self) -> None:
        if not self.last_video:
            return
        if self.player:
            self.player.setSource(QUrl.fromLocalFile(self.last_video))
            self.player.play()
        else:
            open_path(self.last_video)

    def open_folder(self) -> None:
        if self.last_video:
            open_path(str(Path(self.last_video).parent))

    def open_settings(self) -> None:
        dlg = SettingsDialog(self.current_cfg(), self)
        if dlg.exec():
            self.overrides = merge(self.overrides, dlg.values())
            save_user_settings(merge(self.cfg, self.overrides))


def open_path(path: str) -> None:
    if sys.platform == "win32":
        os.startfile(path)  # noqa: S606
    else:
        subprocess.Popen(["xdg-open", path])


def save_user_settings(cfg: dict) -> None:
    import yaml
    with open(ROOT / "config.yaml", "w", encoding="utf-8") as f:
        yaml.safe_dump(cfg, f, allow_unicode=True, sort_keys=False)


def needs_setup() -> bool:
    """Solo obliga a pasar por el asistente si falta algo imprescindible."""
    _, _, steps = installer.plan()
    return any(not s.done and not s.optional for s in steps)


def run_gui() -> int:
    LOGS.mkdir(exist_ok=True)
    logging.basicConfig(level=logging.INFO, filename=LOGS / "shortsauto.log", encoding="utf-8",
                        format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    app = QApplication(sys.argv)
    app.setStyleSheet(STYLE)
    app.setFont(QFont("Segoe UI", 10))
    if needs_setup() and SetupWizard().exec() != QDialog.Accepted:
        return 0
    win = MainWindow()
    win.show()
    return app.exec()
