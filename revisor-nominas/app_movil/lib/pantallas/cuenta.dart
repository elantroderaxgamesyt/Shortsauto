import 'package:material_ui/material_ui.dart';

import '../anuncios.dart';
import '../compras.dart';
import '../tema.dart';
import '../widgets.dart';
import 'tienda.dart';

class PantallaCuenta extends StatelessWidget {
  const PantallaCuenta({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tonos = Tonos.de(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Mi cuenta')),
      body: RefreshIndicator(
        onRefresh: Tienda.yo.refrescarCuenta,
        child: Pagina(children: [
          ListenableBuilder(
            listenable: Tienda.yo,
            builder: (context, _) {
              final c = Tienda.yo.cuenta;
              if (c == null) {
                return Panel(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Icon(Icons.cloud_off_rounded, color: tonos.suave),
                    const SizedBox(width: 12),
                    Expanded(child: Text(Tienda.yo.error ?? 'Cargando…')),
                    IconButton(onPressed: Tienda.yo.refrescarCuenta, icon: const Icon(Icons.refresh_rounded)),
                  ]),
                );
              }
              Widget fila(IconData ic, String titulo, String valor, {Color? color}) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Row(children: [
                      Icon(ic, size: 20, color: color ?? tonos.suave),
                      const SizedBox(width: 12),
                      Expanded(child: Text(titulo)),
                      Text(valor, style: t.textTheme.titleSmall?.copyWith(color: color)),
                    ]),
                  );
              return Panel(
                titulo: 'Tu saldo',
                icono: Icons.account_balance_wallet_outlined,
                child: Column(children: [
                  fila(Icons.workspace_premium_outlined, 'Pro mensual',
                      c.suscripcion ? 'Activo · ${c.mensualRestantes} este mes' : 'No activo',
                      color: c.suscripcion ? Marca.pro : null),
                  const Divider(),
                  fila(Icons.confirmation_number_outlined, 'Revisiones completas', '${c.creditos}',
                      color: c.creditos > 0 ? Marca.pro : null),
                  const Divider(),
                  fila(Icons.today_outlined, 'Revisiones gratis hoy', '${c.freeHoy}'),
                ]),
              );
            },
          ),
          const Hueco(24),
          Text('Conseguir la revisión completa', style: t.textTheme.titleMedium),
          const Hueco(12),
          const ContenidoTienda(cabecera: false),
          const Hueco(24),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              _Enlace(Icons.help_outline_rounded, 'Cómo hacer una buena foto de la nómina', () => _info(context, 'Consejos para la foto', _consejos)),
              const Divider(),
              _Enlace(Icons.lock_outline_rounded, 'Privacidad', () => _info(context, 'Privacidad', _privacidad)),
              ListenableBuilder(
                listenable: Anuncios.yo,
                builder: (context, _) => !Anuncios.yo.privacidadRequerida
                    ? const SizedBox.shrink()
                    : Column(children: [
                        const Divider(),
                        _Enlace(Icons.ads_click_rounded, 'Privacidad de los anuncios', Anuncios.yo.abrirPrivacidad),
                      ]),
              ),
              const Divider(),
              _Enlace(Icons.info_outline_rounded, 'Acerca de', () => _info(context, 'Revisor de nóminas', _acerca)),
            ]),
          ),
        ]),
      ),
    );
  }

  static const _consejos = '• Pon la nómina sobre una mesa, con buena luz y sin sombras.\n'
      '• Que se vea la hoja entera, recta y enfocada.\n'
      '• Si tienes el PDF original (portal del empleado o email), mejor súbelo: es más fiable que una foto.';
  static const _privacidad = 'Tu nómina se envía cifrada a nuestro servidor sólo para analizarla con IA y no se '
      'guarda. Guardamos el informe resultante para que puedas consultarlo y hacer preguntas, '
      'enmascarando datos como el DNI, el número de la Seguridad Social o la cuenta bancaria. '
      'No pedimos registro: tu cuenta es un identificador anónimo de este dispositivo.\n\n'
      'En la versión gratuita para Android mostramos anuncios de Google AdMob. Puedes elegir si son '
      'personalizados al abrir la app o desde "Privacidad de los anuncios". Con Pro no hay anuncios.';
  static const _acerca = 'Revisor de nóminas con IA para nóminas españolas.\n\n'
      'El informe es orientativo y no sustituye el asesoramiento de un graduado social, sindicato o abogado laboralista.';

  static void _info(BuildContext context, String titulo, String texto) => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(titulo, style: Theme.of(context).textTheme.titleLarge),
              const Hueco(12),
              Text(texto, style: Theme.of(context).textTheme.bodyLarge),
            ]),
          ),
        ),
      );
}

class _Enlace extends StatelessWidget {
  const _Enlace(this.icono, this.texto, this.onTap);
  final IconData icono;
  final String texto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icono),
        title: Text(texto),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      );
}
