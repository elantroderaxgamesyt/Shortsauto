import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'api.dart';
import 'widgets.dart' show eur, pct;

/// Informe Pro en PDF (abre el diálogo de imprimir / guardar como PDF / compartir).
Future<void> imprimirInforme(Revision r) async {
  final fuente = await PdfGoogleFonts.robotoRegular();
  final negrita = await PdfGoogleFonts.robotoBold();
  final doc = pw.Document(theme: pw.ThemeData.withFont(base: fuente, bold: negrita));
  final inf = r.informe;
  final d = r.datos;

  const colores = {'ok': PdfColor.fromInt(0xFF1D8A4E), 'aviso': PdfColor.fromInt(0xFFA56300), 'error': PdfColor.fromInt(0xFFC0362C)};
  const nombres = {'ok': 'BIEN', 'aviso': 'REVISAR', 'error': 'ERROR'};

  pw.Widget titulo(String t) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 14, bottom: 4),
        child: pw.Text(t, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      );

  pw.Widget punto(Map p) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 4),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(
            width: 58,
            child: pw.Text(nombres[p['estado']] ?? '',
                style: pw.TextStyle(fontSize: 8, color: colores[p['estado']], fontWeight: pw.FontWeight.bold)),
          ),
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(p['concepto'], style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(p['explicacion'], style: const pw.TextStyle(fontSize: 9.5)),
              if (p['que_hacer'] != null && p['que_hacer'] != 'Nada.')
                pw.Text('Qué hacer: ${p['que_hacer']}', style: const pw.TextStyle(fontSize: 9.5)),
            ]),
          ),
        ]),
      );

  String valor(Map c, String k) => (c['concepto'] as String).startsWith('Porcentaje') ? pct(c[k]) : eur(c[k]);

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(36),
    footer: (ctx) => pw.Text(
      'Informe orientativo generado con IA · Revisor de nóminas · página ${ctx.pageNumber}/${ctx.pagesCount}',
      style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
    ),
    build: (ctx) => [
      pw.Text('Informe de revisión de nómina', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
      pw.Text([d['periodo'], d['empresa'], d['trabajador']].whereType<String>().join(' · ')),
      pw.SizedBox(height: 10),
      pw.Text(inf['resumen']),
      pw.SizedBox(height: 8),
      pw.Text('Devengado: ${eur(d['total_devengado'])}   ·   Deducciones: ${eur(d['total_deducciones'])}   ·   '
          'Líquido: ${eur(d['liquido'])}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
      titulo('Revisión concepto a concepto'),
      ...[for (final p in inf['comprobaciones']) punto(p)],
      titulo('Cálculos recalculados'),
      pw.TableHelper.fromTextArray(
        headers: ['Comprobación', 'En nómina', 'Calculado', 'Estado'],
        data: [for (final c in r.calculos) [c['concepto'], valor(c, 'importe_nomina'), valor(c, 'importe_esperado'), nombres[c['estado']]]],
        cellStyle: const pw.TextStyle(fontSize: 9),
        headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        cellAlignments: {1: pw.Alignment.centerRight, 2: pw.Alignment.centerRight},
      ),
      titulo('Recomendaciones'),
      ...[for (final x in inf['recomendaciones']) pw.Bullet(text: x)],
      titulo('Preguntas para RRHH o la gestoría'),
      ...[for (final x in inf['preguntas_para_rrhh']) pw.Bullet(text: x)],
      titulo('Resumen para la reclamación'),
      pw.Text(inf['reclamacion']['resumen']),
      if (inf['reclamacion']['procede'] == true) ...[
        pw.SizedBox(height: 6),
        pw.TableHelper.fromTextArray(
          headers: ['Concepto', 'Motivo', 'Importe'],
          data: [
            for (final p in inf['reclamacion']['puntos']) [p['concepto'], p['motivo'], eur(p['importe'])],
            ['Total a reclamar', '', eur(inf['reclamacion']['total_reclamado'])],
          ],
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          columnWidths: {0: const pw.FlexColumnWidth(3), 1: const pw.FlexColumnWidth(5), 2: const pw.FlexColumnWidth(2)},
          cellAlignments: {2: pw.Alignment.centerRight},
        ),
        pw.SizedBox(height: 6),
        pw.Text('A quién: ${inf['reclamacion']['a_quien']}'),
        pw.Text('Plazo: ${inf['reclamacion']['plazo']}'),
        ...[for (final x in inf['reclamacion']['pasos']) pw.Bullet(text: x)],
      ],
      if (inf['reclamacion']['texto'] != null) ...[
        pw.SizedBox(height: 6),
        pw.Text('Mensaje para enviar', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          color: PdfColors.grey100,
          child: pw.Text(inf['reclamacion']['texto']),
        ),
      ],
      pw.SizedBox(height: 12),
      pw.Text('Confianza del análisis: ${inf['confianza']}. ${inf['limitaciones']}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
    ],
  ));

  await Printing.layoutPdf(
    name: 'informe_nomina_${(d['periodo'] ?? '').toString().replaceAll(' ', '_')}.pdf',
    onLayout: (_) => doc.save(),
  );
}
