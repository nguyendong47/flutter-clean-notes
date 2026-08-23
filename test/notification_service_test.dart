import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_clean_notes/app/notification_service.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
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
  int getLaunchDetailsCalls = 0;

  final List<ZonedScheduleCall> zonedScheduleCalls = [];
  final List<int> cancelledIds = [];

  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async {
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
              equals('@mipmap/ic_launcher'),
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

      test(
        'Android action receiver is registered without a Dart background callback',
        () async {
          final manifest = await File(
            'android/app/src/main/AndroidManifest.xml',
          ).readAsString();

          expect(
            manifest,
            contains(
              '<receiver\n'
              '            android:name="com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver"\n'
              '            android:exported="false" />',
            ),
          );
        },
      );
    });

    group('Reminder Scheduling', () {
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
          expect(call.title, equals('Note reminder'));
          expect(call.body, equals('Open Aurora Notes to view your reminder.'));
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
    });

    group('Reminder Cancellation', () {
      test('cancelReminder should call plugin cancel', () async {
        await notificationService.cancelReminder(42);

        expect(fakePlugin.cancelledIds, contains(42));
      });
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
          expect(call.title, equals('Note reminder'));
          expect(call.body, equals('Open Aurora Notes to view your reminder.'));
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
        'opaque payload schedules a snoozed reminder on a snooze action',
        () async {
          final payload = notificationService.buildPayload(testNote);
          final response = NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotificationAction,
            actionId: 'snooze_15',
            payload: payload,
          );

          notificationService.handleNotificationResponse(response);
          await pumpEventQueue();

          expect(fakePlugin.zonedScheduleCalls.length, equals(1));
          final call = fakePlugin.zonedScheduleCalls.first;
          expect(call.id, equals(1));
          expect(call.title, equals('Note reminder'));
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

        notificationService.handleNotificationResponse(response);
        await pumpEventQueue();

        expect(fakePlugin.zonedScheduleCalls, hasLength(1));
        final call = fakePlugin.zonedScheduleCalls.single;
        expect(call.id, 1);
        expect(call.title, 'Note reminder');
        expect(call.body, 'Open Aurora Notes to view your reminder.');
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
          notificationService.handleNotificationResponse(
            NotificationResponse(
              notificationResponseType:
                  NotificationResponseType.selectedNotificationAction,
              actionId: 'snooze_15',
              payload: payload,
            ),
          );
        }
        await pumpEventQueue();

        expect(permissionRequests, 0);
        expect(fakePlugin.zonedScheduleCalls, isEmpty);
      });
    });
  });
}
