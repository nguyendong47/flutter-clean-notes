import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

abstract final class AuroraTheme {
  static const indigo = Color(0xFF6757D9);
  static const darkIndigo = Color(0xFFA99BFF);
  static const mint = Color(0xFF2DB9A8);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: dark ? darkIndigo : indigo,
      primary: dark ? darkIndigo : indigo,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark
          ? const Color(0xFF0B1020)
          : const Color(0xFFF4F6FF),
      textTheme: Typography.material2021(platform: defaultTargetPlatform).black
          .apply(
            bodyColor: dark ? const Color(0xFFF4F6FF) : const Color(0xFF17203B),
            displayColor: dark
                ? const Color(0xFFF4F6FF)
                : const Color(0xFF17203B),
          ),
      navigationBarTheme: const NavigationBarThemeData(height: 72),
    );
  }
}
