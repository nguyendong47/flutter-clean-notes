import 'package:flutter_clean_notes/features/notes/domain/entities/reminder_command.dart';

abstract interface class ReminderOutboxRepository {
  Future<List<ReminderCommand>> pending({int? noteId});

  Future<bool> isCurrent(int generation);

  Future<bool> acknowledge(int generation);

  Future<ReminderCommand?> snooze({
    required int noteId,
    required int? expectedGeneration,
    required DateTime scheduledAt,
  });

  Future<void> reconcile({
    required List<PendingReminderNotification> pending,
    required DateTime now,
  });
}

enum ReminderPermissionPolicy { existingOnly, requestIfNeeded }

abstract interface class ReminderNotificationGateway {
  bool get supportsScheduling;

  Future<void> schedule(
    ReminderCommand command, {
    required ReminderPermissionPolicy permissionPolicy,
  });

  Future<void> cancel(int noteId);

  Future<List<PendingReminderNotification>> pendingNotifications();
}
