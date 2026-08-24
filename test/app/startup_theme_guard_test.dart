import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/services.dart';
import 'package:flutter_clean_notes/app/app_providers.dart';
import 'package:flutter_clean_notes/app/notification_service.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_home_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_reminder_gateway_provider.dart';
import 'package:flutter_clean_notes/features/notes/domain/repositories/reminder_outbox_repository.dart';
import 'package:flutter_clean_notes/features/notes/domain/services/reminder_coordinator.dart';
import 'package:flutter_clean_notes/main.dart' as app;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/in_memory_note_repository.dart';
import '../helpers/note_fixtures.dart';

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

  testWidgets(
    'bootstrap attaches durable snooze before notification cold-launch handling',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final events = <String>[];
      final plugin = _ColdSnoozePlugin(events);
      final notifications = NotificationService(plugin: plugin);
      final coordinator = _FakeReminderSyncCoordinator(events);
      final repository = InMemoryNoteRepository.seeded(sampleNotes)
        ..getErrorAtCall = 1;
      ProviderContainer? container;
      try {
        await app.bootstrapApplication(
          notificationService: notifications,
          initializeDatabase: () {},
          createContainer: (service) {
            events.add('container');
            container = ProviderContainer(
              overrides: [
                notificationServiceProvider.overrideWithValue(service),
                noteRepositoryProvider.overrideWithValue(repository),
                reminderCoordinatorProvider.overrideWithValue(coordinator),
                themeModeStoreProvider.overrideWithValue(
                  _CountingThemeModeStore(ThemeMode.system),
                ),
              ],
            );
            return container!;
          },
          runApplication: (_) {
            events.add('run');
            runApp(const SizedBox.shrink());
          },
        );

        expect(events.take(4), ['container', 'init', 'snooze:7:17:15', 'run']);
        tester.binding.scheduleFrame();
        await tester.pump();
        await tester.pump();
        expect(events, contains('reconcile'));
        expect(container!.read(notesProvider).hasError, isFalse);
      } finally {
        container?.dispose();
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets(
    'startup reconciliation diagnostic omits private error and stack details',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final events = <String>[];
      final notifications = NotificationService(
        plugin: _ColdSnoozePlugin(events),
      );
      final coordinator = _FakeReminderSyncCoordinator(
        events,
        reconcileError: StateError('private-reconcile-error-marker'),
        reconcileStackTrace: StackTrace.fromString(
          'private-reconcile-stack-marker',
        ),
      );
      ProviderContainer? container;
      final diagnostics = <FlutterErrorDetails>[];
      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = diagnostics.add;
      try {
        await app.bootstrapApplication(
          notificationService: notifications,
          initializeDatabase: () {},
          createContainer: (service) {
            container = ProviderContainer(
              overrides: [
                notificationServiceProvider.overrideWithValue(service),
                noteRepositoryProvider.overrideWithValue(
                  InMemoryNoteRepository.seeded(sampleNotes),
                ),
                reminderCoordinatorProvider.overrideWithValue(coordinator),
                themeModeStoreProvider.overrideWithValue(
                  _CountingThemeModeStore(ThemeMode.system),
                ),
              ],
            );
            return container!;
          },
          runApplication: (_) => runApp(const SizedBox.shrink()),
        );
        tester.binding.scheduleFrame();
        await tester.pump();
        await tester.pump();
      } finally {
        FlutterError.onError = previousErrorHandler;
        debugDefaultTargetPlatformOverride = null;
        container?.dispose();
      }

      expect(diagnostics, hasLength(1));
      final details = diagnostics.single;
      expect(details.library, 'reminder reconciliation');
      expect(details.toString(), contains('StateError'));
      expect(
        details.toString(),
        isNot(contains('private-reconcile-error-marker')),
      );
      expect(
        details.stack.toString(),
        isNot(contains('private-reconcile-stack-marker')),
      );
    },
  );

  testWidgets(
    'notification initialization failure is sanitized and notes UI still renders',
    (tester) async {
      const privateFailure =
          'notification daemon failed with token=private-notification-token';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_notificationsChannel, (call) async {
            if (call.method == 'initialize') {
              throw PlatformException(
                code: 'notifications-unavailable',
                message: privateFailure,
                details: <String, Object>{'credential': 'private-credential'},
              );
            }
            return null;
          });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            _preferencesChannel,
            (_) async => <String, Object>{},
          );

      ProviderContainer? container;
      final notificationService = NotificationService(
        plugin: FlutterLocalNotificationsPlugin(),
      );
      final diagnostics = <FlutterErrorDetails>[];
      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = diagnostics.add;
      try {
        await app.bootstrapApplication(
          notificationService: notificationService,
          initializeDatabase: () {},
          createContainer: (service) {
            container = ProviderContainer(
              overrides: [
                notificationServiceProvider.overrideWithValue(service),
                noteRepositoryProvider.overrideWithValue(
                  InMemoryNoteRepository.seeded(sampleNotes),
                ),
                reminderCoordinatorProvider.overrideWithValue(
                  _FakeReminderSyncCoordinator(<String>[]),
                ),
              ],
            );
            return container!;
          },
        );
        await tester.pumpAndSettle();
      } finally {
        FlutterError.onError = previousErrorHandler;
      }

      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.byType(NotesHomePage), findsOneWidget);
      expect(find.byKey(const Key('notes-home-header')), findsOneWidget);
      expect(diagnostics, hasLength(2));
      for (final diagnostic in diagnostics) {
        expect(diagnostic.library, 'notification service');
        final renderedDiagnostic = diagnostic.toString();
        expect(renderedDiagnostic, contains('Notifications are unavailable'));
        expect(renderedDiagnostic, isNot(contains(privateFailure)));
        expect(renderedDiagnostic, isNot(contains('private-credential')));
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 1));
      container?.dispose();
    },
  );

  testWidgets(
    'provider bootstrap failure happens before optional notification init',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_notificationsChannel, (call) async {
            if (call.method == 'initialize') {
              throw PlatformException(code: 'notifications-unavailable');
            }
            return null;
          });
      final notificationService = NotificationService(
        plugin: FlutterLocalNotificationsPlugin(),
      );
      final diagnostics = <FlutterErrorDetails>[];
      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = diagnostics.add;
      try {
        await expectLater(
          app.bootstrapApplication(
            notificationService: notificationService,
            initializeDatabase: () {},
            createContainer: (_) =>
                throw StateError('provider bootstrap failed'),
            runApplication: (_) => fail('runApp must not be reached'),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'provider bootstrap failed',
            ),
          ),
        );
      } finally {
        FlutterError.onError = previousErrorHandler;
      }

      expect(
        diagnostics.where(
          (details) => details.library == 'notification service',
        ),
        isEmpty,
      );
    },
  );

  test('database initialization failure remains observable', () async {
    var notificationInitializeCalls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_notificationsChannel, (call) async {
          if (call.method == 'initialize') notificationInitializeCalls += 1;
          return true;
        });
    final notificationService = NotificationService(
      plugin: FlutterLocalNotificationsPlugin(),
    );

    await expectLater(
      app.bootstrapApplication(
        notificationService: notificationService,
        initializeDatabase: () =>
            throw StateError('database initialization failed'),
        runApplication: (_) => fail('runApp must not be reached'),
      ),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'database initialization failed',
        ),
      ),
    );

    expect(notificationInitializeCalls, 0);
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

final class _FakeReminderSyncCoordinator implements ReminderSyncCoordinator {
  _FakeReminderSyncCoordinator(
    this.events, {
    this.reconcileError,
    this.reconcileStackTrace,
  });

  final List<String> events;
  final Object? reconcileError;
  final StackTrace? reconcileStackTrace;

  @override
  Future<void> drain({
    int? noteId,
    ReminderPermissionPolicy permissionPolicy =
        ReminderPermissionPolicy.requestIfNeeded,
  }) async {}

  @override
  Future<void> reconcileAtStartup() async {
    events.add('reconcile');
    final error = reconcileError;
    if (error != null) {
      Error.throwWithStackTrace(
        error,
        reconcileStackTrace ?? StackTrace.current,
      );
    }
  }

  @override
  Future<bool> snooze({
    required int noteId,
    required int? expectedGeneration,
    required int delayMinutes,
  }) async {
    events.add('snooze:$noteId:$expectedGeneration:$delayMinutes');
    return true;
  }
}

final class _ColdSnoozePlugin extends Fake
    implements FlutterLocalNotificationsPlugin {
  _ColdSnoozePlugin(this.events);

  final List<String> events;

  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    events.add('init');
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async {
    return const NotificationAppLaunchDetails(
      true,
      notificationResponse: NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        id: 7,
        actionId: 'snooze_15',
        payload: 'note:v2:7:17',
      ),
    );
  }
}
