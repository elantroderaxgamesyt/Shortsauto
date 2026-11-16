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

/// Las compras con Google Play sólo existen en Android.
bool get comprasGooglePlay => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

const productoRevision = 'revision_pro'; // 2,99 €
const productoMensual = 'pro_mensual'; // 9,99 €/mes
const precioRevision = '2,99 €';
const precioMensual = '9,99 €/mes';
