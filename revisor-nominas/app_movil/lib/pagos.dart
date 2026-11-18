import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// Pago de la revisión completa (2,99 € por revisión, con Google Play). No hay cuentas ni saldo:
///
/// 1. El usuario paga → Google Play da un token de compra.
/// 2. La app manda la nómina y el token al servidor, que verifica la compra con Google.
/// 3. Si el análisis sale bien, la compra se "consume" y ya no vale para otra revisión.
///
/// Si el análisis falla después de pagar, el token se guarda en el móvil y se usa en el
/// siguiente intento: el usuario nunca paga dos veces por la misma revisión.
class Pagos extends ChangeNotifier {
  Pagos._();
  static final yo = Pagos._();

  final _iap = InAppPurchase.instance;
  ProductDetails? _producto;
  bool disponible = false;
  String? error;

  /// Compras pagadas y aún sin usar (token → detalles para poder consumirla).
  final _pendientes = <String, PurchaseDetails?>{};
  Completer<String?>? _esperando;

  /// ¿Hay una revisión completa ya pagada esperando a usarse?
  String? get pagoPendiente => _pendientes.keys.firstOrNull;

  String get precio => _producto?.price ?? precioRevision;

  /// ¿Se puede pagar en este dispositivo? (Google Play sólo existe en Android.)
  bool get sePuedePagar => pagosPrueba || modoDemo || (comprasGooglePlay && disponible);

  Future<void> iniciar() async {
    final prefs = await SharedPreferences.getInstance();
    for (final t in prefs.getStringList('pagos_pendientes') ?? const <String>[]) {
      _pendientes[t] = null;
    }
    if (!comprasGooglePlay) {
      notifyListeners();
      return;
    }
    disponible = await _iap.isAvailable();
    if (disponible) {
      _iap.purchaseStream.listen(_alComprar, onError: (Object e) => _fallo('Error en el pago: $e'));
      final r = await _iap.queryProductDetails({productoRevision});
      _producto = r.productDetails.firstOrNull;
      // Recupera compras pagadas que no llegaron a usarse (p. ej. si se cerró la app).
      await _iap.restorePurchases();
    }
    notifyListeners();
  }

  /// Abre el pago de Google Play. Devuelve el token de compra, o null si se cancela.
  Future<String?> pagar() async {
    final pendiente = pagoPendiente;
    if (pendiente != null) return pendiente;
    if (pagosPrueba || modoDemo) {
      final t = 'prueba-${DateTime.now().microsecondsSinceEpoch}';
      await _guardar(t, null);
      return t;
    }
    final p = _producto;
    if (!disponible || p == null) {
      _fallo('El pago no está disponible ahora mismo. Inténtalo más tarde.');
      return null;
    }
    error = null;
    _esperando = Completer<String?>();
    try {
      // autoConsume: la compra se consume al completarla, y eso sólo se hace tras usarla.
      await _iap.buyConsumable(purchaseParam: PurchaseParam(productDetails: p), autoConsume: true);
    } catch (_) {
      _fallo('No se ha podido abrir el pago.');
      return null;
    }
    return _esperando!.future;
  }

  /// La revisión se ha hecho (o el servidor dice que la compra ya se usó): se consume.
  Future<void> usada(String token) async {
    final d = _pendientes.remove(token);
    await _persistir();
    if (d != null && d.pendingCompletePurchase) await _iap.completePurchase(d);
    notifyListeners();
  }

  Future<void> _alComprar(List<PurchaseDetails> compras) async {
    for (final c in compras) {
      if (c.productID != productoRevision) continue;
      switch (c.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final token = c.verificationData.serverVerificationData;
          await _guardar(token, c);
          _terminar(token);
        case PurchaseStatus.error:
          _fallo(c.error?.message ?? 'El pago no se ha completado.');
        case PurchaseStatus.canceled:
          _terminar(null);
        case PurchaseStatus.pending:
          break; // p. ej. pago en efectivo en tienda: llegará como "purchased" más tarde
      }
    }
  }

  Future<void> _guardar(String token, PurchaseDetails? d) async {
    _pendientes[token] = d ?? _pendientes[token];
    await _persistir();
    notifyListeners();
  }

  Future<void> _persistir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('pagos_pendientes', _pendientes.keys.toList());
  }

  void _terminar(String? token) {
    final e = _esperando;
    _esperando = null;
    if (e != null && !e.isCompleted) e.complete(token);
  }

  void _fallo(String msg) {
    error = msg;
    _terminar(null);
    notifyListeners();
  }
}
