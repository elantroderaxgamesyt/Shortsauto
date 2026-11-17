#!/usr/bin/env bash
# Instala la APK en el emulador, la abre y comprueba que sigue viva.
# Deja captura de pantalla y logcat en prueba-arranque/.
set -u
APK="$1"
PAQUETE=es.revisornominas.app
OUT=prueba-arranque
mkdir -p "$OUT"
adb wait-for-device
adb logcat -c
adb install -r "$APK" || { echo "::error::No se ha podido instalar la APK"; exit 1; }
adb shell am start -W -n "$PAQUETE/es.revisornominas.revisor_nominas.MainActivity"
sleep 25
adb exec-out screencap -p > "$OUT/pantalla.png"
adb logcat -d > "$OUT/logcat.txt"
PID=$(adb shell pidof "$PAQUETE" | tr -d '\r')
echo "---- errores en logcat ----"
grep -nE "FATAL EXCEPTION|AndroidRuntime|E flutter|Error sin capturar|Error de Flutter|Anuncios desactivados" "$OUT/logcat.txt" | head -80
if [ -z "$PID" ] || grep -q "FATAL EXCEPTION" "$OUT/logcat.txt"; then
  echo "::error::La app se cierra al abrirla (ver logcat)"
  grep -n -A40 "FATAL EXCEPTION" "$OUT/logcat.txt" | head -80
  exit 1
fi
echo "La app sigue abierta (pid $PID)"
