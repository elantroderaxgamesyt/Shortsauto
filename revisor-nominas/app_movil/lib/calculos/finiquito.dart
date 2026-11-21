import 'dart:math';

import 'datos.dart';

enum MotivoBaja {
  voluntaria('Baja voluntaria (dimisión)', 0),
  finContrato('Fin de contrato temporal', 12),
  despidoObjetivo('Despido objetivo', 20),
  despidoImprocedente('Despido improcedente', 33),
  despidoDisciplinario('Despido disciplinario procedente', 0);

  const MotivoBaja(this.texto, this.diasPorAnio);
  final String texto;
  final int diasPorAnio; // días de salario por año trabajado
}

class LineaFiniquito {
  LineaFiniquito(this.concepto, this.importe, [this.detalle]);
  final String concepto;
  final double importe;
  final String? detalle;
}

class ResultadoFiniquito {
  ResultadoFiniquito(this.lineas, {required this.indemnizacion, required this.aniosTrabajados});
  final List<LineaFiniquito> lineas;
  final LineaFiniquito? indemnizacion;
  final double aniosTrabajados;

  double get finiquito => lineas.fold(0.0, (s, l) => s + l.importe);
  double get total => finiquito + (indemnizacion?.importe ?? 0);
}

int _dias(DateTime a, DateTime b) => b.difference(DateTime(a.year, a.month, a.day)).inDays + 1;

/// Finiquito (salario pendiente, vacaciones no disfrutadas y parte proporcional de pagas extra)
/// e indemnización según el motivo de la baja. Todo en bruto.
ResultadoFiniquito calcularFiniquito({
  required double brutoAnual,
  required DateTime inicio,
  required DateTime fin,
  required MotivoBaja motivo,
  int pagas = 14,
  double vacacionesDisfrutadas = 0,
  double vacacionesAnteriores = 0, // días pendientes de años anteriores que no han caducado
  bool nominaMesCobrada = false,
}) {
  final diario = brutoAnual / 365;
  final mensual = brutoAnual / 12;
  final lineas = <LineaFiniquito>[];

  // 1) Salario de los días trabajados del último mes.
  if (!nominaMesCobrada) {
    final diasMes = fin.day;
    lineas.add(LineaFiniquito('Salario de $diasMes días de ${_mes(fin.month)}', mensual / 30 * min(diasMes, 30)));
  }

  // 2) Vacaciones: 30 días naturales al año, proporcionales a lo trabajado este año.
  final inicioAnio = inicio.isAfter(DateTime(fin.year, 1, 1)) ? inicio : DateTime(fin.year, 1, 1);
  final generadas = 30 * _dias(inicioAnio, fin) / 365;
  final pendientes = max(0.0, generadas - vacacionesDisfrutadas);
  if (pendientes > 0) {
    lineas.add(LineaFiniquito('Vacaciones no disfrutadas', pendientes * diario,
        '${pendientes.toStringAsFixed(1).replaceAll('.', ',')} días'));
  }

  // 2b) Vacaciones de años anteriores: normalmente caducan, salvo baja médica (hasta 18 meses),
  //     maternidad/paternidad o si la empresa no dejó cogerlas (art. 38 ET y jurisprudencia del TJUE).
  if (vacacionesAnteriores > 0) {
    lineas.add(LineaFiniquito('Vacaciones de años anteriores', vacacionesAnteriores * diario,
        '${vacacionesAnteriores.toStringAsFixed(1).replaceAll('.', ',')} días'));
  }

  // 3) Pagas extra (si no van prorrateadas): la de junio se genera de enero a junio y la de
  //    diciembre de julio a diciembre. Se debe la parte del semestre en curso.
  if (pagas == 14) {
    final paga = brutoAnual / 14;
    final primerSemestre = fin.month <= 6;
    final inicioSemestre = DateTime(fin.year, primerSemestre ? 1 : 7, 1);
    final desde = inicio.isAfter(inicioSemestre) ? inicio : inicioSemestre;
    final diasSemestre = _dias(inicioSemestre, DateTime(fin.year, primerSemestre ? 6 : 12, primerSemestre ? 30 : 31));
    final parte = paga * _dias(desde, fin) / diasSemestre;
    lineas.add(LineaFiniquito('Parte de la paga extra de ${primerSemestre ? 'junio' : 'diciembre'}', parte));
  }

  // 4) Indemnización.
  final anios = _dias(inicio, fin) / 365;
  LineaFiniquito? indemnizacion;
  if (motivo.diasPorAnio > 0) {
    double dias;
    String detalle;
    switch (motivo) {
      case MotivoBaja.despidoImprocedente:
        // Contratos anteriores a la reforma de 2012: 45 días/año hasta esa fecha y 33 después.
        if (inicio.isBefore(Datos.reformaLaboral2012)) {
          final antes = _dias(inicio, Datos.reformaLaboral2012.subtract(const Duration(days: 1))) / 365 * 45;
          final despues = _dias(Datos.reformaLaboral2012, fin) / 365 * 33;
          final tope = antes > 720 ? min(antes, 1260.0) : 720.0;
          dias = min(antes + despues, tope);
          detalle = '45 días/año hasta feb. 2012 y 33 después';
        } else {
          dias = min(anios * 33, 720.0); // máx. 24 mensualidades
          detalle = '33 días por año (máx. 24 mensualidades)';
        }
      case MotivoBaja.despidoObjetivo:
        dias = min(anios * 20, 360.0); // máx. 12 mensualidades
        detalle = '20 días por año (máx. 12 mensualidades)';
      default:
        dias = anios * motivo.diasPorAnio;
        detalle = '${motivo.diasPorAnio} días por año';
    }
    indemnizacion = LineaFiniquito('Indemnización', dias * diario, detalle);
  }

  return ResultadoFiniquito(lineas, indemnizacion: indemnizacion, aniosTrabajados: anios);
}

const _meses = ['enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio', 'julio', 'agosto', 'septiembre',
  'octubre', 'noviembre', 'diciembre'];
String _mes(int m) => _meses[m - 1];
