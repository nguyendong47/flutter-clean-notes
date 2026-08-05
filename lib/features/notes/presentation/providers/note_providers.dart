import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:flutter_clean_notes/app/notification_service.dart';
import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
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
GetNotesByStatus getNotesByStatusUsecase(Ref ref) {
  final repository = ref.watch(noteRepositoryProvider);
  return GetNotesByStatus(repository);
}

@riverpod
SetNoteStatus setNoteStatusUsecase(Ref ref) {
  final repository = ref.watch(noteRepositoryProvider);
  return SetNoteStatus(repository);
}

@riverpod
CleanupTrash cleanupTrashUsecase(Ref ref) {
  final repository = ref.watch(noteRepositoryProvider);
  return CleanupTrash(repository);
}

enum NoteMode { active, archived, trashed }

@riverpod
class NoteModeNotifier extends _$NoteModeNotifier {
  @override
  NoteMode build() => NoteMode.active;

  void set(NoteMode mode) => state = mode;
}

@riverpod
class SearchQuery extends _$SearchQuery {
  @override
  String build() => '';

  void setQuery(String query) => state = query;
}

@riverpod
class SelectedTag extends _$SelectedTag {
  @override
  String? build() => null;

  void select(String? tag) => state = tag;
}

enum NoteSort { newest, oldest, titleAZ, titleZA }

@riverpod
class SortOrder extends _$SortOrder {
  @override
  NoteSort build() => NoteSort.newest;

  void set(NoteSort order) => state = order;
}

@riverpod
List<String> allTags(Ref ref) {
  final notes = ref.watch(notesProvider).value ?? const <Note>[];
  final tags = <String>{};
  for (final note in notes) {
    tags.addAll(note.tags);
  }
  final sorted = tags.toList()..sort();
  return sorted;
}

@riverpod
List<Note> filteredNotes(Ref ref) {
  final notes = ref.watch(notesProvider).value ?? const <Note>[];
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final tag = ref.watch(selectedTagProvider);
  final sort = ref.watch(sortOrderProvider);

  var result = notes;
  if (query.isNotEmpty) {
    result = result
        .where(
          (note) =>
              note.title.toLowerCase().contains(query) ||
              note.content.toLowerCase().contains(query) ||
              note.tags.any((t) => t.toLowerCase().contains(query)),
        )
        .toList();
  }
  if (tag != null) {
    result = result.where((note) => note.tags.contains(tag)).toList();
  }
  switch (sort) {
    case NoteSort.newest:
      result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      break;
    case NoteSort.oldest:
      result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      break;
    case NoteSort.titleAZ:
      result.sort((a, b) => a.title.compareTo(b.title));
      break;
    case NoteSort.titleZA:
      result.sort((a, b) => b.title.compareTo(a.title));
      break;
  }
  return result;
}

@riverpod
class NotesNotifier extends _$NotesNotifier {
  @override
  FutureOr<List<Note>> build() async {
    final mode = ref.watch(noteModeProvider);
    return _fetchNotes(mode);
  }

  NoteStatus _statusFor(NoteMode mode) {
    return switch (mode) {
      NoteMode.active => NoteStatus.active,
      NoteMode.archived => NoteStatus.archived,
      NoteMode.trashed => NoteStatus.trashed,
    };
  }

  Future<List<Note>> _fetchNotes(NoteMode mode) async {
    final getNotes = ref.read(getNotesByStatusUsecaseProvider);
    return await getNotes(_statusFor(mode));
  }

  Future<void> addNote(Note note) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final id = await ref.read(addNoteUsecaseProvider)(note);
      if (note.reminder != null) {
        await NotificationService().scheduleReminder(note.copyWith(id: id));
      }
      return _fetchNotes(ref.read(noteModeProvider));
    });
  }

  Future<void> updateNote(Note note) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(updateNoteUsecaseProvider)(note);
      if (note.id != null) {
        await NotificationService().cancelReminder(note.id!);
        if (note.reminder != null) {
          await NotificationService().scheduleReminder(note);
        }
      }
      return _fetchNotes(ref.read(noteModeProvider));
    });
  }

  Future<void> importBackup(List<Map<String, dynamic>> data) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      // Note: Consider merging with existing notes rather than replacing
      for (final json in data) {
        final note = NoteModel.fromJson(json).copyWith(
          status: NoteStatus.active, // Imported notes start as active
          reminder: null, // Reset reminder on import
        );
        await ref.read(addNoteUsecaseProvider)(note);
      }
      return _fetchNotes(ref.read(noteModeProvider));
    });
  }

  Future<void> togglePin(Note note) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(updateNoteUsecaseProvider)(
        note.copyWith(isPinned: !note.isPinned),
      );
      return _fetchNotes(ref.read(noteModeProvider));
    });
  }

  Future<void> archiveNote(Note note) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(setNoteStatusUsecaseProvider)(
        note.id!,
        NoteStatus.archived,
      );
      return _fetchNotes(ref.read(noteModeProvider));
    });
  }

  Future<void> trashNote(Note note) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(setNoteStatusUsecaseProvider)(
        note.id!,
        NoteStatus.trashed,
      );
      return _fetchNotes(ref.read(noteModeProvider));
    });
  }

  Future<void> restoreNote(Note note) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(setNoteStatusUsecaseProvider)(note.id!, NoteStatus.active);
      return _fetchNotes(ref.read(noteModeProvider));
    });
  }

  Future<void> deleteNote(int id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(deleteNoteUsecaseProvider)(id);
      await NotificationService().cancelReminder(id);
      return _fetchNotes(ref.read(noteModeProvider));
    });
  }

  Future<void> cleanupTrash() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      await ref.read(cleanupTrashUsecaseProvider)();
      return _fetchNotes(ref.read(noteModeProvider));
    });
  }
}
