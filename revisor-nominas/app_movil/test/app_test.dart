import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:revisor_nominas/widgets.dart';

void main() {
  test('formato de euros en español', () {
    expect(eur(1997.23), '1.997,23 €');
    expect(eur(2450), '2.450,00 €');
    expect(eur(-0.49), '-0,49 €');
    expect(eur(null), '—');
    expect(pct(0.15), '0,15 %');
  });

  testWidgets('punto del informe muestra estado y qué hacer', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: PuntoInforme({'concepto': 'MEI', 'estado': 'error', 'explicacion': 'Tipo antiguo', 'que_hacer': 'Avisa a RRHH'}),
      ),
    ));
    expect(find.text('ERROR'), findsOneWidget);
    expect(find.text('MEI'), findsOneWidget);
    expect(find.text('👉 Avisa a RRHH'), findsOneWidget);
  });
}
