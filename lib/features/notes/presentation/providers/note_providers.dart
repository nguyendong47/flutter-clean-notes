import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/repositories/note_repository_impl.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/domain/repositories/note_repository.dart';
import 'package:flutter_clean_notes/features/notes/domain/usecases/note_usecases.dart';

part 'note_providers.g.dart';

@riverpod
LocalNoteDataSource localNoteDataSource(Ref ref) {
  return LocalNoteDataSourceImpl();
}

@riverpod
NoteRepository noteRepository(Ref ref) {
  final localDataSource = ref.watch(localNoteDataSourceProvider);
  return NoteRepositoryImpl(localDataSource);
}

@riverpod
GetNotes getNotesUsecase(Ref ref) {
  final repository = ref.watch(noteRepositoryProvider);
  return GetNotes(repository);
}

@riverpod
AddNote addNoteUsecase(Ref ref) {
  final repository = ref.watch(noteRepositoryProvider);
  return AddNote(repository);
}

@riverpod
UpdateNote updateNoteUsecase(Ref ref) {
  final repository = ref.watch(noteRepositoryProvider);
  return UpdateNote(repository);
}

@riverpod
DeleteNote deleteNoteUsecase(Ref ref) {
  final repository = ref.watch(noteRepositoryProvider);
  return DeleteNote(repository);
}

@riverpod
class NotesNotifier extends _$NotesNotifier {
  @override
  FutureOr<List<Note>> build() async {
    return _fetchNotes();
  }

  Future<List<Note>> _fetchNotes() async {
    final getNotes = ref.read(getNotesUsecaseProvider);
    return await getNotes();
  }

  Future<void> addNote(Note note) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(addNoteUsecaseProvider)(note);
      return _fetchNotes();
    });
  }

  Future<void> updateNote(Note note) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(updateNoteUsecaseProvider)(note);
      return _fetchNotes();
    });
  }

  Future<void> deleteNote(int id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(deleteNoteUsecaseProvider)(id);
      return _fetchNotes();
    });
  }
}
