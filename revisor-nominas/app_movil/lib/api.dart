import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

class ErrorApi implements Exception {
  ErrorApi(this.mensaje, [this.codigo = 0]);
  final String mensaje;
  final int codigo;
  bool get sinSaldo => codigo == 402;
  @override
  String toString() => mensaje;
}

/// Resultado de /api/analizar.
class Revision {
  Revision(this.j);
  final Map<String, dynamic> j;
  String get id => j['id'];
  bool get pro => j['plan'] == 'pro';
  bool get demo => j['demo'] == true;
  Map<String, dynamic> get informe => j['informe'];
  Map<String, dynamic> get datos => informe['datos'];
  List get calculos => j['calculos'];
  int get preguntasChat => j['preguntas_chat'] ?? 0;
  int get preguntasUsadas => j['preguntas_usadas'] ?? 0;
  String? get fecha => j['fecha'];
}

/// Fila del historial.
class ResumenRevision {
  ResumenRevision(this.j);
  final Map<String, dynamic> j;
  String get id => j['id'];
  bool get pro => j['plan'] == 'pro';
  String get veredicto => j['veredicto'];
  String? get periodo => j['periodo'];
  String? get empresa => j['empresa'];
  num? get liquido => j['liquido'];
  String? get fecha => j['fecha'];
}

class Api {
  Api._(this.usuario);
  final String usuario;
  static Api? _yo;
  static Api get yo => _yo!;

  static Future<void> iniciar() async {
    final r = Random.secure();
    String nuevo() => List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    try {
      final prefs = await SharedPreferences.getInstance();
      var id = prefs.getString('usuario');
      if (id == null) {
        id = nuevo();
        await prefs.setString('usuario', id);
      }
      _yo = Api._(id);
    } catch (_) {
      // Si el almacenamiento falla, la app funciona igual con un id de esta sesión.
      _yo = Api._(nuevo());
    }
  }

  Map<String, String> get _cab => {'X-Dispositivo': usuario};
  Uri _u(String ruta) => Uri.parse('$apiUrl$ruta');

  Future<http.Response> _peticion(Future<http.Response> peticion) async {
    final http.Response r;
    try {
      r = await peticion.timeout(const Duration(minutes: 5));
    } catch (_) {
      throw ErrorApi('No se ha podido conectar con el servidor. Revisa tu conexión a internet.');
    }
    if (r.statusCode >= 400) {
      String msg = 'Algo ha ido mal (error ${r.statusCode}). Inténtalo de nuevo.';
      try {
        final d = jsonDecode(utf8.decode(r.bodyBytes))['detail'];
        if (d is String) msg = d;
      } catch (_) {}
      throw ErrorApi(msg, r.statusCode);
    }
    return r;
  }

  Future<Map<String, dynamic>> _json(Future<http.Response> peticion) async {
    final r = await _peticion(peticion);
    try {
      return jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      throw ErrorApi('Respuesta inesperada del servidor.', r.statusCode);
    }
  }

  Future<List<ResumenRevision>> revisiones() async {
    final r = await _peticion(http.get(_u('/api/revisiones'), headers: _cab));
    return [for (final x in jsonDecode(utf8.decode(r.bodyBytes)) as List) ResumenRevision(x)];
  }

  Future<Revision> revision(String id) async => Revision(await _json(http.get(_u('/api/revisiones/$id'), headers: _cab)));

  /// Revisiones gratis que quedan hoy en este dispositivo.
  Future<int> freeRestantesHoy() async =>
      (await _json(http.get(_u('/api/limites'), headers: _cab)))['free_restantes_hoy'] ?? 0;

  /// [compra]: token de Google Play con el que se ha pagado la revisión completa.
  Future<Revision> analizar(Uint8List datos, String nombre, String plan, {String? compra}) async {
    final req = http.MultipartRequest('POST', _u('/api/analizar'))
      ..headers.addAll(_cab)
      ..fields['plan'] = plan
      ..fields['compra'] = compra ?? ''
      ..files.add(http.MultipartFile.fromBytes('archivo', datos, filename: nombre, contentType: _tipo(nombre)));
    return Revision(await _json(req.send().then(http.Response.fromStream)));
  }

  /// Devuelve la respuesta de Nora a trozos, según llega.
  Stream<String> chat(String revision, List<Map<String, String>> historial) async* {
    final req = http.Request('POST', _u('/api/chat'))
      ..headers.addAll({..._cab, 'Content-Type': 'application/json'})
      ..body = jsonEncode({'revision': revision, 'historial': historial});
    final http.StreamedResponse r;
    try {
      r = await http.Client().send(req);
    } catch (_) {
      throw ErrorApi('No se ha podido conectar con el servidor.');
    }
    if (r.statusCode >= 400) {
      final cuerpo = await r.stream.bytesToString();
      String msg = 'Error ${r.statusCode}';
      try {
        msg = jsonDecode(cuerpo)['detail'];
      } catch (_) {}
      throw ErrorApi(msg, r.statusCode);
    }
    yield* r.stream.transform(utf8.decoder);
  }
}

MediaType _tipo(String nombre) {
  final n = nombre.toLowerCase();
  final t = n.endsWith('.pdf')
      ? 'application/pdf'
      : n.endsWith('.png')
          ? 'image/png'
          : n.endsWith('.webp')
              ? 'image/webp'
              : 'image/jpeg';
  return MediaType.parse(t);
}
