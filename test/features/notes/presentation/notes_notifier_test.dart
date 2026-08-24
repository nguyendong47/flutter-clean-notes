import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_reminder_gateway_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/invalid_note_reminder_exception.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/persisted_note_mutation_exception.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/persisted_note_save_exception.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_note_reminder_gateway.dart';
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

  final missingTargetMutations =
      <
        ({
          String name,
          Future<void> Function(NotesNotifier notifier, Note note) run,
        })
      >[
        (name: 'togglePin', run: (notifier, note) => notifier.togglePin(note)),
        (
          name: 'archiveNote',
          run: (notifier, note) => notifier.archiveNote(note),
        ),
        (name: 'trashNote', run: (notifier, note) => notifier.trashNote(note)),
        (
          name: 'restoreNote',
          run: (notifier, note) => notifier.restoreNote(note),
        ),
      ];

  for (final mutation in missingTargetMutations) {
    test(
      '${mutation.name} rejects a stale note without refreshing cached data',
      () async {
        final repository = InMemoryNoteRepository.seeded(sampleNotes);
        final container = ProviderContainer(
          overrides: [noteRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);
        final initial = await container.read(notesProvider.future);
        final staleNote = initial.first;
        await repository.deleteNote(staleNote.id!);
        final persistedNotes = repository.notes;
        final refreshCalls = repository.getCalls;

        await expectLater(
          mutation.run(container.read(notesProvider.notifier), staleNote),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'The note no longer exists.',
            ),
          ),
        );

        final failedState = container.read(notesProvider);
        expect(failedState, isA<AsyncData<List<Note>>>());
        expect(
          failedState.requireValue.map((note) => note.id),
          initial
              .where((note) => note.id != staleNote.id)
              .map((note) => note.id),
        );
        expect(failedState.hasError, isFalse);
        expect(repository.notes, persistedNotes);
        expect(repository.getCalls, refreshCalls);
      },
    );
  }

  test(
    'deleteNote rejects a missing note before cancelling its reminder',
    () async {
      final repository = InMemoryNoteRepository.seeded(sampleNotes);
      final gateway = FakeNoteReminderGateway();
      final container = _container(repository, gateway);
      addTearDown(container.dispose);
      final initial = await container.read(notesProvider.future);
      final staleNote = initial.first;
      await repository.deleteNote(staleNote.id!);
      final persistedNotes = repository.notes;
      final refreshCalls = repository.getCalls;

      await expectLater(
        container.read(notesProvider.notifier).deleteNote(staleNote.id!),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'The note no longer exists.',
          ),
        ),
      );

      final failedState = container.read(notesProvider);
      expect(failedState, isA<AsyncData<List<Note>>>());
      expect(
        failedState.requireValue.map((note) => note.id),
        initial.where((note) => note.id != staleNote.id).map((note) => note.id),
      );
      expect(failedState.hasError, isFalse);
      expect(repository.notes, persistedNotes);
      expect(repository.getCalls, refreshCalls);
      expect(gateway.events, isEmpty);
    },
  );

  test(
    'missing-row eviction precedes the next queued mutation rollback',
    () async {
      final secondFailure = StateError('second write failed');
      final repository = InMemoryNoteRepository.seeded(sampleNotes);
      final container = ProviderContainer(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final initial = await container.read(notesProvider.future);
      final staleNote = initial.first;
      final secondNote = initial[1];
      await repository.deleteNote(staleNote.id!);
      repository.updateError = secondFailure;
      final refreshCalls = repository.getCalls;

      final staleMutation = container
          .read(notesProvider.notifier)
          .archiveNote(staleNote);
      final secondMutation = container
          .read(notesProvider.notifier)
          .togglePin(secondNote);

      await expectLater(staleMutation, throwsStateError);
      await expectLater(secondMutation, throwsA(same(secondFailure)));

      final finalState = container.read(notesProvider);
      expect(finalState, isA<AsyncData<List<Note>>>());
      expect(
        finalState.requireValue.map((note) => note.id),
        initial.where((note) => note.id != staleNote.id).map((note) => note.id),
      );
      expect(repository.getCalls, refreshCalls);
    },
  );

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
    'operation failure restores previous data and rethrows without an error state',
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
      expect(container.read(notesProvider).isLoading, isFalse);
      expect(container.read(notesProvider).hasError, isFalse);
    },
  );

  test(
    'queued success waits for a failing mutation and refreshes final data',
    () async {
      final firstFailure = StateError('first update failed');
      final firstStep = _QueuedUpdateStep(error: firstFailure);
      final secondStep = _QueuedUpdateStep();
      final repository = _SequencedUpdateRepository(sampleNotes, [
        firstStep,
        secondStep,
      ]);
      final container = ProviderContainer(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final initial = await container.read(notesProvider.future);
      final firstNote = initial[0];
      final secondNote = initial[1];

      final firstMutation = container
          .read(notesProvider.notifier)
          .togglePin(firstNote);
      final firstResult = expectLater(
        firstMutation,
        throwsA(same(firstFailure)),
      );
      await firstStep.entered.future;

      final secondMutation = container
          .read(notesProvider.notifier)
          .togglePin(secondNote);
      await Future<void>.delayed(Duration.zero);

      expect(repository.startedIds, [firstNote.id]);

      firstStep.release();
      await firstResult;
      await secondStep.entered.future;
      secondStep.release();
      await secondMutation;

      final finalState = container.read(notesProvider);
      expect(finalState, isA<AsyncData<List<Note>>>());
      expect(finalState.hasError, isFalse);
      expect(
        finalState.requireValue
            .singleWhere((note) => note.id == firstNote.id)
            .isPinned,
        firstNote.isPinned,
      );
      expect(
        finalState.requireValue
            .singleWhere((note) => note.id == secondNote.id)
            .isPinned,
        isNot(secondNote.isPinned),
      );
      expect(
        repository.notes
            .singleWhere((note) => note.id == secondNote.id)
            .isPinned,
        isNot(secondNote.isPinned),
      );
    },
  );

  test(
    'queued failure restores the state from an earlier successful mutation',
    () async {
      final secondFailure = StateError('second update failed');
      final firstStep = _QueuedUpdateStep();
      final secondStep = _QueuedUpdateStep(error: secondFailure);
      final repository = _SequencedUpdateRepository(sampleNotes, [
        firstStep,
        secondStep,
      ]);
      final container = ProviderContainer(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final initial = await container.read(notesProvider.future);
      final firstNote = initial[0];
      final secondNote = initial[1];

      final firstMutation = container
          .read(notesProvider.notifier)
          .togglePin(firstNote);
      await firstStep.entered.future;

      final secondMutation = container
          .read(notesProvider.notifier)
          .togglePin(secondNote);
      final secondResult = expectLater(
        secondMutation,
        throwsA(same(secondFailure)),
      );
      await Future<void>.delayed(Duration.zero);

      expect(repository.startedIds, [firstNote.id]);

      firstStep.release();
      await firstMutation;
      await secondStep.entered.future;
      secondStep.release();
      await secondResult;

      final finalState = container.read(notesProvider);
      expect(finalState, isA<AsyncData<List<Note>>>());
      expect(finalState.hasError, isFalse);
      expect(
        finalState.requireValue
            .singleWhere((note) => note.id == firstNote.id)
            .isPinned,
        isNot(firstNote.isPinned),
      );
      expect(
        finalState.requireValue
            .singleWhere((note) => note.id == secondNote.id)
            .isPinned,
        secondNote.isPinned,
      );
      expect(
        repository.notes
            .singleWhere((note) => note.id == firstNote.id)
            .isPinned,
        isNot(firstNote.isPinned),
      );
    },
  );

  final queuedStatusMutations =
      <
        ({
          String name,
          NoteStatus expectedStatus,
          Future<void> Function(NotesNotifier notifier, Note note) run,
        })
      >[
        (
          name: 'archive',
          expectedStatus: NoteStatus.archived,
          run: (notifier, note) => notifier.archiveNote(note),
        ),
        (
          name: 'trash',
          expectedStatus: NoteStatus.trashed,
          run: (notifier, note) => notifier.trashNote(note),
        ),
      ];

  for (final mutation in queuedStatusMutations) {
    test(
      'queued pin uses the latest persisted note after ${mutation.name}',
      () async {
        final repository = InMemoryNoteRepository.seeded([
          Note(
            id: 901,
            title: 'Cached search result',
            content: 'Do not resurrect this note',
            color: 0,
            createdAt: DateTime.utc(2026, 8, 24),
          ),
        ]);
        final container = ProviderContainer(
          overrides: [noteRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);
        await container.read(notesProvider.future);
        container.read(searchQueryProvider.notifier).setQuery('cached');
        final staleSearchNote = container.read(searchResultsProvider).single;
        final notifier = container.read(notesProvider.notifier);

        final move = mutation.run(notifier, staleSearchNote);
        final pin = notifier.togglePin(staleSearchNote);
        await Future.wait([move, pin]);

        final persisted = repository.notes.single;
        expect(persisted.status, mutation.expectedStatus);
        expect(persisted.isPinned, isTrue);
        final visible = container.read(notesProvider).requireValue.single;
        expect(visible.status, mutation.expectedStatus);
        expect(visible.isPinned, isTrue);
      },
    );
  }

  test('serializes import refresh before the next mutation', () async {
    final repository = _GatedImportRefreshRepository(sampleNotes);
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(notesProvider, (_, _) {});
    addTearDown(subscription.close);
    final initial = await container.read(notesProvider.future);
    final noteToToggle = initial.first;
    final imported = Note(
      title: 'Queued import',
      content: 'Must refresh before the next write',
      color: 0,
      createdAt: DateTime.utc(2026, 8, 24),
    );

    final import = container.read(notesProvider.notifier).importBackup([
      imported,
    ]);
    await repository.importRefreshBlocked.future;

    final mutation = container
        .read(notesProvider.notifier)
        .togglePin(noteToToggle);
    await Future<void>.delayed(Duration.zero);
    repository.releaseImportRefresh();
    await Future.wait([import, mutation]);

    expect(repository.events, [
      'import',
      'release import refresh',
      'update:${noteToToggle.id}',
    ]);
    final finalNotes = container.read(notesProvider).requireValue;
    expect(
      finalNotes.where((note) => note.title == imported.title),
      hasLength(1),
    );
    expect(
      finalNotes.singleWhere((note) => note.id == noteToToggle.id).isPinned,
      isNot(noteToToggle.isPinned),
    );
    expect(
      finalNotes.singleWhere((note) => note.id == noteToToggle.id),
      repository.notes.singleWhere((note) => note.id == noteToToggle.id),
    );
  });

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

  test('add schedules a reminder with the repository allocated ID', () async {
    final repository = InMemoryNoteRepository.seeded(const []);
    final gateway = FakeNoteReminderGateway();
    final container = _container(repository, gateway);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);
    final reminder = DateTime.now().add(const Duration(days: 1));

    await container
        .read(notesProvider.notifier)
        .addNote(
          Note(
            title: 'Allocated reminder',
            content: '',
            color: 0,
            createdAt: DateTime.utc(2026, 8, 23),
            reminder: reminder,
          ),
        );

    expect(repository.addCalls, 1);
    expect(gateway.scheduled, hasLength(1));
    expect(gateway.scheduled.single.id, repository.notes.single.id);
    expect(gateway.scheduled.single.reminder, reminder);
  });

  test('add rejects an expired reminder before repository insertion', () async {
    final repository = InMemoryNoteRepository.seeded(const []);
    final gateway = FakeNoteReminderGateway();
    final container = _container(repository, gateway);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);

    await expectLater(
      container
          .read(notesProvider.notifier)
          .addNote(
            Note(
              title: 'Already expired',
              content: '',
              color: 0,
              createdAt: DateTime.utc(2026, 8, 23),
              reminder: DateTime.now().subtract(const Duration(minutes: 1)),
            ),
          ),
      throwsA(isA<InvalidNoteReminderException>()),
    );

    expect(repository.addCalls, 0);
    expect(repository.notes, isEmpty);
    expect(gateway.events, isEmpty);
  });

  test('add rejects a reminder equal to the injected current time', () async {
    final now = DateTime.utc(2030, 1, 15, 10, 15);
    final repository = InMemoryNoteRepository.seeded(const []);
    final gateway = FakeNoteReminderGateway();
    final container = _container(repository, gateway);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);

    await expectLater(
      _addNoteAt(
        container.read(notesProvider.notifier),
        Note(
          title: 'Equal is expired',
          content: '',
          color: 0,
          createdAt: DateTime.utc(2030, 1, 15),
          reminder: now,
        ),
        () => now,
      ),
      throwsA(isA<InvalidNoteReminderException>()),
    );

    expect(repository.addCalls, 0);
    expect(gateway.events, isEmpty);
  });

  test(
    'queued add rechecks its reminder immediately before insertion',
    () async {
      var now = DateTime.utc(2030, 1, 15, 10, 15);
      final repository = _GatedAddRepository();
      final gateway = FakeNoteReminderGateway();
      final container = _container(repository, gateway);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);
      final notifier = container.read(notesProvider.notifier);
      final blocker = notifier.addNote(
        Note(
          title: 'Queue blocker',
          content: '',
          color: 0,
          createdAt: DateTime.utc(2030, 1, 15),
        ),
      );
      await repository.entered.future;

      final queued = _addNoteAt(
        notifier,
        Note(
          title: 'Expires while queued',
          content: '',
          color: 0,
          createdAt: DateTime.utc(2030, 1, 15),
          reminder: now.add(const Duration(minutes: 1)),
        ),
        () => now,
      );
      now = now.add(const Duration(minutes: 2));
      repository.release();
      await blocker;

      await expectLater(queued, throwsA(isA<InvalidNoteReminderException>()));
      expect(repository.addCalls, 1);
      expect(repository.notes.single.title, 'Queue blocker');
      expect(gateway.events, isEmpty);
    },
  );

  test('add freezes the caller draft before awaiting persistence', () async {
    final now = DateTime.utc(2026, 8, 23, 12);
    final repository = _GatedAddRepository();
    final gateway = FakeNoteReminderGateway();
    final container = _container(repository, gateway);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);
    final sourceTags = <String>['draft'];
    final save = _addNoteAt(
      container.read(notesProvider.notifier),
      Note(
        title: 'Frozen draft',
        content: '',
        color: 0,
        createdAt: DateTime.utc(2026, 8, 23),
        tags: sourceTags,
        reminder: DateTime.utc(2026, 8, 24),
      ),
      () => now,
    );
    await repository.entered.future;

    sourceTags.add('late mutation');
    repository.release();
    await save;

    expect(repository.notes.single.tags, ['draft']);
    expect(gateway.scheduled.single.tags, ['draft']);
    expect(
      () => gateway.scheduled.single.tags.add('inside'),
      throwsUnsupportedError,
    );
  });

  test('add without a reminder performs no notification side effect', () async {
    final repository = InMemoryNoteRepository.seeded(const []);
    final gateway = FakeNoteReminderGateway();
    final container = _container(repository, gateway);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);

    await container
        .read(notesProvider.notifier)
        .addNote(
          Note(
            title: 'Quiet note',
            content: '',
            color: 0,
            createdAt: DateTime.utc(2026, 8, 23),
          ),
        );

    expect(gateway.scheduled, isEmpty);
    expect(gateway.cancelled, isEmpty);
  });

  test(
    'update commits before cancelling and scheduling its reminder',
    () async {
      final events = <String>[];
      final note = sampleNote.copyWith(
        reminder: DateTime.now().add(const Duration(days: 2)),
      );
      final repository = _RecordingNoteRepository([note], events);
      final gateway = FakeNoteReminderGateway(eventLog: events);
      final container = _container(repository, gateway);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);
      events.clear();
      final changed = note.copyWith(
        title: 'Changed',
        reminder: DateTime.now().add(const Duration(days: 3)),
      );

      await container.read(notesProvider.notifier).updateNote(changed);

      expect(events.take(3), ['update:1', 'cancel:1', 'schedule:1']);
      expect(gateway.scheduled.single.title, 'Changed');
    },
  );

  test(
    'update rejects a changed reminder equal to the injected time',
    () async {
      final now = DateTime.utc(2030, 1, 15, 10, 15);
      final original = sampleNote.copyWith(
        reminder: DateTime.utc(2030, 1, 16, 10, 15),
      );
      final repository = _RecordingNoteRepository([original], <String>[]);
      final gateway = FakeNoteReminderGateway();
      final container = _container(repository, gateway);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      await expectLater(
        _updateNoteAt(
          container.read(notesProvider.notifier),
          original.copyWith(title: 'Invalid change', reminder: now),
          () => now,
        ),
        throwsA(isA<InvalidNoteReminderException>()),
      );

      expect(repository.updateCalls, 0);
      expect(repository.notes.single, original);
      expect(gateway.events, isEmpty);
    },
  );

  test('update rejects a changed reminder before the injected time', () async {
    final now = DateTime.utc(2030, 1, 15, 10, 15);
    final original = sampleNote.copyWith(
      reminder: DateTime.utc(2030, 1, 16, 10, 15),
    );
    final repository = _RecordingNoteRepository([original], <String>[]);
    final gateway = FakeNoteReminderGateway();
    final container = _container(repository, gateway);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);

    await expectLater(
      _updateNoteAt(
        container.read(notesProvider.notifier),
        original.copyWith(
          title: 'Invalid past change',
          reminder: now.subtract(const Duration(minutes: 1)),
        ),
        () => now,
      ),
      throwsA(isA<InvalidNoteReminderException>()),
    );

    expect(repository.updateCalls, 0);
    expect(repository.notes.single, original);
    expect(gateway.events, isEmpty);
  });

  test('update preserves an unchanged expired stored reminder', () async {
    final now = DateTime.utc(2030, 1, 15, 10, 15);
    final expired = DateTime.utc(2029, 12, 31, 23, 59);
    final original = sampleNote.copyWith(reminder: expired);
    final repository = _RecordingNoteRepository([original], <String>[]);
    final gateway = FakeNoteReminderGateway();
    final container = _container(repository, gateway);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);

    await _updateNoteAt(
      container.read(notesProvider.notifier),
      original.copyWith(title: 'Unrelated edit'),
      () => now,
    );

    expect(repository.updateCalls, 1);
    expect(repository.notes.single.title, 'Unrelated edit');
    expect(repository.notes.single.reminder, expired);
    expect(gateway.cancelled, [original.id]);
    expect(gateway.scheduled, isEmpty);
  });

  test('pending mutation exposes loading with the previous notes', () async {
    // Mutation caught: leaving notesProvider as plain AsyncData while an
    // update is committed but its reminder side effect is still pending.
    final repository = InMemoryNoteRepository.seeded(sampleNotes);
    final cancelGate = Completer<void>();
    final gateway = FakeNoteReminderGateway()..cancelGate = cancelGate;
    final container = _container(repository, gateway);
    addTearDown(container.dispose);
    final subscription = container.listen(
      notesProvider,
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);
    final initial = await container.read(notesProvider.future);
    final changed = initial.first.copyWith(title: 'Committed while pending');

    final save = container.read(notesProvider.notifier).updateNote(changed);
    await Future<void>.delayed(Duration.zero);

    final pending = container.read(notesProvider);
    final committedTitle = repository.notes.first.title;
    final cancelled = List<int>.of(gateway.cancelled);
    cancelGate.complete();
    await save;

    expect(committedTitle, 'Committed while pending');
    expect(cancelled, [changed.id]);
    expect(pending.isLoading, isTrue);
    expect(pending.value, initial);
    expect(container.read(notesProvider), isA<AsyncData<List<Note>>>());
    expect(
      container.read(notesProvider).requireValue.first.title,
      changed.title,
    );
  });

  test('update freezes the caller draft before awaiting persistence', () async {
    final now = DateTime.utc(2030, 1, 15, 10, 15);
    final sourceTags = <String>['draft'];
    final note = sampleNote.copyWith(
      tags: sourceTags,
      reminder: now.add(const Duration(days: 1)),
    );
    final repository = _GatedUpdateRepository([note]);
    final gateway = FakeNoteReminderGateway();
    final container = _container(repository, gateway);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);

    final save = _updateNoteAt(
      container.read(notesProvider.notifier),
      note,
      () => now,
    );
    await repository.entered.future;
    sourceTags.add('late mutation');
    repository.release();
    await save;

    expect(repository.notes.single.tags, ['draft']);
    expect(gateway.scheduled.single.tags, ['draft']);
    expect(
      () => gateway.scheduled.single.tags.add('inside'),
      throwsUnsupportedError,
    );
  });

  test(
    'clearing a reminder cancels only and remains null after refresh',
    () async {
      final repository = InMemoryNoteRepository.seeded([sampleNote]);
      final gateway = FakeNoteReminderGateway();
      final container = _container(repository, gateway);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      await container
          .read(notesProvider.notifier)
          .updateNote(sampleNote.copyWith(reminder: null));

      expect(gateway.cancelled, [sampleNote.id]);
      expect(gateway.scheduled, isEmpty);
      expect(repository.notes.single.reminder, isNull);
      expect(container.read(notesProvider).value?.single.reminder, isNull);
    },
  );

  test('delete commits before cancelling its notification', () async {
    final events = <String>[];
    final repository = _RecordingNoteRepository([sampleNote], events);
    final gateway = FakeNoteReminderGateway(eventLog: events);
    final container = _container(repository, gateway);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);
    events.clear();

    await container.read(notesProvider.notifier).deleteNote(sampleNote.id!);

    expect(events.take(2), ['delete:1', 'cancel:1']);
    expect(repository.notes, isEmpty);
    expect(gateway.cancelled, [sampleNote.id]);
    expect(gateway.scheduled, isEmpty);
  });

  test('delete cancellation failure is typed after the row commits', () async {
    final failure = StateError('cancel failed');
    final repository = InMemoryNoteRepository.seeded([sampleNote]);
    final gateway = FakeNoteReminderGateway()..cancelError = failure;
    final container = _container(repository, gateway);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);

    late PersistedNoteMutationException exception;
    try {
      await container.read(notesProvider.notifier).deleteNote(sampleNote.id!);
      fail('Expected PersistedNoteMutationException');
    } on PersistedNoteMutationException catch (error) {
      exception = error;
    }

    expect(
      exception.kind,
      PersistedNoteMutationFailureKind.reminderCancellation,
    );
    expect(exception.cause, same(failure));
    expect(exception.causeStackTrace, isNotNull);
    expect(repository.notes, isEmpty);
    expect(gateway.cancelled, [sampleNote.id]);
    expect(gateway.scheduled, isEmpty);
    expect(container.read(notesProvider), isA<AsyncData<List<Note>>>());
    expect(container.read(notesProvider).requireValue, isEmpty);
  });

  test(
    'reminder cancellation recovery coalesces overlap and can retry failure',
    () async {
      // Catches two recovery calls reaching the platform gateway concurrently,
      // or a failed attempt permanently blocking later recovery.
      final repository = InMemoryNoteRepository.seeded(const []);
      final cancelGate = Completer<void>();
      final failure = StateError('cancel retry failed');
      final gateway = FakeNoteReminderGateway()
        ..cancelGate = cancelGate
        ..cancelError = failure;
      final container = _container(repository, gateway);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);
      final notifier = container.read(notesProvider.notifier);

      final first = notifier.retryReminderCancellation(41);
      final second = notifier.retryReminderCancellation(41);
      final firstFailure = expectLater(first, throwsA(same(failure)));
      final secondFailure = expectLater(second, throwsA(same(failure)));
      await Future<void>.delayed(Duration.zero);

      expect(gateway.cancelled, [41]);

      cancelGate.complete();
      await Future.wait([firstFailure, secondFailure]);
      gateway
        ..cancelGate = null
        ..cancelError = null;

      await notifier.retryReminderCancellation(41);

      expect(gateway.cancelled, [41, 41]);
      expect(repository.notes, isEmpty);
    },
  );

  test(
    'post-ID gateway failure exposes a defensive persisted snapshot',
    () async {
      final repository = InMemoryNoteRepository.seeded(const []);
      final failure = StateError('schedule failed');
      final gateway = FakeNoteReminderGateway()..scheduleError = failure;
      final container = _container(repository, gateway);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);
      final tags = <String>['draft'];
      final note = Note(
        title: 'Persisted first',
        content: 'Exact draft',
        color: 7,
        createdAt: DateTime.utc(2026, 8, 23),
        tags: tags,
        reminder: DateTime.now().add(const Duration(days: 1)),
      );

      final exception = await _persistedFailure(
        container.read(notesProvider.notifier).addNote(note),
      );
      tags.add('outside');

      expect(exception.persistedNote.id, repository.notes.single.id);
      expect(exception.persistedNote.title, 'Persisted first');
      expect(exception.persistedNote.tags, ['draft']);
      expect(
        () => exception.persistedNote.tags.add('inside'),
        throwsUnsupportedError,
      );
      expect(exception.cause, same(failure));
      expect(exception.causeStackTrace, isNotNull);
      expect(container.read(notesProvider).value, isEmpty);
      expect(container.read(notesProvider).hasError, isFalse);
    },
  );

  test('refresh failure after an insert is also typed as persisted', () async {
    final repository = InMemoryNoteRepository.seeded(const []);
    final gateway = FakeNoteReminderGateway();
    final container = _container(repository, gateway);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);
    repository.getErrorAtCall = repository.getCalls + 1;

    final exception = await _persistedFailure(
      container
          .read(notesProvider.notifier)
          .addNote(
            Note(
              title: 'Refresh later',
              content: '',
              color: 0,
              createdAt: DateTime.utc(2026, 8, 23),
            ),
          ),
    );

    expect(repository.addCalls, 1);
    expect(exception.persistedNote.id, repository.notes.single.id);
    final mutationError = exception.cause as PersistedNoteMutationException;
    expect(mutationError.cause, isA<StateError>());
    expect(mutationError.causeStackTrace, isNotNull);
    expect(container.read(notesProvider).value, isEmpty);
    expect(container.read(notesProvider).hasError, isTrue);
  });

  test(
    'refresh failure after a committed mutation keeps cached data and is typed',
    () async {
      final repository = InMemoryNoteRepository.seeded(sampleNotes);
      final gateway = FakeNoteReminderGateway();
      final container = _container(repository, gateway);
      addTearDown(container.dispose);
      final initial = await container.read(notesProvider.future);
      repository.getErrorAtCall = repository.getCalls + 1;

      late PersistedNoteMutationException exception;
      try {
        await container.read(notesProvider.notifier).togglePin(initial.first);
        fail('Expected PersistedNoteMutationException');
      } on PersistedNoteMutationException catch (error) {
        exception = error;
      }

      expect(repository.notes.first.isPinned, isFalse);
      expect(exception.kind, PersistedNoteMutationFailureKind.refresh);
      expect(exception.cause, isA<StateError>());
      expect(exception.causeStackTrace, isNotNull);
      expect(container.read(notesProvider).value, initial);
      expect(container.read(notesProvider).hasError, isTrue);
    },
  );

  test(
    'pre-write failures remain original and never become retry-safe',
    () async {
      final failure = StateError('insert failed');
      final now = DateTime.utc(2030, 1, 15, 10, 15);
      final repository = InMemoryNoteRepository.seeded(const [])
        ..addError = failure;
      final gateway = FakeNoteReminderGateway();
      final container = _container(repository, gateway);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      await expectLater(
        _addNoteAt(
          container.read(notesProvider.notifier),
          Note(
            title: 'Never inserted',
            content: '',
            color: 0,
            createdAt: DateTime.utc(2030, 1, 15),
            reminder: now.add(const Duration(hours: 1)),
          ),
          () => now,
        ),
        throwsA(same(failure)),
      );

      expect(repository.notes, isEmpty);
      expect(gateway.events, isEmpty);
    },
  );

  test('zero-row update fails before reminder side effects', () async {
    final repository = InMemoryNoteRepository.seeded(const []);
    final gateway = FakeNoteReminderGateway();
    final container = _container(repository, gateway);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);

    await expectLater(
      container
          .read(notesProvider.notifier)
          .updateNote(
            Note(
              id: 404,
              title: 'Missing',
              content: '',
              color: 0,
              createdAt: DateTime.utc(2026, 8, 23),
            ),
          ),
      throwsStateError,
    );

    expect(gateway.events, isEmpty);
  });

  test(
    'retry after post-ID failure updates one insert instead of adding again',
    () async {
      final repository = _RecordingNoteRepository(const [], <String>[]);
      final gateway = FakeNoteReminderGateway()
        ..scheduleError = StateError('schedule once');
      final container = _container(repository, gateway);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      final exception = await _persistedFailure(
        container
            .read(notesProvider.notifier)
            .addNote(
              Note(
                title: 'One insert',
                content: 'Draft',
                color: 0,
                createdAt: DateTime.utc(2026, 8, 23),
                reminder: DateTime.now().add(const Duration(days: 1)),
              ),
            ),
      );
      gateway.scheduleError = null;
      await container
          .read(notesProvider.notifier)
          .updateNote(
            exception.persistedNote.copyWith(content: 'Latest draft'),
          );

      expect(repository.addCalls, 1);
      expect(repository.updateCalls, 1);
      expect(repository.notes, hasLength(1));
      expect(repository.notes.single.id, exception.persistedNote.id);
      expect(repository.notes.single.content, 'Latest draft');
      expect(gateway.events, [
        'schedule:${exception.persistedNote.id}',
        'cancel:${exception.persistedNote.id}',
        'schedule:${exception.persistedNote.id}',
      ]);
    },
  );

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

  test(
    'failed multi-note import is atomic and retry adds one copy each',
    () async {
      final repository = InMemoryNoteRepository.seeded(sampleNotes)
        ..addErrorAtCall = 2;
      final container = ProviderContainer(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(notesProvider.future);
      final imported = [
        Note(
          title: 'First imported note',
          content: 'First',
          color: 1,
          createdAt: DateTime.utc(2026, 8, 23),
        ),
        Note(
          title: 'Second imported note',
          content: 'Second',
          color: 2,
          createdAt: DateTime.utc(2026, 8, 23, 0, 1),
        ),
      ];

      await expectLater(
        container.read(notesProvider.notifier).importBackup(imported),
        throwsStateError,
      );

      expect(
        repository.notes.where((note) => note.title.contains('imported note')),
        isEmpty,
      );

      repository.addErrorAtCall = null;
      await container.read(notesProvider.notifier).importBackup(imported);

      expect(
        repository.notes.where((note) => note.title == 'First imported note'),
        hasLength(1),
      );
      expect(
        repository.notes.where((note) => note.title == 'Second imported note'),
        hasLength(1),
      );
    },
  );

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

  test('cleanup accepts a zero-row no-op', () async {
    final repository = InMemoryNoteRepository.seeded(const []);
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(notesProvider.future);

    await container.read(notesProvider.notifier).cleanupTrash();

    expect(repository.notes, isEmpty);
    expect(container.read(notesProvider), isA<AsyncData<List<Note>>>());
    expect(container.read(notesProvider).requireValue, isEmpty);
  });

  test('removeTag accepts a zero-row no-op', () async {
    final repository = InMemoryNoteRepository.seeded([sampleNote]);
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final initial = await container.read(notesProvider.future);

    await container.read(notesProvider.notifier).removeTag('missing tag');

    expect(repository.notes, initial);
    expect(container.read(notesProvider), isA<AsyncData<List<Note>>>());
    expect(container.read(notesProvider).requireValue, initial);
  });
}

ProviderContainer _container(
  InMemoryNoteRepository repository,
  FakeNoteReminderGateway gateway,
) {
  return ProviderContainer(
    overrides: [
      noteRepositoryProvider.overrideWithValue(repository),
      noteReminderGatewayProvider.overrideWithValue(gateway),
    ],
  );
}

Future<PersistedNoteSaveException> _persistedFailure(
  Future<void> future,
) async {
  try {
    await future;
  } on PersistedNoteSaveException catch (error) {
    return error;
  }
  throw TestFailure('Expected PersistedNoteSaveException');
}

Future<void> _addNoteAt(
  NotesNotifier notifier,
  Note note,
  DateTime Function() now,
) {
  return notifier.addNote(note, now: now);
}

Future<void> _updateNoteAt(
  NotesNotifier notifier,
  Note note,
  DateTime Function() now,
) {
  return notifier.updateNote(note, now: now);
}

class _RecordingNoteRepository extends InMemoryNoteRepository {
  _RecordingNoteRepository(super.notes, this.events) : super.seeded();

  final List<String> events;
  int updateCalls = 0;

  @override
  Future<int> addNote(Note note) async {
    final id = await super.addNote(note);
    events.add('add:$id');
    return id;
  }

  @override
  Future<int> updateNote(Note note) async {
    final result = await super.updateNote(note);
    updateCalls += 1;
    events.add('update:${note.id}');
    return result;
  }

  @override
  Future<int> deleteNote(int id) async {
    final result = await super.deleteNote(id);
    events.add('delete:$id');
    return result;
  }
}

class _GatedAddRepository extends InMemoryNoteRepository {
  _GatedAddRepository() : super.seeded(const []);

  final entered = Completer<void>();
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<int> addNote(Note note) async {
    if (!entered.isCompleted) entered.complete();
    await _gate.future;
    return super.addNote(note);
  }
}

class _GatedUpdateRepository extends InMemoryNoteRepository {
  _GatedUpdateRepository(super.notes) : super.seeded();

  final entered = Completer<void>();
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<int> updateNote(Note note) async {
    entered.complete();
    await _gate.future;
    return super.updateNote(note);
  }
}

class _QueuedUpdateStep {
  _QueuedUpdateStep({this.error});

  final Object? error;
  final entered = Completer<void>();
  final _gate = Completer<void>();

  void release() => _gate.complete();
}

class _SequencedUpdateRepository extends InMemoryNoteRepository {
  _SequencedUpdateRepository(super.notes, this.steps) : super.seeded();

  final List<_QueuedUpdateStep> steps;
  final List<int?> startedIds = [];
  int _nextStep = 0;

  @override
  Future<int> toggleNotePin(int id) async {
    final step = steps[_nextStep++];
    startedIds.add(id);
    step.entered.complete();
    await step._gate.future;
    if (step.error case final error?) throw error;
    return super.toggleNotePin(id);
  }
}

class _GatedImportRefreshRepository extends InMemoryNoteRepository {
  _GatedImportRefreshRepository(super.notes) : super.seeded();

  final events = <String>[];
  final importRefreshBlocked = Completer<void>();
  final _importRefreshGate = Completer<void>();

  void releaseImportRefresh() {
    events.add('release import refresh');
    _importRefreshGate.complete();
  }

  @override
  Future<void> importNotes(List<Note> notes) async {
    await super.importNotes(notes);
    events.add('import');
  }

  @override
  Future<List<Note>> getNotesByStatus(NoteStatus status) async {
    final snapshot = await super.getNotesByStatus(status);
    final importRefreshSecondRead = NoteStatus.values.length + 2;
    if (getCalls == importRefreshSecondRead) {
      importRefreshBlocked.complete();
      await _importRefreshGate.future;
    }
    return snapshot;
  }

  @override
  Future<int> toggleNotePin(int id) async {
    events.add('update:$id');
    return super.toggleNotePin(id);
  }
}

NoteStatus _statusOf(InMemoryNoteRepository repository, int id) {
  return repository.notes.singleWhere((note) => note.id == id).status;
}
