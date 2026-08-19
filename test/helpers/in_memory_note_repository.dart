import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/domain/repositories/note_repository.dart';

class InMemoryNoteRepository implements NoteRepository {
  InMemoryNoteRepository.seeded(
    Iterable<Note> notes, {
    DateTime Function()? now,
  }) : _notes = [...notes],
       _now = now ?? DateTime.now {
    for (final note in _notes) {
      final id = note.id;
      if (id != null && id >= _nextId) _nextId = id + 1;
    }
  }

  final List<Note> _notes;
  final DateTime Function() _now;
  int _nextId = 1;

  Object? getError;
  Object? addError;
  Object? updateError;
  Object? deleteError;
  Object? statusError;
  Object? cleanupError;

  List<Note> get notes => List<Note>.unmodifiable(_notes);

  Never _throw(Object error) => throw error;

  @override
  Future<List<Note>> getNotes() async {
    if (getError case final error?) _throw(error);
    return [..._notes];
  }

  @override
  Future<List<Note>> getNotesByStatus(NoteStatus status) async {
    if (getError case final error?) _throw(error);
    return _notes.where((note) => note.status == status).toList();
  }

  @override
  Future<int> addNote(Note note) async {
    if (addError case final error?) _throw(error);
    final id = note.id ?? _nextId++;
    if (id >= _nextId) _nextId = id + 1;
    _notes.add(note.copyWith(id: id));
    return id;
  }

  @override
  Future<int> updateNote(Note note) async {
    if (updateError case final error?) _throw(error);
    final index = _notes.indexWhere((candidate) => candidate.id == note.id);
    if (index == -1) return 0;
    _notes[index] = note;
    return 1;
  }

  @override
  Future<int> deleteNote(int id) async {
    if (deleteError case final error?) _throw(error);
    final before = _notes.length;
    _notes.removeWhere((note) => note.id == id);
    return before - _notes.length;
  }

  @override
  Future<int> setNoteStatus(int id, NoteStatus status) async {
    if (statusError case final error?) _throw(error);
    final index = _notes.indexWhere((note) => note.id == id);
    if (index == -1) return 0;
    _notes[index] = _notes[index].copyWith(status: status);
    return 1;
  }

  @override
  Future<int> cleanupTrash() async {
    if (cleanupError case final error?) _throw(error);
    final cutoff = _now().subtract(const Duration(days: 30));
    final before = _notes.length;
    _notes.removeWhere(
      (note) =>
          note.status == NoteStatus.trashed && note.createdAt.isBefore(cutoff),
    );
    return before - _notes.length;
  }
}
