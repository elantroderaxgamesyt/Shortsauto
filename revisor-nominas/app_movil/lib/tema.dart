import 'package:material_ui/material_ui.dart';

/// Paleta y estilos de la app. Todo el aspecto visual sale de aquí.
abstract final class Marca {
  static const azul = Color(0xFF1E40AF); // primario
  static const azulVivo = Color(0xFF2563EB);
  static const marino = Color(0xFF0F1E46);
  static const pro = Color(0xFF6D28D9);
  static const proClaro = Color(0xFF8B5CF6);
  static const ok = Color(0xFF15803D);
  static const aviso = Color(0xFFB45309);
  static const error = Color(0xFFB91C1C);

  static const degradado = LinearGradient(
    colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const degradadoPro = LinearGradient(
    colors: [Color(0xFF5B21B6), Color(0xFF7C3AED)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const radio = 16.0;
}

/// Colores extra que dependen del tema (claro/oscuro).
class Tonos extends ThemeExtension<Tonos> {
  const Tonos({required this.fondo, required this.tarjeta, required this.borde, required this.suave, required this.tenue});

  final Color fondo; // fondo de pantalla
  final Color tarjeta; // fondo de tarjetas
  final Color borde; // bordes finos
  final Color suave; // texto secundario
  final Color tenue; // rellenos de chips, cifras…

  static const claro = Tonos(
    fondo: Color(0xFFF5F7FB),
    tarjeta: Colors.white,
    borde: Color(0xFFE3E8EF),
    suave: Color(0xFF5B6475),
    tenue: Color(0xFFF0F3F8),
  );
  static const oscuro = Tonos(
    fondo: Color(0xFF0B1220),
    tarjeta: Color(0xFF121B2E),
    borde: Color(0xFF243049),
    suave: Color(0xFF9AA6BC),
    tenue: Color(0xFF1A2540),
  );

  static Tonos de(BuildContext c) => Theme.of(c).extension<Tonos>()!;

  @override
  Tonos copyWith() => this;

  @override
  Tonos lerp(ThemeExtension<Tonos>? other, double t) => t < .5 ? this : (other as Tonos? ?? this);
}

ThemeData construirTema(Brightness brillo) {
  final oscuro = brillo == Brightness.dark;
  final tonos = oscuro ? Tonos.oscuro : Tonos.claro;
  final esquema = ColorScheme.fromSeed(
    seedColor: Marca.azul,
    brightness: brillo,
    primary: oscuro ? const Color(0xFF8AA9FF) : Marca.azul,
    surface: tonos.tarjeta,
  );
  final base = ThemeData(colorScheme: esquema, useMaterial3: true, fontFamily: 'Inter', brightness: brillo);
  final texto = base.textTheme.apply(
    bodyColor: oscuro ? const Color(0xFFE6EAF2) : const Color(0xFF111827),
    displayColor: oscuro ? Colors.white : const Color(0xFF0B1324),
  );

  return base.copyWith(
    scaffoldBackgroundColor: tonos.fondo,
    extensions: [tonos],
    textTheme: texto.copyWith(
      headlineSmall: texto.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.4),
      titleLarge: texto.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -.3),
      titleMedium: texto.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      titleSmall: texto.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: texto.bodyMedium?.copyWith(height: 1.45),
      bodyLarge: texto.bodyLarge?.copyWith(height: 1.5),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: tonos.fondo,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: texto.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 20),
    ),
    cardTheme: CardThemeData(
      color: tonos.tarjeta,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Marca.radio),
        side: BorderSide(color: tonos.borde),
      ),
    ),
    dividerTheme: DividerThemeData(color: tonos.borde, space: 1, thickness: 1),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        side: BorderSide(color: tonos.borde),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tonos.tenue,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: tonos.tarjeta,
      surfaceTintColor: Colors.transparent,
      indicatorColor: esquema.primary.withValues(alpha: .12),
      labelTextStyle: WidgetStatePropertyAll(texto.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
      height: 68,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: tonos.tarjeta,
      indicatorColor: esquema.primary.withValues(alpha: .12),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: tonos.tarjeta,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: tonos.tenue,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      labelStyle: texto.labelLarge,
    ),
  );
}
