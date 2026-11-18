import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../api.dart';
import '../pagos.dart';
import '../pdf_informe.dart';
import '../tema.dart';
import '../widgets.dart';
import 'chat.dart';
import 'nueva_revision.dart';

const _titulos = {
  'correcta': 'Tu nómina está bien',
  'revisar': 'Hay puntos que revisar',
  'incorrecta': 'Hemos encontrado errores',
  'ilegible': 'No se ha podido leer bien',
};

class PantallaInforme extends StatelessWidget {
  const PantallaInforme(this.r, {super.key, this.archivo});
  final Revision r;
  final Archivo? archivo; // si viene de una revisión recién hecha, para pasarla a revisión completa

  @override
  Widget build(BuildContext context) {
    final inf = r.informe;
    final tonos = Tonos.de(context);
    final puntos = r.pro ? inf['comprobaciones'] as List : inf['puntos'] as List;

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(r.pro ? 'Informe completo' : 'Informe'),
            if (r.pro) ...[const SizedBox(width: 8), const InsigniaPro()],
          ]),
          if (r.fecha != null)
            Text(fechaCorta(r.fecha), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tonos.suave)),
        ]),
      ),
      bottomNavigationBar: _BarraAcciones(r),
      body: SafeArea(
        bottom: false,
        child: Pagina(children: [
          if (r.demo) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Estilo.de('aviso').fondo(context), borderRadius: BorderRadius.circular(12)),
              child: Text('Modo demo: el servidor no tiene clave de IA y este es un informe de ejemplo.',
                  style: TextStyle(color: Estilo.de('aviso').texto(context))),
            ),
            const Hueco(12),
          ],
          _Cabecera(r, puntos),
          const Hueco(12),
          _Cifras(r.datos),
          const Hueco(12),
          Panel(
            titulo: 'Resumen',
            icono: Icons.notes_rounded,
            padding: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(inf['resumen'], style: Theme.of(context).textTheme.bodyLarge),
            ),
          ),
          const Hueco(12),
          if (!r.pro) ...[
            _Puntos('Lo más importante', Icons.flag_outlined, puntos),
            const Hueco(12),
            Panel(titulo: 'Comprobación de cálculos', icono: Icons.calculate_outlined, child: _TablaCalculos(r.calculos)),
            const Hueco(16),
            _Mejorar(archivo),
          ] else ...[
            if (inf['reclamacion']['procede'] == true) ...[_Reclamacion(inf['reclamacion']), const Hueco(12)],
            _Puntos('Revisión concepto a concepto', Icons.fact_check_outlined, puntos),
            const Hueco(12),
            Panel(
              titulo: 'Cálculos rehechos por la app',
              icono: Icons.calculate_outlined,
              child: _TablaCalculos(r.calculos),
            ),
            const Hueco(12),
            Panel(titulo: 'Detalle de tu nómina', icono: Icons.receipt_long_outlined, child: _Detalle(r.datos)),
            const Hueco(12),
            _Desplegable('Qué significa cada concepto', Icons.menu_book_outlined, [
              for (final (i, p) in (inf['explicacion_conceptos'] as List).indexed)
                PuntoInforme(p, ultimo: i == (inf['explicacion_conceptos'] as List).length - 1),
            ]),
            const Hueco(12),
            _Lista('Recomendaciones', Icons.lightbulb_outline_rounded, inf['recomendaciones']),
            const Hueco(12),
            _Lista('Preguntas para RRHH o la gestoría', Icons.forum_outlined, inf['preguntas_para_rrhh']),
            if (inf['reclamacion']['procede'] != true) ...[const Hueco(12), _Reclamacion(inf['reclamacion'])],
            const Hueco(16),
            Text('Fiabilidad del análisis: ${inf['confianza']}. ${inf['limitaciones']}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tonos.suave)),
          ],
          const Hueco(12),
          Text(
            'Informe orientativo generado con IA. Para reclamar formalmente, consulta con un graduado social, '
            'sindicato o abogado laboralista.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tonos.suave),
          ),
        ]),
      ),
    );
  }
}

class _Cabecera extends StatelessWidget {
  const _Cabecera(this.r, this.puntos);
  final Revision r;
  final List puntos;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final v = r.informe['veredicto'] as String;
    final e = Estilo.de(v);
    final d = r.datos;
    final sub = [d['periodo'], d['empresa']].whereType<String>().join(' · ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(color: e.fondo(context), borderRadius: BorderRadius.circular(14)),
              child: Icon(e.icono, color: e.texto(context), size: 30),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_titulos[v] ?? '', style: t.textTheme.titleLarge),
                if (sub.isNotEmpty)
                  Text(sub, style: t.textTheme.bodyMedium?.copyWith(color: Tonos.de(context).suave)),
              ]),
            ),
          ]),
          const Hueco(14),
          Recuento(puntos),
        ]),
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
    final tonos = Tonos.de(context);
    Widget cifra(String txt, dynamic v, {bool fuerte = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              gradient: fuerte ? Marca.degradado : null,
              color: fuerte ? null : tonos.tarjeta,
              border: fuerte ? null : Border.all(color: tonos.borde),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(txt,
                  style: t.textTheme.labelMedium
                      ?.copyWith(color: fuerte ? Colors.white.withValues(alpha: .85) : tonos.suave)),
              const SizedBox(height: 4),
              FittedBox(
                child: Text(eur(v),
                    style: t.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700, color: fuerte ? Colors.white : null)),
              ),
            ]),
          ),
        );
    return Row(children: [
      cifra('Bruto', d['total_devengado']),
      const SizedBox(width: 8),
      cifra('Descuentos', d['total_deducciones']),
      const SizedBox(width: 8),
      cifra('Cobras', d['liquido'], fuerte: true),
    ]);
  }
}

class _Puntos extends StatelessWidget {
  const _Puntos(this.titulo, this.icono, this.puntos);
  final String titulo;
  final IconData icono;
  final List puntos;

  @override
  Widget build(BuildContext context) {
    // Primero los errores, luego lo que hay que revisar y al final lo correcto.
    const orden = {'error': 0, 'aviso': 1, 'ok': 2};
    final lista = [...puntos]..sort((a, b) => (orden[a['estado']] ?? 1).compareTo(orden[b['estado']] ?? 1));
    return Panel(
      titulo: titulo,
      icono: icono,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
      child: Column(children: [
        for (final (i, p) in lista.indexed) PuntoInforme(p, ultimo: i == lista.length - 1),
      ]),
    );
  }
}

class _TablaCalculos extends StatelessWidget {
  const _TablaCalculos(this.calculos);
  final List calculos;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tonos = Tonos.de(context);
    String valor(Map c, String k) => (c['concepto'] as String).startsWith('Porcentaje') ? pct(c[k]) : eur(c[k]);
    return Column(children: [
      for (final (i, c) in calculos.indexed)
        Container(
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
              border: i == calculos.length - 1 ? null : Border(bottom: BorderSide(color: tonos.borde))),
          child: Row(children: [
            Icon(Estilo.de(c['estado']).icono, size: 18, color: Estilo.de(c['estado']).texto(context)),
            const SizedBox(width: 10),
            Expanded(child: Text(c['concepto'], style: t.textTheme.bodyMedium)),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(valor(c, 'importe_nomina'), style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              if (c['estado'] != 'ok' && c['importe_esperado'] != null)
                Text('debería ser ${valor(c, 'importe_esperado')}',
                    style: t.textTheme.bodySmall?.copyWith(color: Estilo.de(c['estado']).texto(context))),
            ]),
          ]),
        ),
    ]);
  }
}

class _Detalle extends StatelessWidget {
  const _Detalle(this.d);
  final Map d;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tonos = Tonos.de(context);
    Widget fila(String a, String b, {bool cab = false}) => Padding(
          padding: EdgeInsets.only(top: cab ? 12 : 6, bottom: cab ? 4 : 6),
          child: Row(children: [
            Expanded(
                child: Text(a,
                    style: cab
                        ? t.textTheme.labelLarge?.copyWith(color: tonos.suave, letterSpacing: .3)
                        : t.textTheme.bodyMedium)),
            Text(b, style: cab ? t.textTheme.labelLarge?.copyWith(color: tonos.suave) : t.textTheme.bodyMedium),
          ]),
        );
    return Column(children: [
      fila('LO QUE GANAS', 'IMPORTE', cab: true),
      for (final l in d['devengos']) fila(l['concepto'], eur(l['importe'])),
      const Divider(height: 16),
      fila('LO QUE TE DESCUENTAN', 'IMPORTE', cab: true),
      for (final l in d['deducciones'])
        fila('${l['concepto']}${l['porcentaje'] != null ? ' (${pct(l['porcentaje'])})' : ''}', eur(l['importe'])),
      const Divider(height: 16),
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text('Líquido a percibir', style: t.textTheme.titleSmall)),
          Text(eur(d['liquido']), style: t.textTheme.titleSmall),
        ]),
      ),
      const Hueco(6),
    ]);
  }
}

class _Desplegable extends StatelessWidget {
  const _Desplegable(this.titulo, this.icono, this.hijos);
  final String titulo;
  final IconData icono;
  final List<Widget> hijos;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            leading: Icon(icono, color: Theme.of(context).colorScheme.primary, size: 20),
            title: Text(titulo, style: Theme.of(context).textTheme.titleMedium),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            children: hijos,
          ),
        ),
      );
}

class _Lista extends StatelessWidget {
  const _Lista(this.titulo, this.icono, this.items);
  final String titulo;
  final IconData icono;
  final List items;

  @override
  Widget build(BuildContext context) => Panel(
        titulo: titulo,
        icono: icono,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Column(children: [
          for (final x in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, shape: BoxShape.circle)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(x)),
              ]),
            ),
        ]),
      );
}

class _Reclamacion extends StatelessWidget {
  const _Reclamacion(this.r);
  final Map r;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final tonos = Tonos.de(context);
    final procede = r['procede'] == true;
    final e = Estilo.de(procede ? 'error' : 'ok');
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Marca.radio),
        side: BorderSide(color: procede ? e.color.withValues(alpha: .45) : tonos.borde, width: procede ? 1.5 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(procede ? Icons.gavel_rounded : Icons.verified_rounded, color: e.texto(context), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(procede ? 'Resumen para la reclamación' : 'No hace falta reclamar',
                  style: t.textTheme.titleMedium),
            ),
          ]),
          if (procede && r['total_reclamado'] != null) ...[
            const Hueco(14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: e.fondo(context), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                Expanded(child: Text('Total a reclamar este mes', style: TextStyle(color: e.texto(context)))),
                Text(eur(r['total_reclamado']),
                    style: t.textTheme.titleLarge?.copyWith(color: e.texto(context), fontWeight: FontWeight.w800)),
              ]),
            ),
          ],
          const Hueco(12),
          Text(r['resumen'], style: t.textTheme.bodyMedium),
          if (procede) ...[
            for (final p in r['puntos'])
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: tonos.borde), borderRadius: BorderRadius.circular(12)),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p['concepto'], style: t.textTheme.titleSmall),
                      const SizedBox(height: 2),
                      Text(p['motivo'], style: t.textTheme.bodySmall?.copyWith(color: tonos.suave, height: 1.4)),
                    ]),
                  ),
                  const SizedBox(width: 12),
                  Text(eur(p['importe']), style: t.textTheme.titleSmall),
                ]),
              ),
            const Hueco(16),
            _Dato(Icons.person_outline_rounded, 'A quién dirigirte', r['a_quien']),
            _Dato(Icons.event_outlined, 'Plazo', r['plazo']),
            if ((r['pasos'] as List).isNotEmpty) ...[
              const Hueco(8),
              Text('Si no te lo corrigen', style: t.textTheme.titleSmall),
              const Hueco(6),
              for (final (i, paso) in (r['pasos'] as List).indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 22,
                      height: 22,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: tonos.tenue, shape: BoxShape.circle),
                      child: Text('${i + 1}', style: t.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(paso)),
                  ]),
                ),
            ],
          ],
          if (r['texto'] != null) ...[
            const Hueco(16),
            Text('Mensaje para enviar a tu empresa', style: t.textTheme.titleSmall),
            const Hueco(8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: tonos.tenue, borderRadius: BorderRadius.circular(12)),
              child: SelectableText(r['texto'], style: t.textTheme.bodyMedium),
            ),
            const Hueco(10),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy_rounded, size: 18),
              label: const Text('Copiar mensaje'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: r['texto']));
                aviso(context, 'Mensaje copiado. Pégalo en un email a tu empresa.');
              },
            ),
          ],
        ]),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.icono, this.titulo, this.texto);
  final IconData icono;
  final String titulo, texto;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icono, size: 20, color: t.colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: t.textTheme.labelLarge),
            Text(texto, style: t.textTheme.bodyMedium?.copyWith(color: Tonos.de(context).suave)),
          ]),
        ),
      ]),
    );
  }
}

class _Mejorar extends StatelessWidget {
  const _Mejorar(this.archivo);
  final Archivo? archivo;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: Marca.degradadoPro, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const InsigniaPro(texto: 'REVISIÓN COMPLETA'),
        const Hueco(12),
        Text('¿Quieres saber cuánto puedes reclamar?',
            style: t.textTheme.titleLarge?.copyWith(color: Colors.white)),
        const Hueco(10),
        for (final v in const [
          'Recalculamos cada cotización y el IRPF',
          'Resumen para la reclamación con el mensaje listo para enviar',
          '3 preguntas a Nora sin anuncios e informe en PDF',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(v, style: TextStyle(color: Colors.white.withValues(alpha: .92)))),
            ]),
          ),
        const Hueco(12),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Marca.pro),
            onPressed: () {
              if (archivo != null) {
                Navigator.of(context)
                    .pushReplacement(MaterialPageRoute(builder: (_) => PantallaPlan(archivo!, plan: 'pro')));
              } else {
                empezarRevision(context);
              }
            },
            child: Text('${archivo != null ? 'Revisar esta nómina a fondo' : 'Hacer una revisión completa'} · ${Pagos.yo.precio}'),
          ),
        ),
      ]),
    );
  }
}

class _BarraAcciones extends StatelessWidget {
  const _BarraAcciones(this.r);
  final Revision r;

  @override
  Widget build(BuildContext context) {
    final tonos = Tonos.de(context);
    return Container(
      decoration: BoxDecoration(color: tonos.tarjeta, border: Border(top: BorderSide(color: tonos.borde))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Centrado(
            child: Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: r.pro ? FilledButton.styleFrom(backgroundColor: Marca.pro) : null,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 20),
                  label: const Text('Preguntar a Nora'),
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PantallaChat(r))),
                ),
              ),
              if (r.pro) ...[
                const SizedBox(width: 10),
                SizedBox(
                  height: 52,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 16)),
                    onPressed: () => imprimirInforme(r),
                    child: const Row(children: [Icon(Icons.picture_as_pdf_outlined, size: 20), SizedBox(width: 6), Text('PDF')]),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
