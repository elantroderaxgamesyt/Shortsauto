import 'package:flutter/foundation.dart';

/// Dirección del servidor. En producción se pasa al compilar:
///   flutter build appbundle --dart-define=API_URL=https://api.tudominio.es
String get apiUrl {
  const definida = String.fromEnvironment('API_URL');
  if (definida.isNotEmpty) return definida;
  if (kIsWeb) return '';
  // El emulador de Android ve el ordenador como 10.0.2.2.
  if (defaultTargetPlatform == TargetPlatform.android) return 'http://10.0.2.2:8000';
  return 'http://localhost:8000';
}

/// Los pagos con Google Play sólo existen en Android.
bool get comprasGooglePlay => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Sólo desarrollo: simula el pago (el servidor debe tener NOMINAS_PAGOS_PRUEBA=1).
///   flutter run --dart-define=PAGOS_PRUEBA=true
const pagosPrueba = bool.fromEnvironment('PAGOS_PRUEBA');

const productoRevision = 'revision_pro'; // revisión completa, pago por revisión
const precioRevision = '2,99 €';

/// Anuncios (Google AdMob): sólo en Android.
bool get anunciosActivos => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

// Bloques de anuncios. Por defecto, los de PRUEBA de Google (no generan dinero
// y se pueden pulsar sin riesgo). Los reales se pasan al compilar:
//   --dart-define=ADMOB_BANNER=ca-app-pub-XXXX/YYYY --dart-define=ADMOB_APERTURA=ca-app-pub-XXXX/ZZZZ
const admobBanner = String.fromEnvironment('ADMOB_BANNER', defaultValue: 'ca-app-pub-3940256099942544/9214589741');
const admobApertura = String.fromEnvironment('ADMOB_APERTURA', defaultValue: 'ca-app-pub-3940256099942544/9257395921');
