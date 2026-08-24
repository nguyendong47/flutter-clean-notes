import 'dart:async';

import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/note_reminder_gateway.dart';

class FakeNoteReminderGateway implements NoteReminderGateway {
  FakeNoteReminderGateway({
    this.supportsScheduling = true,
    List<String>? eventLog,
  }) : _eventLog = eventLog;

  final List<String>? _eventLog;
  @override
  final bool supportsScheduling;
  final List<Note> scheduled = [];
  final List<int> cancelled = [];
  int syncCalls = 0;
  final List<String> events = [];

  Object? scheduleError;
  Object? cancelError;
  Completer<void>? scheduleGate;
  Completer<void>? cancelGate;
  Completer<void>? syncGate;

  @override
  Future<void> schedule(Note note) async {
    scheduled.add(note.copyWith(tags: List<String>.unmodifiable(note.tags)));
    events.add('schedule:${note.id}');
    _eventLog?.add('schedule:${note.id}');
    final gate = scheduleGate;
    if (gate != null) await gate.future;
    final error = scheduleError;
    if (error != null) throw error;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    events.add('cancel:$id');
    _eventLog?.add('cancel:$id');
    final gate = cancelGate;
    if (gate != null) await gate.future;
    final error = cancelError;
    if (error != null) throw error;
  }

  @override
  Future<void> syncPending() async {
    syncCalls += 1;
    events.add('sync');
    _eventLog?.add('sync');
    final gate = syncGate;
    if (gate != null) await gate.future;
  }
}
