import 'package:material_ui/material_ui.dart';

import '../compras.dart';
import '../config.dart';
import '../main.dart';
import '../widgets.dart';

class PantallaTienda extends StatefulWidget {
  const PantallaTienda({super.key});

  @override
  State<PantallaTienda> createState() => _PantallaTiendaState();
}

class _PantallaTiendaState extends State<PantallaTienda> {
  final codigo = TextEditingController();
  int? _saldoInicial;

  @override
  void initState() {
    super.initState();
    _saldoInicial = _saldo();
    Tienda.yo.addListener(_alCambiar);
  }

  @override
  void dispose() {
    Tienda.yo.removeListener(_alCambiar);
    super.dispose();
  }

  int _saldo() {
    final c = Tienda.yo.cuenta;
    return c == null ? 0 : c.creditos + (c.suscripcion ? 1000 : 0);
  }

  /// En cuanto la compra se confirma, volvemos a la pantalla anterior.
  void _alCambiar() {
    if (mounted && _saldo() > (_saldoInicial ?? 0) && Navigator.of(context).canPop()) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('¡Listo! Ya tienes Pro.')));
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Revisor Pro')),
      body: ListenableBuilder(
        listenable: Tienda.yo,
        builder: (context, _) {
          final tienda = Tienda.yo;
          final c = tienda.cuenta;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Centrado(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('La revisión completa de tu nómina', style: t.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                const Text('Recalculamos cada cotización y el IRPF, te explicamos cada línea, preparamos las '
                    'un resumen para la reclamación listo para enviar, con preguntas ilimitadas a Nora e informe en PDF.'),
                const SizedBox(height: 16),
                if (c != null && (c.creditos > 0 || c.suscripcion))
                  Card(
                    color: ColoresEstado.de(context, 'ok').fondo,
                    child: ListTile(
                      leading: const Icon(Icons.workspace_premium, color: morado),
                      title: Text([
                        if (c.suscripcion) 'Pro mensual activo (${c.mensualRestantes} revisiones este mes)',
                        if (c.creditos > 0) '${c.creditos} revisión${c.creditos == 1 ? '' : 'es'} Pro disponibles',
                      ].join('\n')),
                    ),
                  ),
                const SizedBox(height: 8),
                _Producto(
                  titulo: '1 revisión Pro',
                  detalle: 'Pago único para revisar una nómina.',
                  precio: tienda.precio(productoRevision, precioRevision),
                  onComprar: comprasGooglePlay && !tienda.ocupada ? () => tienda.comprar(productoRevision) : null,
                ),
                const SizedBox(height: 10),
                _Producto(
                  titulo: 'Pro mensual',
                  detalle: 'Hasta 30 revisiones al mes. Ideal si revisas varias nóminas o para toda la familia. '
                      'Cancela cuando quieras desde Google Play.',
                  precio: tienda.precio(productoMensual, precioMensual),
                  destacado: true,
                  onComprar: comprasGooglePlay && !tienda.ocupada ? () => tienda.comprar(productoMensual) : null,
                ),
                if (tienda.ocupada) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
                if (tienda.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(tienda.error!, style: TextStyle(color: t.colorScheme.error)),
                  ),
                if (!comprasGooglePlay)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      'En esta versión el pago dentro de la app aún no está disponible. '
                      'Si tienes un código Pro, canjéalo aquí abajo.',
                      style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                  ),
                if (comprasGooglePlay)
                  TextButton(onPressed: tienda.restaurar, child: const Text('Restaurar compras')),
                const Divider(height: 32),
                Text('¿Tienes un código?', style: t.textTheme.titleSmall),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: codigo,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(hintText: 'XXXX-XXXX-XXXX', border: OutlineInputBorder()),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(onPressed: () => tienda.canjear(codigo.text), child: const Text('Canjear')),
                ]),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}

class _Producto extends StatelessWidget {
  const _Producto({required this.titulo, required this.detalle, required this.precio, this.onComprar, this.destacado = false});
  final String titulo, detalle, precio;
  final VoidCallback? onComprar;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: destacado ? morado : t.colorScheme.outlineVariant, width: destacado ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(titulo, style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                if (destacado) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: morado, borderRadius: BorderRadius.circular(6)),
                    child: const Text('Más completo', style: TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ],
              ]),
              const SizedBox(height: 4),
              Text(detalle, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(width: 12),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: morado),
            onPressed: onComprar,
            child: Text(precio),
          ),
        ]),
      ),
    );
  }
}
