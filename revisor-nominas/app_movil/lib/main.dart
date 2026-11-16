import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'compras.dart';
import 'pantallas/raiz.dart';
import 'tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.iniciar();
  Tienda.yo.iniciar();
  runApp(const RevisorNominas());
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
