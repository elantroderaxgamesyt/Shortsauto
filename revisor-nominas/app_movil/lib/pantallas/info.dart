import 'package:material_ui/material_ui.dart';

import '../anuncios.dart';
import '../config.dart';
import '../widgets.dart';

/// Ayuda, privacidad y datos de la app.
class PantallaInfo extends StatelessWidget {
  const PantallaInfo({super.key});

  static const _consejos = '• Pon la nómina sobre una mesa, con buena luz y sin sombras.\n'
      '• Que se vea la hoja entera, recta y enfocada.\n'
      '• Si tienes el PDF original (portal del empleado o email), mejor súbelo: es más fiable que una foto.';
  static const _privacidad = 'No hace falta registrarse ni crear ninguna cuenta.\n\n'
      'Tu nómina se envía cifrada a nuestro servidor sólo para analizarla con IA y no se guarda. '
      'Guardamos el informe para que puedas volver a consultarlo y hacer preguntas, enmascarando datos '
      'como el DNI, el número de la Seguridad Social o la cuenta bancaria.\n\n'
      'Los pagos los gestiona Google Play: nosotros nunca vemos tus datos de pago.\n\n'
      'En Android mostramos anuncios de Google AdMob. Puedes elegir si son personalizados la primera '
      'vez que abres la app o desde "Privacidad de los anuncios".';
  static const _acerca = 'Revisor de nóminas con IA para nóminas españolas.\n\n'
      'Revisión básica gratis o revisión completa por $precioRevision cada una, sin suscripciones.\n\n'
      'El informe es orientativo y no sustituye el asesoramiento de un graduado social, sindicato o '
      'abogado laboralista.';

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Información')),
        body: SafeArea(
          child: Pagina(children: [
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                _Enlace(Icons.photo_camera_outlined, 'Cómo hacer una buena foto de la nómina',
                    () => _texto(context, 'Consejos para la foto', _consejos)),
                const Divider(),
                _Enlace(Icons.lock_outline_rounded, 'Privacidad', () => _texto(context, 'Privacidad', _privacidad)),
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
                _Enlace(Icons.info_outline_rounded, 'Acerca de', () => _texto(context, 'Revisor de nóminas', _acerca)),
              ]),
            ),
          ]),
        ),
      );

  static void _texto(BuildContext context, String titulo, String texto) => showModalBottomSheet(
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
