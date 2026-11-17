import 'package:material_ui/material_ui.dart';

import '../compras.dart';
import '../config.dart';
import '../tema.dart';
import '../widgets.dart';

/// Pantalla para comprar Pro (se abre cuando hace falta saldo).
class PantallaTienda extends StatefulWidget {
  const PantallaTienda({super.key});

  @override
  State<PantallaTienda> createState() => _PantallaTiendaState();
}

class _PantallaTiendaState extends State<PantallaTienda> {
  late final int _saldoInicial;
  bool _cerrada = false;

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

  /// En cuanto la compra se confirma, volvemos a donde estaba el usuario.
  void _alCambiar() {
    if (!_cerrada && mounted && _saldo() > _saldoInicial && Navigator.of(context).canPop()) {
      _cerrada = true;
      aviso(context, '¡Listo! Ya tienes la revisión completa.');
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Revisión completa')),
        body: const SafeArea(child: Pagina(children: [ContenidoTienda()])),
      );
}

/// Productos, restaurar compras y canjear código. Se usa en la tienda y en Mi cuenta.
class ContenidoTienda extends StatefulWidget {
  const ContenidoTienda({super.key, this.cabecera = true});
  final bool cabecera;

  @override
  State<ContenidoTienda> createState() => _ContenidoTiendaState();
}

class _ContenidoTiendaState extends State<ContenidoTienda> {
  final codigo = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tonos = Tonos.de(context);
    return ListenableBuilder(
      listenable: Tienda.yo,
      builder: (context, _) {
        final tienda = Tienda.yo;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.cabecera) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(gradient: Marca.degradadoPro, borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 32),
                const Hueco(10),
                Text('Revisión completa', style: t.textTheme.titleLarge?.copyWith(color: Colors.white)),
                const Hueco(10),
                for (final v in [
                  'Revisión concepto a concepto',
                  'Recalculamos Seguridad Social e IRPF',
                  'Resumen para la reclamación, listo para enviar',
                  'Preguntas ilimitadas a Nora',
                  'Informe en PDF',
                  if (anunciosActivos) 'Sin anuncios',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Row(children: [
                      const Icon(Icons.check_rounded, color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(v, style: TextStyle(color: Colors.white.withValues(alpha: .92)))),
                    ]),
                  ),
              ]),
            ),
            const Hueco(16),
          ],
          _Producto(
            titulo: 'Una revisión',
            detalle: 'Pago único para revisar una nómina a fondo.',
            precio: tienda.precio(productoRevision, precioRevision),
            onComprar: comprasGooglePlay && !tienda.ocupada ? () => tienda.comprar(productoRevision) : null,
          ),
          const Hueco(10),
          _Producto(
            titulo: 'Pro mensual',
            detalle: 'Hasta 30 revisiones al mes, para ti o tu familia. Cancela cuando quieras.',
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
                'En esta versión aún no se puede pagar dentro de la app. Si tienes un código, canjéalo abajo.',
                style: t.textTheme.bodySmall?.copyWith(color: tonos.suave),
              ),
            ),
          if (comprasGooglePlay)
            Align(child: TextButton(onPressed: tienda.restaurar, child: const Text('Restaurar compras'))),
          const Hueco(16),
          Text('¿Tienes un código?', style: t.textTheme.titleSmall),
          const Hueco(8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: codigo,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'XXXX-XXXX-XXXX'),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 48,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: () async {
                  await tienda.canjear(codigo.text);
                  if (context.mounted && tienda.error == null) {
                    codigo.clear();
                    aviso(context, 'Código canjeado.');
                  }
                },
                child: const Text('Canjear'),
              ),
            ),
          ]),
          if (comprasGooglePlay) ...[
            const Hueco(16),
            Text(
              'El pago se hace con tu cuenta de Google Play. La suscripción se renueva cada mes y puedes '
              'cancelarla en cualquier momento desde Google Play > Suscripciones.',
              style: t.textTheme.bodySmall?.copyWith(color: tonos.suave),
            ),
          ],
        ]);
      },
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
    final tonos = Tonos.de(context);
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Marca.radio),
        side: BorderSide(color: destacado ? Marca.pro : tonos.borde, width: destacado ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
                Text(titulo, style: t.textTheme.titleMedium),
                if (destacado) const InsigniaPro(texto: 'MÁS COMPLETO'),
              ]),
              const SizedBox(height: 4),
              Text(detalle, style: t.textTheme.bodySmall?.copyWith(color: tonos.suave, height: 1.4)),
            ]),
          ),
          const SizedBox(width: 12),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Marca.pro,
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onPressed: onComprar,
            child: Text(precio),
          ),
        ]),
      ),
    );
  }
}
