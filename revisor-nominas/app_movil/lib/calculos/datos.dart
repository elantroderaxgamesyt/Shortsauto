/// Datos legales que usan las calculadoras. **Revisar cada año** (BOE / Orden de cotización /
/// Agencia Tributaria). Los mismos tipos de cotización están en el servidor
/// (app/referencia_2026.json).
abstract final class Datos {
  static const anio = 2026;

  // ---- Seguridad Social (parte del trabajador, %) ----
  static const contingenciasComunes = 4.70;
  static const desempleoIndefinido = 1.55;
  static const desempleoTemporal = 1.60;
  static const formacionProfesional = 0.10;
  static const mei = 0.15;

  /// Base máxima de cotización mensual (verificar cada año).
  static const baseMaximaMensual = 5101.20;

  // ---- IRPF (estimación con la escala general estatal + autonómica tipo) ----
  /// Tramos: (hasta, tipo %). La última fila no tiene límite.
  static const escalaIrpf = <(double, double)>[
    (12450, 19),
    (20200, 24),
    (35200, 30),
    (60000, 37),
    (300000, 45),
    (double.infinity, 47),
  ];

  /// Otros gastos deducibles de los rendimientos del trabajo.
  static const otrosGastos = 2000.0;

  /// Mínimo personal y por descendientes.
  static const minimoPersonal = 5550.0;
  static const minimoMayor65 = 1150.0;
  static const minimoHijos = [2400.0, 2700.0, 4000.0, 4500.0]; // 1º, 2º, 3º, 4º y siguientes
  static const minimoHijoMenor3 = 2800.0;

  /// Reducción por obtención de rendimientos del trabajo (art. 20 LIRPF).
  static const reduccionMax = 7302.0;
  static const reduccionTramo1 = 14852.0;
  static const reduccionTramo2 = 17673.52;
  static const reduccionTramo3 = 19747.5;
  static const reduccionMedia = 2364.34;

  /// Por debajo de este sueldo no se retiene IRPF (sin hijos); y la retención no puede superar
  /// el 43 % de lo que exceda de esta cifra.
  static const limiteSinRetencion = 15876.0;

  // ---- Indemnizaciones por despido ----
  static final reformaLaboral2012 = DateTime(2012, 2, 12);

  // ---- Jornada ----
  /// Días laborables al año (365 - fines de semana - 14 festivos - 22 de vacaciones).
  static const diasLaborablesAnio = 225;

  /// Máximo legal de horas extra al año (art. 35 ET).
  static const maxHorasExtraAnio = 80;
}
