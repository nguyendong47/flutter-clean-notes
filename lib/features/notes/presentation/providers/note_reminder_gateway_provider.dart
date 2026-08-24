import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:flutter_clean_notes/app/app_providers.dart';
import 'package:flutter_clean_notes/features/notes/data/repositories/reminder_outbox_repository_impl.dart';
import 'package:flutter_clean_notes/features/notes/domain/repositories/reminder_outbox_repository.dart';
import 'package:flutter_clean_notes/features/notes/domain/services/reminder_coordinator.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/local_note_datasource_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/note_reminder_gateway.dart';

part 'note_reminder_gateway_provider.g.dart';

@Riverpod(keepAlive: true)
ReminderOutboxRepository reminderOutboxRepository(Ref ref) {
  return ReminderOutboxRepositoryImpl(ref.watch(localNoteDataSourceProvider));
}

@Riverpod(keepAlive: true)
ReminderSyncCoordinator reminderCoordinator(Ref ref) {
  return ReminderCoordinator(
    repository: ref.watch(reminderOutboxRepositoryProvider),
    gateway: ref.watch(notificationServiceProvider),
  );
}

@Riverpod(keepAlive: true)
NoteReminderGateway noteReminderGateway(Ref ref) {
  final coordinator = ref.watch(reminderCoordinatorProvider);
  return NotificationNoteReminderGateway(
    ref.watch(notificationServiceProvider),
    synchronize: ({noteId}) => coordinator.drain(noteId: noteId),
  );
}
