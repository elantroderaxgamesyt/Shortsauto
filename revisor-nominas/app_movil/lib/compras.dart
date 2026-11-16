import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'api.dart';
import 'config.dart';

/// Compras con Google Play. El servidor verifica cada compra con Google
/// antes de dar el saldo; la app nunca da saldo por su cuenta.
class Tienda extends ChangeNotifier {
  Tienda._();
  static final yo = Tienda._();

  final _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  Map<String, ProductDetails> productos = {};
  bool disponible = false;
  bool ocupada = false;
  String? error;
  Cuenta? cuenta;

  Future<void> iniciar() async {
    await refrescarCuenta();
    if (!comprasGooglePlay) return;
    disponible = await _iap.isAvailable();
    if (!disponible) {
      notifyListeners();
      return;
    }
    _sub = _iap.purchaseStream.listen(_alComprar, onError: (e) {
      error = 'Error en la compra: $e';
      ocupada = false;
      notifyListeners();
    });
    final r = await _iap.queryProductDetails({productoRevision, productoMensual});
    productos = {for (final p in r.productDetails) p.id: p};
    notifyListeners();
  }

  Future<void> refrescarCuenta() async {
    try {
      cuenta = await Api.yo.cuenta();
      error = null;
    } on ErrorApi catch (e) {
      error = e.mensaje;
    }
    notifyListeners();
  }

  String precio(String id, String porDefecto) => productos[id]?.price ?? porDefecto;

  Future<void> comprar(String id) async {
    final p = productos[id];
    if (p == null) {
      error = 'Este producto no está disponible ahora mismo.';
      notifyListeners();
      return;
    }
    error = null;
    ocupada = true;
    notifyListeners();
    final param = PurchaseParam(productDetails: p);
    try {
      if (id == productoRevision) {
        await _iap.buyConsumable(purchaseParam: param, autoConsume: true);
      } else {
        await _iap.buyNonConsumable(purchaseParam: param);
      }
    } catch (e) {
      error = 'No se ha podido iniciar la compra.';
      ocupada = false;
      notifyListeners();
    }
  }

  Future<void> restaurar() async {
    if (disponible) await _iap.restorePurchases();
    await refrescarCuenta();
  }

  Future<void> _alComprar(List<PurchaseDetails> compras) async {
    for (final c in compras) {
      var confirmar = true;
      switch (c.status) {
        case PurchaseStatus.pending:
          ocupada = true;
        case PurchaseStatus.error:
          error = c.error?.message ?? 'La compra no se ha completado.';
          ocupada = false;
        case PurchaseStatus.canceled:
          ocupada = false;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          try {
            cuenta = await Api.yo.compraGoogle(c.productID, c.verificationData.serverVerificationData);
            error = null;
          } on ErrorApi catch (e) {
            error = e.mensaje;
            // Si el servidor no ha podido verificarla (p. ej. sin conexión), no se confirma:
            // Google la vuelve a entregar al abrir la app y se reintenta.
            confirmar = e.codigo == 400;
            if (!confirmar) error = 'Compra recibida. Se aplicará en cuanto haya conexión con el servidor.';
          }
          ocupada = false;
      }
      // Hay que confirmar la compra a Google o la reembolsa a los 3 días.
      if (confirmar && c.pendingCompletePurchase) await _iap.completePurchase(c);
      notifyListeners();
    }
  }

  Future<void> canjear(String codigo) async {
    try {
      cuenta = await Api.yo.canjear(codigo);
      error = null;
    } on ErrorApi catch (e) {
      error = e.mensaje;
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
