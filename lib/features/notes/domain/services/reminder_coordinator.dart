import 'dart:async';

import 'package:flutter_clean_notes/features/notes/domain/entities/reminder_command.dart';
import 'package:flutter_clean_notes/features/notes/domain/repositories/reminder_outbox_repository.dart';

abstract interface class ReminderSyncCoordinator {
  Future<void> drain({
    int? noteId,
    ReminderPermissionPolicy permissionPolicy =
        ReminderPermissionPolicy.requestIfNeeded,
  });

  Future<bool> snooze({
    required int noteId,
    required int? expectedGeneration,
    required int delayMinutes,
  });

  Future<void> reconcileAtStartup();
}

final class ReminderCoordinator implements ReminderSyncCoordinator {
  ReminderCoordinator({
    required ReminderOutboxRepository repository,
    required ReminderNotificationGateway gateway,
    DateTime Function()? now,
  }) : _repository = repository,
       _gateway = gateway,
       _now = now ?? DateTime.now;

  final ReminderOutboxRepository _repository;
  final ReminderNotificationGateway _gateway;
  final DateTime Function() _now;
  Future<void> _tail = Future<void>.value();

  @override
  Future<void> drain({
    int? noteId,
    ReminderPermissionPolicy permissionPolicy =
        ReminderPermissionPolicy.requestIfNeeded,
  }) {
    return _serialize(
      () => _drain(noteId: noteId, permissionPolicy: permissionPolicy),
    );
  }

  @override
  Future<bool> snooze({
    required int noteId,
    required int? expectedGeneration,
    required int delayMinutes,
  }) {
    return _serialize(() async {
      if (!const {5, 10, 15, 30, 60}.contains(delayMinutes)) return false;
      final command = await _repository.snooze(
        noteId: noteId,
        expectedGeneration: expectedGeneration,
        scheduledAt: _now().add(Duration(minutes: delayMinutes)),
      );
      if (command == null) return false;
      await _drain(
        noteId: noteId,
        permissionPolicy: ReminderPermissionPolicy.existingOnly,
      );
      return true;
    });
  }

  @override
  Future<void> reconcileAtStartup() {
    return _serialize(() async {
      Object? auditError;
      StackTrace? auditStackTrace;
      if (_gateway.supportsScheduling) {
        try {
          final pending = await _gateway.pendingNotifications();
          await _repository.reconcile(pending: pending, now: _now());
        } catch (error, stackTrace) {
          auditError = error;
          auditStackTrace = stackTrace;
        }
      }

      try {
        await _drain(permissionPolicy: ReminderPermissionPolicy.existingOnly);
      } catch (error, stackTrace) {
        auditError ??= error;
        auditStackTrace ??= stackTrace;
      }
      if (auditError != null) {
        Error.throwWithStackTrace(auditError, auditStackTrace!);
      }
    });
  }

  Future<void> _drain({
    int? noteId,
    required ReminderPermissionPolicy permissionPolicy,
  }) async {
    final attempted = <int>{};
    Object? firstError;
    StackTrace? firstStackTrace;

    while (true) {
      final commands = await _repository.pending(noteId: noteId);
      final remaining = [
        for (final command in commands)
          if (attempted.add(command.generation)) command,
      ];
      if (remaining.isEmpty) break;

      for (final command in remaining) {
        if (!await _repository.isCurrent(command.generation)) continue;
        if (!_gateway.supportsScheduling) {
          await _repository.acknowledge(command.generation);
          continue;
        }

        try {
          switch (command.operation) {
            case ReminderCommandOperation.schedule:
              final scheduledAt = command.scheduledAt;
              if (scheduledAt == null || !scheduledAt.isAfter(_now())) {
                await _gateway.cancel(command.noteId);
              } else {
                await _gateway.schedule(
                  command,
                  permissionPolicy: permissionPolicy,
                );
              }
            case ReminderCommandOperation.cancel:
              await _gateway.cancel(command.noteId);
          }
          if (await _repository.isCurrent(command.generation)) {
            await _repository.acknowledge(command.generation);
          }
        } catch (error, stackTrace) {
          if (await _repository.isCurrent(command.generation)) {
            firstError ??= error;
            firstStackTrace ??= stackTrace;
          }
        }
      }
    }

    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final start = _tail.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    final result = start.then<T>((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }
}
