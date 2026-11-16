# Revisor de nóminas con IA

App para **Android (Google Play)** y **Windows** que revisa nóminas españolas. Subes el PDF
o haces una foto y **Nora**, una asesora laboral con IA (Claude), te dice qué está bien, qué
está mal y qué hacer. Después puedes preguntarle dudas en un chat.

Proyecto independiente del resto del repositorio.

```
revisor-nominas/
├── app/         servidor (Python + FastAPI): IA, cálculos, cuentas y pagos
├── app_movil/   app Flutter: Android y Windows con el mismo código
├── tests/       tests del servidor
└── Dockerfile   para publicar el servidor
```

La clave de la IA **no puede ir dentro de la app** (cualquiera podría sacarla del APK), por eso
la app habla con el servidor y es el servidor quien llama a la IA y verifica los pagos.

## Free y Pro

Una sola app gratuita; Pro se desbloquea con compra dentro de la app.

| | Free | Pro |
|---|---|---|
| Precio | Gratis (3 revisiones/día) | **2,99 € por revisión** o **9,99 €/mes** (hasta 30 revisiones) |
| Informe | Veredicto, resumen y 5 puntos | Revisión concepto a concepto |
| Cálculos que rehace la app | Sumas y líquido | + cada cotización a la SS e IRPF |
| Explicación de cada línea | — | ✅ |
| Resumen para la reclamación (qué, cuánto, a quién, plazo y mensaje listo para enviar) | — | ✅ |
| Preguntas para RRHH | — | ✅ |
| Preguntas a Nora | 1 | Ilimitadas |
| Informe en PDF | — | ✅ |

- Android: pago con Google Play (`revision_pro` consumible, `pro_mensual` suscripción).
  El servidor verifica cada compra con Google antes de dar saldo.
- Windows: de momento Pro se activa con **códigos de canje** (`python -m app.admin codigo --creditos 1`).
  Pendiente: pago en Windows (Microsoft Store o Stripe).
- Una revisión Pro sólo se cobra si el análisis sale bien.

Límites y precios: `app/planes.py` (servidor) y `app_movil/lib/config.dart` (textos de la app;
en Android el precio real lo pone Google Play).

## Desarrollo

Servidor:

```bash
cd revisor-nominas
pip install -r requirements.txt
export ANTHROPIC_API_KEY=...       # sin clave: modo demo con un informe de ejemplo
export NOMINAS_PAGOS_PRUEBA=1      # acepta compras falsas "prueba-..." (sólo desarrollo)
uvicorn app.main:app --reload --host 0.0.0.0
python -m pytest -q tests
```

App (necesita [Flutter](https://docs.flutter.dev/get-started/install) 3.50):

```bash
cd revisor-nominas/app_movil
flutter run                        # emulador Android: usa http://10.0.2.2:8000
flutter run -d windows             # usa http://localhost:8000
flutter test
```

## Compilar

GitHub Actions (`.github/workflows/revisor-nominas.yml`) compila en cada push:

- **Android**: `app-release.apk` (para instalar a mano) y `app-release.aab` (para Play Store).
- **Windows**: carpeta con `revisor_nominas.exe` lista para ejecutar.

Se descargan en la pestaña *Actions* → la ejecución → *Artifacts*.

Configuración en GitHub (*Settings → Secrets and variables → Actions*):

| Tipo | Nombre | Qué es |
|---|---|---|
| Variable | `NOMINAS_API_URL` | URL pública del servidor, p. ej. `https://api.tudominio.es`. **Sin ella la app no sabe dónde está el servidor.** |
| Secreto | `ANDROID_KEYSTORE_BASE64` | Clave de subida a Play Store (`base64 -w0 upload.jks`) |
| Secreto | `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | Datos de esa clave |

## Servidor en producción

```bash
docker build -t revisor-nominas .
docker run -p 8000:8000 -v datos:/datos \
  -e ANTHROPIC_API_KEY=... \
  -e GOOGLE_PLAY_PAQUETE=es.revisornominas.app \
  -e GOOGLE_PLAY_CREDENCIALES=/datos/google.json \
  revisor-nominas
```

Tiene que ir detrás de **HTTPS** (Android no permite http en la versión publicada).
La base de datos (SQLite) se guarda en el volumen `/datos`: saldos, compras y los informes
(nunca la nómina original).

Variables: `NOMINAS_MODELO` (modelo de Claude, por defecto `claude-opus-5-5`),
`NOMINAS_FREE_POR_DIA` (3), `NOMINAS_MENSUAL_POR_MES` (30).

Para publicar en Google Play, ver [PUBLICAR.md](PUBLICAR.md).
