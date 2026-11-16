import 'package:material_ui/material_ui.dart';

import 'tema.dart';

// ---------------------------------------------------------------- formatos

String eur(dynamic n) {
  if (n == null) return '—';
  final v = (n as num).toDouble();
  final partes = v.abs().toStringAsFixed(2).split('.');
  final entero = partes[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
  return '${v < 0 ? '-' : ''}$entero,${partes[1]} €';
}

String pct(dynamic n) => n == null ? '—' : '${(n as num).toString().replaceAll('.', ',')} %';

const _meses = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

String fechaCorta(String? iso) {
  final f = DateTime.tryParse(iso ?? '')?.toLocal();
  if (f == null) return '';
  final hoy = DateTime.now();
  if (f.year == hoy.year && f.month == hoy.month && f.day == hoy.day) {
    return 'Hoy, ${f.hour.toString().padLeft(2, '0')}:${f.minute.toString().padLeft(2, '0')}';
  }
  return '${f.day} ${_meses[f.month - 1]} ${f.year}';
}

// ---------------------------------------------------------------- estados

/// Colores e icono de cada estado (ok / aviso / error y veredictos).
class Estilo {
  const Estilo(this.color, this.icono, this.nombre);
  final Color color;
  final IconData icono;
  final String nombre;

  static Estilo de(String estado) => switch (estado) {
        'ok' || 'correcta' => const Estilo(Marca.ok, Icons.check_circle_rounded, 'Correcto'),
        'error' || 'incorrecta' => const Estilo(Marca.error, Icons.cancel_rounded, 'Error'),
        'ilegible' => const Estilo(Marca.aviso, Icons.image_not_supported_outlined, 'Ilegible'),
        _ => const Estilo(Marca.aviso, Icons.error_rounded, 'Revisar'),
      };

  Color fondo(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark ? color.withValues(alpha: .18) : color.withValues(alpha: .09);
  Color texto(BuildContext c) => Theme.of(c).brightness == Brightness.dark ? Color.lerp(color, Colors.white, .45)! : color;
}

class Etiqueta extends StatelessWidget {
  const Etiqueta(this.estado, {super.key});
  final String estado;

  @override
  Widget build(BuildContext context) {
    final e = Estilo.de(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: e.fondo(context), borderRadius: BorderRadius.circular(99)),
      child: Text(e.nombre,
          style: TextStyle(color: e.texto(context), fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Recuento rápido: "2 errores · 1 a revisar · 6 correctos".
class Recuento extends StatelessWidget {
  const Recuento(this.items, {super.key});
  final List items;

  @override
  Widget build(BuildContext context) {
    int n(String e) => items.where((x) => x['estado'] == e).length;
    final datos = [('error', n('error')), ('aviso', n('aviso')), ('ok', n('ok'))].where((x) => x.$2 > 0);
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final (estado, cuantos) in datos)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: Estilo.de(estado).fondo(context), borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Estilo.de(estado).icono, size: 16, color: Estilo.de(estado).texto(context)),
            const SizedBox(width: 6),
            Text(
              switch (estado) {
                'error' => '$cuantos ${cuantos == 1 ? 'error' : 'errores'}',
                'aviso' => '$cuantos a revisar',
                _ => '$cuantos ${cuantos == 1 ? 'correcto' : 'correctos'}',
              },
              style: TextStyle(color: Estilo.de(estado).texto(context), fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ]),
        ),
    ]);
  }
}

/// Un punto del informe: icono de estado + concepto + explicación (+ qué hacer).
class PuntoInforme extends StatelessWidget {
  const PuntoInforme(this.p, {super.key, this.ultimo = false});
  final Map p;
  final bool ultimo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tonos = Tonos.de(context);
    final e = Estilo.de(p['estado']);
    final hacer = p['que_hacer'] as String?;
    return Container(
      decoration: BoxDecoration(border: ultimo ? null : Border(bottom: BorderSide(color: tonos.borde))),
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(e.icono, color: e.texto(context), size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['concepto'], style: t.textTheme.titleSmall),
            const SizedBox(height: 3),
            Text(p['explicacion'], style: t.textTheme.bodyMedium?.copyWith(color: tonos.suave)),
            if (hacer != null && hacer != 'Nada.' && p['estado'] != 'ok') ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: tonos.tenue, borderRadius: BorderRadius.circular(10)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.arrow_forward_rounded, size: 16, color: t.colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(hacer, style: t.textTheme.bodySmall?.copyWith(height: 1.4))),
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- estructura

/// Tarjeta con título opcional.
class Panel extends StatelessWidget {
  const Panel({super.key, this.titulo, this.icono, this.accion, required this.child, this.padding});
  final String? titulo;
  final IconData? icono;
  final Widget? accion;
  final Widget child;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Card(
      child: Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (titulo != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                if (icono != null) ...[
                  Icon(icono, size: 20, color: t.colorScheme.primary),
                  const SizedBox(width: 8),
                ],
                Expanded(child: Text(titulo!, style: t.textTheme.titleMedium)),
                ?accion,
              ]),
            ),
          child,
        ]),
      ),
    );
  }
}

class InsigniaPro extends StatelessWidget {
  const InsigniaPro({super.key, this.texto = 'PRO'});
  final String texto;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(gradient: Marca.degradadoPro, borderRadius: BorderRadius.circular(6)),
        child: Text(texto,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .6)),
      );
}

/// Ancho máximo para que en Windows o tablet no quede estirado.
class Centrado extends StatelessWidget {
  const Centrado({super.key, required this.child, this.ancho = 720});
  final Widget child;
  final double ancho;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        heightFactor: 1,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: ancho), child: child),
      );
}

/// Lista con scroll, centrada y con márgenes estándar.
class Pagina extends StatelessWidget {
  const Pagina({super.key, required this.children, this.abajo = 24});
  final List<Widget> children;
  final double abajo;

  @override
  Widget build(BuildContext context) => ListView(
        padding: EdgeInsets.fromLTRB(16, 8, 16, abajo),
        children: [
          Centrado(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
        ],
      );
}

class Hueco extends StatelessWidget {
  const Hueco([this.alto = 16, Key? key]) : super(key: key);
  final double alto;
  @override
  Widget build(BuildContext context) => SizedBox(height: alto);
}

void aviso(BuildContext context, String texto) =>
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(texto)));
