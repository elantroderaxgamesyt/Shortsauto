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

class Cuenta {
  Cuenta(this.j);
  final Map<String, dynamic> j;
  int get creditos => j['creditos'] ?? 0;
  bool get suscripcion => j['suscripcion_activa'] == true;
  int get freeHoy => j['free_restantes_hoy'] ?? 0;
  int get mensualRestantes => j['mensual_restantes'] ?? 0;
  bool get puedePro => creditos > 0 || (suscripcion && mensualRestantes > 0);
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
}

class Api {
  Api._(this.usuario);
  final String usuario;
  static Api? _yo;
  static Api get yo => _yo!;

  static Future<void> iniciar() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('usuario');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
      await prefs.setString('usuario', id);
    }
    _yo = Api._(id);
  }

  Map<String, String> get _cab => {'X-Usuario': usuario};
  Uri _u(String ruta) => Uri.parse('$apiUrl$ruta');

  Future<Map<String, dynamic>> _json(Future<http.Response> peticion) async {
    final http.Response r;
    try {
      r = await peticion.timeout(const Duration(minutes: 5));
    } catch (_) {
      throw ErrorApi('No se ha podido conectar con el servidor. Revisa tu conexión.');
    }
    final cuerpo = utf8.decode(r.bodyBytes);
    Map<String, dynamic> j;
    try {
      j = jsonDecode(cuerpo);
    } catch (_) {
      throw ErrorApi('Respuesta inesperada del servidor (${r.statusCode}).', r.statusCode);
    }
    if (r.statusCode >= 400) {
      final d = j['detail'];
      throw ErrorApi(d is String ? d : 'Error ${r.statusCode}', r.statusCode);
    }
    return j;
  }

  Future<Cuenta> cuenta() async => Cuenta(await _json(http.get(_u('/api/cuenta'), headers: _cab)));

  Future<Revision> analizar(Uint8List datos, String nombre, String plan) async {
    final req = http.MultipartRequest('POST', _u('/api/analizar'))
      ..headers.addAll(_cab)
      ..fields['plan'] = plan
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

  Future<Cuenta> compraGoogle(String producto, String token) async => Cuenta(await _json(http.post(
      _u('/api/compras/google'),
      headers: {..._cab, 'Content-Type': 'application/json'},
      body: jsonEncode({'producto': producto, 'token': token}))));

  Future<Cuenta> canjear(String codigo) async => Cuenta(await _json(http.post(_u('/api/canjear'),
      headers: {..._cab, 'Content-Type': 'application/json'}, body: jsonEncode({'codigo': codigo}))));
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
