import 'package:flutter_test/flutter_test.dart';
import 'package:revisor_nominas/calculos/datos.dart';
import 'package:revisor_nominas/calculos/extras.dart';
import 'package:revisor_nominas/calculos/finiquito.dart';
import 'package:revisor_nominas/calculos/neto.dart';
import 'package:revisor_nominas/pantallas/calculadoras.dart';

void main() {
  group('Sueldo neto', () {
    test('30.000 € brutos, indefinido, sin hijos', () {
      final r = calcularNeto(brutoAnual: 30000);
      expect(r.seguridadSocial, closeTo(1950, 0.01)); // 6,50 %
      // IRPF: base 30.000-1.950-2.000 = 26.050 → 5.980,5 de escala - 1.054,5 del mínimo = 4.926
      expect(r.irpf, closeTo(4926, 1));
      expect(r.tipoIrpf, closeTo(16.4, 0.1));
      expect(r.netoPorPaga, closeTo(1651.71, 1)); // 14 pagas
      expect(calcularNeto(brutoAnual: 30000, pagas: 12).netoPorPaga, closeTo(1927, 1));
    });

    test('Sueldo bajo: no se retiene IRPF', () {
      expect(calcularNeto(brutoAnual: 15000).irpf, 0);
    });

    test('Hijos bajan el IRPF', () {
      final sin = calcularNeto(brutoAnual: 30000).irpf;
      final con = calcularNeto(brutoAnual: 30000, hijos: 2, hijosMenores3: 1).irpf;
      expect(con, lessThan(sin));
    });

    test('Temporal cotiza 0,05 % más por desempleo', () {
      expect(calcularNeto(brutoAnual: 30000, temporal: true).seguridadSocial, closeTo(1965, 0.01));
    });

    test('La Seguridad Social tiene tope', () {
      expect(calcularNeto(brutoAnual: 120000).seguridadSocial,
          closeTo(Datos.baseMaximaMensual * 12 * 6.5 / 100, 0.01));
    });

    test('Cerca del límite, la retención no supera el 43 % del exceso', () {
      final r = calcularNeto(brutoAnual: 16000);
      expect(r.irpf, lessThanOrEqualTo(0.43 * (16000 - Datos.limiteSinRetencion) + 0.001));
    });
  });

  group('Finiquito', () {
    test('Despido improcedente tras 2 años, 14 pagas', () {
      final r = calcularFiniquito(
        brutoAnual: 36500, // 100 €/día
        inicio: DateTime(2024, 1, 1),
        fin: DateTime(2025, 12, 31),
        motivo: MotivoBaja.despidoImprocedente,
        vacacionesDisfrutadas: 30,
      );
      // 2 años x 33 días x 100 € = 6.600 €
      expect(r.indemnizacion!.importe, closeTo(6600, 20));
      // Sin vacaciones pendientes (disfrutó las 30)
      expect(r.lineas.any((l) => l.concepto.startsWith('Vacaciones')), isFalse);
      // Paga de diciembre entera pendiente (julio-diciembre trabajado)
      final paga = r.lineas.firstWhere((l) => l.concepto.contains('paga extra'));
      expect(paga.importe, closeTo(36500 / 14, 1));
    });

    test('Baja voluntaria: sin indemnización, vacaciones proporcionales', () {
      final r = calcularFiniquito(
        brutoAnual: 36500,
        inicio: DateTime(2020, 3, 1),
        fin: DateTime(2026, 3, 31),
        motivo: MotivoBaja.voluntaria,
        pagas: 12,
        nominaMesCobrada: true,
      );
      expect(r.indemnizacion, isNull);
      expect(r.lineas.length, 1); // sólo vacaciones (pagas prorrateadas y nómina cobrada)
      // 90 días trabajados este año → 30*90/365 = 7,4 días → ~740 €
      expect(r.finiquito, closeTo(739.7, 1));
    });

    test('Fin de contrato temporal: 12 días por año', () {
      final r = calcularFiniquito(
        brutoAnual: 36500,
        inicio: DateTime(2026, 1, 1),
        fin: DateTime(2026, 12, 31),
        motivo: MotivoBaja.finContrato,
      );
      expect(r.indemnizacion!.importe, closeTo(1200, 5));
    });

    test('Despido objetivo con tope de 12 mensualidades', () {
      final r = calcularFiniquito(
        brutoAnual: 36500,
        inicio: DateTime(2000, 1, 1),
        fin: DateTime(2026, 1, 31),
        motivo: MotivoBaja.despidoObjetivo,
      );
      expect(r.indemnizacion!.importe, closeTo(36000, 1)); // 360 días x 100 €
    });

    test('Improcedente con contrato anterior a 2012: 45 días hasta la reforma', () {
      final r = calcularFiniquito(
        brutoAnual: 36500,
        inicio: DateTime(2010, 2, 12),
        fin: DateTime(2014, 2, 11),
        motivo: MotivoBaja.despidoImprocedente,
      );
      // 2 años x 45 + 2 años x 33 = 156 días → 15.600 €
      expect(r.indemnizacion!.importe, closeTo(15600, 50));
    });
  });

  group('Horas y pagas extra', () {
    test('Hora extra al precio de la ordinaria', () {
      final r = calcularHorasExtra(brutoAnual: 27000, horasSemanales: 40, horas: 10);
      expect(r.precioHoraOrdinaria, closeTo(15, 0.01)); // 27.000 / 1.800 h
      expect(r.total, closeTo(150, 0.1));
    });

    test('Con recargo o precio del convenio', () {
      expect(calcularHorasExtra(brutoAnual: 27000, horasSemanales: 40, horas: 10, recargo: 25).total,
          closeTo(187.5, 0.1));
      expect(calcularHorasExtra(brutoAnual: 27000, horasSemanales: 40, horas: 10, precioConvenio: 20).total, 200);
    });

    test('Paga extra proporcional si entraste a mitad de periodo', () {
      final r = calcularPagaExtra(brutoAnual: 28000, inicio: DateTime(2026, 10, 1), diciembre: true, anio: 2026);
      expect(r.pagaCompleta, 2000);
      expect(r.diasTrabajados, 92);
      expect(r.importe, closeTo(2000 * 92 / 184, 0.01));
      expect(calcularPagaExtra(brutoAnual: 28000, inicio: DateTime(2020, 1, 1), diciembre: false, anio: 2026).completa,
          isTrue);
    });
  });

  group('Lectura de lo que escribe el usuario', () {
    test('números', () {
      expect(leerNumero('30.000'), 30000);
      expect(leerNumero('30000'), 30000);
      expect(leerNumero('30.000,50'), 30000.5);
      expect(leerNumero('1.234.567'), 1234567);
      expect(leerNumero('12,5'), 12.5);
      expect(leerNumero('7.5'), 7.5);
      expect(leerNumero('24 000 €'), 24000);
      expect(leerNumero(''), isNull);
    });

    test('fechas', () {
      expect(leerFecha('15/03/2024'), DateTime(2024, 3, 15));
      expect(leerFecha('1-2-2020'), DateTime(2020, 2, 1));
      expect(leerFecha('31/02/2024'), isNull);
      expect(leerFecha('15/03/24'), DateTime(2024, 3, 15));
      expect(leerFecha('15/03/85'), DateTime(1985, 3, 15));
      expect(fechaTexto(DateTime(2024, 3, 5)), '05/03/2024');
    });

    test('las barras se ponen solas', () {
      String escribir(String t) => FormatoFecha().formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: t)).text;
      expect(escribir('01032022'), '01/03/2022');
      expect(escribir('0103'), '01/03');
      expect(escribir('010'), '01/0');
      expect(escribir('01/03/2022'), '01/03/2022');
      expect(escribir('010320221'), '01/03/2022');
    });
  });
}
