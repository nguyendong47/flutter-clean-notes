import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_clean_notes/app/notification_service.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/reminder_command.dart';
import 'package:flutter_clean_notes/features/notes/domain/repositories/reminder_outbox_repository.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// The concrete plugin API exposes this bound but does not re-export it.
// ignore: depend_on_referenced_packages
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class _ScheduleCall {
  const _ScheduleCall(this.id, this.payload);

  final int id;
  final String? payload;
}

class _PermissionAwarePlugin extends Fake
    implements FlutterLocalNotificationsPlugin {
  final Map<Type, Object> platformImplementations = <Type, Object>{};
  final List<_ScheduleCall> scheduleCalls = <_ScheduleCall>[];

  Completer<void>? initializeGate;
  Completer<void>? scheduleGate;
  Object? scheduleError;
  StackTrace? scheduleStackTrace;
  NotificationAppLaunchDetails launchDetails =
      const NotificationAppLaunchDetails(false);
  DidReceiveNotificationResponseCallback? responseCallback;
  int initializeFailuresRemaining = 0;
  int initializeCalls = 0;
  int launchDetailsCalls = 0;

  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializeCalls += 1;
    responseCallback = onDidReceiveNotificationResponse;
    await initializeGate?.future;
    if (initializeFailuresRemaining > 0) {
      initializeFailuresRemaining -= 1;
      throw StateError('initialize failed');
    }
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async {
    launchDetailsCalls += 1;
    return launchDetails;
  }

  @override
  T? resolvePlatformSpecificImplementation<
    T extends FlutterLocalNotificationsPlatform
  >() {
    return platformImplementations[T] as T?;
  }

  @override
  Future<void> zonedSchedule(
    int id,
    String? title,
    String? body,
    tz.TZDateTime scheduledDate,
    NotificationDetails notificationDetails, {
    required UILocalNotificationDateInterpretation
    uiLocalNotificationDateInterpretation,
    bool androidAllowWhileIdle = false,
    AndroidScheduleMode? androidScheduleMode,
    String? payload,
    DateTimeComponents? matchDateTimeComponents,
  }) async {
    scheduleCalls.add(_ScheduleCall(id, payload));
    await scheduleGate?.future;
    final error = scheduleError;
    if (error != null) {
      final stackTrace = scheduleStackTrace;
      if (stackTrace != null) Error.throwWithStackTrace(error, stackTrace);
      throw error;
    }
  }
}

class _AndroidPermissionPlugin extends Fake
    implements AndroidFlutterLocalNotificationsPlugin {
  _AndroidPermissionPlugin(this.result, {this.enabled});

  final bool? result;
  final bool? enabled;
  int requestCalls = 0;
  int checkCalls = 0;

  @override
  Future<bool?> requestNotificationsPermission() async {
    requestCalls += 1;
    return result;
  }

  @override
  Future<bool?> areNotificationsEnabled() async {
    checkCalls += 1;
    return enabled;
  }
}

class _DarwinPermissionCall {
  const _DarwinPermissionCall({
    required this.alert,
    required this.badge,
    required this.sound,
    required this.provisional,
    required this.critical,
  });

  final bool alert;
  final bool badge;
  final bool sound;
  final bool provisional;
  final bool critical;
}

class _IOSPermissionPlugin extends Fake
    implements IOSFlutterLocalNotificationsPlugin {
  _IOSPermissionPlugin(this.result, {this.enabledOptions});

  final bool? result;
  final NotificationsEnabledOptions? enabledOptions;
  final List<_DarwinPermissionCall> calls = <_DarwinPermissionCall>[];
  int checkCalls = 0;

  @override
  Future<bool?> requestPermissions({
    bool sound = false,
    bool alert = false,
    bool badge = false,
    bool provisional = false,
    bool critical = false,
  }) async {
    calls.add(
      _DarwinPermissionCall(
        alert: alert,
        badge: badge,
        sound: sound,
        provisional: provisional,
        critical: critical,
      ),
    );
    return result;
  }

  @override
  Future<NotificationsEnabledOptions?> checkPermissions() async {
    checkCalls += 1;
    return enabledOptions;
  }
}

class _MacOSPermissionPlugin extends Fake
    implements MacOSFlutterLocalNotificationsPlugin {
  _MacOSPermissionPlugin(this.result, {this.enabledOptions});

  final bool? result;
  final NotificationsEnabledOptions? enabledOptions;
  final List<_DarwinPermissionCall> calls = <_DarwinPermissionCall>[];
  int checkCalls = 0;

  @override
  Future<bool?> requestPermissions({
    bool sound = false,
    bool alert = false,
    bool badge = false,
    bool provisional = false,
    bool critical = false,
  }) async {
    calls.add(
      _DarwinPermissionCall(
        alert: alert,
        badge: badge,
        sound: sound,
        provisional: provisional,
        critical: critical,
      ),
    );
    return result;
  }

  @override
  Future<NotificationsEnabledOptions?> checkPermissions() async {
    checkCalls += 1;
    return enabledOptions;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  final now = DateTime.utc(2030, 1, 15, 10, 15);

  Note noteWithId(int id) {
    return Note(
      id: id,
      title: 'Reminder',
      content: 'Private content',
      color: 0xFF2196F3,
      createdAt: now,
      reminder: now.add(const Duration(hours: 1)),
    );
  }

  NotificationResponse snoozeResponse(int id) {
    return NotificationResponse(
      notificationResponseType:
          NotificationResponseType.selectedNotificationAction,
      actionId: 'snooze_15',
      payload: 'note:v1:$id',
    );
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('initialization lifecycle', () {
    test(
      'concurrent and sequential init calls initialize plugin once',
      () async {
        final plugin = _PermissionAwarePlugin();
        final gate = Completer<void>();
        plugin.initializeGate = gate;
        final service = NotificationService(plugin: plugin, now: () => now);

        final first = service.init();
        final second = service.init();
        await pumpEventQueue();

        expect(plugin.initializeCalls, 1);

        gate.complete();
        await Future.wait(<Future<void>>[first, second]);
        await service.init();

        expect(plugin.initializeCalls, 1);
        expect(plugin.launchDetailsCalls, 1);
      },
    );

    test('failed init is reported and can be retried', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final plugin = _PermissionAwarePlugin()..initializeFailuresRemaining = 1;
      final service = NotificationService(plugin: plugin, now: () => now);
      final diagnostics = <FlutterErrorDetails>[];
      final previousErrorHandler = FlutterError.onError;
      FlutterError.onError = diagnostics.add;
      try {
        await service.init();
      } finally {
        FlutterError.onError = previousErrorHandler;
      }

      expect(diagnostics, hasLength(1));
      expect(
        diagnostics.single.exception,
        isA<NotificationUnavailableException>(),
      );
      expect(service.supportsReminderScheduling, isTrue);
      await service.init();

      expect(plugin.initializeCalls, 2);
      expect(plugin.launchDetailsCalls, 1);
      expect(service.supportsReminderScheduling, isTrue);
    });

    test('cold-launch snooze is complete before init completes', () async {
      final plugin = _PermissionAwarePlugin();
      plugin.launchDetails = NotificationAppLaunchDetails(
        true,
        notificationResponse: snoozeResponse(7),
      );
      final scheduleGate = Completer<void>();
      plugin.scheduleGate = scheduleGate;
      final service = NotificationService(
        plugin: plugin,
        now: () => now,
        requestPermission: () async => true,
      );
      var initCompleted = false;

      final initFuture = service.init().then((_) => initCompleted = true);
      await pumpEventQueue();

      expect(plugin.scheduleCalls, hasLength(1));
      expect(initCompleted, isFalse);

      scheduleGate.complete();
      await initFuture;

      expect(initCompleted, isTrue);
      expect(plugin.scheduleCalls.single.id, 7);
    });

    test(
      'cold-launch snooze failure is reported without failing init',
      () async {
        final plugin = _PermissionAwarePlugin()
          ..launchDetails = NotificationAppLaunchDetails(
            true,
            notificationResponse: snoozeResponse(8),
          )
          ..scheduleError = StateError('private-sql-path-marker')
          ..scheduleStackTrace = StackTrace.fromString(
            'private-cold-stack-marker',
          );
        final service = NotificationService(
          plugin: plugin,
          now: () => now,
          requestPermission: () async => true,
        );
        final reportedError = Completer<FlutterErrorDetails>();
        final previousHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          if (!reportedError.isCompleted) reportedError.complete(details);
        };
        addTearDown(() => FlutterError.onError = previousHandler);

        await service.init();

        final details = await reportedError.future.timeout(
          const Duration(seconds: 2),
        );
        expect(details.exception, isA<NotificationActionFailedException>());
        expect(details.toString(), isNot(contains('private-sql-path-marker')));
        expect(
          details.stack.toString(),
          isNot(contains('private-cold-stack-marker')),
        );
        expect(details.toString(), contains('StateError'));
        expect(plugin.scheduleCalls.single.id, 8);
      },
    );

    test(
      'live callback reports snooze failures through FlutterError',
      () async {
        final plugin = _PermissionAwarePlugin()
          ..scheduleError = StateError('private-plugin-marker')
          ..scheduleStackTrace = StackTrace.fromString(
            'private-live-stack-marker',
          );
        final service = NotificationService(
          plugin: plugin,
          now: () => now,
          requestPermission: () async => true,
        );
        await service.init();
        final reportedError = Completer<FlutterErrorDetails>();
        final previousHandler = FlutterError.onError;
        FlutterError.onError = (details) {
          if (!reportedError.isCompleted) reportedError.complete(details);
        };
        addTearDown(() => FlutterError.onError = previousHandler);

        plugin.responseCallback!(snoozeResponse(9));

        final details = await reportedError.future.timeout(
          const Duration(seconds: 2),
        );
        expect(details.exception, isA<NotificationActionFailedException>());
        expect(details.toString(), isNot(contains('private-plugin-marker')));
        expect(
          details.stack.toString(),
          isNot(contains('private-live-stack-marker')),
        );
        expect(details.toString(), contains('StateError'));
        expect(plugin.scheduleCalls.single.id, 9);
      },
    );
  });

  group('notification ID bounds', () {
    for (final id in <int>[0, -1, 2147483648]) {
      test('schedule rejects out-of-range ID $id before plugin work', () async {
        final plugin = _PermissionAwarePlugin();
        var permissionRequests = 0;
        final service = NotificationService(
          plugin: plugin,
          now: () => now,
          requestPermission: () async {
            permissionRequests += 1;
            return true;
          },
        );

        await expectLater(
          service.scheduleReminder(noteWithId(id)),
          throwsArgumentError,
        );

        expect(permissionRequests, 0);
        expect(plugin.scheduleCalls, isEmpty);
      });
    }

    for (final id in <int>[1, 2147483647]) {
      test('schedule accepts signed 32-bit boundary ID $id', () async {
        final plugin = _PermissionAwarePlugin();
        final service = NotificationService(
          plugin: plugin,
          now: () => now,
          requestPermission: () async => true,
        );

        await service.scheduleReminder(noteWithId(id));

        expect(plugin.scheduleCalls.single.id, id);
        expect(plugin.scheduleCalls.single.payload, 'note:v1:$id');
      });
    }

    test('oversized payload ID is ignored before snooze work', () async {
      final plugin = _PermissionAwarePlugin();
      var permissionRequests = 0;
      final service = NotificationService(
        plugin: plugin,
        now: () => now,
        requestPermission: () async {
          permissionRequests += 1;
          return true;
        },
      );

      await service.handleNotificationResponse(snoozeResponse(2147483648));

      expect(permissionRequests, 0);
      expect(plugin.scheduleCalls, isEmpty);
    });
  });

  group('production permission dispatch', () {
    ReminderCommand command() => ReminderCommand(
      generation: 7,
      noteId: 1,
      operation: ReminderCommandOperation.schedule,
      scheduledAt: now.add(const Duration(hours: 1)),
    );

    test('Android existing-only checks status without requesting', () async {
      final plugin = _PermissionAwarePlugin();
      final android = _AndroidPermissionPlugin(false, enabled: true);
      plugin.platformImplementations[AndroidFlutterLocalNotificationsPlugin] =
          android;
      final service = NotificationService(plugin: plugin, now: () => now);

      await service.schedule(
        command(),
        permissionPolicy: ReminderPermissionPolicy.existingOnly,
      );

      expect(android.checkCalls, 1);
      expect(android.requestCalls, 0);
      expect(plugin.scheduleCalls.single.payload, 'note:v2:1:7');
    });

    for (final platform in <TargetPlatform>[
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ]) {
      test(
        '${platform.name} existing-only accepts provisional without request',
        () async {
          debugDefaultTargetPlatformOverride = platform;
          final plugin = _PermissionAwarePlugin();
          const options = NotificationsEnabledOptions(
            isEnabled: false,
            isSoundEnabled: false,
            isAlertEnabled: true,
            isBadgeEnabled: false,
            isProvisionalEnabled: true,
            isCriticalEnabled: false,
          );
          late final int Function() checkCalls;
          late final int Function() requestCalls;
          if (platform == TargetPlatform.iOS) {
            final ios = _IOSPermissionPlugin(false, enabledOptions: options);
            plugin.platformImplementations[IOSFlutterLocalNotificationsPlugin] =
                ios;
            checkCalls = () => ios.checkCalls;
            requestCalls = () => ios.calls.length;
          } else {
            final macOS = _MacOSPermissionPlugin(
              false,
              enabledOptions: options,
            );
            plugin.platformImplementations[MacOSFlutterLocalNotificationsPlugin] =
                macOS;
            checkCalls = () => macOS.checkCalls;
            requestCalls = () => macOS.calls.length;
          }
          final service = NotificationService(plugin: plugin, now: () => now);

          await service.schedule(
            command(),
            permissionPolicy: ReminderPermissionPolicy.existingOnly,
          );

          expect(checkCalls(), 1);
          expect(requestCalls(), 0);
          expect(plugin.scheduleCalls, hasLength(1));
        },
      );
    }

    test(
      'Android requests notification permission through Android API',
      () async {
        final plugin = _PermissionAwarePlugin();
        final android = _AndroidPermissionPlugin(true);
        plugin.platformImplementations[AndroidFlutterLocalNotificationsPlugin] =
            android;
        final service = NotificationService(plugin: plugin, now: () => now);

        await service.scheduleReminder(noteWithId(1));

        expect(android.requestCalls, 1);
        expect(plugin.scheduleCalls, hasLength(1));
      },
    );

    for (final platform in <TargetPlatform>[
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ]) {
      test('${platform.name} requests alert, badge, and sound only', () async {
        debugDefaultTargetPlatformOverride = platform;
        final plugin = _PermissionAwarePlugin();
        late final List<_DarwinPermissionCall> calls;
        if (platform == TargetPlatform.iOS) {
          final ios = _IOSPermissionPlugin(true);
          plugin.platformImplementations[IOSFlutterLocalNotificationsPlugin] =
              ios;
          calls = ios.calls;
        } else {
          final macOS = _MacOSPermissionPlugin(true);
          plugin.platformImplementations[MacOSFlutterLocalNotificationsPlugin] =
              macOS;
          calls = macOS.calls;
        }
        final service = NotificationService(plugin: plugin, now: () => now);

        await service.scheduleReminder(noteWithId(1));

        expect(calls, hasLength(1));
        final call = calls.single;
        expect(call.alert, isTrue);
        expect(call.badge, isTrue);
        expect(call.sound, isTrue);
        expect(call.provisional, isFalse);
        expect(call.critical, isFalse);
        expect(plugin.scheduleCalls, hasLength(1));
      });
    }

    for (final permissionResult in <bool?>[false, null]) {
      for (final platform in <TargetPlatform>[
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ]) {
        final resultLabel = permissionResult == null ? 'null' : 'false';
        test('${platform.name} $resultLabel permission result is denied', () async {
          debugDefaultTargetPlatformOverride = platform;
          final plugin = _PermissionAwarePlugin();
          late final int Function() permissionRequestCount;
          List<_DarwinPermissionCall>? darwinCalls;
          switch (platform) {
            case TargetPlatform.android:
              final android = _AndroidPermissionPlugin(permissionResult);
              plugin.platformImplementations[AndroidFlutterLocalNotificationsPlugin] =
                  android;
              permissionRequestCount = () => android.requestCalls;
            case TargetPlatform.iOS:
              final ios = _IOSPermissionPlugin(permissionResult);
              plugin.platformImplementations[IOSFlutterLocalNotificationsPlugin] =
                  ios;
              darwinCalls = ios.calls;
              permissionRequestCount = () => ios.calls.length;
            case TargetPlatform.macOS:
              final macOS = _MacOSPermissionPlugin(permissionResult);
              plugin.platformImplementations[MacOSFlutterLocalNotificationsPlugin] =
                  macOS;
              darwinCalls = macOS.calls;
              permissionRequestCount = () => macOS.calls.length;
            case _:
              throw StateError('Unexpected target platform: $platform');
          }
          final service = NotificationService(plugin: plugin, now: () => now);

          await expectLater(
            service.scheduleReminder(noteWithId(1)),
            throwsA(isA<NotificationPermissionDeniedException>()),
          );

          expect(permissionRequestCount(), 1);
          if (darwinCalls case final calls?) {
            final call = calls.single;
            expect(call.alert, isTrue);
            expect(call.badge, isTrue);
            expect(call.sound, isTrue);
            expect(call.provisional, isFalse);
            expect(call.critical, isFalse);
          }
          expect(plugin.scheduleCalls, isEmpty);
        });
      }
    }
  });
}
