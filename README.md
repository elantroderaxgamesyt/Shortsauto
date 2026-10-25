# ShortsAuto

Crea vídeos cortos verticales (YouTube Shorts, TikTok, Reels) de forma **100% automática y 100% local**:
guion, voz, subtítulos karaoke, fondos o imágenes, música, efectos de sonido y miniatura.
Sin API keys, sin cuentas y sin internet después de la primera instalación.

## Instalar (Windows)

1. Descarga `ShortsAuto-Setup-x.y.z.exe` desde la sección **Releases** de este repositorio.
2. Ejecútalo. Si Windows muestra "Windows protegió tu PC", pulsa **Más información → Ejecutar de todas formas**
   (el instalador no está firmado).
3. Abre ShortsAuto. La primera vez, el asistente detecta tu PC y descarga los modelos de IA
   (entre 3 GB en modo ligero y unos 15 GB con GPU). Si se corta, pulsa Reintentar: continúa donde iba.

## Usar

- **Un vídeo**: escribe un tema (o pulsa 🎲 Sorpréndeme) y pulsa **Generar**.
- **Lote**: un tema por línea, o escribe un nicho y cuántos vídeos quieres.
- **Mi guion**: pega tu propio texto; la app pone voz, subtítulos, imágenes y música.

Cada vídeo se guarda en `output/<fecha>_<tema>/`:
`video.mp4`, `miniatura.jpg`, `subtitulos.srt`, `guion.json` y `metadatos.txt` (título, descripción y hashtags).

Si una etapa falla, pulsa **Reintentar**: se continúa desde esa etapa sin repetir lo anterior.

### Línea de comandos

```
ShortsAuto-consola.bat --tema "datos curiosos de los pulpos" --duracion 45
ShortsAuto-consola.bat --sorprendeme
ShortsAuto-consola.bat --guion mi_guion.txt
ShortsAuto-consola.bat --lote temas.txt
ShortsAuto-consola.bat --reanudar "output\2026-10-25_120000_pulpos"
```

## Requisitos

| Modo | Equipo | Tiempo por vídeo (aprox.) |
|---|---|---|
| Ligero (fondos animados) | Windows 10/11 64 bits, 8 GB RAM, 4 núcleos | 2–5 min |
| GPU (imágenes con IA) | NVIDIA con 6 GB+ de VRAM, 16 GB RAM | 3–6 min |

El modo se elige solo. Si la GPU se queda sin memoria, se pasa al modo ligero automáticamente.

## Cómo funciona

| Etapa | Tecnología |
|---|---|
| Guion | Qwen3 (1.7B/4B/8B según tu PC) con llama.cpp, salida JSON validada |
| Voz | Kokoro-82M (ONNX), voces Dora, Álex y Santa |
| Subtítulos | Tiempos por palabra calculados en la síntesis → karaoke con libass |
| Visuales | Fondos procedurales, o SDXL-Lightning / SD1.5-LCM + Ken Burns |
| Música | Compositor procedural propio según el "mood" del guion |
| Efectos | Whoosh, pop, riser, impacto y click sintetizados |
| Montaje | FFmpeg: ducking de la música, -14 LUFS, NVENC si hay GPU NVIDIA |

Ajustes avanzados en `config.yaml`.

## Desarrollo

```
python -m venv .venv && .venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python main.py
```

Instalador: `powershell -ExecutionPolicy Bypass -File packaging\build_windows.ps1`
(o publica una etiqueta `v*` y GitHub Actions lo compila y lo sube a Releases).
Linux: `./install.sh` y luego `./shortsauto`.
