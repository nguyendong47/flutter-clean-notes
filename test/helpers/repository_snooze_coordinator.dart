import 'package:flutter_clean_notes/features/notes/domain/repositories/reminder_outbox_repository.dart';
import 'package:flutter_clean_notes/features/notes/domain/services/reminder_coordinator.dart';

import 'in_memory_note_repository.dart';

final class RepositorySnoozeCoordinator implements ReminderSyncCoordinator {
  RepositorySnoozeCoordinator({
    required this.repository,
    required this.snoozedAt,
    this.afterCommitError,
  });

  final InMemoryNoteRepository repository;
  final DateTime snoozedAt;
  final Object? afterCommitError;

  @override
  Future<void> drain({
    int? noteId,
    ReminderPermissionPolicy permissionPolicy =
        ReminderPermissionPolicy.requestIfNeeded,
  }) async {}

  @override
  Future<void> reconcileAtStartup() async {}

  @override
  Future<bool> snooze({
    required int noteId,
    required int? expectedGeneration,
    required int delayMinutes,
  }) async {
    final note = repository.notes.singleWhere(
      (candidate) => candidate.id == noteId,
    );
    await repository.updateNote(note.copyWith(reminder: snoozedAt));
    if (afterCommitError case final error?) throw error;
    return true;
  }
}
