import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';

typedef OnNotificationTap = void Function(Note note, BuildContext context);

class NotificationPermissionDeniedException implements Exception {
  const NotificationPermissionDeniedException();

  @override
  String toString() =>
      'NotificationPermissionDeniedException: Notification permission was not granted.';
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    DateTime Function()? now,
    Future<bool> Function()? requestPermission,
  }) {
    if (plugin != null || now != null || requestPermission != null) {
      return NotificationService._internal(
        plugin: plugin,
        now: now,
        requestPermission: requestPermission,
      );
    }
    return _instance;
  }
  NotificationService._internal({
    FlutterLocalNotificationsPlugin? plugin,
    DateTime Function()? now,
    Future<bool> Function()? requestPermission,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _now = now ?? DateTime.now,
       _requestPermissionOverride = requestPermission;

  final FlutterLocalNotificationsPlugin _plugin;
  final DateTime Function() _now;
  final Future<bool> Function()? _requestPermissionOverride;

  OnNotificationTap? _onNotificationTap;
  GlobalKey<NavigatorState>? _navigatorKey;
  final ListQueue<Note> _pendingOpens = ListQueue<Note>();
  Future<void>? _initFuture;
  bool _flushScheduled = false;
  bool _launchDetailsChecked = false;

  OnNotificationTap? get onNotificationTap => _onNotificationTap;

  set onNotificationTap(OnNotificationTap? callback) {
    _onNotificationTap = callback;
    _schedulePendingDelivery();
  }

  static const String actionSnooze = 'snooze';
  static const String actionOpen = 'open';

  Future<void> init() {
    final inFlightOrCompleted = _initFuture;
    if (inFlightOrCompleted != null) return inFlightOrCompleted;

    late final Future<void> initialization;
    initialization = _initialize().onError((error, stackTrace) {
      if (identical(_initFuture, initialization)) _initFuture = null;
      Error.throwWithStackTrace(error as Object, stackTrace);
    });
    _initFuture = initialization;
    return initialization;
  }

  Future<void> _initialize() async {
    tz.initializeTimeZones();
    const android = AndroidInitializationSettings('ic_stat_clean_notes');
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linux = LinuxInitializationSettings(
      defaultActionName: 'Open notification',
    );
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      linux: linux,
    );
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _handleLiveNotificationResponse,
    );

    if (_launchDetailsChecked || !_supportsNotificationLaunchDetails) return;
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (_launchDetailsChecked) return;
    _launchDetailsChecked = true;
    final launchResponse = launchDetails?.notificationResponse;
    if (launchDetails?.didNotificationLaunchApp ?? false) {
      if (launchResponse != null) {
        await _handleNotificationResponseSafely(launchResponse);
      }
    }
  }

  void _handleLiveNotificationResponse(NotificationResponse response) {
    unawaited(_handleNotificationResponseSafely(response));
  }

  Future<void> _handleNotificationResponseSafely(
    NotificationResponse response,
  ) async {
    try {
      await handleNotificationResponse(response);
    } catch (error, stackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'notification service',
          context: ErrorDescription('while handling a notification action'),
        ),
      );
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

  Future<void> handleNotificationResponse(NotificationResponse response) async {
    final payload = response.payload;
    if (payload == null) return;

    final id = _noteIdFromPayload(payload);
    if (id == null) return;

    final note = Note(
      id: id,
      title: '',
      content: '',
      color: 0,
      createdAt: DateTime.utc(1970),
    );

    final action = response.actionId;
    if (action != null &&
        (action == actionSnooze || action.startsWith('snooze'))) {
      final delayMinutes = snoozeDelayMinutes(action);
      await scheduleSnoozedReminder(note, delayMinutes);
    } else if (action == actionOpen || action == null || action.isEmpty) {
      _openOrQueue(note);
    }
  }

  int? _noteIdFromPayload(String payload) {
    final opaqueParts = payload.split(':');
    final opaqueId =
        opaqueParts.length == 3 &&
            opaqueParts[0] == 'note' &&
            opaqueParts[1] == 'v1'
        ? int.tryParse(opaqueParts[2])
        : null;

    final legacyParts = payload.split('|');
    final legacyId = legacyParts.length == 6
        ? int.tryParse(legacyParts[0])
        : null;
    final id = opaqueId ?? legacyId;
    return _isValidNotificationId(id) ? id : null;
  }

  static const int _maxNotificationId = 0x7fffffff;

  static bool _isValidNotificationId(int? id) {
    return id != null && id >= 1 && id <= _maxNotificationId;
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
    return 'note:v1:${note.id}';
  }

  Future<void> scheduleSnoozedReminder(Note note, int delayMinutes) async {
    final snoozedTime = _now().add(Duration(minutes: delayMinutes));
    final updatedNote = note.copyWith(reminder: snoozedTime);
    await scheduleReminder(updatedNote);
  }

  Future<void> scheduleReminder(Note note) async {
    final id = note.id;
    if (!_isValidNotificationId(id)) {
      throw ArgumentError.value(
        id,
        'note.id',
        'A persisted note ID between 1 and $_maxNotificationId is required',
      );
    }
    final reminder = note.reminder;
    if (reminder == null) {
      throw ArgumentError.value(
        reminder,
        'note.reminder',
        'A reminder time is required',
      );
    }
    if (!reminder.isAfter(_now())) {
      throw ArgumentError.value(
        reminder,
        'note.reminder',
        'The reminder must be in the future',
      );
    }

    final payload = buildPayload(note);
    final snoozeActions = <AndroidNotificationAction>[];
    for (final minutes in [5, 15, 30, 60]) {
      snoozeActions.add(
        AndroidNotificationAction(
          'snooze_$minutes',
          'Snooze $minutes min',
          showsUserInterface: true,
        ),
      );
    }

    final androidDetails = AndroidNotificationDetails(
      'note_reminders',
      'Note Reminders',
      importance: Importance.max,
      priority: Priority.high,
      visibility: NotificationVisibility.private,
      actions: snoozeActions,
    );

    final permissionGranted = await _requestNotificationPermission();
    if (!permissionGranted) {
      throw const NotificationPermissionDeniedException();
    }

    await _plugin.zonedSchedule(
      id!,
      'Clean Notes',
      'Open Clean Notes to view your reminder.',
      tz.TZDateTime.from(reminder, tz.local),
      NotificationDetails(
        android: androidDetails,
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  Future<bool> _requestNotificationPermission() async {
    final override = _requestPermissionOverride;
    if (override != null) return override();

    if (kIsWeb) {
      throw UnsupportedError(
        'Scheduling reminders is not supported on the web.',
      );
    }

    final permissionGranted = switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission(),
      TargetPlatform.iOS =>
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true),
      TargetPlatform.macOS =>
        await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true),
      final platform => throw UnsupportedError(
        'Scheduling reminders is not supported on ${platform.name}.',
      ),
    };

    return permissionGranted ?? false;
  }

  Future<void> cancelReminder(int id) async {
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) return;
    await _plugin.cancel(id);
  }
}
