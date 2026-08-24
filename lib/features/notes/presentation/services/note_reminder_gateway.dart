import 'package:flutter_clean_notes/app/notification_service.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';

abstract interface class NoteReminderGateway {
  bool get supportsScheduling;

  Future<void> schedule(Note note);

  Future<void> cancel(int id);

  Future<void> syncPending();
}

class NotificationNoteReminderGateway implements NoteReminderGateway {
  const NotificationNoteReminderGateway(
    this._notificationService, {
    Future<void> Function({int? noteId})? synchronize,
  }) : _synchronize = synchronize;

  final NotificationService _notificationService;
  final Future<void> Function({int? noteId})? _synchronize;

  @override
  bool get supportsScheduling =>
      _notificationService.supportsReminderScheduling;

  @override
  Future<void> schedule(Note note) {
    final synchronize = _synchronize;
    if (synchronize != null) return synchronize(noteId: note.id);
    return _notificationService.scheduleReminder(note);
  }

  @override
  Future<void> cancel(int id) {
    final synchronize = _synchronize;
    if (synchronize != null) return synchronize(noteId: id);
    return _notificationService.cancelReminder(id);
  }

  @override
  Future<void> syncPending() {
    final synchronize = _synchronize;
    return synchronize == null ? Future<void>.value() : synchronize();
  }
}
