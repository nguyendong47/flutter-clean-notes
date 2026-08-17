import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';

void main() {
  test('Aurora themes provide equal Material 3 light and dark systems', () {
    final light = AuroraTheme.light();
    final dark = AuroraTheme.dark();

    expect(light.useMaterial3, isTrue);
    expect(dark.useMaterial3, isTrue);
    expect(light.brightness, Brightness.light);
    expect(dark.brightness, Brightness.dark);
    expect(light.colorScheme.primary, AuroraTheme.indigo);
    expect(dark.colorScheme.primary, AuroraTheme.darkIndigo);
    expect(light.navigationBarTheme.height, 72);
    expect(dark.navigationBarTheme.height, 72);
  });
}
