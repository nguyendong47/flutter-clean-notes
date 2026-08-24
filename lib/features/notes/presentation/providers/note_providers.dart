import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/repositories/note_repository_impl.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/domain/repositories/note_repository.dart';
import 'package:flutter_clean_notes/features/notes/domain/usecases/note_usecases.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_filters.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_reminder_gateway_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/invalid_note_reminder_exception.dart';
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
ToggleNotePin toggleNotePinUsecase(Ref ref) {
  final repository = ref.watch(noteRepositoryProvider);
  return ToggleNotePin(repository);
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
  Future<void> _mutationQueue = Future<void>.value();
  final Map<int, Future<void>> _reminderCancellationRetries = {};

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

  Future<List<Note>> readPersistedNotes() {
    final keepAlive = ref.keepAlive();
    final result = _mutationQueue.then((_) => _fetchAllNotes());
    _mutationQueue = result.then<void>(
      (_) => keepAlive.close(),
      onError: (Object _, StackTrace _) => keepAlive.close(),
    );
    return result;
  }

  Future<void> _mutate(Future<void> Function() operation) {
    final keepAlive = ref.keepAlive();
    final result = _mutationQueue.then((_) async {
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
    });
    _mutationQueue = result.then<void>(
      (_) => keepAlive.close(),
      onError: (Object _, StackTrace _) => keepAlive.close(),
    );
    return result;
  }

  Future<void> addNote(Note note, {DateTime Function()? now}) async {
    final requestedNote = _persistedSnapshot(note);
    Note? persistedNote;
    try {
      await _mutate(() async {
        final reminder = requestedNote.reminder;
        final currentTime = now?.call() ?? DateTime.now();
        if (reminder != null && !reminder.isAfter(currentTime)) {
          throw const InvalidNoteReminderException();
        }
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

  Future<void> updateNote(
    Note note, {
    DateTime Function()? now,
    DateTime? persistedReminder,
    bool forceReminderReconciliation = false,
  }) async {
    final requestedNote = _persistedSnapshot(note);
    var reminderBeforeUpdate = persistedReminder;
    if (reminderBeforeUpdate == null) {
      for (final currentNote in state.value ?? const <Note>[]) {
        if (currentNote.id == requestedNote.id) {
          reminderBeforeUpdate = currentNote.reminder;
          break;
        }
      }
    }
    Note? persistedNote;
    try {
      await _mutate(() async {
        final reminder = requestedNote.reminder;
        final currentTime = now?.call() ?? DateTime.now();
        final reminderChanged = reminder != reminderBeforeUpdate;
        final shouldReconcileReminder =
            reminderChanged || forceReminderReconciliation;
        if (reminder != null &&
            shouldReconcileReminder &&
            !reminder.isAfter(currentTime)) {
          throw const InvalidNoteReminderException();
        }
        final updated = await ref.read(updateNoteUsecaseProvider)(
          requestedNote,
        );
        if (updated != 1) {
          throw StateError('The note no longer exists.');
        }
        persistedNote = requestedNote;
        final id = requestedNote.id;
        if (id != null && shouldReconcileReminder) {
          final gateway = ref.read(noteReminderGatewayProvider);
          await gateway.cancel(id);
          if (reminder != null && reminder.isAfter(currentTime)) {
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
    final keepAlive = ref.keepAlive();
    final result = _mutationQueue.then((_) {
      return _importAndRefresh(() async {
        await ref.read(importNotesUsecaseProvider)(notes);
      });
    });
    _mutationQueue = result.then<void>(
      (_) => keepAlive.close(),
      onError: (Object _, StackTrace _) => keepAlive.close(),
    );
    return result;
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

  Future<void> _mutateOneExistingNote(
    int? noteId,
    Future<int> Function() operation, {
    Future<void> Function()? afterCommit,
    PersistedNoteMutationFailureKind afterCommitFailureKind =
        PersistedNoteMutationFailureKind.refresh,
  }) {
    StateError? missingNoteError;
    PersistedNoteMutationException? afterCommitError;
    final keepAlive = ref.keepAlive();
    final mutation = _mutate(() async {
      final affectedRows = await operation();
      if (affectedRows != 1) {
        final error = StateError('The note no longer exists.');
        missingNoteError = error;
        throw error;
      }
      try {
        await afterCommit?.call();
      } catch (error, stackTrace) {
        final persistedError = PersistedNoteMutationException(
          cause: error,
          causeStackTrace: stackTrace,
          kind: afterCommitFailureKind,
        );
        afterCommitError = persistedError;
        Error.throwWithStackTrace(persistedError, stackTrace);
      }
    });
    final result = mutation.onError((Object error, StackTrace stackTrace) {
      final removeMissingNote = identical(error, missingNoteError);
      final removeCommittedNote = identical(error, afterCommitError);
      if ((removeMissingNote || removeCommittedNote) && noteId != null) {
        final cachedNotes = state.value;
        if (cachedNotes != null) {
          state = AsyncData([
            for (final note in cachedNotes)
              if (note.id != noteId) note,
          ]);
        }
      }
      Error.throwWithStackTrace(error, stackTrace);
    });
    _mutationQueue = result.then<void>(
      (_) => keepAlive.close(),
      onError: (Object _, StackTrace _) => keepAlive.close(),
    );
    return result;
  }

  Future<void> togglePin(Note note) {
    final noteId = note.id;
    return _mutateOneExistingNote(noteId, () {
      if (noteId == null) return Future.value(0);
      return ref.read(toggleNotePinUsecaseProvider)(noteId);
    });
  }

  Future<void> archiveNote(Note note) {
    return _mutateOneExistingNote(note.id, () {
      return ref.read(setNoteStatusUsecaseProvider)(
        note.id!,
        NoteStatus.archived,
      );
    });
  }

  Future<void> trashNote(Note note) {
    return _mutateOneExistingNote(note.id, () {
      return ref.read(setNoteStatusUsecaseProvider)(
        note.id!,
        NoteStatus.trashed,
      );
    });
  }

  Future<void> restoreNote(Note note) {
    return _mutateOneExistingNote(note.id, () {
      return ref.read(setNoteStatusUsecaseProvider)(
        note.id!,
        NoteStatus.active,
      );
    });
  }

  Future<void> deleteNote(int id) {
    return _mutateOneExistingNote(
      id,
      () => ref.read(deleteNoteUsecaseProvider)(id),
      afterCommit: () => ref.read(noteReminderGatewayProvider).cancel(id),
      afterCommitFailureKind:
          PersistedNoteMutationFailureKind.reminderCancellation,
    );
  }

  Future<void> retryReminderCancellation(int id) {
    final pending = _reminderCancellationRetries[id];
    if (pending != null) return pending;

    final keepAlive = ref.keepAlive();
    late final Future<void> retry;
    retry =
        Future<void>.sync(
          () => ref.read(noteReminderGatewayProvider).cancel(id),
        ).whenComplete(() {
          if (identical(_reminderCancellationRetries[id], retry)) {
            _reminderCancellationRetries.remove(id);
          }
          keepAlive.close();
        });
    _reminderCancellationRetries[id] = retry;
    return retry;
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
