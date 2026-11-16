import 'package:material_ui/material_ui.dart';

/// Pestaña visible de la pantalla principal (0 inicio, 1 revisiones, 2 cuenta).
final pestana = ValueNotifier<int>(0);

/// Se incrementa cada vez que hay una revisión nueva, para refrescar el historial.
final historialCambiado = ValueNotifier<int>(0);
