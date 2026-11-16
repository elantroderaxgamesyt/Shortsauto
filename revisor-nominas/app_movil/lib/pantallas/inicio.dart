import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../compras.dart';
import '../config.dart';
import '../main.dart';
import '../widgets.dart';
import 'informe.dart';
import 'tienda.dart';

class PantallaInicio extends StatefulWidget {
  const PantallaInicio({super.key});

  @override
  State<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends State<PantallaInicio> {
  String plan = 'free';
  Uint8List? datos;
  String? nombre;
  bool analizando = false;

  bool get camara => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> elegirArchivo() async {
    final f = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
    );
    if (f == null) return;
    final b = await f.xFile.readAsBytes();
    setState(() {
      datos = b;
      nombre = f.name;
    });
  }

  Future<void> hacerFoto() async {
    final f = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2400);
    if (f == null) return;
    final b = await f.readAsBytes();
    setState(() {
      datos = b;
      nombre = 'foto_nomina.jpg';
    });
  }

  Future<void> analizar() async {
    final tienda = Tienda.yo;
    if (plan == 'pro' && !(tienda.cuenta?.puedePro ?? false)) {
      await abrirTienda();
      if (!(Tienda.yo.cuenta?.puedePro ?? false)) return;
    }
    setState(() => analizando = true);
    try {
      final r = await Api.yo.analizar(datos!, nombre!, plan);
      await tienda.refrescarCuenta();
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => PantallaInforme(r, datos: datos!, nombre: nombre!)));
    } on ErrorApi catch (e) {
      if (!mounted) return;
      if (e.sinSaldo && plan == 'pro') {
        await abrirTienda();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
      }
    } finally {
      if (mounted) setState(() => analizando = false);
    }
  }

  Future<void> abrirTienda() =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PantallaTienda()));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final pro = plan == 'pro';
    final acento = pro ? morado : azul;
    if (analizando) return const _Cargando();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisor de nóminas'),
        actions: [
          IconButton(tooltip: 'Comprar Pro', icon: const Icon(Icons.workspace_premium_outlined), onPressed: abrirTienda),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Centrado(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('¿Tu nómina está bien?', style: t.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                'Sube tu nómina o hazle una foto. Nora, nuestra asesora con IA, la revisa concepto '
                'por concepto y te explica qué está bien y qué no.',
                style: t.textTheme.bodyLarge?.copyWith(color: t.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              const _Saldo(),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'free', label: Text('Free'), icon: Icon(Icons.description_outlined)),
                  ButtonSegment(value: 'pro', label: Text('Pro'), icon: Icon(Icons.workspace_premium_outlined)),
                ],
                selected: {plan},
                onSelectionChanged: (s) => setState(() => plan = s.first),
              ),
              const SizedBox(height: 12),
              _Ventajas(pro: pro),
              const SizedBox(height: 16),
              _ZonaArchivo(nombre: nombre, onElegir: elegirArchivo, onFoto: camara ? hacerFoto : null),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: acento, padding: const EdgeInsets.all(16)),
                onPressed: datos == null ? null : analizar,
                child: Text(pro ? 'Revisión completa (Pro)' : 'Revisar nómina gratis'),
              ),
              const SizedBox(height: 10),
              Text(
                'Tu nómina se envía al servidor sólo para analizarla y no se guarda. '
                'Este informe es orientativo y no sustituye el asesoramiento de un profesional.',
                style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Saldo extends StatelessWidget {
  const _Saldo();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Tienda.yo,
        builder: (context, _) {
          final c = Tienda.yo.cuenta;
          if (c == null) {
            final err = Tienda.yo.error;
            return err == null
                ? const SizedBox.shrink()
                : Card(
                    color: Theme.of(context).colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.cloud_off),
                      title: Text(err),
                      trailing: IconButton(icon: const Icon(Icons.refresh), onPressed: Tienda.yo.refrescarCuenta),
                    ),
                  );
          }
          final textos = <String>[
            if (c.suscripcion) 'Pro mensual activo · ${c.mensualRestantes} revisiones este mes',
            if (c.creditos > 0) '${c.creditos} revisión${c.creditos == 1 ? '' : 'es'} Pro',
            '${c.freeHoy} revisiones gratis hoy',
          ];
          return Card(
            child: ListTile(
              leading: Icon(c.puedePro ? Icons.workspace_premium : Icons.account_balance_wallet_outlined,
                  color: c.puedePro ? morado : null),
              title: Text(textos.first),
              subtitle: textos.length > 1 ? Text(textos.skip(1).join(' · ')) : null,
            ),
          );
        },
      );
}

class _Ventajas extends StatelessWidget {
  const _Ventajas({required this.pro});
  final bool pro;

  static const free = [
    'Veredicto y resumen sencillo',
    'Los 5 puntos más importantes',
    'Comprobación de sumas y líquido',
    '1 pregunta a Nora',
  ];
  static const pros = [
    'Revisión completa concepto a concepto',
    'Recalcula Seguridad Social e IRPF',
    'Explicación de cada línea de la nómina',
    'Resumen para la reclamación, listo para enviar',
    'Preguntas ilimitadas a Nora',
    'Informe en PDF',
  ];

  @override
  Widget build(BuildContext context) {
    final color = pro ? morado : azul;
    return Card(
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), side: BorderSide(color: color.withValues(alpha: .5), width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final v in pro ? pros : free)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(children: [
                Icon(Icons.check_circle, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(v)),
              ]),
            ),
          if (pro)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('$precioRevision por revisión o $precioMensual',
                  style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            ),
        ]),
      ),
    );
  }
}

class _ZonaArchivo extends StatelessWidget {
  const _ZonaArchivo({required this.nombre, required this.onElegir, this.onFoto});
  final String? nombre;
  final VoidCallback onElegir;
  final VoidCallback? onFoto;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onElegir,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.colorScheme.outlineVariant, width: 2),
          ),
          child: Column(children: [
            Icon(nombre == null ? Icons.upload_file : Icons.description, size: 36, color: t.colorScheme.primary),
            const SizedBox(height: 8),
            Text(nombre ?? 'Elige tu nómina (PDF o imagen)', textAlign: TextAlign.center, style: t.textTheme.titleSmall),
            if (nombre != null)
              Text('Toca para cambiarla', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
      if (onFoto != null) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(onPressed: onFoto, icon: const Icon(Icons.photo_camera_outlined), label: const Text('Hacer una foto')),
      ],
    ]);
  }
}

class _Cargando extends StatelessWidget {
  const _Cargando();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Nora está revisando tu nómina…'),
            SizedBox(height: 4),
            Text('Puede tardar hasta un minuto', style: TextStyle(fontSize: 12)),
          ]),
        ),
      );
}
