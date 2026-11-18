import 'dart:async';
import 'dart:convert';

import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

/// Pagos con Google Play. No hay cuentas ni saldo; cada cosa se paga cuando se usa:
///   - revisión completa: 2,99 € ([productoRevision])
///   - informe en PDF de una revisión completa: 0,50 € ([productoPdf])
///
/// 1. El usuario paga → Google Play da un token de compra.
/// 2. La app manda el token al servidor, que lo verifica con Google.
/// 3. Si todo sale bien, la compra se "consume" y ya no vale para otra cosa.
///
/// Si algo falla después de pagar, el token se guarda en el móvil y se usa en el
/// siguiente intento: el usuario nunca paga dos veces por lo mismo.
class Pagos extends ChangeNotifier {
  Pagos._();
  static final yo = Pagos._();

  final _iap = InAppPurchase.instance;
  final _productos = <String, ProductDetails>{};
  bool disponible = false;
  String? error;

  /// Compras pagadas y aún sin usar: token → producto (y detalles para poder consumirla).
  final _pendientes = <String, String>{};
  final _detalles = <String, PurchaseDetails>{};
  final _esperando = <String, Completer<String?>>{};

  /// Token de una compra ya pagada y sin usar de este producto, si la hay.
  String? pagoPendiente(String producto) =>
      _pendientes.entries.where((e) => e.value == producto).map((e) => e.key).firstOrNull;

  String precio(String producto) =>
      _productos[producto]?.price ?? (producto == productoPdf ? precioPdf : precioRevision);

  /// ¿Se puede pagar en este dispositivo? (Google Play sólo existe en Android.)
  bool get sePuedePagar => pagosPrueba || modoDemo || (comprasGooglePlay && disponible);

  Future<void> iniciar() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final guardados = jsonDecode(prefs.getString('pagos_pendientes_v2') ?? '{}') as Map<String, dynamic>;
      guardados.forEach((t, p) => _pendientes[t] = p as String);
    } catch (_) {}
    // Versión anterior: sólo había revisiones.
    for (final t in prefs.getStringList('pagos_pendientes') ?? const <String>[]) {
      _pendientes[t] = productoRevision;
    }
    if (!comprasGooglePlay) {
      notifyListeners();
      return;
    }
    disponible = await _iap.isAvailable();
    if (disponible) {
      _iap.purchaseStream.listen(_alComprar, onError: (Object e) => _fallo(null, 'Error en el pago: $e'));
      final r = await _iap.queryProductDetails({productoRevision, productoPdf});
      for (final p in r.productDetails) {
        _productos[p.id] = p;
      }
      // Recupera compras pagadas que no llegaron a usarse (p. ej. si se cerró la app).
      await _iap.restorePurchases();
    }
    notifyListeners();
  }

  /// Abre el pago de Google Play. Devuelve el token de compra, o null si se cancela.
  Future<String?> pagar(String producto) async {
    final pendiente = pagoPendiente(producto);
    if (pendiente != null) return pendiente;
    if (pagosPrueba || modoDemo) {
      final t = 'prueba-$producto-${DateTime.now().microsecondsSinceEpoch}';
      await _guardar(t, producto);
      return t;
    }
    final p = _productos[producto];
    if (!disponible || p == null) {
      _fallo(producto, 'El pago no está disponible ahora mismo. Inténtalo más tarde.');
      return null;
    }
    error = null;
    final espera = _esperando[producto] = Completer<String?>();
    try {
      // autoConsume: la compra se consume al completarla, y eso sólo se hace tras usarla.
      await _iap.buyConsumable(purchaseParam: PurchaseParam(productDetails: p), autoConsume: true);
    } catch (_) {
      _fallo(producto, 'No se ha podido abrir el pago.');
      return null;
    }
    return espera.future;
  }

  /// La compra ya se ha usado (o el servidor dice que ya estaba usada): se consume.
  Future<void> usada(String token) async {
    _pendientes.remove(token);
    final d = _detalles.remove(token);
    await _persistir();
    if (d != null && d.pendingCompletePurchase) await _iap.completePurchase(d);
    notifyListeners();
  }

  Future<void> _alComprar(List<PurchaseDetails> compras) async {
    for (final c in compras) {
      final producto = c.productID;
      if (producto != productoRevision && producto != productoPdf) continue;
      switch (c.status) {
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          final token = c.verificationData.serverVerificationData;
          _detalles[token] = c;
          await _guardar(token, producto);
          _terminar(producto, token);
        case PurchaseStatus.error:
          _fallo(producto, c.error?.message ?? 'El pago no se ha completado.');
        case PurchaseStatus.canceled:
          _terminar(producto, null);
        case PurchaseStatus.pending:
          break; // p. ej. pago en efectivo en tienda: llegará como "purchased" más tarde
      }
    }
  }

  Future<void> _guardar(String token, String producto) async {
    _pendientes[token] = producto;
    await _persistir();
    notifyListeners();
  }

  Future<void> _persistir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pagos_pendientes_v2', jsonEncode(_pendientes));
    await prefs.remove('pagos_pendientes');
  }

  void _terminar(String producto, String? token) {
    final e = _esperando.remove(producto);
    if (e != null && !e.isCompleted) e.complete(token);
  }

  void _fallo(String? producto, String msg) {
    error = msg;
    if (producto != null) {
      _terminar(producto, null);
    } else {
      for (final p in _esperando.keys.toList()) {
        _terminar(p, null);
      }
    }
    notifyListeners();
  }
}
