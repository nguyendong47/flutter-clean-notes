import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_clean_notes/app/app_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to system and persists an explicit mode', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(await container.read(appThemeProvider.future), ThemeMode.system);

    await container.read(appThemeProvider.notifier).setMode(ThemeMode.dark);

    expect(container.read(appThemeProvider).value, ThemeMode.dark);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('theme_mode'), 'dark');
  });

  test('restores a persisted theme mode', () async {
    SharedPreferences.setMockInitialValues({'theme_mode': 'light'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(await container.read(appThemeProvider.future), ThemeMode.light);
  });

  test('keeps prior mode when persistence fails', () async {
    final store = _FakeThemeModeStore()..writeError = StateError('disk full');
    final container = ProviderContainer(
      overrides: [themeModeStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    expect(await container.read(appThemeProvider.future), ThemeMode.system);

    await expectLater(
      container.read(appThemeProvider.notifier).setMode(ThemeMode.dark),
      throwsStateError,
    );

    expect(store.writeCalls, 1);
    expect(store.mode, ThemeMode.system);
    expect(container.read(appThemeProvider).value, ThemeMode.system);
    expect(container.read(appThemeProvider).hasError, isFalse);
  });
}

class _FakeThemeModeStore implements ThemeModeStore {
  ThemeMode mode = ThemeMode.system;
  Object? writeError;
  int writeCalls = 0;

  @override
  Future<ThemeMode> readMode() async => mode;

  @override
  Future<void> writeMode(ThemeMode mode) async {
    writeCalls += 1;
    if (writeError case final error?) throw error;
    this.mode = mode;
  }
}
