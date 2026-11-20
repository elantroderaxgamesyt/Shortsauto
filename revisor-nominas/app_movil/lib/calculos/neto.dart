import 'dart:math';

import 'datos.dart';

/// Resultado de pasar de sueldo bruto a neto (todo en euros al año salvo lo indicado).
class ResultadoNeto {
  ResultadoNeto({
    required this.brutoAnual,
    required this.seguridadSocial,
    required this.irpf,
    required this.pagas,
  });

  final double brutoAnual;
  final double seguridadSocial;
  final double irpf;
  final int pagas;

  double get netoAnual => brutoAnual - seguridadSocial - irpf;
  double get netoPorPaga => netoAnual / pagas;
  double get tipoIrpf => brutoAnual == 0 ? 0 : irpf / brutoAnual * 100;
  double get tipoSeguridadSocial => brutoAnual == 0 ? 0 : seguridadSocial / brutoAnual * 100;
}

/// Estimación del sueldo neto. La Seguridad Social es exacta (con el tope de base máxima);
/// el IRPF es una estimación con la escala general, sin deducciones autonómicas.
ResultadoNeto calcularNeto({
  required double brutoAnual,
  int pagas = 14,
  bool temporal = false,
  int hijos = 0,
  int hijosMenores3 = 0,
  bool mayor65 = false,
}) {
  final bruto = max(0.0, brutoAnual);
  final ss = seguridadSocialAnual(bruto, temporal: temporal);
  final irpf = irpfAnual(bruto, ss, hijos: hijos, hijosMenores3: hijosMenores3, mayor65: mayor65);
  return ResultadoNeto(brutoAnual: bruto, seguridadSocial: ss, irpf: irpf, pagas: pagas);
}

double tipoSeguridadSocial({bool temporal = false}) =>
    Datos.contingenciasComunes +
    (temporal ? Datos.desempleoTemporal : Datos.desempleoIndefinido) +
    Datos.formacionProfesional +
    Datos.mei;

double seguridadSocialAnual(double bruto, {bool temporal = false}) {
  final base = min(bruto, Datos.baseMaximaMensual * 12);
  return base * tipoSeguridadSocial(temporal: temporal) / 100;
}

double _escala(double base) {
  var cuota = 0.0;
  var desde = 0.0;
  for (final (hasta, tipo) in Datos.escalaIrpf) {
    if (base <= desde) break;
    cuota += (min(base, hasta) - desde) * tipo / 100;
    desde = hasta;
  }
  return cuota;
}

double _reduccionTrabajo(double rendimientoNeto) {
  if (rendimientoNeto <= Datos.reduccionTramo1) return Datos.reduccionMax;
  if (rendimientoNeto <= Datos.reduccionTramo2) {
    return Datos.reduccionMax - 1.75 * (rendimientoNeto - Datos.reduccionTramo1);
  }
  if (rendimientoNeto <= Datos.reduccionTramo3) {
    return Datos.reduccionMedia - 1.14 * (rendimientoNeto - Datos.reduccionTramo2);
  }
  return 0;
}

double irpfAnual(double bruto, double ss, {int hijos = 0, int hijosMenores3 = 0, bool mayor65 = false}) {
  if (bruto <= Datos.limiteSinRetencion && hijos == 0) return 0;
  final rendimientoNeto = bruto - ss;
  final base = max(0.0, rendimientoNeto - Datos.otrosGastos - _reduccionTrabajo(rendimientoNeto));

  var minimos = Datos.minimoPersonal + (mayor65 ? Datos.minimoMayor65 : 0);
  for (var i = 0; i < hijos; i++) {
    minimos += Datos.minimoHijos[min(i, Datos.minimoHijos.length - 1)];
  }
  minimos += min(hijosMenores3, hijos) * Datos.minimoHijoMenor3;

  var cuota = max(0.0, _escala(base) - _escala(minimos));
  // La retención no puede superar el 43 % de lo que exceda del límite sin retención.
  cuota = min(cuota, max(0.0, 0.43 * (bruto - Datos.limiteSinRetencion)));
  return cuota;
}
