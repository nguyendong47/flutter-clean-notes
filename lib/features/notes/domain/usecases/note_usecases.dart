import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/domain/repositories/note_repository.dart';

class GetNotes {
  final NoteRepository repository;

  GetNotes(this.repository);

  Future<List<Note>> call() async {
    return repository.getNotes();
  }
}

class AddNote {
  final NoteRepository repository;

  AddNote(this.repository);

  Future<int> call(Note note) async {
    return repository.addNote(note);
  }
}

class UpdateNote {
  final NoteRepository repository;

  UpdateNote(this.repository);

  Future<int> call(Note note) async {
    return repository.updateNote(note);
  }
}

class DeleteNote {
  final NoteRepository repository;

  DeleteNote(this.repository);

  Future<int> call(int id) async {
    return repository.deleteNote(id);
  }
}

class GetNotesByStatus {
  final NoteRepository repository;

  GetNotesByStatus(this.repository);

  Future<List<Note>> call(NoteStatus status) async {
    return repository.getNotesByStatus(status);
  }
}

class SetNoteStatus {
  final NoteRepository repository;

  SetNoteStatus(this.repository);

  Future<int> call(int id, NoteStatus status) async {
    return repository.setNoteStatus(id, status);
  }
}

class CleanupTrash {
  final NoteRepository repository;

  CleanupTrash(this.repository);

  Future<int> call() async {
    return repository.cleanupTrash();
  }
}
