import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../compras.dart';
import '../config.dart';
import '../estado.dart';
import '../tema.dart';
import '../widgets.dart';
import 'informe.dart';
import 'tienda.dart';

class Archivo {
  Archivo(this.datos, this.nombre);
  final Uint8List datos;
  final String nombre;
  bool get esPdf => nombre.toLowerCase().endsWith('.pdf');
  String get tamano => datos.length > 1024 * 1024
      ? '${(datos.length / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB'
      : '${(datos.length / 1024).ceil()} KB';
}

bool get _hayCamara => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// Punto de entrada: elegir de dónde sale la nómina y seguir con el plan.
Future<void> empezarRevision(BuildContext context) async {
  final archivo = await elegirArchivo(context);
  if (archivo == null || !context.mounted) return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PantallaPlan(archivo)));
}

Future<Archivo?> elegirArchivo(BuildContext context) async {
  final origen = await showModalBottomSheet<String>(
    context: context,
    builder: (context) {
      final t = Theme.of(context);
      Widget opcion(String id, IconData ic, String titulo, String sub) => ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: t.colorScheme.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
              child: Icon(ic, color: t.colorScheme.primary),
            ),
            title: Text(titulo, style: t.textTheme.titleSmall),
            subtitle: Text(sub),
            onTap: () => Navigator.pop(context, id),
          );
      return SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text('¿Cómo quieres subir tu nómina?', style: t.textTheme.titleMedium),
          ),
          if (_hayCamara) opcion('camara', Icons.photo_camera_outlined, 'Hacer una foto', 'Con buena luz y la nómina entera'),
          opcion('pdf', Icons.picture_as_pdf_outlined, 'Subir PDF', 'La que te envía tu empresa o descargas del portal'),
          opcion('imagen', Icons.image_outlined, 'Elegir una imagen', 'Una foto o captura que ya tengas'),
          const Hueco(12),
        ]),
      );
    },
  );
  switch (origen) {
    case 'camara':
      final f = await ImagePicker().pickImage(source: ImageSource.camera, imageQuality: 85, maxWidth: 2400);
      return f == null ? null : Archivo(await f.readAsBytes(), 'foto_nomina.jpg');
    case 'pdf' || 'imagen':
      final f = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: origen == 'pdf' ? const ['pdf'] : const ['png', 'jpg', 'jpeg', 'webp'],
      );
      if (f == null) return null;
      final datos = await f.xFile.readAsBytes();
      if (datos.length > 10 * 1024 * 1024) {
        if (context.mounted) aviso(context, 'El archivo pesa más de 10 MB. Prueba con una foto más ligera.');
        return null;
      }
      return Archivo(datos, f.name);
  }
  return null;
}

// ------------------------------------------------------------------ elegir plan

class PantallaPlan extends StatefulWidget {
  const PantallaPlan(this.archivo, {super.key, this.plan = 'free'});
  final Archivo archivo;
  final String plan;

  @override
  State<PantallaPlan> createState() => _PantallaPlanState();
}

class _PantallaPlanState extends State<PantallaPlan> {
  late Archivo archivo = widget.archivo;
  late String plan = widget.plan;

  Future<void> continuar() async {
    if (plan == 'pro' && !(Tienda.yo.cuenta?.puedePro ?? false)) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PantallaTienda()));
      if (!(Tienda.yo.cuenta?.puedePro ?? false)) return;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PantallaAnalizando(archivo, plan)));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tonos = Tonos.de(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Nueva revisión')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Tienda.yo,
          builder: (context, _) {
            final c = Tienda.yo.cuenta;
            final puedePro = c?.puedePro ?? false;
            return Column(children: [
              Expanded(
                child: Pagina(children: [
                  Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                      leading: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(color: tonos.tenue, borderRadius: BorderRadius.circular(10)),
                        child: Icon(archivo.esPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
                            color: archivo.esPdf ? Marca.error : t.colorScheme.primary),
                      ),
                      title: Text(archivo.nombre, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.textTheme.titleSmall),
                      subtitle: Text(archivo.tamano),
                      trailing: TextButton(
                        onPressed: () async {
                          final nuevo = await elegirArchivo(context);
                          if (nuevo != null) setState(() => archivo = nuevo);
                        },
                        child: const Text('Cambiar'),
                      ),
                    ),
                  ),
                  const Hueco(24),
                  Text('Elige el tipo de revisión', style: t.textTheme.titleMedium),
                  const Hueco(12),
                  _TarjetaPlan(
                    seleccionado: plan == 'free',
                    onTap: () => setState(() => plan = 'free'),
                    titulo: 'Revisión básica',
                    precio: 'Gratis',
                    nota: c == null ? null : 'Te quedan ${c.freeHoy} hoy',
                    ventajas: const [
                      'Veredicto y resumen sencillo',
                      'Los 5 puntos más importantes',
                      'Comprobación de sumas y líquido',
                      '1 pregunta a Nora',
                    ],
                  ),
                  const Hueco(12),
                  _TarjetaPlan(
                    pro: true,
                    seleccionado: plan == 'pro',
                    onTap: () => setState(() => plan = 'pro'),
                    titulo: 'Revisión completa',
                    precio: puedePro ? 'Incluida' : precioRevision,
                    nota: puedePro
                        ? (c!.suscripcion ? 'Con tu Pro mensual' : 'Tienes ${c.creditos} disponible${c.creditos == 1 ? '' : 's'}')
                        : 'o $precioMensual',
                    ventajas: const [
                      'Revisión concepto a concepto',
                      'Recalcula Seguridad Social e IRPF',
                      'Resumen para la reclamación, listo para enviar',
                      'Preguntas ilimitadas a Nora',
                      'Informe en PDF',
                    ],
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(color: tonos.tarjeta, border: Border(top: BorderSide(color: tonos.borde))),
                child: Centrado(
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: plan == 'pro' ? FilledButton.styleFrom(backgroundColor: Marca.pro) : null,
                      onPressed: continuar,
                      child: Text(plan == 'free'
                          ? 'Revisar gratis'
                          : puedePro
                              ? 'Hacer revisión completa'
                              : 'Desbloquear revisión completa'),
                    ),
                  ),
                ),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

class _TarjetaPlan extends StatelessWidget {
  const _TarjetaPlan({
    required this.seleccionado,
    required this.onTap,
    required this.titulo,
    required this.precio,
    required this.ventajas,
    this.nota,
    this.pro = false,
  });
  final bool seleccionado, pro;
  final VoidCallback onTap;
  final String titulo, precio;
  final String? nota;
  final List<String> ventajas;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tonos = Tonos.de(context);
    final color = pro ? Marca.pro : t.colorScheme.primary;
    return Material(
      color: tonos.tarjeta,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Marca.radio),
        side: BorderSide(color: seleccionado ? color : tonos.borde, width: seleccionado ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(seleccionado ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: seleccionado ? color : tonos.suave),
              const SizedBox(width: 10),
              Expanded(
                child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, children: [
                  Text(titulo, style: t.textTheme.titleMedium),
                  if (pro) const InsigniaPro(),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(precio, style: t.textTheme.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
                if (nota != null) Text(nota!, style: t.textTheme.bodySmall?.copyWith(color: tonos.suave)),
              ]),
            ]),
            const Hueco(12),
            for (final v in ventajas)
              Padding(
                padding: const EdgeInsets.only(left: 34, bottom: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.check_rounded, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(child: Text(v, style: t.textTheme.bodyMedium)),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ analizando

class PantallaAnalizando extends StatefulWidget {
  const PantallaAnalizando(this.archivo, this.plan, {super.key});
  final Archivo archivo;
  final String plan;

  @override
  State<PantallaAnalizando> createState() => _PantallaAnalizandoState();
}

class _PantallaAnalizandoState extends State<PantallaAnalizando> {
  static const pasos = [
    'Leyendo tu nómina',
    'Comprobando salario y complementos',
    'Revisando cotizaciones a la Seguridad Social',
    'Comprobando la retención de IRPF',
    'Preparando tu informe',
  ];
  int paso = 0;
  Timer? reloj;
  String? error;

  @override
  void initState() {
    super.initState();
    _lanzar();
  }

  @override
  void dispose() {
    reloj?.cancel();
    super.dispose();
  }

  Future<void> _lanzar() async {
    setState(() {
      error = null;
      paso = 0;
    });
    reloj?.cancel();
    reloj = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (paso < pasos.length - 1) setState(() => paso++);
    });
    try {
      final r = await Api.yo.analizar(widget.archivo.datos, widget.archivo.nombre, widget.plan);
      reloj?.cancel();
      Tienda.yo.refrescarCuenta();
      historialCambiado.value++;
      if (!mounted) return;
      setState(() => paso = pasos.length);
      await Future.delayed(const Duration(milliseconds: 350));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => PantallaInforme(r, archivo: widget.archivo)));
    } on ErrorApi catch (e) {
      reloj?.cancel();
      if (mounted) setState(() => error = e.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tonos = Tonos.de(context);
    final pro = widget.plan == 'pro';
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: error != null),
      body: SafeArea(
        child: Centrado(
          ancho: 480,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: error != null
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.cloud_off_rounded, size: 56, color: tonos.suave),
                    const Hueco(16),
                    Text('No se ha podido revisar', style: t.textTheme.titleLarge, textAlign: TextAlign.center),
                    const Hueco(8),
                    Text(error!, textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(color: tonos.suave)),
                    const Hueco(24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(onPressed: _lanzar, child: const Text('Reintentar')),
                    ),
                    const Hueco(8),
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('Volver')),
                  ])
                : Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                          gradient: pro ? Marca.degradadoPro : Marca.degradado, borderRadius: BorderRadius.circular(18)),
                      child: const Padding(
                        padding: EdgeInsets.all(18),
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                      ),
                    ),
                    const Hueco(24),
                    Text('Nora está revisando tu nómina', style: t.textTheme.titleLarge),
                    const Hueco(6),
                    Text(pro ? 'La revisión completa tarda alrededor de un minuto.' : 'Tardará unos segundos.',
                        style: t.textTheme.bodyMedium?.copyWith(color: tonos.suave)),
                    const Hueco(28),
                    for (final (i, txt) in pasos.indexed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: i < paso
                                ? const Icon(Icons.check_circle_rounded, color: Marca.ok)
                                : i == paso
                                    ? const Padding(
                                        padding: EdgeInsets.all(3), child: CircularProgressIndicator(strokeWidth: 2.4))
                                    : Icon(Icons.circle_outlined, color: tonos.borde),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(txt,
                                style: t.textTheme.bodyLarge?.copyWith(
                                  color: i <= paso ? null : tonos.suave,
                                  fontWeight: i == paso ? FontWeight.w600 : null,
                                )),
                          ),
                        ]),
                      ),
                  ]),
          ),
        ),
      ),
    );
  }
}
