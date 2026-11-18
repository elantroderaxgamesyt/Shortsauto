# Publicar en Google Play: lista de pasos

## 1. Servidor
- [ ] Contratar un servidor con HTTPS (Railway, Render, Fly.io, un VPS…) y desplegar el `Dockerfile`.
- [ ] Poner `ANTHROPIC_API_KEY` en el servidor.
- [ ] Guardar la URL en GitHub como variable `NOMINAS_API_URL`.
- [ ] Revisar `app/referencia_2026.json`: confirmar base máxima y rellenar el SMI de 2026.

## 2. Cuenta de desarrollador
- [ ] Alta en [Google Play Console](https://play.google.com/console) (pago único de 25 $).
- [ ] Perfil de pagos (para cobrar las compras). Google se queda un 15 % del primer millón de
      ingresos al año.

## 3. Firma de la app
```bash
keytool -genkey -v -keystore upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias subida
base64 -w0 upload.jks   # → secreto ANDROID_KEYSTORE_BASE64
```
- [ ] Guardar `upload.jks` y sus contraseñas en un sitio seguro (si se pierden, hay que pedir a Google que la cambie).
- [ ] Crear los 4 secretos en GitHub (ver README) y lanzar el workflow → descargar `app-release.aab`.

## 4. Crear la app en Play Console
- [ ] Nombre: *Revisor de nóminas* (o el definitivo). Id del paquete: `es.revisornominas.app`
      (está en `app_movil/android/app/build.gradle.kts`; **no se puede cambiar una vez publicada**).
- [ ] Subir el `.aab` a **Pruebas internas** primero (las compras sólo funcionan con la app subida a Play).

## 5. Productos
En *Monetizar → Productos*:
- [ ] Producto integrado (consumible) `revision_pro` — 2,99 € — "Revisión completa de una nómina".
- [ ] Añadir tu cuenta en *Configuración → Pruebas de licencias* para comprar sin pagar.

## 6. Verificación de compras en el servidor
- [ ] Google Cloud: crear una cuenta de servicio y activar la API *Google Play Android Developer*.
- [ ] Play Console → *Usuarios y permisos*: invitar el email de la cuenta de servicio con permiso
      para ver datos financieros y gestionar pedidos.
- [ ] Descargar su JSON y montarlo en el servidor (`GOOGLE_PLAY_CREDENCIALES`).

## 7. Anuncios (AdMob)
- [ ] Alta gratuita en [AdMob](https://admob.google.com) con tu cuenta de Google; datos fiscales y de pago (IBAN).
- [ ] *Apps → Añadir app* (Android, vinculada a Play) y crear dos bloques: **Banner** y **Apertura de app**.
- [ ] Guardar en GitHub las variables `ADMOB_APP_ID`, `ADMOB_BANNER` y `ADMOB_APERTURA` y recompilar.
- [ ] *Privacidad y mensajes*: crear el mensaje de **RGPD** (consentimiento) para la UE. La app ya lo muestra.
- [ ] *Bloquear contenido*: quitar categorías que no pegan con la app (préstamos rápidos, apuestas, citas…).
- [ ] Publicar `app-ads.txt` (te lo da AdMob) en la raíz de la web que pongas como sitio del desarrollador en Play.
- [ ] Play Console → *Contenido de la app*: marcar **"Contiene anuncios"** y actualizar *Seguridad de los datos*
      (AdMob recoge el id de publicidad y datos del dispositivo).
- [ ] **Nunca** pulses tus propios anuncios reales: Google puede cerrar la cuenta. Para probar, usa los de prueba.

## 8. Cobros
- Revisiones completas: Google Play las cobra y, tras su comisión (15 %), transfiere el resto cada mes a la
  cuenta bancaria del perfil de pagos de Play Console.
- Anuncios: AdMob paga hacia el día 21 del mes siguiente si se supera el mínimo (unos 70 €).
- Los costes (IA, servidor) se pagan aparte. Consulta con un gestor el alta como autónomo, el IVA y el ROI.

## 9. Ficha y requisitos legales
- [ ] **Política de privacidad** publicada en una URL (obligatoria: la app trata datos personales y
      salariales). Debe decir: qué se envía (la nómina, sólo para analizarla), que se procesa con un
      proveedor de IA, que no se guarda la nómina y que el informe se guarda para el chat.
- [ ] Formulario de **Seguridad de los datos**: la nómina (datos financieros y personales) se transmite
      cifrada y no se comparte; el id de publicidad y datos del dispositivo los recoge Google AdMob para
      los anuncios de la versión gratuita.
- [ ] Clasificación de contenido, público objetivo (mayores de 18), capturas de pantalla, icono 512×512,
      gráfico de funciones 1024×500.
- [ ] Aviso en la ficha: informe orientativo, no sustituye a un asesor laboral.

## 10. Windows
- [ ] De momento se distribuye la carpeta compilada (artefacto *revisor-nominas-windows*).
- [ ] Pendiente decidir: Microsoft Store (con su sistema de pagos) o instalador propio con pago por Stripe.
