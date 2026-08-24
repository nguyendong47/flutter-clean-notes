import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/reminder_command.dart';
import 'package:flutter_clean_notes/features/notes/domain/repositories/reminder_outbox_repository.dart';

final class ReminderOutboxRepositoryImpl implements ReminderOutboxRepository {
  const ReminderOutboxRepositoryImpl(this._localDataSource);

  final ReminderOutboxDataSource _localDataSource;

  @override
  Future<bool> acknowledge(int generation) {
    return _localDataSource.acknowledgeReminderCommand(generation);
  }

  @override
  Future<bool> isCurrent(int generation) {
    return _localDataSource.isReminderCommandCurrent(generation);
  }

  @override
  Future<List<ReminderCommand>> pending({int? noteId}) {
    return _localDataSource.pendingReminderCommands(noteId: noteId);
  }

  @override
  Future<void> reconcile({
    required List<PendingReminderNotification> pending,
    required DateTime now,
  }) {
    return _localDataSource.reconcileReminderNotifications(
      pending: pending,
      now: now,
    );
  }

  @override
  Future<ReminderCommand?> snooze({
    required int noteId,
    required int? expectedGeneration,
    required DateTime scheduledAt,
  }) {
    return _localDataSource.snoozeReminder(
      noteId: noteId,
      expectedGeneration: expectedGeneration,
      scheduledAt: scheduledAt,
    );
  }
}
