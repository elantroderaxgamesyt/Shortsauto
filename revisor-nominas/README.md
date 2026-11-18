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

## Revisión básica (gratis) y completa (2,99 €)

Una sola app gratuita, **sin cuentas ni registro y sin suscripciones**. La revisión completa se
paga cada vez que se hace (2,99 €, compra dentro de la app).

| | Básica | Completa |
|---|---|---|
| Precio | Gratis (3 revisiones/día) | **2,99 € por revisión** |
| Informe | Veredicto, resumen y 5 puntos | Revisión concepto a concepto |
| Cálculos que rehace la app | Sumas y líquido | + cada cotización a la SS e IRPF |
| Explicación de cada línea | — | ✅ |
| Resumen para la reclamación (qué, cuánto, a quién, plazo y mensaje listo para enviar) | — | ✅ |
| Preguntas para RRHH | — | ✅ |
| Preguntas a Nora | 1 por anuncio visto (máx. 5) | 3 sin anuncios + 1 por anuncio visto (máx. 5) |
| Informe en PDF | — | ✅ |

Anuncios (sólo Android): al abrir la app (máx. 1 cada 4 h) y un banner en Inicio y Mis revisiones.
Nunca dentro del informe.

Cómo funciona el pago (`app_movil/lib/pagos.dart`, `app/google_play.py`):
1. El usuario elige la revisión completa y paga con Google Play (producto consumible `revision_pro`).
2. La app manda la nómina y el token de la compra; el servidor lo verifica con Google.
3. Si el análisis sale bien, la compra se consume y queda registrada: no vale para otra revisión.
   Si falla, el pago se queda guardado en el móvil y se usa en el siguiente intento.

Sin cuentas: cada instalación manda un identificador anónimo (`X-Dispositivo`) que sólo sirve para el
límite diario gratis, el historial y el chat. Windows: de momento sólo revisión básica (no hay Google
Play); pendiente decidir pago (Microsoft Store o Stripe).

Anuncios: Google AdMob (`app_movil/lib/anuncios.dart`). Antes de cargar ninguno se pide el
consentimiento del RGPD con el formulario oficial de Google. Nunca salen en el informe ni la primera
vez que se abre la app. Mientras no configures tu cuenta se usan los anuncios de **prueba** de Google.

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
| Variable | `NOMINAS_API_URL` | URL pública del servidor, p. ej. `https://api.tudominio.es`. **Sin ella la app se compila en modo demo** (sin servidor, informe de ejemplo y pagos simulados). |
| Secreto | `ANDROID_KEYSTORE_BASE64` | Clave de subida a Play Store (`base64 -w0 upload.jks`) |
| Secreto | `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` | Datos de esa clave |
| Variable | `ADMOB_APP_ID` | Id de la app en AdMob (`ca-app-pub-…~…`) |
| Variable | `ADMOB_BANNER`, `ADMOB_APERTURA`, `ADMOB_RECOMPENSA` | Ids de los bloques de anuncios (`ca-app-pub-…/…`) |

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

Preguntas a Nora: `NOMINAS_PREGUNTAS_GRATIS` (0) y `NOMINAS_PREGUNTAS_COMPLETA` (3) incluidas;
después 1 por anuncio con recompensa, hasta `NOMINAS_MAX_PREGUNTAS_ANUNCIO` (5) por revisión.
`NOMINAS_VERIFICACION_ANUNCIOS`: `app` (se fía de la app; sólo con anuncios de prueba) o `ssv`
(Google avisa al servidor en `/api/admob/recompensa` con firma; **obligatorio con anuncios reales**).

Variables: modelos de Claude `NOMINAS_MODELO_FREE` y `NOMINAS_MODELO_CHAT` (por defecto
`claude-haiku-5-5`, el más barato) y `NOMINAS_MODELO_PRO` (por defecto `claude-opus-5-5`, el de
más calidad, sólo para la revisión de pago),
`NOMINAS_FREE_POR_DIA` (3), `NOMINAS_MENSUAL_POR_MES` (30).

Para publicar en Google Play, ver [PUBLICAR.md](PUBLICAR.md).
