import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_clean_notes/app/notification_service.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
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

    setUp(() {
      fakePlugin = FakeFlutterLocalNotificationsPlugin();
      notificationService = NotificationService(plugin: fakePlugin);

      testNote = Note(
        id: 1,
        title: 'Test Note',
        content: 'Test Content',
        color: 0xFF2196F3,
        createdAt: DateTime.now(),
        isPinned: false,
        tags: const [],
        status: NoteStatus.active,
        reminder: DateTime.now().add(const Duration(hours: 1)),
      );
    });

    group('Initialization', () {
      test('init should initialize plugin with proper settings', () async {
        await notificationService.init();

        expect(fakePlugin.lastInitSettings, isNotNull);
        expect(
          fakePlugin.lastInitSettings!.android?.defaultIcon,
          equals('@mipmap/ic_launcher'),
        );
        expect(fakePlugin.onDidReceiveNotificationResponse, isNotNull);
      });
    });

    group('Reminder Scheduling', () {
      test('scheduleReminder should call plugin zonedSchedule when reminder is valid', () async {
        await notificationService.scheduleReminder(testNote);

        expect(fakePlugin.zonedScheduleCalls.length, equals(1));
        final call = fakePlugin.zonedScheduleCalls.first;
        expect(call.id, equals(1));
        expect(call.title, equals('Reminder: Test Note'));
        expect(call.body, equals('Test Content'));
        expect(call.androidScheduleMode, equals(AndroidScheduleMode.exactAllowWhileIdle));
        expect(
          call.uiLocalNotificationDateInterpretation,
          equals(UILocalNotificationDateInterpretation.absoluteTime),
        );
        expect(call.payload, equals(notificationService.buildPayload(testNote)));
      });

      test('scheduleReminder should return early when reminder is null', () async {
        final noteWithoutReminder = Note(
          id: 1,
          title: 'No Reminder',
          content: 'No Reminder Content',
          color: 0xFF2196F3,
          createdAt: DateTime.now(),
          reminder: null,
        );

        await notificationService.scheduleReminder(noteWithoutReminder);

        expect(fakePlugin.zonedScheduleCalls, isEmpty);
      });

      test('scheduleReminder should return early when reminder is in the past', () async {
        final pastNote = testNote.copyWith(
          reminder: DateTime.now().subtract(const Duration(hours: 1)),
        );

        await notificationService.scheduleReminder(pastNote);

        expect(fakePlugin.zonedScheduleCalls, isEmpty);
      });

      test('scheduleReminder should return early when id is null', () async {
        final noteWithoutId = Note(
          id: null,
          title: 'No ID',
          content: 'No ID Content',
          color: 0xFF2196F3,
          createdAt: DateTime.now(),
          reminder: DateTime.now().add(const Duration(hours: 1)),
        );

        await notificationService.scheduleReminder(noteWithoutId);

        expect(fakePlugin.zonedScheduleCalls, isEmpty);
      });
    });

    group('Reminder Cancellation', () {
      test('cancelReminder should call plugin cancel', () async {
        await notificationService.cancelReminder(42);

        expect(fakePlugin.cancelledIds, contains(42));
      });
    });

    group('Snooze Functionality', () {
      test('snooze delay should return correct values for different actions', () {
        expect(NotificationService.snoozeDelayMinutes('snooze_5'), equals(5));
        expect(NotificationService.snoozeDelayMinutes('snooze_15'), equals(15));
        expect(NotificationService.snoozeDelayMinutes('snooze_30'), equals(30));
        expect(NotificationService.snoozeDelayMinutes('snooze_60'), equals(60));
        expect(NotificationService.snoozeDelayMinutes('snooze'), equals(10));
        expect(NotificationService.snoozeDelayMinutes('unknown'), equals(10));
        expect(NotificationService.snoozeDelayMinutes(null), equals(10));
      });

      test('scheduleSnoozedReminder should schedule reminder for the delay period', () async {
        await notificationService.scheduleSnoozedReminder(testNote, 15);

        expect(fakePlugin.zonedScheduleCalls.length, equals(1));
        final call = fakePlugin.zonedScheduleCalls.first;
        expect(call.id, equals(1));
        expect(call.title, equals('Reminder: Test Note'));
        expect(call.body, equals('Test Content'));
      });
    });

    group('Payload Serialization', () {
      test('buildPayload should correctly format note data and sanitize pipe characters', () {
        final noteWithPipes = Note(
          id: 5,
          title: 'Hello|World',
          content: 'Foo|Bar|Baz',
          color: 0xFF9C27B0,
          createdAt: DateTime.parse('2026-08-16 10:00:00'),
          reminder: DateTime.parse('2026-08-16 12:00:00'),
        );

        final payload = notificationService.buildPayload(noteWithPipes);
        expect(
          payload,
          equals(
            '5|HelloWorld|FooBarBaz|4288423856|2026-08-16T10:00:00.000|2026-08-16T12:00:00.000',
          ),
        );
      });
    });

    group('Response Handling', () {
      test('handleNotificationResponse should schedule snoozed reminder on snooze action', () async {
        final payload = notificationService.buildPayload(testNote);
        final response = NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: 'snooze_15',
          payload: payload,
        );

        notificationService.handleNotificationResponse(response);

        expect(fakePlugin.zonedScheduleCalls.length, equals(1));
        final call = fakePlugin.zonedScheduleCalls.first;
        expect(call.id, equals(1));
        expect(call.title, equals('Reminder: Test Note'));
      });
    });
  });
}