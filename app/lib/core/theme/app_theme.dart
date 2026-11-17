import 'package:material_ui/material_ui.dart';

/// Material 3 light and dark themes from one seed colour.
class AppTheme {
  static const Color seed = Color(0xFF00796B); // Teal

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    );
  }
}

/// Status colours that stay readable in both themes.
extension StatusColors on ColorScheme {
  Color get ok => brightness == Brightness.light ? const Color(0xFF1B7F3B) : const Color(0xFF7DDB95);
  Color get warn => brightness == Brightness.light ? const Color(0xFF8A5A00) : const Color(0xFFFFC66B);
}
