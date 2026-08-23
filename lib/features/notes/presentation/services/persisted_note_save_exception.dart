import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';

/// A save failed only after the repository had already persisted this note.
class PersistedNoteSaveException implements Exception {
  PersistedNoteSaveException({
    required Note persistedNote,
    required this.cause,
    required this.causeStackTrace,
  }) : persistedNote = persistedNote.copyWith(
         tags: List<String>.unmodifiable(persistedNote.tags),
       );

  final Note persistedNote;
  final Object cause;
  final StackTrace causeStackTrace;

  @override
  String toString() {
    return 'PersistedNoteSaveException(${persistedNote.id}): $cause';
  }
}
