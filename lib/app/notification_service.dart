import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';

typedef OnNotificationTap = void Function(Note note, BuildContext context);

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService({FlutterLocalNotificationsPlugin? plugin}) {
    if (plugin != null) {
      return NotificationService._internal(plugin: plugin);
    }
    return _instance;
  }
  NotificationService._internal({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  OnNotificationTap? _onNotificationTap;
  GlobalKey<NavigatorState>? _navigatorKey;
  final ListQueue<Note> _pendingOpens = ListQueue<Note>();
  bool _flushScheduled = false;
  bool _launchDetailsChecked = false;

  OnNotificationTap? get onNotificationTap => _onNotificationTap;

  set onNotificationTap(OnNotificationTap? callback) {
    _onNotificationTap = callback;
    _schedulePendingDelivery();
  }

  static const String actionSnooze = 'snooze';
  static const String actionOpen = 'open';

  Future<void> init() async {
    tz.initializeTimeZones();
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: handleNotificationResponse,
    );

    if (_launchDetailsChecked || !_supportsNotificationLaunchDetails) return;
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (_launchDetailsChecked) return;
    _launchDetailsChecked = true;
    final launchResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      if (launchResponse != null) handleNotificationResponse(launchResponse);
    }
  }

  bool get _supportsNotificationLaunchDetails {
    if (kIsWeb) return false;
    return switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS => true,
      _ => false,
    };
  }

  void handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;

    final parts = payload.split('|');
    if (parts.length < 6) return;

    final id = int.tryParse(parts[0]);
    final title = parts[1];
    final content = parts.length > 2 ? parts[2] : '';
    final color = int.tryParse(parts[3]) ?? 0xFF2196F3;
    final createdAt = DateTime.tryParse(parts[4]) ?? DateTime.now();
    final reminder = DateTime.tryParse(parts[5]);

    if (id == null) return;

    final note = Note(
      id: id,
      title: title,
      content: content,
      color: color,
      createdAt: createdAt,
      reminder: reminder,
    );

    final action = response.actionId;
    if (action != null &&
        (action == actionSnooze || action.startsWith('snooze'))) {
      final delayMinutes = snoozeDelayMinutes(action);
      scheduleSnoozedReminder(note, delayMinutes);
    } else if (action == actionOpen || action == null || action.isEmpty) {
      _openOrQueue(note);
    }
  }

  static int snoozeDelayMinutes(String? actionId) {
    if (actionId == null) return 10;
    const delays = {
      'snooze_5': 5,
      'snooze_15': 15,
      'snooze_30': 30,
      'snooze_60': 60,
    };
    return delays[actionId] ?? 10;
  }

  void attachContext(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;
    _schedulePendingDelivery();
  }

  void _openOrQueue(Note note) {
    final context = _readyContext;
    final callback = _onNotificationTap;
    if (context != null && callback != null) {
      callback(note, context);
      return;
    }

    _pendingOpens.add(note);
    _schedulePendingDelivery();
  }

  BuildContext? get _readyContext {
    final context = _navigatorKey?.currentContext;
    return context != null && context.mounted ? context : null;
  }

  void _schedulePendingDelivery() {
    if (_pendingOpens.isEmpty || _flushScheduled) return;
    _flushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      _flushPendingOpens();
    });
  }

  void _flushPendingOpens() {
    final context = _readyContext;
    final callback = _onNotificationTap;
    if (context == null || callback == null) {
      if (_navigatorKey != null && callback != null) {
        _schedulePendingDelivery();
      }
      return;
    }

    while (_pendingOpens.isNotEmpty) {
      final note = _pendingOpens.removeFirst();
      callback(note, context);
    }
  }

  String buildPayload(Note note) {
    final title = note.title.replaceAll('|', '');
    final content = note.content.replaceAll('|', '');
    return '${note.id}|$title|$content|${note.color}|${note.createdAt.toIso8601String()}|${note.reminder?.toIso8601String() ?? ''}';
  }

  Future<void> scheduleSnoozedReminder(Note note, int delayMinutes) async {
    final snoozedTime = DateTime.now().add(Duration(minutes: delayMinutes));
    final updatedNote = note.copyWith(reminder: snoozedTime);
    await scheduleReminder(updatedNote);
  }

  Future<void> scheduleReminder(Note note) async {
    if (note.reminder == null || note.id == null) return;
    if (note.reminder!.isBefore(DateTime.now())) return;

    final payload = buildPayload(note);
    final snoozeActions = <AndroidNotificationAction>[];
    for (final minutes in [5, 15, 30, 60]) {
      snoozeActions.add(
        AndroidNotificationAction(
          'snooze_$minutes',
          'Snooze $minutes min',
          showsUserInterface: false,
        ),
      );
    }

    final androidDetails = AndroidNotificationDetails(
      'note_reminders',
      'Note Reminders',
      importance: Importance.max,
      priority: Priority.high,
      actions: snoozeActions,
    );

    await _plugin.zonedSchedule(
      note.id!,
      'Reminder: ${note.title}',
      note.content,
      tz.TZDateTime.from(note.reminder!, tz.local),
      NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  Future<void> cancelReminder(int id) async {
    await _plugin.cancel(id);
  }
}
