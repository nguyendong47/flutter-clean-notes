import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_library_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_reminder_gateway_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/library_segmented_control.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/notes_state_view.dart';
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

  testWidgets('starts in Archive with semantic 48 pixel segments', (
    tester,
  ) async {
    final repository = _ControlledNoteRepository.seeded(sampleNotes);
    await _pumpLibrary(tester, repository: repository);

    _expectStableChrome();
    final control = tester.widget<LibrarySegmentedControl>(
      find.byType(LibrarySegmentedControl),
    );
    expect(control.selected, LibrarySection.archived);

    final archived = find.text('Archived');
    final trash = find.text('Trash');
    expect(
      tester.getSemantics(archived).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(
      tester.getSemantics(trash).flagsCollection.isSelected,
      Tristate.isFalse,
    );
    expect(tester.getSize(archived).height, lessThanOrEqualTo(48));
    expect(
      tester.getSize(find.byType(SegmentedButton<LibrarySection>)).height,
      greaterThanOrEqualTo(48),
    );
    expect(find.text('Archived launch notes'), findsOneWidget);
    expect(find.text('Discarded draft'), findsNothing);
    expect(repository.cleanupCalls, 0);
  });

  testWidgets('switches to Trash in place without route or scroll reset', (
    tester,
  ) async {
    final notes = <Note>[
      for (var index = 0; index < 12; index++)
        _libraryNote(
          id: 100 + index,
          title: 'Archived item $index',
          status: NoteStatus.archived,
        ),
      for (var index = 0; index < 12; index++)
        _libraryNote(
          id: 200 + index,
          title: 'Trash item $index',
          status: NoteStatus.trashed,
        ),
    ];
    await _pumpLibrary(
      tester,
      repository: _ControlledNoteRepository.seeded(notes),
    );

    final routeBefore = ModalRoute.of(
      tester.element(find.byType(NotesLibraryPage)),
    );
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -28));
    await tester.pump();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    );
    final offsetBefore = scrollable.position.pixels;
    expect(offsetBefore, greaterThan(0));

    await tester.tap(find.text('Trash'));
    await tester.pumpAndSettle();

    final routeAfter = ModalRoute.of(
      tester.element(find.byType(NotesLibraryPage)),
    );
    expect(routeAfter, same(routeBefore));
    expect(scrollable.position.pixels, moreOrLessEquals(offsetBefore));
    expect(find.text('Archived item 0'), findsNothing);
    expect(find.text('Trash item 0'), findsOneWidget);
  });

  testWidgets('restore waits, removes archived note, and Undo re-archives it', (
    tester,
  ) async {
    final repository = _ControlledNoteRepository.seeded(sampleNotes)
      ..statusGate = Completer<void>();
    await _pumpLibrary(tester, repository: repository);

    await _chooseCardAction(tester, 'Archived launch notes', 'Restore');
    await tester.pump();

    expect(find.text('Archived launch notes'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(repository.statusCalls, 1);

    repository.statusGate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Archived launch notes'), findsNothing);
    expect(_statusOf(repository, 4), NoteStatus.active);
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(_statusOf(repository, 4), NoteStatus.archived);
    expect(find.text('Archived launch notes'), findsOneWidget);
  });

  testWidgets('archive-to-trash Undo returns the note to Archive', (
    tester,
  ) async {
    final repository = _ControlledNoteRepository.seeded(sampleNotes);
    await _pumpLibrary(tester, repository: repository);

    await _chooseCardAction(tester, 'Archived launch notes', 'Move to trash');
    await tester.pumpAndSettle();

    expect(_statusOf(repository, 4), NoteStatus.trashed);
    expect(find.text('Archived launch notes'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(_statusOf(repository, 4), NoteStatus.archived);
    expect(find.text('Archived launch notes'), findsOneWidget);
  });

  testWidgets(
    'archive-to-trash stays visible and busy until persistence completes',
    (tester) async {
      final repository = _ControlledNoteRepository.seeded(sampleNotes)
        ..statusGate = Completer<void>();
      await _pumpLibrary(tester, repository: repository);

      await _chooseCardAction(tester, 'Archived launch notes', 'Move to trash');

      expect(find.text('Archived launch notes'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(repository.statusCalls, 1);
      expect(_statusOf(repository, 4), NoteStatus.archived);
      expect(find.text('Undo'), findsNothing);

      repository.statusGate!.complete();
      await tester.pumpAndSettle();

      expect(repository.statusCalls, 1);
      expect(_statusOf(repository, 4), NoteStatus.trashed);
      expect(find.text('Archived launch notes'), findsNothing);
      expect(find.text('Undo'), findsOneWidget);
    },
  );

  testWidgets('trash restore Undo returns the note to Trash', (tester) async {
    final repository = _ControlledNoteRepository.seeded(sampleNotes);
    await _pumpLibrary(tester, repository: repository);
    await _selectTrash(tester);

    await _chooseCardAction(tester, 'Discarded draft', 'Restore');
    await tester.pumpAndSettle();

    expect(_statusOf(repository, 5), NoteStatus.active);
    expect(find.text('Discarded draft'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(_statusOf(repository, 5), NoteStatus.trashed);
    expect(find.text('Discarded draft'), findsOneWidget);
  });

  testWidgets(
    'committed archive restore keeps success and Undo after refresh failure',
    (tester) async {
      final repository = _ControlledNoteRepository.seeded(sampleNotes);
      await _pumpLibrary(tester, repository: repository);
      repository.getErrorAtCall = repository.getCalls + 1;

      await _chooseCardAction(tester, 'Archived launch notes', 'Restore');
      await tester.pumpAndSettle();

      expect(_statusOf(repository, 4), NoteStatus.active);
      expect(
        tester
            .widget<LibrarySegmentedControl>(
              find.byType(LibrarySegmentedControl),
            )
            .selected,
        LibrarySection.archived,
      );
      expect(find.text('Archived launch notes'), findsOneWidget);
      expect(find.text('Archived launch notes restored'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      _expectSingleCachedRefreshNotice(tester);
      _expectNoCommittedMutationFailureUi();

      repository.getErrorAtCall = null;
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(_statusOf(repository, 4), NoteStatus.archived);
      expect(find.text('Archived launch notes'), findsOneWidget);
    },
  );

  testWidgets(
    'committed archive trash keeps success and Undo after refresh failure',
    (tester) async {
      final repository = _ControlledNoteRepository.seeded(sampleNotes);
      await _pumpLibrary(tester, repository: repository);
      repository.getErrorAtCall = repository.getCalls + 1;

      await _chooseCardAction(tester, 'Archived launch notes', 'Move to trash');
      await tester.pumpAndSettle();

      expect(_statusOf(repository, 4), NoteStatus.trashed);
      expect(
        tester
            .widget<LibrarySegmentedControl>(
              find.byType(LibrarySegmentedControl),
            )
            .selected,
        LibrarySection.archived,
      );
      expect(find.text('Archived launch notes'), findsOneWidget);
      expect(find.text('Archived launch notes moved to trash'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      _expectSingleCachedRefreshNotice(tester);
      _expectNoCommittedMutationFailureUi();

      repository.getErrorAtCall = null;
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(_statusOf(repository, 4), NoteStatus.archived);
      expect(find.text('Archived launch notes'), findsOneWidget);
    },
  );

  testWidgets(
    'committed trash restore keeps success and Undo after refresh failure',
    (tester) async {
      final repository = _ControlledNoteRepository.seeded(sampleNotes);
      await _pumpLibrary(tester, repository: repository);
      await _selectTrash(tester);
      repository.getErrorAtCall = repository.getCalls + 1;

      await _chooseCardAction(tester, 'Discarded draft', 'Restore');
      await tester.pumpAndSettle();

      expect(_statusOf(repository, 5), NoteStatus.active);
      expect(
        tester
            .widget<LibrarySegmentedControl>(
              find.byType(LibrarySegmentedControl),
            )
            .selected,
        LibrarySection.trash,
      );
      expect(find.text('Discarded draft'), findsOneWidget);
      expect(find.text('Discarded draft restored'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);
      _expectSingleCachedRefreshNotice(tester);
      _expectNoCommittedMutationFailureUi();

      repository.getErrorAtCall = null;
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();

      expect(_statusOf(repository, 5), NoteStatus.trashed);
      expect(find.text('Discarded draft'), findsOneWidget);
    },
  );

  testWidgets('delete dialog has exact warning and Cancel restores focus', (
    tester,
  ) async {
    final repository = _ControlledNoteRepository.seeded(sampleNotes);
    await _pumpLibrary(tester, repository: repository);
    await _selectTrash(tester);

    final origin = await _focusCardMenu(tester, 'Discarded draft');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete forever').last);
    await tester.pumpAndSettle();

    expect(find.text('Delete “Discarded draft” forever?'), findsOneWidget);
    expect(find.text('Discarded draft'), findsOneWidget);
    expect(find.text('This action cannot be undone.'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(repository.deleteCalls, 0);
    expect(find.text('Discarded draft'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, same(origin));

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete forever').last);
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(repository.deleteCalls, 0);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Discarded draft'), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, same(origin));
  });

  testWidgets('confirm stays mounted and blocks duplicate delete while busy', (
    tester,
  ) async {
    final repository = _ControlledNoteRepository.seeded(sampleNotes)
      ..deleteGate = Completer<void>();
    await _pumpLibrary(tester, repository: repository);
    await _selectTrash(tester);
    await _openDeleteDialog(tester, 'Discarded draft');

    await tester.tap(find.widgetWithText(FilledButton, 'Delete forever'));
    await tester.pump();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Deleting…'), findsOneWidget);
    expect(repository.deleteCalls, 1);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repository.deleteCalls, 1);

    repository.deleteGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Discarded draft'), findsNothing);
    expect(repository.deleteCalls, 1);
  });

  testWidgets('failed permanent delete stays inline and can retry', (
    tester,
  ) async {
    final repository = _ControlledNoteRepository.seeded(sampleNotes)
      ..deleteError = StateError('disk write failed');
    await _pumpLibrary(tester, repository: repository);
    await _selectTrash(tester);
    await _openDeleteDialog(tester, 'Discarded draft');

    await tester.tap(find.widgetWithText(FilledButton, 'Delete forever'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text('Could not delete “Discarded draft”. Try again.'),
      findsOneWidget,
    );
    expect(find.text('Discarded draft'), findsOneWidget);
    expect(repository.deleteCalls, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Delete forever'),
          )
          .onPressed,
      isNotNull,
    );
    expect(
      find.text('Could not update library. Showing saved notes.'),
      findsNothing,
    );
    expect(find.textContaining('disk write failed'), findsNothing);
    expect(find.textContaining('StateError'), findsNothing);

    repository.deleteError = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Delete forever'));
    await tester.pumpAndSettle();

    expect(repository.deleteCalls, 2);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Discarded draft'), findsNothing);
  });

  testWidgets(
    'committed delete retries reminder cancellation without deleting again',
    (tester) async {
      final repository = _ControlledNoteRepository.seeded(sampleNotes);
      final reminderGateway = FakeNoteReminderGateway()
        ..cancelError = StateError('private cancellation details');
      await _pumpLibrary(
        tester,
        repository: repository,
        reminderGateway: reminderGateway,
      );
      await _selectTrash(tester);
      await _openDeleteDialog(tester, 'Discarded draft');

      await tester.tap(find.widgetWithText(FilledButton, 'Delete forever'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      _expectPermanentlyDeletedNoteUnavailable(
        repository,
        id: 5,
        title: 'Discarded draft',
      );
      expect(reminderGateway.cancelled, [5]);
      const warning = 'Note deleted, but its reminder could not be cancelled.';
      expect(find.text(warning), findsOneWidget);
      expect(
        tester.getSemantics(find.text(warning)).flagsCollection.isLiveRegion,
        isTrue,
      );
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
      expect(
        find.text('Could not update library. Showing saved notes.'),
        findsNothing,
      );
      expect(
        find.text('Could not delete “Discarded draft”. Try again.'),
        findsNothing,
      );
      expect(find.textContaining('private cancellation details'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
      expect(
        find.textContaining('PersistedNoteMutationException'),
        findsNothing,
      );

      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(warning), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);

      reminderGateway.cancelError = null;
      await tester.tap(find.widgetWithText(SnackBarAction, 'Retry'));
      await tester.pumpAndSettle();

      expect(repository.deleteCalls, 1);
      expect(repository.notes.any((note) => note.id == 5), isFalse);
      expect(reminderGateway.cancelled, [5, 5]);
      const success = 'Reminder cancelled.';
      expect(find.text(success), findsOneWidget);
      expect(
        tester.getSemantics(find.text(success)).flagsCollection.isLiveRegion,
        isTrue,
      );
      expect(find.text(warning), findsNothing);
      expect(find.widgetWithText(SnackBarAction, 'Retry'), findsNothing);
      expect(find.textContaining('private cancellation details'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
      expect(find.text('Library'), findsOneWidget);
    },
  );

  testWidgets(
    'failed cancellation retry keeps one retry path and coalesces duplicate taps',
    (tester) async {
      // Catches Retry re-running deletion, leaking platform errors, or issuing
      // overlapping cancellation calls when the action is triggered twice.
      final repository = _ControlledNoteRepository.seeded(sampleNotes);
      final reminderGateway = FakeNoteReminderGateway()
        ..cancelError = StateError('initial private cancellation details');
      await _pumpLibrary(
        tester,
        repository: repository,
        reminderGateway: reminderGateway,
      );
      await _selectTrash(tester);
      await _openDeleteDialog(tester, 'Discarded draft');

      await tester.tap(find.widgetWithText(FilledButton, 'Delete forever'));
      await tester.pumpAndSettle();

      const warning = 'Note deleted, but its reminder could not be cancelled.';
      expect(find.text(warning), findsOneWidget);
      final cancelGate = Completer<void>();
      reminderGateway
        ..cancelGate = cancelGate
        ..cancelError = StateError('retry private cancellation details');
      final action = tester.widget<SnackBarAction>(
        find.widgetWithText(SnackBarAction, 'Retry'),
      );

      action.onPressed();
      action.onPressed();
      await tester.pump();

      expect(reminderGateway.cancelled, [5, 5]);
      expect(repository.deleteCalls, 1);

      cancelGate.complete();
      await tester.pumpAndSettle();

      expect(reminderGateway.cancelled, [5, 5]);
      expect(repository.deleteCalls, 1);
      expect(repository.notes.any((note) => note.id == 5), isFalse);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(warning), findsOneWidget);
      expect(
        tester.getSemantics(find.text(warning)).flagsCollection.isLiveRegion,
        isTrue,
      );
      expect(find.widgetWithText(SnackBarAction, 'Retry'), findsOneWidget);
      expect(
        find.textContaining('retry private cancellation details'),
        findsNothing,
      );
      expect(find.textContaining('StateError'), findsNothing);
      expect(find.text('Library'), findsOneWidget);
    },
  );

  testWidgets(
    'committed delete releases its tombstone after fresh same-ID data',
    (tester) async {
      final repository = _ControlledNoteRepository.seeded(sampleNotes);
      final container = await _pumpLibrary(tester, repository: repository);
      await _selectTrash(tester);
      await _openDeleteDialog(tester, 'Discarded draft');
      repository.getErrorAtCall = repository.getCalls + 1;

      await tester.tap(find.widgetWithText(FilledButton, 'Delete forever'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      _expectPermanentlyDeletedNoteUnavailable(
        repository,
        id: 5,
        title: 'Discarded draft',
      );
      expect(
        find.text('Could not delete “Discarded draft”. Try again.'),
        findsNothing,
      );
      expect(find.widgetWithText(FilledButton, 'Delete forever'), findsNothing);
      _expectSingleCachedRefreshNotice(tester);
      _expectNoCommittedMutationFailureUi();

      final recoveredNote = _libraryNote(
        id: 5,
        title: 'Recovered same ID',
        status: NoteStatus.trashed,
      );
      repository.getErrorAtCall = null;
      await repository.importNotes([recoveredNote]);
      container.invalidate(notesProvider);
      await container.read(notesProvider.future);
      await tester.pumpAndSettle();

      expect(
        repository.notes.singleWhere((note) => note.id == 5).title,
        'Recovered same ID',
      );
      expect(find.text('Discarded draft'), findsNothing);
      expect(find.text('Recovered same ID'), findsOneWidget);
      expect(
        find.byTooltip('More actions for Recovered same ID'),
        findsOneWidget,
      );
      expect(
        find.text('Could not update library. Showing saved notes.'),
        findsNothing,
      );

      repository.getErrorAtCall = repository.getCalls + 1;
      await expectLater(
        container.read(notesProvider.notifier).trashNote(recoveredNote),
        throwsA(anything),
      );
      await tester.pumpAndSettle();

      _expectSingleCachedRefreshNotice(tester);
      expect(find.text('Recovered same ID'), findsOneWidget);
      final recoveredMenu = find.byTooltip(
        'More actions for Recovered same ID',
      );
      expect(recoveredMenu, findsOneWidget);
      await tester.tap(recoveredMenu);
      await tester.pumpAndSettle();
      expect(find.text('Delete forever'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Archive and Trash empty states have distinct useful actions', (
    tester,
  ) async {
    var showNotesCalls = 0;
    await _pumpLibrary(
      tester,
      repository: _ControlledNoteRepository.seeded(const []),
      onShowNotes: () => showNotesCalls += 1,
    );

    expect(find.text('No archived notes'), findsOneWidget);
    expect(find.text('Notes you archive will appear here.'), findsOneWidget);
    final browse = find.widgetWithText(FilledButton, 'Browse notes');
    expect(tester.getSize(browse).height, greaterThanOrEqualTo(48));
    await tester.tap(browse);
    await tester.pump();

    await _selectTrash(tester);
    expect(find.text('Trash is empty'), findsOneWidget);
    expect(
      find.text(
        'Deleted notes stay here until you restore or delete them forever.',
      ),
      findsOneWidget,
    );
    final back = find.widgetWithText(FilledButton, 'Back to notes');
    expect(tester.getSize(back).height, greaterThanOrEqualTo(48));
    await tester.tap(back);
    await tester.pump();

    expect(showNotesCalls, 2);
  });

  testWidgets('loading and initial error retain Library chrome and retry', (
    tester,
  ) async {
    final deferred = _DeferredReadRepository(sampleNotes);
    await _pumpLibrary(tester, repository: deferred, settle: false);
    await tester.pump();

    _expectStableChrome();
    expect(find.byType(NotesSkeleton), findsOneWidget);

    deferred.release();
    await tester.pumpAndSettle();
    expect(find.text('Archived launch notes'), findsOneWidget);

    final failed = _ControlledNoteRepository.seeded(const [])
      ..getError = StateError('read failed');
    await _pumpLibrary(tester, repository: failed);

    _expectStableChrome();
    expect(find.byType(NotesErrorState), findsOneWidget);
    final retry = find.widgetWithText(FilledButton, 'Try again');
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));

    failed.getError = null;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.text('No archived notes'), findsOneWidget);
  });

  testWidgets('failed restore keeps cards and announces once', (tester) async {
    final repository = _ControlledNoteRepository.seeded(sampleNotes)
      ..statusError = StateError('write failed');
    final container = await _pumpLibrary(tester, repository: repository);
    final before = container.read(notesProvider).requireValue;

    await _chooseCardAction(tester, 'Archived launch notes', 'Restore');
    await tester.pumpAndSettle();

    final state = container.read(notesProvider);
    expect(state, isA<AsyncData<List<Note>>>());
    expect(state.value, same(before));
    expect(state.hasError, isFalse);
    _expectStableChrome();
    expect(
      tester
          .widget<LibrarySegmentedControl>(find.byType(LibrarySegmentedControl))
          .selected,
      LibrarySection.archived,
    );
    expect(find.text('Archived launch notes'), findsOneWidget);
    expect(
      find.text('Could not update library. Showing saved notes.'),
      findsNothing,
    );
    expect(
      tester
          .getSemantics(find.text('Could not update library. Try again.'))
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );
    expect(find.text('Could not update library. Try again.'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('Undo'), findsNothing);
    expect(find.textContaining('write failed'), findsNothing);
    expect(find.textContaining('StateError'), findsNothing);
    expect(find.textContaining('PersistedNoteMutationException'), findsNothing);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Could not update library. Try again.'), findsOneWidget);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('Trash selection and content survive notesProvider refresh', (
    tester,
  ) async {
    final repository = _ControlledNoteRepository.seeded(sampleNotes);
    final container = await _pumpLibrary(tester, repository: repository);
    await _selectTrash(tester);

    expect(
      tester.getSemantics(find.text('Trash')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(find.text('Discarded draft'), findsOneWidget);

    container.invalidate(notesProvider);
    await container.read(notesProvider.future);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<LibrarySegmentedControl>(find.byType(LibrarySegmentedControl))
          .selected,
      LibrarySection.trash,
    );
    expect(
      tester.getSemantics(find.text('Trash')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(find.text('Discarded draft'), findsOneWidget);
  });

  testWidgets('fits 320 pixels at text scale 1.5 in both Aurora themes', (
    tester,
  ) async {
    final compactNotes = [
      _libraryNote(
        id: 301,
        title: 'An archived note with a title that needs space to wrap',
        status: NoteStatus.archived,
      ),
      _libraryNote(
        id: 302,
        title: 'A discarded draft with a long permanent deletion title',
        status: NoteStatus.trashed,
      ),
    ];

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await _pumpLibrary(
        tester,
        repository: _ControlledNoteRepository.seeded(compactNotes),
        size: const Size(320, 900),
        textScaler: const TextScaler.linear(1.5),
        themeMode: mode,
      );

      _expectStableChrome();
      expect(find.byType(SafeArea), findsOneWidget);
      expect(
        tester.getSize(find.byType(LibrarySegmentedControl)).width,
        lessThanOrEqualTo(288),
      );
      expect(tester.takeException(), isNull, reason: '$mode archive');

      await _selectTrash(tester);
      await _openDeleteDialog(
        tester,
        'A discarded draft with a long permanent deletion title',
      );

      expect(
        tester.getSize(find.byType(AlertDialog)).width,
        lessThanOrEqualTo(320),
      );
      expect(tester.takeException(), isNull, reason: '$mode dialog');

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      final scrollView = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      final bottomSliver = scrollView.slivers.last as SliverPadding;
      expect(bottomSliver.key, const Key('notes-library-bottom-padding'));
      expect(
        bottomSliver.padding.resolve(TextDirection.ltr).bottom,
        greaterThanOrEqualTo(112),
      );
      expect(tester.takeException(), isNull, reason: '$mode final');
    }
  });
}

Future<ProviderContainer> _pumpLibrary(
  WidgetTester tester, {
  required InMemoryNoteRepository repository,
  Size size = const Size(375, 1000),
  TextScaler textScaler = TextScaler.noScaling,
  ThemeMode themeMode = ThemeMode.light,
  ValueChanged<Note>? onOpenNote,
  VoidCallback? onShowNotes,
  FakeNoteReminderGateway? reminderGateway,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        noteRepositoryProvider.overrideWithValue(repository),
        if (reminderGateway != null)
          noteReminderGatewayProvider.overrideWithValue(reminderGateway),
      ],
      child: MaterialApp(
        theme: AuroraTheme.light(),
        darkTheme: AuroraTheme.dark(),
        themeMode: themeMode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: NotesLibraryPage(
          onOpenNote: onOpenNote,
          onShowNotes: onShowNotes,
        ),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();

  return ProviderScope.containerOf(
    tester.element(find.byType(NotesLibraryPage)),
  );
}

void _expectStableChrome() {
  expect(find.byKey(const Key('notes-library-heading')), findsOneWidget);
  expect(find.text('Library'), findsOneWidget);
  expect(find.byType(LibrarySegmentedControl), findsOneWidget);
}

void _expectSingleCachedRefreshNotice(WidgetTester tester) {
  final notice = find.text('Could not update library. Showing saved notes.');
  expect(notice, findsOneWidget);
  expect(tester.getSemantics(notice).flagsCollection.isLiveRegion, isTrue);
}

void _expectNoCommittedMutationFailureUi() {
  expect(find.text('Could not update library. Try again.'), findsNothing);
  expect(
    find.text('Note deleted, but its reminder could not be cancelled.'),
    findsNothing,
  );
  expect(find.textContaining('PersistedNoteMutationException'), findsNothing);
  expect(find.textContaining('note refresh'), findsNothing);
  expect(find.textContaining('StateError'), findsNothing);
}

void _expectPermanentlyDeletedNoteUnavailable(
  _ControlledNoteRepository repository, {
  required int id,
  required String title,
}) {
  expect(repository.deleteCalls, 1);
  expect(repository.notes.any((note) => note.id == id), isFalse);
  expect(find.text(title), findsNothing);
  expect(find.byTooltip('More actions for $title'), findsNothing);
  expect(find.text('Delete forever'), findsNothing);
}

Future<void> _selectTrash(WidgetTester tester) async {
  await tester.tap(find.text('Trash'));
  await tester.pumpAndSettle();
}

Future<void> _chooseCardAction(
  WidgetTester tester,
  String noteTitle,
  String action,
) async {
  await tester.tap(find.byTooltip('More actions for $noteTitle'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action).last);
  await tester.pump();
}

Future<void> _openDeleteDialog(WidgetTester tester, String noteTitle) async {
  await _chooseCardAction(tester, noteTitle, 'Delete forever');
  await tester.pumpAndSettle();
  expect(find.byType(AlertDialog), findsOneWidget);
}

Future<FocusNode> _focusCardMenu(WidgetTester tester, String noteTitle) async {
  final menu = find.byTooltip('More actions for $noteTitle');
  for (var attempt = 0; attempt < 24; attempt++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && _isDescendantOf(focus.context, menu)) return focus;
  }
  throw TestFailure('Could not focus menu for $noteTitle');
}

bool _isDescendantOf(BuildContext? context, Finder ancestor) {
  if (context is! Element) return false;
  final target = ancestor.evaluate().single;
  Element? current = context;
  while (current != null) {
    if (identical(current, target)) return true;
    Element? parent;
    current.visitAncestorElements((element) {
      parent = element;
      return false;
    });
    current = parent;
  }
  return false;
}

NoteStatus _statusOf(InMemoryNoteRepository repository, int id) {
  return repository.notes.singleWhere((note) => note.id == id).status;
}

Note _libraryNote({
  required int id,
  required String title,
  required NoteStatus status,
}) {
  return Note(
    id: id,
    title: title,
    content: 'Library content for $title',
    color: 0xFF6757D9,
    createdAt: DateTime.utc(2026, 8, 20).subtract(Duration(minutes: id)),
    tags: const ['library', 'mobile'],
    status: status,
  );
}

class _ControlledNoteRepository extends InMemoryNoteRepository {
  _ControlledNoteRepository.seeded(super.notes) : super.seeded();

  Completer<void>? statusGate;
  Completer<void>? deleteGate;
  int statusCalls = 0;
  int deleteCalls = 0;
  int cleanupCalls = 0;

  @override
  Future<int> setNoteStatus(int id, NoteStatus status) async {
    statusCalls += 1;
    await statusGate?.future;
    return super.setNoteStatus(id, status);
  }

  @override
  Future<int> deleteNote(int id) async {
    deleteCalls += 1;
    await deleteGate?.future;
    return super.deleteNote(id);
  }

  @override
  Future<int> cleanupTrash() async {
    cleanupCalls += 1;
    return super.cleanupTrash();
  }
}

class _DeferredReadRepository extends _ControlledNoteRepository {
  _DeferredReadRepository(super.notes) : super.seeded();

  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<List<Note>> getNotesByStatus(NoteStatus status) async {
    await _gate.future;
    return super.getNotesByStatus(status);
  }
}
