import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:flutter_clean_notes/app/app_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/note_reminder_gateway.dart';

part 'note_reminder_gateway_provider.g.dart';

@Riverpod(keepAlive: true)
NoteReminderGateway noteReminderGateway(Ref ref) {
  return NotificationNoteReminderGateway(
    ref.watch(notificationServiceProvider),
  );
}
