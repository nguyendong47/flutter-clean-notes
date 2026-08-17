import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'app_providers.g.dart';

const _kThemePrefKey = 'theme_mode';

/// Theme mode controller that respects a saved preference.
@riverpod
class AppTheme extends _$AppTheme {
  @override
  Future<ThemeMode> build() async {
    final preferences = await SharedPreferences.getInstance();
    final savedName = preferences.getString(_kThemePrefKey);
    if (savedName == null) return ThemeMode.system;
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == savedName,
      orElse: () => ThemeMode.system,
    );
  }

  /// Save the selected theme mode and update state.
  Future<void> setMode(ThemeMode mode) async {
    state = AsyncValue.data(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemePrefKey, mode.name);
  }
}
