import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show rootBundle;

/// Servidor de mentira dentro de la app, para probarla sin servidor.
///
/// Se usa cuando la app se compila sin API_URL (ver config.dart). Devuelve un informe de
/// ejemplo (assets/demo), guarda el historial en memoria y responde el chat con textos fijos.
/// Todo lo que enseña va marcado como "Modo demo".
class ServidorDemo {
  final _revisiones = <String, Map<String, dynamic>>{};
  int _freeHoy = 3;
  final _rnd = Random();

  Future<Map<String, dynamic>> _plantilla(String plan) async =>
      jsonDecode(await rootBundle.loadString('assets/demo/revision_$plan.json')) as Map<String, dynamic>;

  Future<int> freeRestantesHoy() async => _freeHoy;

  Future<Map<String, dynamic>> analizar(String plan, String? compra) async {
    if (plan == 'free') {
      if (_freeHoy <= 0) throw StateError('Has usado las 3 revisiones gratis de hoy.');
      _freeHoy--;
    }
    await Future.delayed(Duration(seconds: plan == 'pro' ? 6 : 4)); // como si pensara la IA
    final r = await _plantilla(plan);
    final id = 'demo${_rnd.nextInt(1 << 30)}';
    r['id'] = id;
    r['fecha'] = DateTime.now().toUtc().toIso8601String();
    r['demo'] = true;
    r['preguntas_extra'] = 0;
    _revisiones[id] = r;
    return Map.of(r);
  }

  List<Map<String, dynamic>> revisiones() => [
        for (final r in _revisiones.values.toList().reversed)
          {
            'id': r['id'],
            'plan': r['plan'],
            'fecha': r['fecha'],
            'veredicto': r['informe']['veredicto'],
            'periodo': r['informe']['datos']['periodo'],
            'empresa': r['informe']['datos']['empresa'],
            'liquido': r['informe']['datos']['liquido'],
          }
      ];

  Map<String, dynamic>? revision(String id) => _revisiones[id] == null ? null : Map.of(_revisiones[id]!);

  int recompensa(String id) {
    final r = _revisiones[id];
    if (r == null) return 0;
    if ((r['preguntas_extra'] as int) >= 5) throw StateError('Has llegado al máximo de preguntas para esta revisión.');
    r['preguntas_extra'] = (r['preguntas_extra'] as int) + 1;
    r['preguntas_disponibles'] = (r['preguntas_disponibles'] as int) + 1;
    r['preguntas_por_anuncio'] = (r['preguntas_extra'] as int) < 5;
    return r['preguntas_disponibles'];
  }

  Stream<String> chat(String id, String pregunta) async* {
    final r = _revisiones[id];
    if (r == null || (r['preguntas_disponibles'] as int) <= 0) {
      throw StateError('Mira un anuncio corto para hacer otra pregunta a Nora.');
    }
    r['preguntas_disponibles'] = (r['preguntas_disponibles'] as int) - 1;
    final texto = '(Modo demo) Esta es una respuesta de ejemplo: con el servidor conectado, Nora '
        'contestaría a "$pregunta" usando los datos de tu nómina, por ejemplo explicándote cada '
        'concepto, revisando los importes o diciéndote qué pedir a tu empresa.';
    for (final palabra in texto.split(' ')) {
      await Future.delayed(const Duration(milliseconds: 35));
      yield '$palabra ';
    }
  }
}
