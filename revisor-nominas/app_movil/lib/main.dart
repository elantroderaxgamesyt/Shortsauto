import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'compras.dart';
import 'pantallas/raiz.dart';
import 'tema.dart';

Future<void> main() async {
  // Ningún fallo al arrancar debe dejar la app colgada en la pantalla de carga:
  // se registra y la app sigue.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    FlutterError.onError = (d) {
      FlutterError.presentError(d);
      debugPrint('Error de Flutter: ${d.exceptionAsString()}');
    };
    await Api.iniciar();
    runApp(const RevisorNominas());
    unawaited(Tienda.yo.iniciar().catchError((Object e) => debugPrint('Tienda: $e')));
  }, (e, pila) => debugPrint('Error sin capturar: $e\n$pila'));
}

class RevisorNominas extends StatelessWidget {
  const RevisorNominas({super.key});

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(statusBarColor: Colors.transparent),
        child: MaterialApp(
          title: 'Revisor de nóminas',
          debugShowCheckedModeBanner: false,
          theme: construirTema(Brightness.light),
          darkTheme: construirTema(Brightness.dark),
          home: const PantallaRaiz(),
        ),
      );
}
