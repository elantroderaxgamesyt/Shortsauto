import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../compras.dart';
import '../main.dart';
import '../pdf_informe.dart';
import '../widgets.dart';
import 'chat.dart';
import 'tienda.dart';

const _veredictos = {
  'correcta': (Icons.check_circle, 'Tu nómina parece correcta'),
  'revisar': (Icons.warning_amber_rounded, 'Hay puntos que conviene revisar'),
  'incorrecta': (Icons.error, 'Hemos encontrado errores'),
  'ilegible': (Icons.search_off, 'No se ha podido leer bien la nómina'),
};

class PantallaInforme extends StatefulWidget {
  const PantallaInforme(this.r, {super.key, required this.datos, required this.nombre});
  final Revision r;
  final Uint8List datos;
  final String nombre;

  @override
  State<PantallaInforme> createState() => _PantallaInformeState();
}

class _PantallaInformeState extends State<PantallaInforme> {
  bool mejorando = false;

  Future<void> mejorarAPro() async {
    if (!(Tienda.yo.cuenta?.puedePro ?? false)) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PantallaTienda()));
      if (!(Tienda.yo.cuenta?.puedePro ?? false)) return;
    }
    setState(() => mejorando = true);
    try {
      final r = await Api.yo.analizar(widget.datos, widget.nombre, 'pro');
      await Tienda.yo.refrescarCuenta();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => PantallaInforme(r, datos: widget.datos, nombre: widget.nombre),
        ),
      );
    } on ErrorApi catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.mensaje)));
    } finally {
      if (mounted) setState(() => mejorando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.r;
    final inf = r.informe;
    final d = r.datos;
    final t = Theme.of(context);
    final (icono, titulo) = _veredictos[inf['veredicto']] ?? _veredictos['revisar']!;
    final cv = ColoresEstado.de(context, inf['veredicto']);
    final acento = r.pro ? morado : azul;

    return Scaffold(
      appBar: AppBar(
        title: Text(r.pro ? 'Informe Pro' : 'Informe'),
        actions: [
          if (r.pro)
            IconButton(
              tooltip: 'Guardar o imprimir PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => imprimirInforme(r),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: acento,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.chat_bubble_outline),
        label: const Text('Pregúntale a Nora'),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PantallaChat(r))),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Centrado(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (r.demo)
                    Card(
                      color: ColoresEstado.de(context, 'aviso').fondo,
                      child: const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Modo demo: el servidor no tiene clave de IA. Esto es un informe de ejemplo.'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: cv.fondo, borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      children: [
                        Icon(icono, color: cv.texto, size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                titulo,
                                style: t.textTheme.titleMedium?.copyWith(color: cv.texto, fontWeight: FontWeight.w700),
                              ),
                              Text(
                                [d['periodo'], d['empresa']].whereType<String>().join(' · '),
                                style: TextStyle(color: cv.texto),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(inf['resumen'], style: t.textTheme.bodyLarge),
                  const SizedBox(height: 12),
                  _Cifras(d),
                  if (!r.pro) ...[
                    Seccion('Lo más importante', [for (final p in inf['puntos']) PuntoInforme(p)]),
                    Seccion('Comprobación de cálculos', [_TablaCalculos(r.calculos)]),
                    const SizedBox(height: 16),
                    _MejorarPro(onPressed: mejorando ? null : mejorarAPro, cargando: mejorando),
                  ] else ...[
                    Seccion('Revisión concepto a concepto', [for (final p in inf['comprobaciones']) PuntoInforme(p)]),
                    Seccion('Cálculos recalculados por la app', [_TablaCalculos(r.calculos)]),
                    Seccion('Detalle de la nómina', [_Detalle(d)]),
                    Seccion('Qué significa cada concepto', [
                      for (final p in inf['explicacion_conceptos']) PuntoInforme(p),
                    ]),
                    Seccion('Recomendaciones', [for (final x in inf['recomendaciones']) _Vineta(x)]),
                    Seccion('Preguntas para RRHH o la gestoría', [
                      for (final x in inf['preguntas_para_rrhh']) _Vineta(x),
                    ]),
                    Seccion('Resumen para la reclamación', [_Reclamacion(inf['reclamacion'])]),
                    const SizedBox(height: 16),
                    Text(
                      'Confianza del análisis: ${inf['confianza']}. ${inf['limitaciones']}',
                      style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'Informe orientativo generado con IA. Para reclamar formalmente, consulta con un graduado social, '
                    'sindicato o abogado laboralista.',
                    style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cifras extends StatelessWidget {
  const _Cifras(this.d);
  final Map d;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget cifra(String txt, dynamic v, {bool fuerte = false}) => Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: fuerte ? t.colorScheme.primaryContainer : t.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(txt, style: t.textTheme.labelSmall),
            FittedBox(
              child: Text(eur(v), style: t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
    return Row(
      children: [
        cifra('Devengado', d['total_devengado']),
        const SizedBox(width: 8),
        cifra('Deducciones', d['total_deducciones']),
        const SizedBox(width: 8),
        cifra('Líquido', d['liquido'], fuerte: true),
      ],
    );
  }
}

class _TablaCalculos extends StatelessWidget {
  const _TablaCalculos(this.calculos);
  final List calculos;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      children: [
        for (final c in calculos)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Expanded(child: Text(c['concepto'], style: t.textTheme.bodyMedium)),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _valor(c, 'importe_nomina'),
                      style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (c['estado'] != 'ok' && c['importe_esperado'] != null)
                      Text(
                        'debería: ${_valor(c, 'importe_esperado')}',
                        style: t.textTheme.bodySmall?.copyWith(color: ColoresEstado.de(context, c['estado']).texto),
                      ),
                  ],
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 72,
                  child: Align(alignment: Alignment.centerRight, child: Etiqueta(c['estado'])),
                ),
              ],
            ),
          ),
      ],
    );
  }

  String _valor(Map c, String k) => (c['concepto'] as String).startsWith('Porcentaje') ? pct(c[k]) : eur(c[k]);
}

class _Detalle extends StatelessWidget {
  const _Detalle(this.d);
  final Map d;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    Widget fila(String a, String b, {bool cab = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(a, style: cab ? t.textTheme.titleSmall : null)),
          Text(b, style: cab ? t.textTheme.titleSmall : null),
        ],
      ),
    );
    return Column(
      children: [
        fila('Devengos', 'Importe', cab: true),
        for (final l in d['devengos']) fila(l['concepto'], eur(l['importe'])),
        const Divider(),
        fila('Deducciones', 'Importe', cab: true),
        for (final l in d['deducciones'])
          fila('${l['concepto']}${l['porcentaje'] != null ? ' (${pct(l['porcentaje'])})' : ''}', eur(l['importe'])),
      ],
    );
  }
}

class _Vineta extends StatelessWidget {
  const _Vineta(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('•  '),
        Expanded(child: Text(texto)),
      ],
    ),
  );
}

class _Reclamacion extends StatelessWidget {
  const _Reclamacion(this.r);
  final Map r;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final procede = r['procede'] == true;
    final c = ColoresEstado.de(context, procede ? 'error' : 'ok');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.fondo, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(procede ? Icons.gavel : Icons.verified, color: c.texto),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      procede ? 'Tienes algo que reclamar' : 'No hace falta reclamar',
                      style: t.textTheme.titleSmall?.copyWith(color: c.texto, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (r['total_reclamado'] != null)
                    Text(
                      eur(r['total_reclamado']),
                      style: t.textTheme.titleMedium?.copyWith(color: c.texto, fontWeight: FontWeight.w800),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(r['resumen']),
            ],
          ),
        ),
        for (final p in r['puntos'])
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['concepto'], style: t.textTheme.titleSmall),
                      Text(p['motivo'], style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(eur(p['importe']), style: t.textTheme.titleSmall),
              ],
            ),
          ),
        if (procede) ...[
          const SizedBox(height: 12),
          _Dato(Icons.person_outline, 'A quién', r['a_quien']),
          _Dato(Icons.schedule, 'Plazo', r['plazo']),
          if ((r['pasos'] as List).isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Si no te lo corrigen', style: t.textTheme.titleSmall),
            for (final (i, paso) in (r['pasos'] as List).indexed)
              Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text('${i + 1}. $paso')),
          ],
        ],
        if (r['texto'] != null) ...[
          const SizedBox(height: 12),
          Text('Mensaje para enviar', style: t.textTheme.titleSmall),
          const SizedBox(height: 6),
          _Borrador(r['texto']),
        ],
      ],
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.icono, this.titulo, this.texto);
  final IconData icono;
  final String titulo, texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icono, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$titulo: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: texto),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _Borrador extends StatelessWidget {
  const _Borrador(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(texto),
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          icon: const Icon(Icons.copy, size: 18),
          label: const Text('Copiar texto'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: texto));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copiado')));
          },
        ),
      ],
    );
  }
}

class _MejorarPro extends StatelessWidget {
  const _MejorarPro({required this.onPressed, required this.cargando});
  final VoidCallback? onPressed;
  final bool cargando;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: morado.withValues(alpha: .6)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '¿Quieres la revisión completa?',
          style: TextStyle(fontWeight: FontWeight.w700, color: morado),
        ),
        const SizedBox(height: 4),
        const Text(
          'Con Pro recalculamos cada cotización y el IRPF, te explicamos cada línea, te damos las '
          'un resumen para la reclamación si hay errores y preguntas ilimitadas a Nora.',
        ),
        const SizedBox(height: 10),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: morado,
            side: const BorderSide(color: morado),
          ),
          onPressed: onPressed,
          child: cargando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Revisar esta nómina con Pro'),
        ),
      ],
    ),
  );
}
