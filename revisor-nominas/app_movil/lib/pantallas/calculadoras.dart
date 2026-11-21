import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../anuncios.dart';
import '../calculos/datos.dart';
import '../calculos/extras.dart';
import '../calculos/finiquito.dart';
import '../calculos/neto.dart';
import '../tema.dart';
import '../widgets.dart';
import 'nueva_revision.dart';

/// Calculadoras gratuitas: se calculan en el móvil, sin servidor ni IA (no cuestan nada).
class PantallaCalculadoras extends StatelessWidget {
  const PantallaCalculadoras({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Calculadoras')),
        body: SafeArea(
          child: Pagina(children: [
            Text('Gratis y al momento. Los resultados son orientativos.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Tonos.de(context).suave)),
            const Hueco(16),
            const TarjetasCalculadoras(),
          ]),
        ),
      );
}

/// Las tres tarjetas (se usan también en Inicio).
class TarjetasCalculadoras extends StatelessWidget {
  const TarjetasCalculadoras({super.key});

  static final calculadoras = <(IconData, String, String, Widget Function())>[
    (Icons.payments_outlined, 'Sueldo neto', 'Cuánto cobras al mes de tu sueldo bruto', () => const CalculadoraNeto()),
    (Icons.work_off_outlined, 'Finiquito e indemnización', 'Vacaciones, pagas extra y despido',
        () => const CalculadoraFiniquito()),
    (Icons.more_time_rounded, 'Horas y pagas extra', 'Precio de la hora extra y paga proporcional',
        () => const CalculadoraExtras()),
  ];

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Column(children: [
      for (final (icono, titulo, sub, pantalla) in calculadoras) ...[
        Card(
          clipBehavior: Clip.antiAlias,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: t.colorScheme.primary.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
              child: Icon(icono, color: t.colorScheme.primary),
            ),
            title: Text(titulo, style: t.textTheme.titleSmall),
            subtitle: Text(sub),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => pantalla())),
          ),
        ),
        const Hueco(10),
      ],
    ]);
  }
}

// ======================================================================= piezas comunes

/// Convierte lo que escribe el usuario en número, venga con formato español o inglés:
/// "30.000", "30,000", "1.650", "1,650" (miles), "30000,5", "1.234,56", "1,234.56", "24 000 €".
double? leerNumero(String texto) {
  var s = texto.replaceAll(RegExp(r'[\s€]'), '');
  if (s.isEmpty) return null;
  final ultimoPunto = s.lastIndexOf('.'), ultimaComa = s.lastIndexOf(',');
  if (ultimoPunto >= 0 && ultimaComa >= 0) {
    // Los dos: el último que aparece es el decimal.
    final decimal = ultimoPunto > ultimaComa ? '.' : ',';
    final miles = decimal == '.' ? ',' : '.';
    s = s.replaceAll(miles, '').replaceAll(decimal, '.');
  } else if (ultimoPunto >= 0 || ultimaComa >= 0) {
    final sep = ultimoPunto >= 0 ? '.' : ',';
    final partes = s.split(sep);
    // Uno solo: si separa grupos de exactamente 3 cifras, son miles (1,650 = 1.650); si no, decimal.
    final sonMiles = partes.length > 2 || (partes.length == 2 && partes[1].length == 3 && partes[0].isNotEmpty && partes[0] != '0');
    s = sonMiles ? partes.join() : s.replaceAll(sep, '.');
  }
  return double.tryParse(s);
}

/// Sueldo anual a partir de lo escrito, que puede ser anual o de cada paga.
double? sueldoAnual(String texto, {required bool porMes, required int pagas}) {
  final v = leerNumero(texto);
  return v == null ? null : (porMes ? v * pagas : v);
}

/// Selector "al año / al mes" + campo del sueldo + aviso si la cifra anual parece mensual.
class CampoSueldo extends StatelessWidget {
  const CampoSueldo({
    super.key,
    required this.controlador,
    required this.porMes,
    required this.onPorMes,
    required this.onChanged,
    this.pagas = 14,
  });
  final TextEditingController controlador;
  final bool porMes;
  final ValueChanged<bool> onPorMes;
  final VoidCallback onChanged;
  final int pagas;

  @override
  Widget build(BuildContext context) {
    final escrito = leerNumero(controlador.text);
    final pareceMensual = !porMes && escrito != null && escrito > 0 && escrito < 6000;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Opciones(
        valor: porMes,
        opciones: const [(false, 'Bruto al año'), (true, 'Bruto al mes')],
        onChanged: onPorMes,
      ),
      const Hueco(12),
      CampoNumero(
        controlador,
        porMes ? 'Sueldo bruto de cada paga' : 'Sueldo bruto anual',
        ayuda: porMes
            ? 'El "Total devengado" de una nómina'
            : 'Lo que pone en tu contrato, p. ej. 24.000',
        onChanged: onChanged,
      ),
      if (pareceMensual)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('¿Es tu sueldo de un mes? Elige "Bruto al mes" arriba.',
              style: TextStyle(color: Estilo.de('aviso').texto(context), fontWeight: FontWeight.w600)),
        ),
    ]);
  }
}

/// Convierte "15/03/2024" (o con - o .) en fecha.
DateTime? leerFecha(String texto) {
  final m = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2}|\d{4})$').firstMatch(texto.trim());
  if (m == null) return null;
  final d = int.parse(m[1]!), mes = int.parse(m[2]!);
  var a = int.parse(m[3]!);
  if (m[3]!.length == 2) a += a <= (DateTime.now().year % 100) + 1 ? 2000 : 1900; // 15/03/24 → 2024
  final f = DateTime(a, mes, d);
  return (f.day == d && f.month == mes && a > 1950 && a < 2100) ? f : null;
}

String fechaTexto(DateTime f) =>
    '${f.day.toString().padLeft(2, '0')}/${f.month.toString().padLeft(2, '0')}/${f.year}';

class CampoNumero extends StatelessWidget {
  const CampoNumero(this.controlador, this.etiqueta, {super.key, this.sufijo = '€', this.ayuda, this.onChanged});
  final TextEditingController controlador;
  final String etiqueta;
  final String sufijo;
  final String? ayuda;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controlador,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]'))],
        onChanged: (_) => onChanged?.call(),
        decoration: InputDecoration(labelText: etiqueta, suffixText: sufijo, helperText: ayuda),
      );
}

/// Pone las barras solas mientras se escribe: 01032022 → 01/03/2022.
class FormatoFecha extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue anterior, TextEditingValue nuevo) {
    final digitos = nuevo.text.replaceAll(RegExp(r'\D'), '');
    final d = digitos.length > 8 ? digitos.substring(0, 8) : digitos;
    final b = StringBuffer();
    for (var i = 0; i < d.length; i++) {
      if (i == 2 || i == 4) b.write('/');
      b.write(d[i]);
    }
    final texto = b.toString();
    return TextEditingValue(text: texto, selection: TextSelection.collapsed(offset: texto.length));
  }
}

class CampoFecha extends StatelessWidget {
  const CampoFecha(this.controlador, this.etiqueta, {super.key, this.onChanged});
  final TextEditingController controlador;
  final String etiqueta;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final texto = controlador.text;
    // Sólo se avisa cuando la fecha está completa (no mientras se escribe).
    final mal = texto.length == 10 && leerFecha(texto) == null;
    return TextField(
      controller: controlador,
      keyboardType: TextInputType.number,
      inputFormatters: [FormatoFecha()],
      onChanged: (_) => onChanged?.call(),
      decoration: InputDecoration(
        labelText: etiqueta,
        hintText: 'dd/mm/aaaa',
        errorText: mal ? 'Fecha no válida' : null,
        suffixIcon: const Icon(Icons.event_outlined),
      ),
    );
  }
}

/// Elegir entre pocas opciones con botones.
class Opciones<T> extends StatelessWidget {
  const Opciones({super.key, required this.valor, required this.opciones, required this.onChanged});
  final T valor;
  final List<(T, String)> opciones;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: double.infinity,
        child: SegmentedButton<T>(
          showSelectedIcon: false,
          segments: [for (final (v, txt) in opciones) ButtonSegment(value: v, label: Text(txt))],
          selected: {valor},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      );
}

class FilaResultado extends StatelessWidget {
  const FilaResultado(this.concepto, this.valor, {super.key, this.detalle, this.fuerte = false});
  final String concepto;
  final String valor;
  final String? detalle;
  final bool fuerte;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final estilo = fuerte ? t.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700) : t.textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(concepto, style: estilo),
            if (detalle != null)
              Text(detalle!, style: t.textTheme.bodySmall?.copyWith(color: Tonos.de(context).suave)),
          ]),
        ),
        const SizedBox(width: 12),
        Text(valor, style: estilo?.copyWith(fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

/// Gran cifra destacada arriba del resultado.
class CifraPrincipal extends StatelessWidget {
  const CifraPrincipal(this.titulo, this.valor, {super.key, this.sub});
  final String titulo;
  final String valor;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(gradient: Marca.degradado, borderRadius: BorderRadius.circular(18)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titulo, style: t.textTheme.labelLarge?.copyWith(color: Colors.white.withValues(alpha: .85))),
        const SizedBox(height: 4),
        FittedBox(
          child: Text(valor,
              style: t.textTheme.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
        ),
        if (sub != null) Text(sub!, style: TextStyle(color: Colors.white.withValues(alpha: .85))),
      ]),
    );
  }
}

/// Lleva de la calculadora a la revisión de la nómina real (lo que da dinero).
class PromoRevision extends StatelessWidget {
  const PromoRevision(this.texto, {super.key});
  final String texto;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.fact_check_outlined, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(texto, style: Theme.of(context).textTheme.titleSmall)),
            ]),
            const Hueco(12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => empezarRevision(context),
                child: const Text('Revisar mi nómina'),
              ),
            ),
          ]),
        ),
      );
}

class _Aviso extends StatelessWidget {
  const _Aviso(this.texto);
  final String texto;

  @override
  Widget build(BuildContext context) => Text(texto,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Tonos.de(context).suave, height: 1.4));
}

/// Estructura común: formulario + resultado + promoción, con banner abajo.
class _PantallaCalculadora extends StatelessWidget {
  const _PantallaCalculadora({required this.titulo, required this.children});
  final String titulo;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(titulo)),
        bottomNavigationBar: const SafeArea(top: false, child: BannerAnuncio()),
        body: SafeArea(
          bottom: false,
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Pagina(children: children),
          ),
        ),
      );
}

String _p(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

// ======================================================================= 1. sueldo neto

class CalculadoraNeto extends StatefulWidget {
  const CalculadoraNeto({super.key});

  @override
  State<CalculadoraNeto> createState() => _CalculadoraNetoState();
}

class _CalculadoraNetoState extends State<CalculadoraNeto> {
  final bruto = TextEditingController();
  bool porMes = false; // el usuario escribe el bruto mensual en vez del anual
  int pagas = 14;
  bool temporal = false;
  int hijos = 0;
  int menores3 = 0;

  @override
  Widget build(BuildContext context) {
    final b = sueldoAnual(bruto.text, porMes: porMes, pagas: pagas);
    final r = (b != null && b > 0)
        ? calcularNeto(brutoAnual: b, pagas: pagas, temporal: temporal, hijos: hijos, hijosMenores3: menores3)
        : null;
    void cambia() => setState(() {});
    return _PantallaCalculadora(titulo: 'Sueldo neto', children: [
      CampoSueldo(
          controlador: bruto, porMes: porMes, pagas: pagas, onPorMes: (v) => setState(() => porMes = v), onChanged: cambia),
      const Hueco(16),
      Text('Número de pagas', style: Theme.of(context).textTheme.labelLarge),
      const Hueco(6),
      Opciones(valor: pagas, opciones: const [(12, '12 (prorrateadas)'), (14, '14')], onChanged: (v) => setState(() => pagas = v)),
      const Hueco(12),
      Text('Contrato', style: Theme.of(context).textTheme.labelLarge),
      const Hueco(6),
      Opciones(valor: temporal, opciones: const [(false, 'Indefinido'), (true, 'Temporal')],
          onChanged: (v) => setState(() => temporal = v)),
      const Hueco(12),
      Row(children: [
        Expanded(child: _Contador('Hijos', hijos, (v) => setState(() {
              hijos = v;
              if (menores3 > hijos) menores3 = hijos;
            }))),
        const SizedBox(width: 12),
        Expanded(child: _Contador('Menores de 3 años', menores3, (v) => setState(() => menores3 = v.clamp(0, hijos)))),
      ]),
      const Hueco(20),
      if (r == null)
        const _Aviso('Escribe tu sueldo bruto anual para ver el resultado.')
      else ...[
        CifraPrincipal('Cobrarás al mes', eur(r.netoPorPaga),
            sub: pagas == 14 ? '14 pagas · ${eur(r.netoAnual)} netos al año' : '12 pagas · ${eur(r.netoAnual)} netos al año'),
        const Hueco(12),
        Panel(
          titulo: 'Desglose anual',
          icono: Icons.receipt_long_outlined,
          child: Column(children: [
            FilaResultado('Sueldo bruto', eur(r.brutoAnual)),
            FilaResultado('Seguridad Social', '- ${eur(r.seguridadSocial)}', detalle: '${_p(r.tipoSeguridadSocial)} %'),
            FilaResultado('Retención de IRPF (estimada)', '- ${eur(r.irpf)}', detalle: '${_p(r.tipoIrpf)} %'),
            const Divider(),
            FilaResultado('Sueldo neto', eur(r.netoAnual), fuerte: true),
            const Hueco(4),
          ]),
        ),
        const Hueco(12),
        const _Aviso('El IRPF es una estimación con la escala general (${Datos.anio}). Tu retención real puede '
            'variar según tu comunidad autónoma, discapacidad, pensiones compensatorias u otras situaciones.'),
        const Hueco(16),
        const PromoRevision('¿Tu nómina coincide con este cálculo? Compruébalo gratis.'),
      ],
    ]);
  }
}

class _Contador extends StatelessWidget {
  const _Contador(this.titulo, this.valor, this.onChanged);
  final String titulo;
  final int valor;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final tonos = Tonos.de(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
      decoration: BoxDecoration(color: tonos.tenue, borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Expanded(child: Text(titulo, style: Theme.of(context).textTheme.bodySmall)),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: valor > 0 ? () => onChanged(valor - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        Text('$valor', style: Theme.of(context).textTheme.titleSmall),
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: valor < 9 ? () => onChanged(valor + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ]),
    );
  }
}

// ======================================================================= 2. finiquito

class CalculadoraFiniquito extends StatefulWidget {
  const CalculadoraFiniquito({super.key});

  @override
  State<CalculadoraFiniquito> createState() => _CalculadoraFiniquitoState();
}

class _CalculadoraFiniquitoState extends State<CalculadoraFiniquito> {
  final bruto = TextEditingController();
  bool porMes = true; // casi todo el mundo sabe lo que cobra al mes
  final inicio = TextEditingController();
  final fin = TextEditingController(text: fechaTexto(DateTime.now()));
  final disfrutadas = TextEditingController(text: '0');
  MotivoBaja motivo = MotivoBaja.voluntaria;
  int pagas = 14;
  bool nominaCobrada = false;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    void cambia() => setState(() {});
    final b = sueldoAnual(bruto.text, porMes: porMes, pagas: pagas);
    final fi = leerFecha(inicio.text);
    final ff = leerFecha(fin.text);
    final fechasMal = fi != null && ff != null && !ff.isAfter(fi);
    final r = (b != null && b > 0 && fi != null && ff != null && !fechasMal)
        ? calcularFiniquito(
            brutoAnual: b,
            inicio: fi,
            fin: ff,
            motivo: motivo,
            pagas: pagas,
            vacacionesDisfrutadas: leerNumero(disfrutadas.text) ?? 0,
            nominaMesCobrada: nominaCobrada,
          )
        : null;

    return _PantallaCalculadora(titulo: 'Finiquito', children: [
      CampoSueldo(
          controlador: bruto, porMes: porMes, pagas: pagas, onPorMes: (v) => setState(() => porMes = v), onChanged: cambia),
      const Hueco(12),
      Row(children: [
        Expanded(child: CampoFecha(inicio, 'Empezaste', onChanged: cambia)),
        const SizedBox(width: 12),
        Expanded(child: CampoFecha(fin, 'Último día', onChanged: cambia)),
      ]),
      const Hueco(12),
      DropdownButtonFormField<MotivoBaja>(
        initialValue: motivo,
        decoration: const InputDecoration(labelText: 'Motivo'),
        items: [for (final m in MotivoBaja.values) DropdownMenuItem(value: m, child: Text(m.texto))],
        onChanged: (v) => setState(() => motivo = v ?? motivo),
      ),
      const Hueco(12),
      CampoNumero(disfrutadas, 'Días de vacaciones ya disfrutados este año', sufijo: 'días', onChanged: cambia),
      const Hueco(12),
      Text('Pagas extra', style: t.textTheme.labelLarge),
      const Hueco(6),
      Opciones(valor: pagas, opciones: const [(14, 'Aparte (14 pagas)'), (12, 'Prorrateadas (12)')],
          onChanged: (v) => setState(() => pagas = v)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Ya he cobrado la nómina de este último mes'),
        value: nominaCobrada,
        onChanged: (v) => setState(() => nominaCobrada = v),
      ),
      const Hueco(8),
      if (fechasMal)
        const _Aviso('El último día tiene que ser posterior a la fecha de inicio.')
      else if (r == null)
        const _Aviso('Rellena el sueldo y las fechas para ver el resultado.')
      else ...[
        CifraPrincipal('Te corresponde (bruto)', eur(r.total),
            sub: 'Finiquito ${eur(r.finiquito)}${r.indemnizacion != null ? ' + indemnización ${eur(r.indemnizacion!.importe)}' : ''}'),
        const Hueco(12),
        Panel(
          titulo: 'Finiquito',
          icono: Icons.receipt_long_outlined,
          child: Column(children: [
            for (final l in r.lineas) FilaResultado(l.concepto, eur(l.importe), detalle: l.detalle),
            if (r.lineas.isEmpty) const FilaResultado('No queda nada pendiente', '0,00 €'),
            const Hueco(4),
          ]),
        ),
        const Hueco(12),
        Panel(
          titulo: 'Indemnización',
          icono: Icons.gavel_rounded,
          child: Column(children: [
            if (r.indemnizacion == null)
              FilaResultado('${motivo.texto}: sin indemnización', '0,00 €')
            else
              FilaResultado('${_p(r.aniosTrabajados)} años trabajados', eur(r.indemnizacion!.importe),
                  detalle: r.indemnizacion!.detalle),
            const Hueco(4),
          ]),
        ),
        const Hueco(12),
        const _Aviso('Cálculo orientativo en bruto (antes de IRPF y Seguridad Social). La indemnización por '
            'despido está exenta de IRPF hasta el límite legal. Tu convenio puede mejorar estas cantidades.'),
        const Hueco(16),
        const PromoRevision('¿Te han dado ya el finiquito? Súbelo y comprobamos si está bien.'),
      ],
    ]);
  }
}

// ======================================================================= 3. horas y pagas extra

class CalculadoraExtras extends StatefulWidget {
  const CalculadoraExtras({super.key});

  @override
  State<CalculadoraExtras> createState() => _CalculadoraExtrasState();
}

class _CalculadoraExtrasState extends State<CalculadoraExtras> {
  int modo = 0; // 0 horas extra, 1 paga extra
  final bruto = TextEditingController();
  bool porMes = true;
  final jornada = TextEditingController(text: '40');
  final horas = TextEditingController();
  final precioConvenio = TextEditingController();
  int recargo = 0;
  final inicio = TextEditingController();
  bool diciembre = DateTime.now().month > 6;

  @override
  Widget build(BuildContext context) {
    void cambia() => setState(() {});
    return _PantallaCalculadora(titulo: 'Horas y pagas extra', children: [
      Opciones(valor: modo, opciones: const [(0, 'Horas extra'), (1, 'Paga extra')], onChanged: (v) => setState(() => modo = v)),
      const Hueco(16),
      CampoSueldo(controlador: bruto, porMes: porMes, onPorMes: (v) => setState(() => porMes = v), onChanged: cambia),
      const Hueco(12),
      if (modo == 0) ..._horasExtra(cambia) else ..._pagaExtra(cambia),
    ]);
  }

  List<Widget> _horasExtra(VoidCallback cambia) {
    final t = Theme.of(context);
    final b = sueldoAnual(bruto.text, porMes: porMes, pagas: 14);
    final j = leerNumero(jornada.text);
    final h = leerNumero(horas.text);
    final pc = leerNumero(precioConvenio.text);
    final r = (b != null && b > 0 && j != null && j > 0 && h != null && h > 0)
        ? calcularHorasExtra(brutoAnual: b, horasSemanales: j, horas: h, recargo: recargo.toDouble(), precioConvenio: pc)
        : null;
    return [
      Row(children: [
        Expanded(child: CampoNumero(jornada, 'Jornada semanal', sufijo: 'h', onChanged: cambia)),
        const SizedBox(width: 12),
        Expanded(child: CampoNumero(horas, 'Horas extra hechas', sufijo: 'h', onChanged: cambia)),
      ]),
      const Hueco(12),
      Text('¿Cuánto se pagan? (mira tu convenio)', style: t.textTheme.labelLarge),
      const Hueco(6),
      Opciones(
        valor: recargo,
        opciones: const [(0, 'Igual'), (25, '+25 %'), (50, '+50 %'), (75, '+75 %')],
        onChanged: (v) => setState(() => recargo = v),
      ),
      const Hueco(12),
      CampoNumero(precioConvenio, 'Precio fijo del convenio (opcional)', sufijo: '€/h', onChanged: cambia),
      const Hueco(20),
      if (r == null)
        const _Aviso('Rellena el sueldo, la jornada y las horas extra.')
      else ...[
        CifraPrincipal('Te deben pagar (bruto)', eur(r.total), sub: '${_p(r.horas)} h a ${eur(r.precioHoraExtra)}/h'),
        const Hueco(12),
        Panel(
          titulo: 'Detalle',
          icono: Icons.schedule_rounded,
          child: Column(children: [
            FilaResultado('Precio de tu hora ordinaria', '${eur(r.precioHoraOrdinaria)}/h',
                detalle: 'Sueldo anual entre ${Datos.diasLaborablesAnio} días laborables'),
            FilaResultado('Precio de la hora extra', '${eur(r.precioHoraExtra)}/h'),
            const Hueco(4),
          ]),
        ),
        const Hueco(12),
        _Aviso('Por ley, la hora extra se paga como mínimo igual que la ordinaria o se compensa con descanso. '
            'El máximo son ${Datos.maxHorasExtraAnio} horas extra al año.'
            '${r.superaMaximoAnual ? ' ⚠️ Superas ese máximo.' : ''}'),
        const Hueco(16),
        const PromoRevision('¿Aparecen tus horas extra en la nómina? Compruébalo gratis.'),
      ],
    ];
  }

  List<Widget> _pagaExtra(VoidCallback cambia) {
    final b = sueldoAnual(bruto.text, porMes: porMes, pagas: 14);
    final fi = leerFecha(inicio.text);
    final anio = DateTime.now().year;
    final r = (b != null && b > 0 && fi != null)
        ? calcularPagaExtra(brutoAnual: b, inicio: fi, diciembre: diciembre, anio: anio)
        : null;
    return [
      CampoFecha(inicio, 'Fecha en que empezaste a trabajar', onChanged: cambia),
      const Hueco(12),
      Opciones(
        valor: diciembre,
        opciones: [(false, 'Paga de junio $anio'), (true, 'Paga de diciembre $anio')],
        onChanged: (v) => setState(() => diciembre = v),
      ),
      const Hueco(20),
      if (r == null)
        const _Aviso('Rellena el sueldo y la fecha de inicio.')
      else ...[
        CifraPrincipal(diciembre ? 'Paga de diciembre' : 'Paga de junio', eur(r.importe),
            sub: r.completa ? 'Paga completa' : 'Proporcional: ${r.diasTrabajados} de ${r.diasPeriodo} días'),
        const Hueco(12),
        Panel(
          titulo: 'Detalle',
          icono: Icons.card_giftcard_outlined,
          child: Column(children: [
            FilaResultado('Paga extra completa', eur(r.pagaCompleta), detalle: 'Sueldo anual entre 14'),
            FilaResultado('Días trabajados del periodo', '${r.diasTrabajados} de ${r.diasPeriodo}',
                detalle: diciembre ? 'De julio a diciembre' : 'De enero a junio'),
            const Hueco(4),
          ]),
        ),
        const Hueco(12),
        const _Aviso('Supone 14 pagas con pagas extra de junio y diciembre. Algunos convenios usan otros periodos '
            '(por ejemplo, la paga de junio de julio a junio) o pagas de distinto importe.'),
        const Hueco(16),
        const PromoRevision('¿Te han pagado bien la paga extra? Revisa tu nómina gratis.'),
      ],
    ];
  }
}
