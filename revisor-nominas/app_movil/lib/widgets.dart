import 'package:material_ui/material_ui.dart';

/// Colores de estado que funcionan en tema claro y oscuro.
class ColoresEstado {
  ColoresEstado(this.fondo, this.texto);
  final Color fondo;
  final Color texto;

  static ColoresEstado de(BuildContext context, String estado) {
    final oscuro = Theme.of(context).brightness == Brightness.dark;
    final base = switch (estado) {
      'ok' || 'correcta' => const Color(0xFF1D8A4E),
      'error' || 'incorrecta' => const Color(0xFFC0362C),
      _ => const Color(0xFFA56300),
    };
    return oscuro
        ? ColoresEstado(Color.lerp(base, Colors.black, .72)!, Color.lerp(base, Colors.white, .35)!)
        : ColoresEstado(Color.lerp(base, Colors.white, .88)!, base);
  }
}

const etiquetas = {'ok': 'BIEN', 'aviso': 'REVISAR', 'error': 'ERROR'};

class Etiqueta extends StatelessWidget {
  const Etiqueta(this.estado, {super.key});
  final String estado;

  @override
  Widget build(BuildContext context) {
    final c = ColoresEstado.de(context, estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.fondo, borderRadius: BorderRadius.circular(99)),
      child: Text(etiquetas[estado] ?? estado,
          style: TextStyle(color: c.texto, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: .4)),
    );
  }
}

/// Un punto del informe: etiqueta + concepto + explicación (+ qué hacer).
class PuntoInforme extends StatelessWidget {
  const PuntoInforme(this.p, {super.key});
  final Map p;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final hacer = p['que_hacer'] as String?;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 78, child: Align(alignment: Alignment.topLeft, child: Etiqueta(p['estado']))),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p['concepto'], style: t.textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(p['explicacion'], style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
            if (hacer != null && hacer != 'Nada.')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('👉 $hacer', style: t.textTheme.bodyMedium),
              ),
          ]),
        ),
      ]),
    );
  }
}

class Seccion extends StatelessWidget {
  const Seccion(this.titulo, this.hijos, {super.key});
  final String titulo;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          ...hijos,
        ]),
      );
}

String eur(dynamic n) {
  if (n == null) return '—';
  final v = (n as num).toDouble();
  final partes = v.abs().toStringAsFixed(2).split('.');
  final entero = partes[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
  return '${v < 0 ? '-' : ''}$entero,${partes[1]} €';
}

String pct(dynamic n) => n == null ? '—' : '${(n as num).toString().replaceAll('.', ',')} %';

/// Ancho máximo para que en Windows / tablet no quede estirado.
class Centrado extends StatelessWidget {
  const Centrado({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: child),
      );
}
