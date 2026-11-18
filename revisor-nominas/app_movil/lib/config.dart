import 'package:flutter/foundation.dart';

/// Dirección del servidor. Se pasa al compilar:
///   flutter build appbundle --dart-define=API_URL=https://api.tudominio.es
///   (emulador de Android con el servidor en el ordenador: API_URL=http://10.0.2.2:8000)
/// Sin ella, la app funciona en **modo demo**: sin servidor, con un informe de ejemplo.
const apiUrl = String.fromEnvironment('API_URL');

bool get modoDemo => apiUrl.isEmpty;

/// Los pagos con Google Play sólo existen en Android.
bool get comprasGooglePlay => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Sólo desarrollo: simula el pago (el servidor debe tener NOMINAS_PAGOS_PRUEBA=1).
///   flutter run --dart-define=PAGOS_PRUEBA=true
const pagosPrueba = bool.fromEnvironment('PAGOS_PRUEBA');

const productoRevision = 'revision_pro'; // revisión completa, pago por revisión
const precioRevision = '2,99 €';
const productoPdf = 'informe_pdf'; // informe en PDF de una revisión completa
const precioPdf = '0,50 €';

/// Anuncios (Google AdMob): sólo en Android.
bool get anunciosActivos => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

// Bloques de anuncios. Por defecto, los de PRUEBA de Google (no generan dinero
// y se pueden pulsar sin riesgo). Los reales se pasan al compilar:
//   --dart-define=ADMOB_BANNER=… --dart-define=ADMOB_APERTURA=… --dart-define=ADMOB_RECOMPENSA=…
const admobBanner = String.fromEnvironment('ADMOB_BANNER', defaultValue: 'ca-app-pub-3940256099942544/9214589741');
const admobApertura = String.fromEnvironment('ADMOB_APERTURA', defaultValue: 'ca-app-pub-3940256099942544/9257395921');
const admobRecompensa =
    String.fromEnvironment('ADMOB_RECOMPENSA', defaultValue: 'ca-app-pub-3940256099942544/5224354917');

/// Sólo desarrollo (web/Windows, donde no hay AdMob): simula los anuncios con recompensa.
const simularAnuncios = bool.fromEnvironment('SIMULAR_ANUNCIOS');
