import 'package:flutter/services.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/in_memory_note_repository.dart';
import '../../../helpers/note_fixtures.dart';

const _notificationsChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_notificationsChannel, (_) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_notificationsChannel, null);
  });

  test('loads active archived and trashed notes together', () async {
    final repository = InMemoryNoteRepository.seeded(sampleNotes);
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);

    final notes = await container.read(notesProvider.future);

    expect(notes, hasLength(sampleNotes.length));
    expect(notes.map((note) => note.status).toSet(), NoteStatus.values.toSet());
  });

  test(
    'derived providers expose home search status and legacy collections',
    () async {
      final repository = InMemoryNoteRepository.seeded(sampleNotes);
      final container = ProviderContainer(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      expect(
        container
            .read(notesByStatusProvider(NoteStatus.archived))
            .map((note) => note.id),
        [4],
      );
      expect(container.read(homeNotesProvider).map((note) => note.id), [
        1,
        2,
        3,
      ]);
      expect(container.read(homeTagsProvider), ['design', 'personal', 'work']);

      container.read(selectedTagProvider.notifier).select('work');
      expect(container.read(homeNotesProvider).map((note) => note.id), [1, 2]);

      container.read(selectedTagProvider.notifier).select(null);
      container.read(searchQueryProvider.notifier).setQuery('stationery');
      expect(container.read(searchResultsProvider).map((note) => note.id), [3]);

      container.read(searchQueryProvider.notifier).setQuery('');
      container.read(noteModeProvider.notifier).set(NoteMode.archived);
      expect(container.read(filteredNotesProvider).map((note) => note.id), [4]);
      expect(container.read(allTagsProvider), ['archive', 'work']);
      expect(
        container.read(notesProvider).value,
        hasLength(sampleNotes.length),
      );
    },
  );

  test(
    'preserves visible data surfaces an error and rethrows on failure',
    () async {
      final repository = InMemoryNoteRepository.seeded(sampleNotes);
      final container = ProviderContainer(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);

      final initial = await container.read(notesProvider.future);
      repository.updateError = StateError('write failed');

      await expectLater(
        container.read(notesProvider.notifier).togglePin(initial.first),
        throwsStateError,
      );

      expect(container.read(notesProvider).value, initial);
      expect(container.read(notesProvider).hasError, isTrue);
    },
  );

  test('adds and updates notes then refreshes the all-status state', () async {
    final repository = InMemoryNoteRepository.seeded(sampleNotes);
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(notesProvider.future);

    await container
        .read(notesProvider.notifier)
        .addNote(
          Note(
            title: 'New note',
            content: 'Created in the test',
            color: 0,
            createdAt: DateTime.utc(2026, 8, 20),
          ),
        );
    final added = repository.notes.singleWhere(
      (note) => note.title == 'New note',
    );
    await container
        .read(notesProvider.notifier)
        .updateNote(added.copyWith(title: 'Updated note'));

    expect(
      container.read(notesProvider).value!.map((note) => note.title),
      contains('Updated note'),
    );
    expect(
      container.read(notesProvider).value,
      hasLength(sampleNotes.length + 1),
    );
  });

  test('togglePin persists the inverse pin state', () async {
    final repository = InMemoryNoteRepository.seeded(sampleNotes);
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final initial = await container.read(notesProvider.future);

    await container.read(notesProvider.notifier).togglePin(initial.first);

    expect(
      repository.notes
          .singleWhere((note) => note.id == initial.first.id)
          .isPinned,
      isFalse,
    );
    expect(container.read(notesProvider).value, hasLength(sampleNotes.length));
  });

  test('import resets status and reminder before refreshing state', () async {
    final repository = InMemoryNoteRepository.seeded(sampleNotes);
    final existingIds = repository.notes.map((note) => note.id).toSet();
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(notesProvider.future);
    final imported = Note(
      id: 99,
      title: 'Imported note',
      content: 'From backup',
      color: 0,
      createdAt: DateTime.utc(2026, 8, 13),
      status: NoteStatus.archived,
      reminder: DateTime.utc(2026, 8, 21),
    );

    await container.read(notesProvider.notifier).importBackup([imported]);

    final stored = repository.notes.singleWhere(
      (note) => note.title == 'Imported note',
    );
    expect(stored.id, isNot(99));
    expect(stored.status, NoteStatus.active);
    expect(stored.reminder, isNull);
    expect(repository.notes.map((note) => note.id), containsAll(existingIds));
    expect(
      container.read(notesProvider).value!.map((note) => note.id),
      contains(stored.id),
    );
  });

  test('archive trash restore and delete mutate the full collection', () async {
    final repository = InMemoryNoteRepository.seeded(sampleNotes);
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(notesProvider.future);
    final note = repository.notes.singleWhere((candidate) => candidate.id == 2);

    await container.read(notesProvider.notifier).archiveNote(note);
    expect(_statusOf(repository, 2), NoteStatus.archived);

    await container
        .read(notesProvider.notifier)
        .trashNote(
          repository.notes.singleWhere((candidate) => candidate.id == 2),
        );
    expect(_statusOf(repository, 2), NoteStatus.trashed);

    await container
        .read(notesProvider.notifier)
        .restoreNote(
          repository.notes.singleWhere((candidate) => candidate.id == 2),
        );
    expect(_statusOf(repository, 2), NoteStatus.active);

    await container.read(notesProvider.notifier).deleteNote(2);
    expect(repository.notes.any((candidate) => candidate.id == 2), isFalse);
    expect(
      container.read(notesProvider).value,
      hasLength(repository.notes.length),
    );
  });

  test('cleanup removes only trashed notes older than thirty days', () async {
    final now = DateTime.utc(2026, 8, 19, 12);
    final oldTrash = Note(
      id: 50,
      title: 'Old trash',
      content: '',
      color: 0,
      createdAt: now.subtract(const Duration(days: 30, seconds: 1)),
      status: NoteStatus.trashed,
    );
    final boundaryTrash = Note(
      id: 51,
      title: 'Boundary trash',
      content: '',
      color: 0,
      createdAt: now.subtract(const Duration(days: 30)),
      status: NoteStatus.trashed,
    );
    final recentTrash = Note(
      id: 52,
      title: 'Recent trash',
      content: '',
      color: 0,
      createdAt: now.subtract(const Duration(days: 29)),
      status: NoteStatus.trashed,
    );
    final repository = InMemoryNoteRepository.seeded([
      sampleNote,
      oldTrash,
      boundaryTrash,
      recentTrash,
    ], now: () => now);
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(notesProvider.future);

    await container.read(notesProvider.notifier).cleanupTrash();

    expect(repository.notes.map((note) => note.id), [1, 51, 52]);
    expect(container.read(notesProvider).value!.map((note) => note.id), [
      1,
      51,
      52,
    ]);
  });
}

NoteStatus _statusOf(InMemoryNoteRepository repository, int id) {
  return repository.notes.singleWhere((note) => note.id == id).status;
}
