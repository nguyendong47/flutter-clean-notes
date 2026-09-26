import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_clean_notes/features/notes/data/repositories/audio_attachment_repository.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/domain/repositories/note_repository.dart';

class NoteRepositoryImpl implements NoteRepository {
  final LocalNoteDataSource localDataSource;
  final AudioAttachmentRepository _audioAttachmentRepository;

  NoteRepositoryImpl(
    this.localDataSource, {
    required AudioAttachmentRepository audioAttachmentRepository,
  }) : _audioAttachmentRepository = audioAttachmentRepository;

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
  Future<void> importNotes(List<Note> notes) async {
    final noteModels = notes.map(NoteModel.fromEntity).toList(growable: false);
    await localDataSource.importNotes(noteModels);
  }

  @override
  Future<int> updateNote(Note note) async {
    final noteModel = NoteModel.fromEntity(note);
    return await localDataSource.updateNote(noteModel);
  }

  @override
  Future<int> deleteNote(int id) async {
    final deleted = await localDataSource.deleteNote(id);
    if (deleted == 1) {
      try {
        await _audioAttachmentRepository.deleteAttachmentsForNote(id);
      } catch (e) {
        // A secondary-cleanup failure must never make note deletion itself
        // fail from the caller's point of view - the note is already gone.
        debugPrint('audio attachment cleanup failed for note $id: $e');
      }
    }
    return deleted;
  }

  @override
  Future<List<Note>> getNotesByStatus(NoteStatus status) async {
    final noteModels = await localDataSource.getNotesByStatus(status.index);
    return noteModels;
  }

  @override
  Future<int> setNoteStatus(int id, NoteStatus status) async {
    return await localDataSource.setNoteStatus(id, status.index);
  }

  @override
  Future<int> toggleNotePin(int id) async {
    return localDataSource.toggleNotePin(id);
  }

  @override
  Future<int> cleanupTrash() async {
    return await localDataSource.cleanupTrash();
  }

  @override
  Future<int> removeTag(String tag) async {
    return localDataSource.removeTag(tag);
  }
}
