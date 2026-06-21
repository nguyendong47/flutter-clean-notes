import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/domain/repositories/note_repository.dart';

class NoteRepositoryImpl implements NoteRepository {
  final LocalNoteDataSource localDataSource;

  NoteRepositoryImpl(this.localDataSource);

  @override
  Future<List<Note>> getNotes() async {
    final noteModels = await localDataSource.getNotes();
    return noteModels; // NoteModel inherently extends Note
  }

  @override
  Future<int> addNote(Note note) async {
    final noteModel = NoteModel.fromEntity(note);
    return await localDataSource.addNote(noteModel);
  }

  @override
  Future<int> updateNote(Note note) async {
    final noteModel = NoteModel.fromEntity(note);
    return await localDataSource.updateNote(noteModel);
  }

  @override
  Future<int> deleteNote(int id) async {
    return await localDataSource.deleteNote(id);
  }
}
