import 'package:material_ui/material_ui.dart';

import '../anuncios.dart';
import '../estado.dart';
import '../tema.dart';
import 'historial.dart';
import 'inicio.dart';

/// Navegación principal: barra inferior en móvil y barra lateral en Windows / tablet.
class PantallaRaiz extends StatefulWidget {
  const PantallaRaiz({super.key});

  @override
  State<PantallaRaiz> createState() => _PantallaRaizState();
}

class _PantallaRaizState extends State<PantallaRaiz> {
  @override
  void initState() {
    super.initState();
    // Consentimiento y anuncios cuando la primera pantalla ya está dibujada.
    WidgetsBinding.instance.addPostFrameCallback((_) => Anuncios.yo.iniciar());
  }

  static const _destinos = [
    (Icons.home_outlined, Icons.home_rounded, 'Inicio'),
    (Icons.history_rounded, Icons.history_rounded, 'Mis revisiones'),
  ];

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: pestana,
        builder: (context, i, _) {
          final ancho = MediaQuery.sizeOf(context).width >= 840;
          final cuerpo = IndexedStack(index: i, children: const [PantallaInicio(), PantallaHistorial()]);
          if (!ancho) {
            return Scaffold(
              body: cuerpo,
              bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
                // Banner abajo en Inicio y Mis revisiones (nunca en el informe, que es otra pantalla).
                const BannerAnuncio(),
                NavigationBar(
                  selectedIndex: i,
                  onDestinationSelected: (n) => pestana.value = n,
                  destinations: [
                    for (final (ic, sel, txt) in _destinos)
                      NavigationDestination(icon: Icon(ic), selectedIcon: Icon(sel), label: txt),
                  ],
                ),
              ]),
            );
          }
          return Scaffold(
            body: Row(children: [
              NavigationRail(
                selectedIndex: i,
                onDestinationSelected: (n) => pestana.value = n,
                labelType: NavigationRailLabelType.all,
                leading: const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: _Logo()),
                destinations: [
                  for (final (ic, sel, txt) in _destinos)
                    NavigationRailDestination(icon: Icon(ic), selectedIcon: Icon(sel), label: Text(txt)),
                ],
              ),
              VerticalDivider(width: 1, color: Tonos.de(context).borde),
              Expanded(child: cuerpo),
            ]),
          );
        },
      );
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.asset('assets/icono/icono.png', width: 44, height: 44),
      );
}
