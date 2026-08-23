import 'package:flutter_clean_notes/app/notification_service.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';

abstract interface class NoteReminderGateway {
  Future<void> schedule(Note note);

  Future<void> cancel(int id);
}

class NotificationNoteReminderGateway implements NoteReminderGateway {
  const NotificationNoteReminderGateway(this._notificationService);

  final NotificationService _notificationService;

  @override
  Future<void> schedule(Note note) {
    return _notificationService.scheduleReminder(note);
  }

  @override
  Future<void> cancel(int id) {
    return _notificationService.cancelReminder(id);
  }
}
