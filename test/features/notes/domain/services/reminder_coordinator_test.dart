import 'dart:async';

import 'package:flutter_clean_notes/features/notes/domain/entities/reminder_command.dart';
import 'package:flutter_clean_notes/features/notes/domain/repositories/reminder_outbox_repository.dart';
import 'package:flutter_clean_notes/features/notes/domain/services/reminder_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2030, 1, 15, 10);

  test('applies and acknowledges a current schedule command', () async {
    final events = <String>[];
    final repository = _FakeOutboxRepository()
      ..put(_schedule(1, noteId: 7, at: now.add(const Duration(hours: 1))));
    final gateway = _FakeReminderNotificationGateway(events: events)
      ..nativeGenerations[7] = 0;
    final coordinator = ReminderCoordinator(
      repository: repository,
      gateway: gateway,
      now: () => now,
    );

    await coordinator.drain();

    expect(gateway.scheduled.single.command.generation, 1);
    expect(events, ['cancel:7', 'schedule:7']);
    expect(gateway.nativeGenerations, {7: 1});
    expect(
      gateway.scheduled.single.policy,
      ReminderPermissionPolicy.requestIfNeeded,
    );
    expect(repository.commands, isEmpty);
  });

  test(
    'failed replacement clears native predecessor and keeps successor',
    () async {
      final failure = StateError('native replacement failed');
      final events = <String>[];
      final successor = _schedule(
        2,
        noteId: 7,
        at: now.add(const Duration(hours: 2)),
      );
      final repository = _FakeOutboxRepository()..put(successor);
      final gateway = _FakeReminderNotificationGateway(events: events)
        ..nativeGenerations[7] = 1
        ..scheduleErrors[7] = failure;
      final coordinator = ReminderCoordinator(
        repository: repository,
        gateway: gateway,
        now: () => now,
      );

      await expectLater(coordinator.drain(), throwsA(same(failure)));

      expect(events, ['cancel:7', 'schedule:7']);
      expect(gateway.nativeGenerations, isEmpty);
      expect(repository.commands, [successor]);
    },
  );

  test(
    'successor created after native cancel skips the stale schedule',
    () async {
      final events = <String>[];
      final repository = _FakeOutboxRepository()
        ..put(_schedule(1, noteId: 7, at: now.add(const Duration(hours: 1))));
      final gateway = _FakeReminderNotificationGateway(events: events)
        ..nativeGenerations[7] = 0;
      final cancelled = Completer<void>();
      final releaseCancel = Completer<void>();
      gateway.cancelHooks[7] = () async {
        cancelled.complete();
        await releaseCancel.future;
      };
      final coordinator = ReminderCoordinator(
        repository: repository,
        gateway: gateway,
        now: () => now,
      );

      final drain = coordinator.drain();
      await cancelled.future;
      repository.put(
        _schedule(2, noteId: 7, at: now.add(const Duration(hours: 2))),
      );
      gateway.cancelHooks.remove(7);
      releaseCancel.complete();
      await drain;

      expect(gateway.scheduled.map((attempt) => attempt.command.generation), [
        2,
      ]);
      expect(events, ['cancel:7', 'cancel:7', 'schedule:7']);
      expect(gateway.nativeGenerations, {7: 2});
      expect(repository.commands, isEmpty);
    },
  );

  test('a failed schedule does not starve a later cancellation', () async {
    final denied = _PermissionDenied();
    final repository = _FakeOutboxRepository()
      ..put(_schedule(1, noteId: 7, at: now.add(const Duration(hours: 1))))
      ..put(_cancel(2, noteId: 8));
    final gateway = _FakeReminderNotificationGateway()
      ..scheduleErrors[7] = denied;
    final coordinator = ReminderCoordinator(
      repository: repository,
      gateway: gateway,
      now: () => now,
    );

    await expectLater(
      coordinator.drain(
        permissionPolicy: ReminderPermissionPolicy.existingOnly,
      ),
      throwsA(same(denied)),
    );

    expect(gateway.cancelled, [7, 8]);
    expect(
      gateway.scheduled.single.policy,
      ReminderPermissionPolicy.existingOnly,
    );
    expect(repository.commands.map((command) => command.generation), [1]);
  });

  test('a successor wins when it supersedes an in-flight schedule', () async {
    final repository = _FakeOutboxRepository()
      ..put(_schedule(1, noteId: 7, at: now.add(const Duration(hours: 1))));
    final gateway = _FakeReminderNotificationGateway();
    final firstStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    gateway.scheduleHooks[1] = () async {
      firstStarted.complete();
      await releaseFirst.future;
    };
    final coordinator = ReminderCoordinator(
      repository: repository,
      gateway: gateway,
      now: () => now,
    );

    final drain = coordinator.drain();
    await firstStarted.future;
    repository.put(
      _schedule(2, noteId: 7, at: now.add(const Duration(hours: 2))),
    );
    releaseFirst.complete();
    await drain;

    expect(gateway.scheduled.map((attempt) => attempt.command.generation), [
      1,
      2,
    ]);
    expect(repository.commands, isEmpty);
  });

  test('expired schedule is cancelled and acknowledged', () async {
    final repository = _FakeOutboxRepository()
      ..put(_schedule(1, noteId: 7, at: now));
    final gateway = _FakeReminderNotificationGateway();
    final coordinator = ReminderCoordinator(
      repository: repository,
      gateway: gateway,
      now: () => now,
    );

    await coordinator.drain();

    expect(gateway.scheduled, isEmpty);
    expect(gateway.cancelled, [7]);
    expect(repository.commands, isEmpty);
  });

  test(
    'snooze persists before scheduling and never requests permission',
    () async {
      final events = <String>[];
      final repository = _FakeOutboxRepository(events: events);
      final gateway = _FakeReminderNotificationGateway(events: events);
      final coordinator = ReminderCoordinator(
        repository: repository,
        gateway: gateway,
        now: () => now,
      );

      final accepted = await coordinator.snooze(
        noteId: 7,
        expectedGeneration: 1,
        delayMinutes: 15,
      );

      expect(accepted, isTrue);
      expect(events, ['persist:7', 'cancel:7', 'schedule:7']);
      expect(
        gateway.scheduled.single.policy,
        ReminderPermissionPolicy.existingOnly,
      );
    },
  );

  test(
    'startup audit uses pending inventory and existing permission only',
    () async {
      final events = <String>[];
      final repository = _FakeOutboxRepository(events: events);
      final gateway = _FakeReminderNotificationGateway(events: events)
        ..pending = const [
          PendingReminderNotification.legacy(notificationId: 7),
        ];
      repository.reconcileResult = _schedule(
        1,
        noteId: 8,
        at: now.add(const Duration(hours: 1)),
      );
      final coordinator = ReminderCoordinator(
        repository: repository,
        gateway: gateway,
        now: () => now,
      );

      await coordinator.reconcileAtStartup();

      expect(events, ['pending', 'reconcile', 'cancel:8', 'schedule:8']);
      expect(
        gateway.scheduled.single.policy,
        ReminderPermissionPolicy.existingOnly,
      );
    },
  );

  test(
    'unsupported platform acknowledges commands without native work',
    () async {
      final repository = _FakeOutboxRepository()
        ..put(_schedule(1, noteId: 7, at: now.add(const Duration(hours: 1))))
        ..put(_cancel(2, noteId: 8));
      final gateway = _FakeReminderNotificationGateway()
        ..supportsScheduling = false;
      final coordinator = ReminderCoordinator(
        repository: repository,
        gateway: gateway,
        now: () => now,
      );

      await coordinator.drain();

      expect(repository.commands, isEmpty);
      expect(gateway.scheduled, isEmpty);
      expect(gateway.cancelled, isEmpty);
    },
  );

  test('concurrent drains never overlap native operations', () async {
    final repository = _FakeOutboxRepository()
      ..put(_cancel(1, noteId: 7))
      ..put(_cancel(2, noteId: 8));
    final gateway = _FakeReminderNotificationGateway();
    final gate = Completer<void>();
    gateway.cancelGate = gate;
    final coordinator = ReminderCoordinator(
      repository: repository,
      gateway: gateway,
      now: () => now,
    );

    final first = coordinator.drain();
    final second = coordinator.drain();
    await pumpEventQueue();
    expect(gateway.maxConcurrentOperations, 1);
    gate.complete();
    await Future.wait([first, second]);

    expect(gateway.maxConcurrentOperations, 1);
  });
}

ReminderCommand _schedule(
  int generation, {
  required int noteId,
  required DateTime at,
}) => ReminderCommand(
  generation: generation,
  noteId: noteId,
  operation: ReminderCommandOperation.schedule,
  scheduledAt: at,
);

ReminderCommand _cancel(int generation, {required int noteId}) =>
    ReminderCommand(
      generation: generation,
      noteId: noteId,
      operation: ReminderCommandOperation.cancel,
    );

final class _PermissionDenied implements Exception {}

final class _FakeOutboxRepository implements ReminderOutboxRepository {
  _FakeOutboxRepository({this.events});

  final List<String>? events;
  final Map<int, ReminderCommand> _byNote = {};
  ReminderCommand? reconcileResult;
  int _nextGeneration = 10;

  List<ReminderCommand> get commands =>
      _byNote.values.toList()
        ..sort((a, b) => a.generation.compareTo(b.generation));

  void put(ReminderCommand command) => _byNote[command.noteId] = command;

  @override
  Future<bool> acknowledge(int generation) async {
    final entry = _byNote.entries
        .where((entry) => entry.value.generation == generation)
        .firstOrNull;
    if (entry == null) return false;
    _byNote.remove(entry.key);
    return true;
  }

  @override
  Future<bool> isCurrent(int generation) async =>
      _byNote.values.any((command) => command.generation == generation);

  @override
  Future<List<ReminderCommand>> pending({int? noteId}) async => [
    for (final command in commands)
      if (noteId == null || command.noteId == noteId) command,
  ];

  @override
  Future<void> reconcile({
    required List<PendingReminderNotification> pending,
    required DateTime now,
  }) async {
    events?.add('reconcile');
    if (reconcileResult case final command?) put(command);
  }

  @override
  Future<ReminderCommand?> snooze({
    required int noteId,
    required int? expectedGeneration,
    required DateTime scheduledAt,
  }) async {
    events?.add('persist:$noteId');
    final command = _schedule(
      _nextGeneration++,
      noteId: noteId,
      at: scheduledAt,
    );
    put(command);
    return command;
  }
}

final class _FakeReminderNotificationGateway
    implements ReminderNotificationGateway {
  _FakeReminderNotificationGateway({this.events});

  final List<String>? events;
  @override
  bool supportsScheduling = true;
  List<PendingReminderNotification> pending = const [];
  final List<({ReminderCommand command, ReminderPermissionPolicy policy})>
  scheduled = [];
  final List<int> cancelled = [];
  final Map<int, int> nativeGenerations = {};
  final Map<int, Object> scheduleErrors = {};
  final Map<int, Future<void> Function()> scheduleHooks = {};
  final Map<int, Future<void> Function()> cancelHooks = {};
  Completer<void>? cancelGate;
  int _concurrentOperations = 0;
  int maxConcurrentOperations = 0;

  @override
  Future<void> cancel(int noteId) => _track(() async {
    cancelled.add(noteId);
    events?.add('cancel:$noteId');
    nativeGenerations.remove(noteId);
    await cancelHooks[noteId]?.call();
    final gate = cancelGate;
    if (gate != null) await gate.future;
  });

  @override
  Future<List<PendingReminderNotification>> pendingNotifications() async {
    events?.add('pending');
    return pending;
  }

  @override
  Future<void> schedule(
    ReminderCommand command, {
    required ReminderPermissionPolicy permissionPolicy,
  }) => _track(() async {
    scheduled.add((command: command, policy: permissionPolicy));
    events?.add('schedule:${command.noteId}');
    await scheduleHooks[command.generation]?.call();
    final error = scheduleErrors[command.noteId];
    if (error != null) throw error;
    nativeGenerations[command.noteId] = command.generation;
  });

  Future<void> _track(Future<void> Function() operation) async {
    _concurrentOperations += 1;
    if (_concurrentOperations > maxConcurrentOperations) {
      maxConcurrentOperations = _concurrentOperations;
    }
    try {
      await operation();
    } finally {
      _concurrentOperations -= 1;
    }
  }
}
