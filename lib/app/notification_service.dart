import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/reminder_command.dart';
import 'package:flutter_clean_notes/features/notes/domain/repositories/reminder_outbox_repository.dart';

typedef OnNotificationTap = void Function(Note note, BuildContext context);
typedef OnReminderSnooze =
    Future<bool> Function({
      required int noteId,
      required int? expectedGeneration,
      required int delayMinutes,
    });

bool supportsReminderSchedulingOn({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (isWeb) return false;
  return switch (platform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.macOS => true,
    _ => false,
  };
}

UnsupportedError _unsupportedReminderSchedulingError({
  required bool isWeb,
  required TargetPlatform platform,
}) {
  return UnsupportedError(
    isWeb
        ? 'Scheduling reminders is not supported on the web.'
        : 'Scheduling reminders is not supported on ${platform.name}.',
  );
}

class NotificationPermissionDeniedException implements Exception {
  const NotificationPermissionDeniedException();

  @override
  String toString() =>
      'NotificationPermissionDeniedException: Notification permission was not granted.';
}

class NotificationUnavailableException implements Exception {
  const NotificationUnavailableException();

  @override
  String toString() =>
      'Notifications are unavailable. Restart Clean Notes and try again.';
}

class NotificationActionFailedException implements Exception {
  const NotificationActionFailedException();

  @override
  String toString() =>
      'A notification action could not be completed. Open Clean Notes to retry.';
}

class NotificationService
    implements ReminderNotificationGateway, ReminderNotificationRecovery {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService({
    FlutterLocalNotificationsPlugin? plugin,
    DateTime Function()? now,
    Future<bool> Function()? requestPermission,
    Future<bool> Function()? checkPermission,
  }) {
    if (plugin != null ||
        now != null ||
        requestPermission != null ||
        checkPermission != null) {
      return NotificationService._internal(
        plugin: plugin,
        now: now,
        requestPermission: requestPermission,
        checkPermission: checkPermission,
      );
    }
    return _instance;
  }
  NotificationService._internal({
    FlutterLocalNotificationsPlugin? plugin,
    DateTime Function()? now,
    Future<bool> Function()? requestPermission,
    Future<bool> Function()? checkPermission,
  }) : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
       _now = now ?? DateTime.now,
       _requestPermissionOverride = requestPermission,
       _checkPermissionOverride = checkPermission;

  final FlutterLocalNotificationsPlugin _plugin;
  final DateTime Function() _now;
  final Future<bool> Function()? _requestPermissionOverride;
  final Future<bool> Function()? _checkPermissionOverride;

  OnNotificationTap? _onNotificationTap;
  OnReminderSnooze? _onReminderSnooze;
  GlobalKey<NavigatorState>? _navigatorKey;
  final ListQueue<Note> _pendingOpens = ListQueue<Note>();
  Future<void>? _initFuture;
  Future<void>? _nativeReadyFuture;
  bool _flushScheduled = false;
  bool _launchDetailsChecked = false;
  bool _initializationFailed = false;

  OnNotificationTap? get onNotificationTap => _onNotificationTap;

  bool get supportsReminderScheduling => supportsReminderSchedulingOn(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
  );

  @override
  bool get supportsScheduling => supportsReminderScheduling;

  set onNotificationTap(OnNotificationTap? callback) {
    _onNotificationTap = callback;
    _schedulePendingDelivery();
  }

  void attachSnoozeHandler(OnReminderSnooze handler) {
    _onReminderSnooze = handler;
  }

  static const String actionSnooze = 'snooze';
  static const String actionOpen = 'open';

  Future<void> init() => _startInitialization();

  /// Waits for the current initialization attempt, including its cold-launch
  /// action, without starting another native retry.
  Future<void> waitForCurrentInitialization() =>
      _initFuture ?? Future<void>.value();

  Future<void> _startInitialization() {
    final inFlightOrCompleted = _initFuture;
    if (inFlightOrCompleted != null) return inFlightOrCompleted;

    final nativeReady = Completer<void>();
    late final Future<void> initialization;
    initialization = _initialize(nativeReady)
        .then<void>((_) => _initializationFailed = false)
        .onError((error, _) {
          _initializationFailed = true;
          if (!nativeReady.isCompleted) nativeReady.complete();
          if (identical(_initFuture, initialization)) {
            _initFuture = null;
            _nativeReadyFuture = null;
          }
          final failureType = error.runtimeType.toString();
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: const NotificationUnavailableException(),
              stack: StackTrace.current,
              library: 'notification service',
              context: ErrorDescription(
                'while initializing optional notifications',
              ),
              informationCollector: () => <DiagnosticsNode>[
                StringProperty('Native failure type', failureType),
              ],
            ),
          );
        });
    _nativeReadyFuture = nativeReady.future;
    _initFuture = initialization;
    return initialization;
  }

  Future<void> _recoverInitializationIfNeeded() async {
    if (!_initializationFailed) return;
    final initialization = _startInitialization();
    final nativeReady = _nativeReadyFuture;
    await (nativeReady ?? initialization);
    if (_initializationFailed) {
      throw const NotificationUnavailableException();
    }
  }

  @override
  Future<void> recoverForReminderSync() => _recoverInitializationIfNeeded();

  Future<void> _initialize(Completer<void> nativeReady) async {
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
    // Native initialization is ready before cold-launch action routing. A
    // snooze handled below may immediately call back into scheduling.
    _initializationFailed = false;
    if (!nativeReady.isCompleted) nativeReady.complete();

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
    } catch (error) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: const NotificationActionFailedException(),
          stack: StackTrace.current,
          library: 'notification service',
          context: ErrorDescription('while handling a notification action'),
          informationCollector: () => <DiagnosticsNode>[
            StringProperty('Native failure type', error.runtimeType.toString()),
          ],
        ),
      );
    }
  }

  bool get _supportsNotificationLaunchDetails => supportsReminderSchedulingOn(
    isWeb: kIsWeb,
    platform: defaultTargetPlatform,
  );

  Future<void> handleNotificationResponse(NotificationResponse response) async {
    final payload = response.payload;
    if (payload == null) return;

    final reminderPayload = _reminderPayloadFromText(payload);
    if (reminderPayload == null) return;
    final id = reminderPayload.noteId;

    final note = Note(
      id: id,
      title: '',
      content: '',
      color: 0,
      createdAt: DateTime.utc(1970),
    );

    final action = response.actionId;
    final snoozeDelay = _snoozeDelayForAction(action);
    if (snoozeDelay != null) {
      if (reminderPayload.generation != null && response.id != id) return;
      final handler = _onReminderSnooze;
      if (handler != null) {
        await handler(
          noteId: id,
          expectedGeneration: reminderPayload.generation,
          delayMinutes: snoozeDelay,
        );
      } else if (reminderPayload.generation == null) {
        await scheduleSnoozedReminder(note, snoozeDelay);
      }
    } else if (action == actionOpen || action == null || action.isEmpty) {
      _openOrQueue(note);
    }
  }

  static const int _maxNotificationId = 0x7fffffff;

  static bool _isValidNotificationId(int? id) {
    return id != null && id >= 1 && id <= _maxNotificationId;
  }

  static bool _isValidGeneration(int? generation) {
    return generation != null &&
        generation >= 1 &&
        generation <= 0x7fffffffffffffff;
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

  static int? _snoozeDelayForAction(String? actionId) {
    return switch (actionId) {
      actionSnooze => 10,
      'snooze_5' => 5,
      'snooze_15' => 15,
      'snooze_30' => 30,
      'snooze_60' => 60,
      _ => null,
    };
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

  String buildPayload(Note note, {int? generation}) {
    return generation == null
        ? 'note:v1:${note.id}'
        : 'note:v2:${note.id}:$generation';
  }

  Future<void> scheduleSnoozedReminder(Note note, int delayMinutes) async {
    final snoozedTime = _now().add(Duration(minutes: delayMinutes));
    final updatedNote = note.copyWith(reminder: snoozedTime);
    await scheduleReminder(updatedNote);
  }

  Future<void> scheduleReminder(
    Note note, {
    ReminderPermissionPolicy permissionPolicy =
        ReminderPermissionPolicy.requestIfNeeded,
    int? generation,
  }) async {
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
    if (!supportsReminderSchedulingOn(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      throw _unsupportedReminderSchedulingError(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
      );
    }
    await _recoverInitializationIfNeeded();

    if (generation != null && !_isValidGeneration(generation)) {
      throw ArgumentError.value(
        generation,
        'generation',
        'A positive signed 64-bit generation is required',
      );
    }
    await _scheduleReminder(
      noteId: id!,
      reminder: reminder,
      generation: generation,
      permissionPolicy: permissionPolicy,
    );
  }

  Future<void> _scheduleReminder({
    required int noteId,
    required DateTime reminder,
    required int? generation,
    required ReminderPermissionPolicy permissionPolicy,
  }) async {
    final payload = generation == null
        ? 'note:v1:$noteId'
        : 'note:v2:$noteId:$generation';
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

    final permissionGranted = switch (permissionPolicy) {
      ReminderPermissionPolicy.existingOnly =>
        await _hasNotificationPermission(),
      ReminderPermissionPolicy.requestIfNeeded =>
        await _requestNotificationPermission(),
    };
    if (!permissionGranted) {
      throw const NotificationPermissionDeniedException();
    }

    await _plugin.zonedSchedule(
      noteId,
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

    if (!supportsReminderSchedulingOn(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      throw _unsupportedReminderSchedulingError(
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
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
      final platform => throw _unsupportedReminderSchedulingError(
        isWeb: false,
        platform: platform,
      ),
    };

    return permissionGranted ?? false;
  }

  Future<bool> _hasNotificationPermission() async {
    final override = _checkPermissionOverride;
    if (override != null) return override();

    if (!supportsReminderSchedulingOn(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      return false;
    }

    return switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        await _plugin
                .resolvePlatformSpecificImplementation<
                  AndroidFlutterLocalNotificationsPlugin
                >()
                ?.areNotificationsEnabled() ??
            false,
      TargetPlatform.iOS => switch (await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions()) {
        final options? => options.isEnabled || options.isProvisionalEnabled,
        null => false,
      },
      TargetPlatform.macOS => switch (await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.checkPermissions()) {
        final options? => options.isEnabled || options.isProvisionalEnabled,
        null => false,
      },
      _ => false,
    };
  }

  @override
  Future<void> schedule(
    ReminderCommand command, {
    required ReminderPermissionPolicy permissionPolicy,
  }) {
    if (command.operation != ReminderCommandOperation.schedule ||
        command.scheduledAt == null) {
      throw ArgumentError.value(
        command,
        'command',
        'A schedule command is required',
      );
    }
    return scheduleReminder(
      Note(
        id: command.noteId,
        title: '',
        content: '',
        color: 0,
        createdAt: DateTime.utc(1970),
        reminder: command.scheduledAt,
      ),
      permissionPolicy: permissionPolicy,
      generation: command.generation,
    );
  }

  @override
  Future<void> cancel(int noteId) => cancelReminder(noteId);

  @override
  Future<List<PendingReminderNotification>> pendingNotifications() async {
    if (!supportsReminderScheduling) return const [];
    await _recoverInitializationIfNeeded();
    final requests = await _plugin.pendingNotificationRequests();
    return [
      for (final request in requests)
        if (_reminderPayloadFromText(request.payload ?? '') case final payload?)
          if (payload.noteId == request.id)
            payload.generation == null
                ? PendingReminderNotification.legacy(notificationId: request.id)
                : PendingReminderNotification.v2(
                    notificationId: request.id,
                    generation: payload.generation!,
                  ),
    ];
  }

  Future<void> cancelReminder(int id) async {
    if (!supportsReminderSchedulingOn(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      return;
    }
    await _recoverInitializationIfNeeded();
    await _plugin.cancel(id);
  }

  _ReminderPayload? _reminderPayloadFromText(String payload) {
    final v2 = RegExp(
      r'^note:v2:([1-9][0-9]*):([1-9][0-9]*)$',
    ).firstMatch(payload);
    if (v2 != null) {
      final id = int.tryParse(v2.group(1)!);
      final generation = int.tryParse(v2.group(2)!);
      if (_isValidNotificationId(id) && _isValidGeneration(generation)) {
        return _ReminderPayload(noteId: id!, generation: generation);
      }
      return null;
    }

    final v1 = RegExp(r'^note:v1:([1-9][0-9]*)$').firstMatch(payload);
    if (v1 != null) {
      final id = int.tryParse(v1.group(1)!);
      if (_isValidNotificationId(id)) return _ReminderPayload(noteId: id!);
      return null;
    }

    final legacyParts = payload.split('|');
    if (legacyParts.length != 6) return null;
    final legacyId = int.tryParse(legacyParts.first);
    return _isValidNotificationId(legacyId)
        ? _ReminderPayload(noteId: legacyId!)
        : null;
  }
}

final class _ReminderPayload {
  const _ReminderPayload({required this.noteId, this.generation});

  final int noteId;
  final int? generation;
}
