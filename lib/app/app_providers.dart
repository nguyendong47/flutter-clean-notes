import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

part 'app_providers.g.dart';

const _kThemePrefKey = 'theme_mode';

/// Theme mode controller that respects saved preference and follows system changes.
@riverpod
class AppTheme extends _$AppTheme {
  @override
  ThemeMode build() {
    // Initialize from saved preference or system
    final prefs = SharedPreferences.getInstance();
    return prefs.then((prefs) {
      final name = prefs.getString(_kThemePrefKey);
      if (name != null) {
        return ThemeMode.values.firstWhere(
          (mode) => mode.name == name,
          orElse: () => ThemeMode.system,
        );
      }
      return ThemeMode.system;
    }).then((value) {
      // Listen to system brightness changes
      ui.window.onPlatformBrightnessChanged = () {
        // If no saved preference, follow system
        ref.state = AsyncValue.data(ThemeMode.system);
      };
      return value;
    });
  }

  /// Save the selected theme mode and update state.
  Future<void> setMode(ThemeMode mode) async {
    state = AsyncValue.data(mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemePrefKey, mode.name);
    // Disable system following when user explicitly sets a mode
    ui.window.onPlatformBrightnessChanged = null;
  }
}