# Publicar en Google Play: lista de pasos

## 1. Servidor
- [ ] Contratar un servidor con HTTPS (Railway, Render, Fly.io, un VPS…) y desplegar el `Dockerfile`.
- [ ] Poner `ANTHROPIC_API_KEY` en el servidor.
- [ ] Guardar la URL en GitHub como variable `NOMINAS_API_URL`.
- [ ] Revisar `app/referencia_2026.json`: confirmar base máxima y rellenar el SMI de 2026.

## 2. Cuenta de desarrollador
- [ ] Alta en [Google Play Console](https://play.google.com/console) (pago único de 25 $).
- [ ] Perfil de pagos (para cobrar las compras). Google se queda un 15 % de las suscripciones
      y del primer millón de ingresos al año.

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
- [ ] Producto integrado `revision_pro` — 2,99 € — "1 revisión Pro".
- [ ] Suscripción `pro_mensual` con un plan base mensual de 9,99 €.
- [ ] Añadir tu cuenta en *Configuración → Pruebas de licencias* para comprar sin pagar.

## 6. Verificación de compras en el servidor
- [ ] Google Cloud: crear una cuenta de servicio y activar la API *Google Play Android Developer*.
- [ ] Play Console → *Usuarios y permisos*: invitar el email de la cuenta de servicio con permiso
      para ver datos financieros y gestionar pedidos.
- [ ] Descargar su JSON y montarlo en el servidor (`GOOGLE_PLAY_CREDENCIALES`).

## 7. Ficha y requisitos legales
- [ ] **Política de privacidad** publicada en una URL (obligatoria: la app trata datos personales y
      salariales). Debe decir: qué se envía (la nómina, sólo para analizarla), que se procesa con un
      proveedor de IA, que no se guarda la nómina y que el informe se guarda para el chat.
- [ ] Formulario de **Seguridad de los datos**: datos financieros y personales, transmitidos cifrados,
      no compartidos con terceros para publicidad.
- [ ] Clasificación de contenido, público objetivo (mayores de 18), capturas de pantalla, icono 512×512,
      gráfico de funciones 1024×500.
- [ ] Aviso en la ficha: informe orientativo, no sustituye a un asesor laboral.

## 8. Windows
- [ ] De momento se distribuye la carpeta compilada (artefacto *revisor-nominas-windows*).
- [ ] Pendiente decidir: Microsoft Store (con su sistema de pagos) o instalador propio con pago por Stripe.
