import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/repositories/note_repository_impl.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/domain/repositories/note_repository.dart';
import 'package:flutter_clean_notes/features/notes/domain/usecases/note_usecases.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_filters.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_reminder_gateway_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/persisted_note_mutation_exception.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/persisted_note_save_exception.dart';

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
ImportNotes importNotesUsecase(Ref ref) {
  final repository = ref.watch(noteRepositoryProvider);
  return ImportNotes(repository);
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

@riverpod
RemoveTag removeTagUsecase(Ref ref) {
  final repository = ref.watch(noteRepositoryProvider);
  return RemoveTag(repository);
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

class TagUsage {
  const TagUsage({required this.tag, required this.count});

  final String tag;
  final int count;
}

@riverpod
List<TagUsage> tagUsage(Ref ref) {
  final notes = ref.watch(notesProvider).value ?? const <Note>[];
  final counts = <String, int>{};
  for (final note in notes) {
    for (final tag in note.tags.toSet()) {
      if (tag.trim().isEmpty) continue;
      counts.update(tag, (count) => count + 1, ifAbsent: () => 1);
    }
  }
  final tags = counts.keys.toList()..sort();
  return [for (final tag in tags) TagUsage(tag: tag, count: counts[tag]!)];
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
    final previous = state;
    state = const AsyncLoading<List<Note>>();
    try {
      await operation();
    } catch (error, stackTrace) {
      state = previous;
      Error.throwWithStackTrace(error, stackTrace);
    }

    try {
      state = AsyncData(await _fetchAllNotes());
    } catch (error, stackTrace) {
      state = AsyncError<List<Note>>(error, stackTrace);
      Error.throwWithStackTrace(
        PersistedNoteMutationException(
          cause: error,
          causeStackTrace: stackTrace,
        ),
        stackTrace,
      );
    }
  }

  Future<void> addNote(Note note) async {
    final requestedNote = _persistedSnapshot(note);
    Note? persistedNote;
    try {
      await _mutate(() async {
        final id = await ref.read(addNoteUsecaseProvider)(requestedNote);
        persistedNote = requestedNote.copyWith(id: id);
        if (requestedNote.reminder != null) {
          await ref.read(noteReminderGatewayProvider).schedule(persistedNote!);
        }
      });
    } catch (error, stackTrace) {
      final checkpoint = persistedNote;
      if (checkpoint != null) {
        Error.throwWithStackTrace(
          PersistedNoteSaveException(
            persistedNote: checkpoint,
            cause: error,
            causeStackTrace: stackTrace,
          ),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> updateNote(Note note) async {
    final requestedNote = _persistedSnapshot(note);
    Note? persistedNote;
    try {
      await _mutate(() async {
        final updated = await ref.read(updateNoteUsecaseProvider)(
          requestedNote,
        );
        if (updated != 1) {
          throw StateError('The note no longer exists.');
        }
        persistedNote = requestedNote;
        final id = requestedNote.id;
        if (id != null) {
          final gateway = ref.read(noteReminderGatewayProvider);
          await gateway.cancel(id);
          if (requestedNote.reminder != null) {
            await gateway.schedule(persistedNote!);
          }
        }
      });
    } catch (error, stackTrace) {
      final checkpoint = persistedNote;
      if (checkpoint != null) {
        Error.throwWithStackTrace(
          PersistedNoteSaveException(
            persistedNote: checkpoint,
            cause: error,
            causeStackTrace: stackTrace,
          ),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> importBackup(List<Note> notes) {
    return _importAndRefresh(() async {
      await ref.read(importNotesUsecaseProvider)(notes);
    });
  }

  Future<void> _importAndRefresh(Future<void> Function() import) async {
    try {
      await import();
    } catch (error, stackTrace) {
      state = AsyncError<List<Note>>(error, stackTrace);
      rethrow;
    }

    try {
      state = AsyncData(await _fetchAllNotes());
    } catch (error, stackTrace) {
      // The transaction has already committed. Keep the cached list available
      // and do not turn a refresh issue into a retryable import failure.
      state = AsyncError<List<Note>>(error, stackTrace);
    }
  }

  Future<void> removeTag(String tag) async {
    await _mutate(() async {
      await ref.read(removeTagUsecaseProvider)(tag);
    });
    if (ref.read(selectedTagProvider) == tag) {
      ref.read(selectedTagProvider.notifier).select(null);
    }
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
      await ref.read(noteReminderGatewayProvider).cancel(id);
    });
  }

  Future<void> cleanupTrash() {
    return _mutate(() async {
      await ref.read(cleanupTrashUsecaseProvider)();
    });
  }
}

Note _persistedSnapshot(Note note) {
  return note.copyWith(tags: List<String>.unmodifiable(note.tags));
}
