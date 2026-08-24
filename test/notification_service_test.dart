import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_clean_notes/app/notification_service.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/reminder_command.dart';
import 'package:flutter_clean_notes/features/notes/domain/repositories/reminder_outbox_repository.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/note_reminder_gateway.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class ZonedScheduleCall {
  final int id;
  final String? title;
  final String? body;
  final tz.TZDateTime scheduledDate;
  final NotificationDetails notificationDetails;
  final UILocalNotificationDateInterpretation
  uiLocalNotificationDateInterpretation;
  final bool androidAllowWhileIdle;
  final AndroidScheduleMode? androidScheduleMode;
  final String? payload;
  final DateTimeComponents? matchDateTimeComponents;

  ZonedScheduleCall({
    required this.id,
    required this.title,
    required this.body,
    required this.scheduledDate,
    required this.notificationDetails,
    required this.uiLocalNotificationDateInterpretation,
    this.androidAllowWhileIdle = false,
    this.androidScheduleMode,
    this.payload,
    this.matchDateTimeComponents,
  });
}

class FakeFlutterLocalNotificationsPlugin extends Fake
    implements FlutterLocalNotificationsPlugin {
  InitializationSettings? lastInitSettings;
  DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse;
  DidReceiveBackgroundNotificationResponseCallback?
  onDidReceiveBackgroundNotificationResponse;
  Object? initializationError;
  StackTrace? initializationStackTrace;
  int initializeCalls = 0;
  int getLaunchDetailsCalls = 0;

  final List<ZonedScheduleCall> zonedScheduleCalls = [];
  final List<int> cancelledIds = [];
  List<PendingNotificationRequest> pendingRequests = const [];

  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
    initializeCalls += 1;
    final error = initializationError;
    if (error != null) {
      Error.throwWithStackTrace(
        error,
        initializationStackTrace ?? StackTrace.current,
      );
    }
    lastInitSettings = initializationSettings;
    this.onDidReceiveNotificationResponse = onDidReceiveNotificationResponse;
    this.onDidReceiveBackgroundNotificationResponse =
        onDidReceiveBackgroundNotificationResponse;
    return true;
  }

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async {
    getLaunchDetailsCalls += 1;
    return const NotificationAppLaunchDetails(false);
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
    zonedScheduleCalls.add(
      ZonedScheduleCall(
        id: id,
        title: title,
        body: body,
        scheduledDate: scheduledDate,
        notificationDetails: notificationDetails,
        uiLocalNotificationDateInterpretation:
            uiLocalNotificationDateInterpretation,
        androidAllowWhileIdle: androidAllowWhileIdle,
        androidScheduleMode: androidScheduleMode,
        payload: payload,
        matchDateTimeComponents: matchDateTimeComponents,
      ),
    );
  }

  @override
  Future<void> cancel(int id, {String? tag}) async {
    cancelledIds.add(id);
  }

  @override
  Future<List<PendingNotificationRequest>> pendingNotificationRequests() async {
    return pendingRequests;
  }
}

Future<List<FlutterErrorDetails>> _captureFlutterErrors(
  Future<void> Function() action,
) async {
  final diagnostics = <FlutterErrorDetails>[];
  final previousErrorHandler = FlutterError.onError;
  FlutterError.onError = diagnostics.add;
  try {
    await action();
  } finally {
    FlutterError.onError = previousErrorHandler;
  }
  return diagnostics;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();

  group('NotificationService Tests', () {
    late FakeFlutterLocalNotificationsPlugin fakePlugin;
    late NotificationService notificationService;
    late Note testNote;
    late DateTime now;
    late int permissionRequests;

    setUp(() {
      now = DateTime.utc(2030, 1, 15, 10, 15);
      permissionRequests = 0;
      fakePlugin = FakeFlutterLocalNotificationsPlugin();
      notificationService = NotificationService(
        plugin: fakePlugin,
        now: () => now,
        requestPermission: () async {
          permissionRequests += 1;
          return true;
        },
      );

      testNote = Note(
        id: 1,
        title: 'Test Note',
        content: 'Test Content',
        color: 0xFF2196F3,
        createdAt: now,
        isPinned: false,
        tags: const [],
        status: NoteStatus.active,
        reminder: now.add(const Duration(hours: 1)),
      );
    });

    group('Initialization', () {
      test('platform capability includes only schedulable native targets', () {
        const cases = <({bool isWeb, TargetPlatform platform, bool expected})>[
          (isWeb: false, platform: TargetPlatform.android, expected: true),
          (isWeb: false, platform: TargetPlatform.iOS, expected: true),
          (isWeb: false, platform: TargetPlatform.macOS, expected: true),
          (isWeb: false, platform: TargetPlatform.windows, expected: false),
          (isWeb: false, platform: TargetPlatform.linux, expected: false),
          (isWeb: true, platform: TargetPlatform.android, expected: false),
        ];

        for (final testCase in cases) {
          expect(
            supportsReminderSchedulingOn(
              isWeb: testCase.isWeb,
              platform: testCase.platform,
            ),
            testCase.expected,
            reason:
                'isWeb=${testCase.isWeb}, platform=${testCase.platform.name}',
          );
        }
      });

      test('service exposes the current native platform capability', () {
        const cases = <({TargetPlatform platform, bool expected})>[
          (platform: TargetPlatform.android, expected: true),
          (platform: TargetPlatform.iOS, expected: true),
          (platform: TargetPlatform.macOS, expected: true),
          (platform: TargetPlatform.windows, expected: false),
          (platform: TargetPlatform.linux, expected: false),
        ];

        try {
          for (final testCase in cases) {
            debugDefaultTargetPlatformOverride = testCase.platform;
            expect(
              notificationService.supportsReminderScheduling,
              testCase.expected,
              reason: testCase.platform.name,
            );
          }
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

      test(
        'init diagnostic keeps the failure type but omits private error and stack text',
        () async {
          fakePlugin.initializationError = StateError(
            'private notification error details',
          );
          fakePlugin.initializationStackTrace = StackTrace.fromString(
            'private notification stack details',
          );
          final diagnostics = await _captureFlutterErrors(
            notificationService.init,
          );

          expect(diagnostics, hasLength(1));
          final renderedDiagnostic = diagnostics.single.toString();
          expect(renderedDiagnostic, contains('StateError'));
          expect(
            renderedDiagnostic,
            isNot(contains('private notification error details')),
          );
          expect(
            renderedDiagnostic,
            isNot(contains('private notification stack details')),
          );
        },
      );

      test(
        'service capability stays platform-only after initialization fails',
        () async {
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          fakePlugin.initializationError = StateError(
            'private notification initialization details',
          );
          await _captureFlutterErrors(notificationService.init);

          expect(notificationService.supportsReminderScheduling, isTrue);
        },
      );

      test('a later successful init restores reminder capability', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        fakePlugin.initializationError = StateError(
          'private notification initialization details',
        );
        await _captureFlutterErrors(notificationService.init);
        fakePlugin.initializationError = null;

        await notificationService.init();

        expect(fakePlugin.initializeCalls, 2);
        expect(notificationService.supportsReminderScheduling, isTrue);
      });

      for (final platform in [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ]) {
        test(
          'init configures every target and reads cold launch details on ${platform.name}',
          () async {
            debugDefaultTargetPlatformOverride = platform;
            addTearDown(() => debugDefaultTargetPlatformOverride = null);

            await notificationService.init();

            final settings = fakePlugin.lastInitSettings;
            expect(settings, isNotNull);
            expect(
              settings!.android?.defaultIcon,
              equals('ic_stat_clean_notes'),
            );
            expect(settings.iOS, isNotNull);
            expect(settings.macOS, isNotNull);
            expect(settings.iOS!.requestAlertPermission, isFalse);
            expect(settings.iOS!.requestBadgePermission, isFalse);
            expect(settings.iOS!.requestSoundPermission, isFalse);
            expect(settings.macOS!.requestAlertPermission, isFalse);
            expect(settings.macOS!.requestBadgePermission, isFalse);
            expect(settings.macOS!.requestSoundPermission, isFalse);
            expect(settings.linux?.defaultActionName, 'Open notification');
            expect(fakePlugin.onDidReceiveNotificationResponse, isNotNull);
            expect(
              fakePlugin.onDidReceiveBackgroundNotificationResponse,
              isNull,
            );
            expect(fakePlugin.getLaunchDetailsCalls, 1);
          },
        );
      }

      for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
        test(
          'init configures ${platform.name} without an unsupported launch query',
          () async {
            debugDefaultTargetPlatformOverride = platform;
            addTearDown(() => debugDefaultTargetPlatformOverride = null);

            await notificationService.init();

            final settings = fakePlugin.lastInitSettings;
            expect(settings, isNotNull);
            expect(settings!.macOS, isNotNull);
            expect(settings.linux?.defaultActionName, 'Open notification');
            expect(fakePlugin.getLaunchDetailsCalls, 0);
          },
        );
      }
    });

    group('Reminder Scheduling', () {
      test(
        'outbox scheduling uses v2 payload without prompting in existing-only mode',
        () async {
          var permissionChecks = 0;
          final service = NotificationService(
            plugin: fakePlugin,
            now: () => now,
            requestPermission: () async {
              permissionRequests += 1;
              return true;
            },
            checkPermission: () async {
              permissionChecks += 1;
              return true;
            },
          );
          final command = ReminderCommand(
            generation: 17,
            noteId: 1,
            operation: ReminderCommandOperation.schedule,
            scheduledAt: now.add(const Duration(hours: 1)),
          );

          await service.schedule(
            command,
            permissionPolicy: ReminderPermissionPolicy.existingOnly,
          );

          expect(permissionChecks, 1);
          expect(permissionRequests, 0);
          expect(fakePlugin.zonedScheduleCalls.single.payload, 'note:v2:1:17');
        },
      );

      test(
        'existing-only schedule recovers a transient init failure without prompting',
        () async {
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          var permissionChecks = 0;
          final service = NotificationService(
            plugin: fakePlugin,
            now: () => now,
            requestPermission: () async {
              permissionRequests += 1;
              return true;
            },
            checkPermission: () async {
              permissionChecks += 1;
              return true;
            },
          );
          fakePlugin.initializationError = StateError('transient init failure');
          await _captureFlutterErrors(service.init);
          fakePlugin.initializationError = null;
          final command = ReminderCommand(
            generation: 18,
            noteId: 1,
            operation: ReminderCommandOperation.schedule,
            scheduledAt: now.add(const Duration(hours: 1)),
          );

          await service.schedule(
            command,
            permissionPolicy: ReminderPermissionPolicy.existingOnly,
          );

          expect(fakePlugin.initializeCalls, 2);
          expect(permissionChecks, 1);
          expect(permissionRequests, 0);
          expect(fakePlugin.zonedScheduleCalls.single.payload, 'note:v2:1:18');
        },
      );

      test('pending inventory recovers a transient init failure', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        fakePlugin.initializationError = StateError('transient init failure');
        await _captureFlutterErrors(notificationService.init);
        fakePlugin
          ..initializationError = null
          ..pendingRequests = const [
            PendingNotificationRequest(1, null, null, 'note:v2:1:19'),
          ];

        final pending = await notificationService.pendingNotifications();

        expect(fakePlugin.initializeCalls, 2);
        expect(pending.single.generation, 19);
      });

      test('existing-only denial leaves native schedule untouched', () async {
        final service = NotificationService(
          plugin: fakePlugin,
          now: () => now,
          requestPermission: () async {
            permissionRequests += 1;
            return true;
          },
          checkPermission: () async => false,
        );
        final command = ReminderCommand(
          generation: 17,
          noteId: 1,
          operation: ReminderCommandOperation.schedule,
          scheduledAt: now.add(const Duration(hours: 1)),
        );

        await expectLater(
          service.schedule(
            command,
            permissionPolicy: ReminderPermissionPolicy.existingOnly,
          ),
          throwsA(isA<NotificationPermissionDeniedException>()),
        );

        expect(permissionRequests, 0);
        expect(fakePlugin.zonedScheduleCalls, isEmpty);
      });

      test(
        'repeated initialization failure makes scheduling fail without scheduling',
        () async {
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          fakePlugin.initializationError = StateError(
            'private notification initialization details',
          );
          await _captureFlutterErrors(notificationService.init);

          final diagnostics = await _captureFlutterErrors(() async {
            await expectLater(
              notificationService.scheduleReminder(testNote),
              throwsA(
                isA<NotificationUnavailableException>().having(
                  (error) => error.toString(),
                  'message',
                  allOf(
                    contains('Notifications are unavailable'),
                    isNot(contains('private notification')),
                  ),
                ),
              ),
            );
          });

          expect(diagnostics, hasLength(1));
          expect(fakePlugin.initializeCalls, 2);
          expect(permissionRequests, 0);
          expect(fakePlugin.zonedScheduleCalls, isEmpty);
        },
      );

      test(
        'supported scheduling and cancellation share a successful recovery',
        () async {
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          fakePlugin.initializationError = StateError(
            'private notification initialization details',
          );
          await _captureFlutterErrors(notificationService.init);
          fakePlugin.initializationError = null;

          await Future.wait([
            notificationService.scheduleReminder(testNote),
            notificationService.cancelReminder(42),
          ]);

          expect(fakePlugin.initializeCalls, 2);
          expect(permissionRequests, 1);
          expect(fakePlugin.zonedScheduleCalls, hasLength(1));
          expect(fakePlugin.cancelledIds, [42]);
        },
      );

      test(
        'scheduleReminder uses a private generic inexact notification when permission is granted',
        () async {
          final sensitiveNote = testNote.copyWith(
            tags: const ['classified-tag'],
          );

          await notificationService.scheduleReminder(sensitiveNote);

          expect(permissionRequests, 1);
          expect(fakePlugin.zonedScheduleCalls.length, equals(1));
          final call = fakePlugin.zonedScheduleCalls.first;
          expect(call.id, equals(1));
          expect(call.title, equals('Clean Notes'));
          expect(call.body, equals('Open Clean Notes to view your reminder.'));
          expect(
            call.androidScheduleMode,
            equals(AndroidScheduleMode.inexactAllowWhileIdle),
          );
          expect(
            call.uiLocalNotificationDateInterpretation,
            equals(UILocalNotificationDateInterpretation.absoluteTime),
          );
          expect(call.payload, equals('note:v1:1'));
          expect(
            call.notificationDetails.android?.visibility,
            NotificationVisibility.private,
          );
          final actions = call.notificationDetails.android?.actions;
          expect(
            actions?.map((action) => action.id),
            orderedEquals(['snooze_5', 'snooze_15', 'snooze_30', 'snooze_60']),
          );
          expect(actions?.every((action) => action.showsUserInterface), isTrue);
          final previewAndPayload =
              '${call.title}|${call.body}|${call.payload}';
          expect(previewAndPayload, isNot(contains(testNote.title)));
          expect(previewAndPayload, isNot(contains(testNote.content)));
          expect(previewAndPayload, isNot(contains('classified-tag')));
          expect(
            previewAndPayload,
            isNot(contains(testNote.createdAt.toIso8601String())),
          );
          expect(
            previewAndPayload,
            isNot(contains(testNote.reminder!.toIso8601String())),
          );
        },
      );

      test(
        'scheduleReminder rejects a null reminder without plugin work',
        () async {
          final noteWithoutReminder = Note(
            id: 1,
            title: 'No Reminder',
            content: 'No Reminder Content',
            color: 0xFF2196F3,
            createdAt: now,
            reminder: null,
          );

          await expectLater(
            notificationService.scheduleReminder(noteWithoutReminder),
            throwsArgumentError,
          );

          expect(fakePlugin.zonedScheduleCalls, isEmpty);
          expect(permissionRequests, 0);
        },
      );

      test(
        'scheduleReminder rejects a past reminder without plugin work',
        () async {
          final pastNote = testNote.copyWith(
            reminder: now.subtract(const Duration(hours: 1)),
          );

          await expectLater(
            notificationService.scheduleReminder(pastNote),
            throwsArgumentError,
          );

          expect(fakePlugin.zonedScheduleCalls, isEmpty);
          expect(permissionRequests, 0);
        },
      );

      test('scheduleReminder rejects a null ID without plugin work', () async {
        final noteWithoutId = Note(
          id: null,
          title: 'No ID',
          content: 'No ID Content',
          color: 0xFF2196F3,
          createdAt: now,
          reminder: now.add(const Duration(hours: 1)),
        );

        await expectLater(
          notificationService.scheduleReminder(noteWithoutId),
          throwsArgumentError,
        );

        expect(fakePlugin.zonedScheduleCalls, isEmpty);
        expect(permissionRequests, 0);
      });

      test(
        'scheduleReminder rejects a reminder equal to the injected time',
        () async {
          final now = DateTime.utc(2030, 1, 15, 10, 15);
          final service = NotificationService(
            plugin: fakePlugin,
            now: () => now,
          );
          final equalReminder = testNote.copyWith(reminder: now);

          await expectLater(
            service.scheduleReminder(equalReminder),
            throwsArgumentError,
          );

          expect(fakePlugin.zonedScheduleCalls, isEmpty);
          expect(permissionRequests, 0);
        },
      );

      test('concrete gateway rejects every invalid reminder shape', () async {
        final gateway = NotificationNoteReminderGateway(notificationService);
        final invalidNotes = <Note>[
          testNote.copyWith(id: null),
          testNote.copyWith(reminder: null),
          testNote.copyWith(reminder: now.subtract(const Duration(seconds: 1))),
          testNote.copyWith(reminder: now),
        ];

        for (final note in invalidNotes) {
          await expectLater(gateway.schedule(note), throwsArgumentError);
        }

        expect(fakePlugin.zonedScheduleCalls, isEmpty);
        expect(permissionRequests, 0);
      });

      test(
        'scheduleReminder throws a typed error without scheduling when permission is denied',
        () async {
          final service = NotificationService(
            plugin: fakePlugin,
            now: () => now,
            requestPermission: () async {
              permissionRequests += 1;
              return false;
            },
          );

          await expectLater(
            service.scheduleReminder(testNote),
            throwsA(isA<NotificationPermissionDeniedException>()),
          );

          expect(permissionRequests, 1);
          expect(fakePlugin.zonedScheduleCalls, isEmpty);
        },
      );

      for (final platform in [
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        test(
          'scheduleReminder rejects unsupported ${platform.name} before scheduling',
          () async {
            debugDefaultTargetPlatformOverride = platform;
            addTearDown(() => debugDefaultTargetPlatformOverride = null);
            final service = NotificationService(
              plugin: fakePlugin,
              now: () => now,
            );

            await expectLater(
              service.scheduleReminder(testNote),
              throwsA(
                isA<UnsupportedError>().having(
                  (error) => error.message,
                  'message',
                  contains(platform.name),
                ),
              ),
            );

            expect(fakePlugin.zonedScheduleCalls, isEmpty);
          },
        );
      }

      for (final platform in [
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        test(
          'unsupported ${platform.name} stays unsupported after init failure',
          () async {
            debugDefaultTargetPlatformOverride = platform;
            addTearDown(() => debugDefaultTargetPlatformOverride = null);
            fakePlugin.initializationError = StateError(
              'private notification initialization details',
            );
            await _captureFlutterErrors(notificationService.init);

            await expectLater(
              notificationService.scheduleReminder(testNote),
              throwsA(isA<UnsupportedError>()),
            );

            expect(fakePlugin.zonedScheduleCalls, isEmpty);
            expect(permissionRequests, 0);
          },
        );
      }
    });

    group('Reminder Cancellation', () {
      test(
        'repeated initialization failure makes cancellation fail without cancellation',
        () async {
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          fakePlugin.initializationError = StateError(
            'private notification initialization details',
          );
          await _captureFlutterErrors(notificationService.init);

          final diagnostics = await _captureFlutterErrors(() async {
            await expectLater(
              notificationService.cancelReminder(42),
              throwsA(isA<NotificationUnavailableException>()),
            );
          });

          expect(diagnostics, hasLength(1));
          expect(fakePlugin.initializeCalls, 2);
          expect(fakePlugin.cancelledIds, isEmpty);
        },
      );

      test('cancelReminder delegates on a supported platform', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        await notificationService.cancelReminder(42);

        expect(fakePlugin.cancelledIds, [42]);
      });

      test('cancelReminder is a no-op on unsupported Windows', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.windows;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        await notificationService.cancelReminder(42);

        expect(fakePlugin.cancelledIds, isEmpty);
      });

      for (final platform in [
        TargetPlatform.linux,
        TargetPlatform.windows,
        TargetPlatform.fuchsia,
      ]) {
        test(
          'unsupported ${platform.name} cancellation stays a no-op after init failure',
          () async {
            debugDefaultTargetPlatformOverride = platform;
            addTearDown(() => debugDefaultTargetPlatformOverride = null);
            fakePlugin.initializationError = StateError(
              'private notification initialization details',
            );
            await _captureFlutterErrors(notificationService.init);

            await notificationService.cancelReminder(42);

            expect(fakePlugin.cancelledIds, isEmpty);
          },
        );
      }
    });

    group('Snooze Functionality', () {
      test(
        'snooze delay should return correct values for different actions',
        () {
          expect(NotificationService.snoozeDelayMinutes('snooze_5'), equals(5));
          expect(
            NotificationService.snoozeDelayMinutes('snooze_15'),
            equals(15),
          );
          expect(
            NotificationService.snoozeDelayMinutes('snooze_30'),
            equals(30),
          );
          expect(
            NotificationService.snoozeDelayMinutes('snooze_60'),
            equals(60),
          );
          expect(NotificationService.snoozeDelayMinutes('snooze'), equals(10));
          expect(NotificationService.snoozeDelayMinutes('unknown'), equals(10));
          expect(NotificationService.snoozeDelayMinutes(null), equals(10));
        },
      );

      test(
        'scheduleSnoozedReminder should schedule reminder for the delay period',
        () async {
          await notificationService.scheduleSnoozedReminder(testNote, 15);

          expect(fakePlugin.zonedScheduleCalls.length, equals(1));
          final call = fakePlugin.zonedScheduleCalls.first;
          expect(call.id, equals(1));
          expect(call.title, equals('Clean Notes'));
          expect(call.body, equals('Open Clean Notes to view your reminder.'));
          expect(
            call.scheduledDate,
            tz.TZDateTime.from(now.add(const Duration(minutes: 15)), tz.local),
          );
          expect(
            call.androidScheduleMode,
            AndroidScheduleMode.inexactAllowWhileIdle,
          );
        },
      );
    });

    group('Payload Serialization', () {
      test('buildPayload contains only the version and persisted note ID', () {
        final noteWithPipes = Note(
          id: 5,
          title: 'Hello|World',
          content: 'Foo|Bar|Baz',
          color: 0xFF9C27B0,
          createdAt: DateTime.parse('2026-08-16 10:00:00'),
          reminder: DateTime.parse('2026-08-16 12:00:00'),
        );

        final payload = notificationService.buildPayload(noteWithPipes);
        expect(payload, equals('note:v1:5'));
        expect(payload, isNot(contains('Hello')));
        expect(payload, isNot(contains('Foo')));
        expect(payload, isNot(contains('4288423856')));
        expect(payload, isNot(contains('2026-08-16')));
      });
    });

    group('Response Handling', () {
      test(
        'v2 snooze delegates generation without permission or native work',
        () async {
          final calls = <({int id, int? generation, int delay})>[];
          notificationService.attachSnoozeHandler(({
            required int noteId,
            required int? expectedGeneration,
            required int delayMinutes,
          }) async {
            calls.add((
              id: noteId,
              generation: expectedGeneration,
              delay: delayMinutes,
            ));
            return true;
          });

          await notificationService.handleNotificationResponse(
            const NotificationResponse(
              notificationResponseType:
                  NotificationResponseType.selectedNotificationAction,
              id: 1,
              actionId: 'snooze_15',
              payload: 'note:v2:1:17',
            ),
          );

          expect(calls, [(id: 1, generation: 17, delay: 15)]);
          expect(permissionRequests, 0);
          expect(fakePlugin.zonedScheduleCalls, isEmpty);
        },
      );

      test(
        'unknown snooze actions and mismatched v2 response IDs are ignored',
        () async {
          var calls = 0;
          notificationService.attachSnoozeHandler(({
            required int noteId,
            required int? expectedGeneration,
            required int delayMinutes,
          }) async {
            calls += 1;
            return true;
          });

          for (final response in const [
            NotificationResponse(
              notificationResponseType:
                  NotificationResponseType.selectedNotificationAction,
              id: 1,
              actionId: 'snooze_evil',
              payload: 'note:v2:1:17',
            ),
            NotificationResponse(
              notificationResponseType:
                  NotificationResponseType.selectedNotificationAction,
              id: 2,
              actionId: 'snooze_15',
              payload: 'note:v2:1:17',
            ),
          ]) {
            await notificationService.handleNotificationResponse(response);
          }

          expect(calls, 0);
        },
      );

      test(
        'pending audit inventory accepts only owned canonical payloads',
        () async {
          fakePlugin.pendingRequests = const [
            PendingNotificationRequest(1, null, null, 'note:v2:1:17'),
            PendingNotificationRequest(2, null, null, 'note:v1:2'),
            PendingNotificationRequest(3, null, null, 'note:v2:4:18'),
            PendingNotificationRequest(4, null, null, 'note:v3:4:18'),
            PendingNotificationRequest(5, null, null, null),
          ];

          final pending = await notificationService.pendingNotifications();

          expect(pending, hasLength(2));
          expect(pending.first.notificationId, 1);
          expect(pending.first.generation, 17);
          expect(pending.last.notificationId, 2);
          expect(pending.last.isLegacy, isTrue);
        },
      );

      test(
        'opaque payload schedules a snoozed reminder on a snooze action',
        () async {
          final payload = notificationService.buildPayload(testNote);
          final response = NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
            actionId: 'snooze_15',
            payload: payload,
          );

          await notificationService.handleNotificationResponse(response);

          expect(fakePlugin.zonedScheduleCalls.length, equals(1));
          final call = fakePlugin.zonedScheduleCalls.first;
          expect(call.id, equals(1));
          expect(call.title, equals('Clean Notes'));
          expect(call.payload, 'note:v1:1');
        },
      );

      test('legacy six-part payload remains snooze compatible', () async {
        final response = NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: 'snooze_15',
          payload:
              '1|Legacy private title|Legacy private body|4280391411|2030-01-15T10:15:00.000Z|2030-01-15T11:15:00.000Z',
        );

        await notificationService.handleNotificationResponse(response);

        expect(fakePlugin.zonedScheduleCalls, hasLength(1));
        final call = fakePlugin.zonedScheduleCalls.single;
        expect(call.id, 1);
        expect(call.title, 'Clean Notes');
        expect(call.body, 'Open Clean Notes to view your reminder.');
        expect(call.payload, 'note:v1:1');
      });

      test('invalid or missing payload IDs are ignored without work', () async {
        final invalidPayloads = <String?>[
          null,
          '',
          'note:v1:',
          'note:v1:not-an-id',
          'note:v1:0',
          'note:v1:-1',
          'not|six|parts',
          'not-an-id|title|body|4280391411|2030-01-15T10:15:00.000Z|2030-01-15T11:15:00.000Z',
          '0|title|body|4280391411|2030-01-15T10:15:00.000Z|2030-01-15T11:15:00.000Z',
          '-1|title|body|4280391411|2030-01-15T10:15:00.000Z|2030-01-15T11:15:00.000Z',
        ];

        for (final payload in invalidPayloads) {
          await notificationService.handleNotificationResponse(
            NotificationResponse(
              notificationResponseType:
                  NotificationResponseType.selectedNotificationAction,
              actionId: 'snooze_15',
              payload: payload,
            ),
          );
        }
        expect(permissionRequests, 0);
        expect(fakePlugin.zonedScheduleCalls, isEmpty);
      });
    });
  });
}
