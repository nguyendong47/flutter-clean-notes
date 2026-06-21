import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';

abstract class NoteRepository {
  Future<List<Note>> getNotes();
  Future<int> addNote(Note note);
  Future<int> updateNote(Note note);
  Future<int> deleteNote(int id);
}
