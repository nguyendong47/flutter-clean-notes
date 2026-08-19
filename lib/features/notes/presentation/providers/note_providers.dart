import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:flutter_clean_notes/app/notification_service.dart';
import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_clean_notes/features/notes/data/repositories/note_repository_impl.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/domain/repositories/note_repository.dart';
import 'package:flutter_clean_notes/features/notes/domain/usecases/note_usecases.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_filters.dart';

export 'package:flutter_clean_notes/features/notes/presentation/providers/note_filters.dart'
    show NoteSort;

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

@riverpod
class SortOrder extends _$SortOrder {
  @override
  NoteSort build() => NoteSort.newest;

  void set(NoteSort order) => state = order;
}

@riverpod
List<Note> notesByStatus(Ref ref, NoteStatus status) {
  final notes = ref.watch(notesProvider).value ?? const <Note>[];
  return notes.where((note) => note.status == status).toList();
}

@riverpod
List<Note> homeNotes(Ref ref) {
  final notes = ref.watch(notesProvider).value ?? const <Note>[];
  return filterNotes(
    notes: notes,
    status: NoteStatus.active,
    tag: ref.watch(selectedTagProvider),
    sort: ref.watch(sortOrderProvider),
  );
}

@riverpod
List<String> homeTags(Ref ref) {
  return _sortedTags(ref.watch(notesByStatusProvider(NoteStatus.active)));
}

@riverpod
List<Note> searchResults(Ref ref) {
  final notes = ref.watch(notesProvider).value ?? const <Note>[];
  return filterNotes(
    notes: notes,
    status: NoteStatus.active,
    query: ref.watch(searchQueryProvider),
    tag: ref.watch(selectedTagProvider),
    sort: ref.watch(sortOrderProvider),
  );
}

@riverpod
List<String> allTags(Ref ref) {
  final status = _statusForMode(ref.watch(noteModeProvider));
  return _sortedTags(ref.watch(notesByStatusProvider(status)));
}

List<String> _sortedTags(List<Note> notes) {
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
  return filterNotes(
    notes: notes,
    status: _statusForMode(ref.watch(noteModeProvider)),
    query: ref.watch(searchQueryProvider),
    tag: ref.watch(selectedTagProvider),
    sort: ref.watch(sortOrderProvider),
  );
}

NoteStatus _statusForMode(NoteMode mode) {
  return switch (mode) {
    NoteMode.active => NoteStatus.active,
    NoteMode.archived => NoteStatus.archived,
    NoteMode.trashed => NoteStatus.trashed,
  };
}

@riverpod
class NotesNotifier extends _$NotesNotifier {
  @override
  FutureOr<List<Note>> build() async {
    return _fetchAllNotes();
  }

  Future<List<Note>> _fetchAllNotes() async {
    final getNotes = ref.read(getNotesByStatusUsecaseProvider);
    final notes = <Note>[];
    for (final status in NoteStatus.values) {
      notes.addAll(await getNotes(status));
    }
    return notes;
  }

  Future<void> _mutate(Future<void> Function() operation) async {
    try {
      await operation();
      state = AsyncData(await _fetchAllNotes());
    } catch (error, stackTrace) {
      state = AsyncError<List<Note>>(error, stackTrace);
      rethrow;
    }
  }

  Future<void> addNote(Note note) {
    return _mutate(() async {
      final id = await ref.read(addNoteUsecaseProvider)(note);
      if (note.reminder != null) {
        await NotificationService().scheduleReminder(note.copyWith(id: id));
      }
    });
  }

  Future<void> updateNote(Note note) {
    return _mutate(() async {
      await ref.read(updateNoteUsecaseProvider)(note);
      if (note.id != null) {
        await NotificationService().cancelReminder(note.id!);
        if (note.reminder != null) {
          await NotificationService().scheduleReminder(note);
        }
      }
    });
  }

  Future<void> importBackup(List<Map<String, dynamic>> data) {
    return _mutate(() async {
      // Note: Consider merging with existing notes rather than replacing
      for (final json in data) {
        final note = NoteModel.fromJson(json).copyWith(
          id: null, // Let the destination database allocate a fresh ID
          status: NoteStatus.active, // Imported notes start as active
          reminder: null, // Reset reminder on import
        );
        await ref.read(addNoteUsecaseProvider)(note);
      }
    });
  }

  Future<void> togglePin(Note note) {
    return _mutate(() async {
      await ref.read(updateNoteUsecaseProvider)(
        note.copyWith(isPinned: !note.isPinned),
      );
    });
  }

  Future<void> archiveNote(Note note) {
    return _mutate(() async {
      await ref.read(setNoteStatusUsecaseProvider)(
        note.id!,
        NoteStatus.archived,
      );
    });
  }

  Future<void> trashNote(Note note) {
    return _mutate(() async {
      await ref.read(setNoteStatusUsecaseProvider)(
        note.id!,
        NoteStatus.trashed,
      );
    });
  }

  Future<void> restoreNote(Note note) {
    return _mutate(() async {
      await ref.read(setNoteStatusUsecaseProvider)(note.id!, NoteStatus.active);
    });
  }

  Future<void> deleteNote(int id) {
    return _mutate(() async {
      await ref.read(deleteNoteUsecaseProvider)(id);
      await NotificationService().cancelReminder(id);
    });
  }

  Future<void> cleanupTrash() {
    return _mutate(() async {
      await ref.read(cleanupTrashUsecaseProvider)();
    });
  }
}
