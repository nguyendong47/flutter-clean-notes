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
  int? getErrorAtCall;
  int getCalls = 0;
  Object? addError;
  int? addErrorAtCall;
  int addCalls = 0;
  Object? updateError;
  Object? deleteError;
  Object? statusError;
  Object? cleanupError;
  Object? removeTagError;
  int removeTagCalls = 0;

  List<Note> get notes => List<Note>.unmodifiable(_notes);

  Never _throw(Object error) => throw error;

  @override
  Future<List<Note>> getNotes() async {
    getCalls += 1;
    if (getError case final error?) _throw(error);
    if (getErrorAtCall == getCalls) {
      throw StateError('note refresh $getCalls failed');
    }
    return [..._notes];
  }

  @override
  Future<List<Note>> getNotesByStatus(NoteStatus status) async {
    getCalls += 1;
    if (getError case final error?) _throw(error);
    if (getErrorAtCall == getCalls) {
      throw StateError('note refresh $getCalls failed');
    }
    return _notes.where((note) => note.status == status).toList();
  }

  @override
  Future<int> addNote(Note note) async {
    addCalls += 1;
    if (addError case final error?) _throw(error);
    if (addErrorAtCall == addCalls) {
      throw StateError('import insert $addCalls failed');
    }
    final id = note.id ?? _nextId++;
    if (id >= _nextId) _nextId = id + 1;
    _notes.add(note.copyWith(id: id));
    return id;
  }

  @override
  Future<void> importNotes(List<Note> notes) async {
    final staged = <Note>[];
    var nextId = _nextId;
    for (final note in notes) {
      addCalls += 1;
      if (addError case final error?) _throw(error);
      if (addErrorAtCall == addCalls) {
        throw StateError('import insert $addCalls failed');
      }
      final id = note.id ?? nextId++;
      if (id >= nextId) nextId = id + 1;
      staged.add(note.copyWith(id: id));
    }
    _notes.addAll(staged);
    _nextId = nextId;
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
  Future<int> toggleNotePin(int id) async {
    if (updateError case final error?) _throw(error);
    final index = _notes.indexWhere((note) => note.id == id);
    if (index == -1) return 0;
    _notes[index] = _notes[index].copyWith(isPinned: !_notes[index].isPinned);
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

  @override
  Future<int> removeTag(String tag) async {
    removeTagCalls += 1;
    if (removeTagError case final error?) _throw(error);
    var changed = 0;
    final staged = [
      for (final note in _notes)
        if (note.tags.contains(tag))
          note.copyWith(
            tags: note.tags.where((candidate) => candidate != tag).toList(),
          )
        else
          note,
    ];
    for (var index = 0; index < _notes.length; index++) {
      if (!identical(staged[index], _notes[index])) changed += 1;
    }
    _notes
      ..clear()
      ..addAll(staged);
    return changed;
  }
}
