import 'package:material_ui/material_ui.dart';

import 'api.dart';
import 'compras.dart';
import 'pantallas/inicio.dart';

const azul = Color(0xFF2457D6);
const morado = Color(0xFF6B3FD4);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Api.iniciar();
  Tienda.yo.iniciar();
  runApp(const RevisorNominas());
}

ThemeData tema(Brightness brillo) => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: azul, brightness: brillo),
      useMaterial3: true,
      cardTheme: const CardThemeData(margin: EdgeInsets.zero),
    );

class RevisorNominas extends StatelessWidget {
  const RevisorNominas({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Revisor de nóminas',
        debugShowCheckedModeBanner: false,
        theme: tema(Brightness.light),
        darkTheme: tema(Brightness.dark),
        home: const PantallaInicio(),
      );
}
