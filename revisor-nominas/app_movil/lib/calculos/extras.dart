import 'dart:math';

import 'datos.dart';

class ResultadoHorasExtra {
  ResultadoHorasExtra({required this.precioHoraOrdinaria, required this.precioHoraExtra, required this.horas});
  final double precioHoraOrdinaria;
  final double precioHoraExtra;
  final double horas;
  double get total => precioHoraExtra * horas;
  bool get superaMaximoAnual => horas > Datos.maxHorasExtraAnio;
}

/// Horas extra: la hora extra vale como mínimo lo mismo que la ordinaria (art. 35 ET);
/// el convenio puede fijar un recargo o un precio concreto.
ResultadoHorasExtra calcularHorasExtra({
  required double brutoAnual,
  required double horasSemanales,
  required double horas,
  double recargo = 0, // % sobre la hora ordinaria
  double? precioConvenio,
}) {
  final horasAnuales = horasSemanales / 5 * Datos.diasLaborablesAnio;
  final ordinaria = horasAnuales <= 0 ? 0.0 : brutoAnual / horasAnuales;
  final extra = precioConvenio ?? ordinaria * (1 + recargo / 100);
  return ResultadoHorasExtra(precioHoraOrdinaria: ordinaria, precioHoraExtra: max(extra, 0), horas: horas);
}

class ResultadoPagaExtra {
  ResultadoPagaExtra({required this.pagaCompleta, required this.diasTrabajados, required this.diasPeriodo});
  final double pagaCompleta;
  final int diasTrabajados;
  final int diasPeriodo;
  double get importe => pagaCompleta * diasTrabajados / diasPeriodo;
  bool get completa => diasTrabajados >= diasPeriodo;
}

/// Paga extra (14 pagas): la de junio se genera de enero a junio y la de diciembre de julio a
/// diciembre. Si empezaste a trabajar a mitad de periodo, te toca la parte proporcional.
ResultadoPagaExtra calcularPagaExtra({
  required double brutoAnual,
  required DateTime inicio,
  required bool diciembre,
  required int anio,
}) {
  final desdePeriodo = DateTime(anio, diciembre ? 7 : 1, 1);
  final hastaPeriodo = DateTime(anio, diciembre ? 12 : 6, diciembre ? 31 : 30);
  final diasPeriodo = hastaPeriodo.difference(desdePeriodo).inDays + 1;
  final desde = inicio.isAfter(desdePeriodo) ? inicio : desdePeriodo;
  final trabajados = inicio.isAfter(hastaPeriodo) ? 0 : hastaPeriodo.difference(desde).inDays + 1;
  return ResultadoPagaExtra(pagaCompleta: brutoAnual / 14, diasTrabajados: trabajados, diasPeriodo: diasPeriodo);
}
