import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_clean_notes/app/app_providers.dart';
import 'package:flutter_clean_notes/main.dart' as app;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _notificationsChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);
const _preferencesChannel = MethodChannel(
  'plugins.flutter.io/shared_preferences',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.resetStatic();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_notificationsChannel, (call) async {
          return switch (call.method) {
            'initialize' => true,
            'getNotificationAppLaunchDetails' => null,
            _ => null,
          };
        });
  });

  tearDown(() {
    SharedPreferences.resetStatic();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_notificationsChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_preferencesChannel, null);
  });

  testWidgets('cold start emits no app frame before saved theme resolves', (
    tester,
  ) async {
    // Mutation caught: removing the startup await would render a system-theme
    // MaterialApp while the saved dark preference is still loading.
    final readGate = Completer<Map<String, Object>>();
    var readCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_preferencesChannel, (_) {
          readCalls += 1;
          return readGate.future;
        });

    app.main();
    await tester.pump();
    await tester.pump();

    expect(find.byType(MaterialApp), findsNothing);

    readGate.complete(<String, Object>{'flutter.theme_mode': 'dark'});
    await tester.pump();
    await tester.pump();

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.themeMode, ThemeMode.dark);
    expect(readCalls, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 1));
  });

  test(
    'theme read failure resolves to system without provider error',
    () async {
      // Mutation caught: allowing read failures to escape leaves startup stuck
      // or exposes AsyncError instead of the documented safe system fallback.
      final container = ProviderContainer(
        overrides: [
          themeModeStoreProvider.overrideWithValue(_FailingThemeModeStore()),
        ],
      );
      addTearDown(container.dispose);

      expect(await container.read(appThemeProvider.future), ThemeMode.system);
      expect(container.read(appThemeProvider).hasError, isFalse);
    },
  );

  test(
    'preloaded theme survives startup handoff without a second read',
    () async {
      // Mutation caught: making the global theme controller auto-dispose allows
      // the preload to vanish before MyApp attaches its first-frame listener.
      final store = _CountingThemeModeStore(ThemeMode.dark);
      final container = ProviderContainer(
        overrides: [themeModeStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);

      expect(await container.read(appThemeProvider.future), ThemeMode.dark);
      await container.pump();
      expect(await container.read(appThemeProvider.future), ThemeMode.dark);

      expect(store.readCalls, 1);
    },
  );
}

class _FailingThemeModeStore implements ThemeModeStore {
  @override
  Future<ThemeMode> readMode() =>
      Future<ThemeMode>.error(StateError('preferences unavailable'));

  @override
  Future<void> writeMode(ThemeMode mode) async {}
}

class _CountingThemeModeStore implements ThemeModeStore {
  _CountingThemeModeStore(this.mode);

  final ThemeMode mode;
  int readCalls = 0;

  @override
  Future<ThemeMode> readMode() async {
    readCalls += 1;
    return mode;
  }

  @override
  Future<void> writeMode(ThemeMode mode) async {}
}
