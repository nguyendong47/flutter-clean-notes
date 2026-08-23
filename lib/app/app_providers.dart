import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_clean_notes/app/notification_service.dart';

part 'app_providers.g.dart';

const _kThemePrefKey = 'theme_mode';

@riverpod
NotificationService notificationService(Ref ref) => NotificationService();

abstract interface class ThemeModeStore {
  Future<ThemeMode> readMode();

  Future<void> writeMode(ThemeMode mode);
}

class SharedPreferencesThemeModeStore implements ThemeModeStore {
  const SharedPreferencesThemeModeStore();

  @override
  Future<ThemeMode> readMode() async {
    final preferences = await SharedPreferences.getInstance();
    final savedName = preferences.getString(_kThemePrefKey);
    if (savedName == null) return ThemeMode.system;
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == savedName,
      orElse: () => ThemeMode.system,
    );
  }

  @override
  Future<void> writeMode(ThemeMode mode) async {
    final preferences = await SharedPreferences.getInstance();
    final saved = await preferences.setString(_kThemePrefKey, mode.name);
    if (!saved) throw StateError('Could not save theme preference.');
  }
}

@riverpod
ThemeModeStore themeModeStore(Ref ref) {
  return const SharedPreferencesThemeModeStore();
}

/// Theme mode controller that respects a saved preference.
@riverpod
class AppTheme extends _$AppTheme {
  @override
  Future<ThemeMode> build() {
    return ref.watch(themeModeStoreProvider).readMode();
  }

  /// Save the selected theme mode and update state.
  Future<void> setMode(ThemeMode mode) async {
    await ref.read(themeModeStoreProvider).writeMode(mode);
    state = AsyncValue.data(mode);
  }
}
