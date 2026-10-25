#!/usr/bin/env bash
# Instalación en Linux: entorno virtual + dependencias. Necesita python3 y ffmpeg del sistema.
set -euo pipefail
cd "$(dirname "$0")"
command -v ffmpeg >/dev/null || { echo "Instala ffmpeg (ej: sudo apt install ffmpeg)"; exit 1; }
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
cat > shortsauto <<'SH'
#!/usr/bin/env bash
cd "$(dirname "$0")" && exec .venv/bin/python main.py "$@"
SH
chmod +x shortsauto
echo "Listo. Ejecuta ./shortsauto"
