import 'dart:async';
import 'dart:ui' show SemanticsAction, SemanticsActionEvent, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_clean_notes/app/app_providers.dart';
import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_home_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_reminder_gateway_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/notes_state_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/in_memory_note_repository.dart';
import '../../../helpers/fake_note_reminder_gateway.dart';
import '../../../helpers/note_fixtures.dart';

void main() {
  testWidgets('separates pinned notes, selects tags, and opens search', (
    tester,
  ) async {
    var searchOpened = false;
    final repository = InMemoryNoteRepository.seeded(sampleNotes);
    await _pumpHome(
      tester,
      repository: repository,
      size: const Size(800, 1100),
      onOpenSearch: () => searchOpened = true,
    );

    final pinnedSection = find.byKey(const Key('pinned-notes-section'));
    final collection = find.byKey(const Key('notes-collection'));
    final greeting = find.textContaining(RegExp(r'^Good '));
    expect(tester.getSemantics(greeting).flagsCollection.isHeader, isTrue);
    expect(
      find.descendant(of: pinnedSection, matching: find.text(sampleNote.title)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: collection, matching: find.text(sampleNote.title)),
      findsNothing,
    );
    expect(
      find.descendant(of: collection, matching: find.text('Design follow-up')),
      findsOneWidget,
    );
    expect(
      tester
          .getTopLeft(
            find.descendant(
              of: pinnedSection,
              matching: find.text(sampleNote.title),
            ),
          )
          .dy,
      lessThan(
        tester
            .getTopLeft(
              find.descendant(
                of: collection,
                matching: find.text('Design follow-up'),
              ),
            )
            .dy,
      ),
    );

    final searchSemantics = find.bySemanticsLabel(RegExp(r'^Search notes$'));
    expect(searchSemantics, findsOneWidget);
    final searchData = tester.getSemantics(searchSemantics).getSemanticsData();
    expect(searchData.label, 'Search notes');
    expect(searchData.hasAction(SemanticsAction.tap), isTrue);

    final workChip = find.widgetWithText(FilterChip, 'work');
    await tester.tap(workChip);
    await tester.pumpAndSettle();

    expect(tester.widget<FilterChip>(workChip).selected, isTrue);
    expect(
      tester.getSemantics(workChip).flagsCollection.isSelected,
      Tristate.isTrue,
    );

    await tester.tap(find.byKey(const Key('notes-home-search')));
    await tester.pump();
    expect(searchOpened, isTrue);
  });

  testWidgets('resets a tag that disappears after its last note is archived', (
    tester,
  ) async {
    final repository = InMemoryNoteRepository.seeded(sampleNotes);
    final container = await _pumpHome(
      tester,
      repository: repository,
      size: const Size(800, 1100),
    );

    await tester.tap(find.widgetWithText(FilterChip, 'personal'));
    await tester.pumpAndSettle();
    expect(container.read(selectedTagProvider), 'personal');

    await tester.tap(find.byTooltip('More actions for Personal errands'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive').last);
    await tester.pumpAndSettle();

    expect(container.read(selectedTagProvider), isNull);
    expect(
      tester
          .widget<FilterChip>(find.widgetWithText(FilterChip, 'All'))
          .selected,
      isTrue,
    );
    expect(find.text('Design follow-up'), findsOneWidget);
    expect(find.byType(NotesEmptyState), findsNothing);
  });

  testWidgets('keeps home chrome and skeleton geometry while loading', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final repository = _DeferredNoteRepository(sampleNotes);
    await _pumpHome(tester, repository: repository, settle: false);
    await tester.pump();

    _expectStableChrome();
    expect(find.byType(NotesSkeleton), findsOneWidget);
    expect(find.byKey(const Key('notes-skeleton-card-0')), findsOneWidget);
    expect(find.byKey(const Key('notes-skeleton-card-3')), findsOneWidget);
    final loading = find.bySemanticsLabel('Loading notes');
    expect(loading, findsOneWidget);
    final loadingNode = tester.getSemantics(loading);
    expect(loadingNode.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    expect(loadingNode.childrenCountInTraversalOrder, 0);

    repository.release();
    await tester.pumpAndSettle();
    expect(find.byType(NotesSkeleton), findsNothing);
    semantics.dispose();
  });

  testWidgets('empty state retains chrome and invokes the create action', (
    tester,
  ) async {
    var created = false;
    await _pumpHome(
      tester,
      repository: InMemoryNoteRepository.seeded(const []),
      onCreateNote: () => created = true,
    );

    _expectStableChrome();
    expect(find.byType(NotesEmptyState), findsOneWidget);
    expect(find.textContaining('Create your first note'), findsOneWidget);
    final createButton = find.widgetWithText(FilledButton, 'Create note');
    expect(tester.getSize(createButton).height, greaterThanOrEqualTo(44));

    await tester.tap(createButton);
    await tester.pump();
    expect(created, isTrue);
  });

  testWidgets(
    'unsupported reminders keep empty copy and stored metadata honest',
    (tester) async {
      final unsupported = FakeNoteReminderGateway(supportsScheduling: false);
      await _pumpHome(
        tester,
        repository: InMemoryNoteRepository.seeded(const []),
        reminderGateway: unsupported,
      );

      expect(
        find.textContaining(RegExp('reminder', caseSensitive: false)),
        findsNothing,
      );

      await _pumpHome(
        tester,
        repository: InMemoryNoteRepository.seeded(sampleNotes),
        reminderGateway: unsupported,
      );

      expect(find.text('Stored reminder · Aug 18, 9:00 AM'), findsOneWidget);
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Open note Aurora design'))
            .value,
        contains(
          'Stored reminder date Aug 18, 9:00 AM. '
          'Notifications unavailable on this device',
        ),
      );
    },
  );

  testWidgets('active-empty state does not claim the notebook is empty', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      repository: InMemoryNoteRepository.seeded([
        sampleNote.copyWith(status: NoteStatus.archived),
        sampleNotes.last,
      ]),
    );

    expect(find.text('No active notes'), findsOneWidget);
    expect(find.textContaining('Create your first note'), findsNothing);
  });

  testWidgets('initial error retains chrome and a 48 pixel retry action', (
    tester,
  ) async {
    final repository = InMemoryNoteRepository.seeded(const [])
      ..getError = StateError('read failed');
    await _pumpHome(tester, repository: repository);

    _expectStableChrome();
    expect(find.byType(NotesErrorState), findsOneWidget);
    expect(find.text('Could not load notes'), findsOneWidget);
    expect(
      find.text('Try again. Your saved notes are unchanged.'),
      findsOneWidget,
    );
    expect(find.textContaining('connection'), findsNothing);
    final retry = find.widgetWithText(FilledButton, 'Try again');
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
    final errorTitle = tester
        .getSemantics(find.bySemanticsLabel('Could not load notes'))
        .getSemanticsData();
    expect(errorTitle.flagsCollection.isHeader, isTrue);
    expect(errorTitle.flagsCollection.isLiveRegion, isTrue);
    expect(
      tester
          .getSemantics(retry)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );

    repository.getError = null;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.byType(NotesEmptyState), findsOneWidget);
  });

  for (final textScale in [2.0, 3.0]) {
    testWidgets(
      'critical home CTAs reflow at 320x640 with ${textScale}x text',
      (tester) async {
        await _pumpHome(
          tester,
          repository: InMemoryNoteRepository.seeded(const []),
          size: const Size(320, 640),
          textScaler: TextScaler.linear(textScale),
        );
        final create = find.widgetWithText(FilledButton, 'Create note');
        await _revealInHome(tester, create);
        expect(tester.getSize(create).height, greaterThanOrEqualTo(48));
        if (textScale == 3) {
          expect(tester.getSize(create).height, greaterThan(48));
        }
        expect(tester.takeException(), isNull, reason: 'empty ${textScale}x');

        final failed = InMemoryNoteRepository.seeded(const [])
          ..getError = StateError('read failed');
        await _pumpHome(
          tester,
          repository: failed,
          size: const Size(320, 640),
          textScaler: TextScaler.linear(textScale),
        );
        final retry = find.widgetWithText(FilledButton, 'Try again');
        await _revealInHome(tester, retry);
        expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
        if (textScale == 3) {
          expect(tester.getSize(retry).height, greaterThan(48));
        }
        expect(tester.takeException(), isNull, reason: 'error ${textScale}x');
      },
    );
  }

  testWidgets(
    'failed retry without cached notes announces a sanitized load error',
    (tester) async {
      final repository = InMemoryNoteRepository.seeded(const [])
        ..getError = StateError(r'C:\private\notes.db read failed');
      await _pumpHome(tester, repository: repository);

      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      const message = 'Could not load notes. Try again.';
      expect(find.byType(NotesErrorState), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text(message), findsOneWidget);
      expect(
        find.text('Could not refresh notes. Showing saved notes. Try again.'),
        findsNothing,
      );
      expect(find.textContaining('notes.db'), findsNothing);

      final announcement = find.bySemanticsLabel(message);
      expect(announcement, findsOneWidget);
      final semantics = tester.getSemantics(announcement).getSemanticsData();
      expect(semantics.label, message);
      expect(semantics.flagsCollection.isLiveRegion, isTrue);
    },
  );

  testWidgets('pre-write failure restores notes without a refresh notice', (
    tester,
  ) async {
    final repository = InMemoryNoteRepository.seeded(sampleNotes);
    final container = await _pumpHome(tester, repository: repository);
    final initial = container.read(notesProvider).requireValue;
    repository.updateError = StateError('write failed');

    await expectLater(
      container.read(notesProvider.notifier).togglePin(initial.first),
      throwsStateError,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final state = container.read(notesProvider);
    expect(state, isA<AsyncData<List<Note>>>());
    expect(state.value, same(initial));
    expect(state.hasError, isFalse);
    _expectStableChrome();
    expect(find.text(sampleNote.title), findsOneWidget);
    expect(find.byType(NotesErrorState), findsNothing);
    expect(find.textContaining('write failed'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets(
    'archive and trash pre-write failures show one neutral failure without Undo',
    (tester) async {
      for (final action in ['Archive', 'Move to trash']) {
        final repository = InMemoryNoteRepository.seeded(sampleNotes)
          ..statusError = StateError(r'C:\private\notes.db write failed');
        await _pumpHome(
          tester,
          repository: repository,
          size: const Size(800, 1100),
        );

        await tester.tap(find.byTooltip('More actions for Design follow-up'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(action).last);
        await tester.pumpAndSettle();

        expect(_statusOf(repository, 2), NoteStatus.active, reason: action);
        expect(find.text('Design follow-up'), findsOneWidget, reason: action);
        expect(
          find.text(
            'Could not update this note. Check the note list before trying '
            'again.',
          ),
          findsOneWidget,
          reason: action,
        );
        expect(find.byType(SnackBar), findsOneWidget, reason: action);
        expect(find.textContaining('notes.db'), findsNothing, reason: action);
        expect(find.text('Undo'), findsNothing, reason: action);
      }
    },
  );

  testWidgets(
    'missing archive target shows one failure without Undo or refresh feedback',
    (tester) async {
      final repository = InMemoryNoteRepository.seeded(sampleNotes);
      final container = await _pumpHome(
        tester,
        repository: repository,
        size: const Size(800, 1100),
      );
      final cachedNotes = container.read(notesProvider).requireValue;
      await repository.deleteNote(2);
      final refreshCalls = repository.getCalls;

      await tester.tap(find.byTooltip('More actions for Design follow-up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive').last);
      await tester.pumpAndSettle();

      final state = container.read(notesProvider);
      expect(state, isA<AsyncData<List<Note>>>());
      expect(
        state.requireValue.map((note) => note.id),
        cachedNotes.where((note) => note.id != 2).map((note) => note.id),
      );
      expect(repository.getCalls, refreshCalls);
      expect(repository.notes.any((note) => note.id == 2), isFalse);
      expect(find.text('Design follow-up'), findsNothing);
      expect(
        find.text(
          'Could not update this note. Check the note list before trying '
          'again.',
        ),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('Could not refresh notes'), findsNothing);
      expect(find.text('Undo'), findsNothing);
    },
  );

  testWidgets(
    'archive and trash committed refresh failures keep Undo and restore the note',
    (tester) async {
      for (final scenario in <({String action, NoteStatus status})>[
        (action: 'Archive', status: NoteStatus.archived),
        (action: 'Move to trash', status: NoteStatus.trashed),
      ]) {
        final repository = InMemoryNoteRepository.seeded(sampleNotes);
        await _pumpHome(
          tester,
          repository: repository,
          size: const Size(800, 1100),
        );
        repository.getErrorAtCall = repository.getCalls + 1;

        await tester.tap(find.byTooltip('More actions for Design follow-up'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(scenario.action).last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(_statusOf(repository, 2), scenario.status);
        expect(find.text('Undo'), findsOneWidget, reason: scenario.action);
        expect(
          find.textContaining('Could not update this note'),
          findsNothing,
          reason: scenario.action,
        );
        final successMessage = scenario.status == NoteStatus.archived
            ? 'Design follow-up archived'
            : 'Design follow-up moved to trash';
        expect(
          find.text(
            '$successMessage. Could not refresh notes; showing saved notes.',
          ),
          findsOneWidget,
        );
        expect(find.byType(SnackBar), findsOneWidget);

        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();

        expect(_statusOf(repository, 2), NoteStatus.active);
        expect(find.text('Design follow-up'), findsOneWidget);
      }
    },
  );

  testWidgets(
    'cached refresh Retry supports semantics and keyboard activation',
    (tester) async {
      final repository = InMemoryNoteRepository.seeded(sampleNotes);
      final container = await _pumpHome(tester, repository: repository);
      repository.getError = StateError(r'C:\private\notes.db unavailable');

      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();

      expect(find.text(sampleNote.title), findsOneWidget);
      expect(
        find.text('Could not refresh notes. Showing saved notes. Try again.'),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('notes.db'), findsNothing);
      expect(container.read(notesProvider).hasError, isTrue);

      var retry = find.widgetWithText(TextButton, 'Retry');
      expect(retry, findsOneWidget);
      var semanticRetry = find.bySemanticsLabel(RegExp(r'\bRetry\b'));
      expect(semanticRetry, findsOneWidget);
      _performSemanticTap(tester, semanticRetry);
      await tester.pumpAndSettle();
      expect(container.read(notesProvider).hasError, isTrue);
      expect(
        find.text('Could not refresh notes. Showing saved notes. Try again.'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);

      repository.getError = null;
      semanticRetry = find.bySemanticsLabel(RegExp(r'\bRetry\b'));
      _performSemanticTap(tester, semanticRetry);
      await tester.pumpAndSettle();
      expect(container.read(notesProvider), isA<AsyncData<List<Note>>>());
      expect(find.byType(SnackBar), findsNothing);

      repository.getError = StateError(
        r'C:\private\notes.db unavailable again',
      );
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pump();
      expect(container.read(notesProvider).hasError, isTrue);
      retry = find.widgetWithText(TextButton, 'Retry');
      expect(retry, findsOneWidget);
      await _focus(tester, retry);
      repository.getError = null;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(container.read(notesProvider), isA<AsyncData<List<Note>>>());
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('notes.db'), findsNothing);
    },
  );

  testWidgets('cached Retry coalesces an overlapping pull refresh', (
    tester,
  ) async {
    final repository = _GatedRefreshRepository(sampleNotes);
    final container = await _pumpHome(tester, repository: repository);
    repository.getError = StateError('refresh unavailable');

    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(container.read(notesProvider).hasError, isTrue);

    repository
      ..getError = null
      ..gateRefresh();
    await tester.tap(find.widgetWithText(TextButton, 'Retry'));
    await tester.pump();
    expect(repository.gatedGetCalls, 1);

    final overlappingRefresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pump();
    expect(repository.gatedGetCalls, 1);

    repository.releaseRefresh();
    await overlappingRefresh;
    await tester.pumpAndSettle();
    expect(container.read(notesProvider), isA<AsyncData<List<Note>>>());
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('archive and trash actions each offer working Undo restoration', (
    tester,
  ) async {
    for (final scenario in <({String action, NoteStatus status})>[
      (action: 'Archive', status: NoteStatus.archived),
      (action: 'Move to trash', status: NoteStatus.trashed),
    ]) {
      final repository = InMemoryNoteRepository.seeded(sampleNotes);
      await _pumpHome(
        tester,
        repository: repository,
        size: const Size(800, 1100),
      );

      await tester.tap(find.byTooltip('More actions for Design follow-up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(scenario.action).last);
      await tester.pumpAndSettle();

      expect(_statusOf(repository, 2), scenario.status);
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(_statusOf(repository, 2), NoteStatus.active);
      expect(find.text('Design follow-up'), findsOneWidget);
    }
  });

  testWidgets('restoration failures surface without replacing cached notes', (
    tester,
  ) async {
    final repository = InMemoryNoteRepository.seeded(sampleNotes);
    final container = await _pumpHome(
      tester,
      repository: repository,
      size: const Size(800, 1100),
    );
    await tester.tap(find.byTooltip('More actions for Design follow-up'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive').last);
    await tester.pumpAndSettle();
    final beforeUndo = container.read(notesProvider).requireValue;
    final restoreError = StateError('restore failed');
    repository.statusError = restoreError;

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(_statusOf(repository, 2), NoteStatus.archived);
    final state = container.read(notesProvider);
    expect(state, isA<AsyncData<List<Note>>>());
    expect(state.value, same(beforeUndo));
    expect(state.hasError, isFalse);
    _expectStableChrome();
    expect(find.text(sampleNote.title), findsOneWidget);
    expect(
      find.text(
        'Could not update this note. Check the note list before trying again.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('restore failed'), findsNothing);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets(
    'theme toggle is a 48 pixel labeled control with neutral failure feedback',
    (tester) async {
      final store = _FakeThemeModeStore(ThemeMode.light)
        ..writeError = StateError('C:\\private\\theme.db');
      await _pumpHome(
        tester,
        repository: InMemoryNoteRepository.seeded(sampleNotes),
        themeStore: store,
      );

      final toggle = find.byKey(const Key('notes-home-theme-toggle'));
      expect(toggle, findsOneWidget);
      expect(tester.getSize(toggle).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48));
      expect(find.byTooltip('Use dark theme'), findsOneWidget);
      expect(find.bySemanticsLabel('Use dark theme'), findsOneWidget);

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      expect(store.writeCalls, 1);
      expect(store.mode, ThemeMode.light);
      expect(find.textContaining('theme.db'), findsNothing);
      expect(find.text('Theme stays unchanged. Try again.'), findsOneWidget);
    },
  );

  testWidgets('theme toggle exposes and handles its semantic tap action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final store = _FakeThemeModeStore(ThemeMode.light);
    await _pumpHome(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
      themeStore: store,
    );

    final toggle = find.byKey(const Key('notes-home-theme-toggle'));
    _performSemanticTap(tester, toggle);
    await tester.pumpAndSettle();

    expect(store.writeCalls, 1);
    expect(store.mode, ThemeMode.dark);
    semantics.dispose();
  });

  testWidgets(
    'theme toggle announces pending persistence and prevents repeat writes',
    (tester) async {
      final gate = Completer<void>();
      final store = _FakeThemeModeStore(ThemeMode.light)..writeGate = gate;
      await _pumpHome(
        tester,
        repository: InMemoryNoteRepository.seeded(sampleNotes),
        themeStore: store,
      );

      final toggle = find.byKey(const Key('notes-home-theme-toggle'));
      await tester.tap(toggle);
      await tester.pump();

      expect(store.writeCalls, 1);
      expect(
        find.descendant(
          of: toggle,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      final loadingSemantics = tester.getSemantics(toggle).getSemanticsData();
      expect(loadingSemantics.value, 'Saving theme preference…');
      expect(loadingSemantics.flagsCollection.isLiveRegion, isTrue);
      expect(loadingSemantics.hasAction(SemanticsAction.tap), isFalse);

      await tester.tap(toggle, warnIfMissed: false);
      await tester.pump();
      expect(store.writeCalls, 1);

      gate.complete();
      await tester.pumpAndSettle();
      expect(store.writeCalls, 1);
      expect(store.mode, ThemeMode.dark);
    },
  );

  testWidgets('adapts at 320, 375, and tablet widths with scaled text', (
    tester,
  ) async {
    final responsiveNotes = [
      sampleNote.copyWith(
        title: 'A pinned note with a title that needs room to wrap',
        tags: const ['a very long planning category', 'design', 'mobile'],
      ),
      sampleNotes[1].copyWith(
        content:
            'This preview is intentionally long enough to exercise natural '
            'wrapping at a larger system text size.',
        tags: const ['a very long planning category', 'accessibility'],
      ),
      sampleNotes[2],
    ];
    final surfaces =
        <({Size size, int columns, double contentWidth, ThemeMode mode})>[
          (
            size: const Size(320, 1000),
            columns: 1,
            contentWidth: 288,
            mode: ThemeMode.light,
          ),
          (
            size: const Size(359, 1000),
            columns: 1,
            contentWidth: 327,
            mode: ThemeMode.light,
          ),
          (
            size: const Size(360, 1000),
            columns: 2,
            contentWidth: 328,
            mode: ThemeMode.light,
          ),
          (
            size: const Size(375, 1000),
            columns: 2,
            contentWidth: 343,
            mode: ThemeMode.light,
          ),
          (
            size: const Size(390, 1000),
            columns: 2,
            contentWidth: 358,
            mode: ThemeMode.light,
          ),
          (
            size: const Size(600, 1100),
            columns: 2,
            contentWidth: 552,
            mode: ThemeMode.dark,
          ),
          (
            size: const Size(700, 1100),
            columns: 3,
            contentWidth: 652,
            mode: ThemeMode.dark,
          ),
          (
            size: const Size(768, 1100),
            columns: 3,
            contentWidth: 720,
            mode: ThemeMode.dark,
          ),
          (
            size: const Size(900, 1200),
            columns: 3,
            contentWidth: 840,
            mode: ThemeMode.dark,
          ),
        ];

    for (final surface in surfaces) {
      await _pumpHome(
        tester,
        repository: InMemoryNoteRepository.seeded(responsiveNotes),
        size: surface.size,
        textScaler: const TextScaler.linear(1.5),
        themeMode: surface.mode,
      );
      final searchWidth = tester
          .getSize(find.byKey(const Key('notes-home-search')))
          .width;
      final searchHeight = tester
          .getSize(find.byKey(const Key('notes-home-search')))
          .height;
      final allChipHeight = tester
          .getSize(find.widgetWithText(FilterChip, 'All'))
          .height;

      if (find.byType(SliverMasonryGrid).evaluate().isEmpty) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await tester.pumpAndSettle();
      }

      final masonry = tester.widget<SliverMasonryGrid>(
        find.byType(SliverMasonryGrid),
      );
      final delegate =
          masonry.gridDelegate
              as SliverSimpleGridDelegateWithFixedCrossAxisCount;
      expect(delegate.crossAxisCount, surface.columns);
      final expectedCardWidth =
          (surface.contentWidth - (surface.columns - 1) * 12) / surface.columns;
      expect(
        tester.getSize(find.byKey(const ValueKey('note-card-2'))).width,
        moreOrLessEquals(expectedCardWidth),
      );
      expect(searchWidth, moreOrLessEquals(surface.contentWidth));
      expect(searchHeight, greaterThanOrEqualTo(52));
      expect(allChipHeight, greaterThanOrEqualTo(44));
      expect(find.byType(RefreshIndicator), findsOneWidget);
      expect(find.byType(SafeArea), findsOneWidget);
      final scrollView = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      expect(scrollView.physics, isA<AlwaysScrollableScrollPhysics>());
      final bottomSliver = scrollView.slivers.last as SliverPadding;
      expect(bottomSliver.key, const Key('notes-home-bottom-padding'));
      final bottomPadding = bottomSliver.padding
          .resolve(TextDirection.ltr)
          .bottom;
      expect(bottomPadding, greaterThanOrEqualTo(112));
      expect(tester.takeException(), isNull, reason: '${surface.size}');
    }
  });

  testWidgets('loading grid matches populated columns at every breakpoint', (
    tester,
  ) async {
    final surfaces = <({Size size, int columns, double contentWidth})>[
      (size: const Size(359, 1000), columns: 1, contentWidth: 327),
      (size: const Size(360, 1000), columns: 2, contentWidth: 328),
      (size: const Size(390, 1000), columns: 2, contentWidth: 358),
      (size: const Size(600, 1100), columns: 2, contentWidth: 552),
      (size: const Size(700, 1100), columns: 3, contentWidth: 652),
      (size: const Size(768, 1100), columns: 3, contentWidth: 720),
      (size: const Size(900, 1200), columns: 3, contentWidth: 840),
    ];

    for (final surface in surfaces) {
      final repository = _DeferredNoteRepository(sampleNotes);
      await _pumpHome(
        tester,
        repository: repository,
        size: surface.size,
        settle: false,
      );
      await tester.pump();

      final masonry = tester.widget<SliverMasonryGrid>(
        find.descendant(
          of: find.byType(NotesSkeleton),
          matching: find.byType(SliverMasonryGrid),
        ),
      );
      final delegate =
          masonry.gridDelegate
              as SliverSimpleGridDelegateWithFixedCrossAxisCount;
      expect(
        delegate.crossAxisCount,
        surface.columns,
        reason: '${surface.size.width} loading columns',
      );
      final expectedCardWidth =
          (surface.contentWidth - (surface.columns - 1) * 12) / surface.columns;
      expect(
        tester.getSize(find.byKey(const Key('notes-skeleton-card-0'))).width,
        moreOrLessEquals(expectedCardWidth),
        reason: '${surface.size.width} loading card width',
      );

      repository.release();
      await tester.pumpAndSettle();
    }
  });
}

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  required InMemoryNoteRepository repository,
  Size size = const Size(375, 1000),
  TextScaler textScaler = TextScaler.noScaling,
  ThemeMode themeMode = ThemeMode.light,
  ThemeModeStore? themeStore,
  FakeNoteReminderGateway? reminderGateway,
  VoidCallback? onOpenSearch,
  VoidCallback? onCreateNote,
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
        if (themeStore != null)
          themeModeStoreProvider.overrideWithValue(themeStore),
      ],
      child: MaterialApp(
        theme: AuroraTheme.light(),
        darkTheme: AuroraTheme.dark(),
        themeMode: themeMode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: textScaler),
          child: child!,
        ),
        home: NotesHomePage(
          onOpenSearch: onOpenSearch,
          onCreateNote: onCreateNote,
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  }

  return ProviderScope.containerOf(tester.element(find.byType(NotesHomePage)));
}

Future<void> _revealInHome(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 8 && target.evaluate().isEmpty; attempt++) {
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -160));
    await tester.pump();
  }
  expect(target, findsOneWidget);
}

void _expectStableChrome() {
  expect(find.byKey(const Key('notes-home-header')), findsOneWidget);
  expect(find.byKey(const Key('notes-home-search')), findsOneWidget);
  expect(find.text('Search notes'), findsOneWidget);
}

void _performSemanticTap(WidgetTester tester, Finder target) {
  final node = tester.getSemantics(target);
  expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  tester.platformDispatcher.onSemanticsActionEvent!(
    SemanticsActionEvent(
      type: SemanticsAction.tap,
      nodeId: node.id,
      viewId: tester.view.viewId,
    ),
  );
}

Future<FocusNode> _focus(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && _isDescendantOf(focus.context, target)) return focus;
  }
  throw TestFailure('Could not focus the requested widget');
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

class _DeferredNoteRepository extends InMemoryNoteRepository {
  _DeferredNoteRepository(super.notes) : super.seeded();

  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<List<Note>> getNotesByStatus(NoteStatus status) async {
    await _gate.future;
    return super.getNotesByStatus(status);
  }
}

class _GatedRefreshRepository extends InMemoryNoteRepository {
  _GatedRefreshRepository(super.notes) : super.seeded();

  Completer<void>? _refreshGate;
  int gatedGetCalls = 0;

  void gateRefresh() {
    _refreshGate = Completer<void>();
    gatedGetCalls = 0;
  }

  void releaseRefresh() {
    final gate = _refreshGate;
    _refreshGate = null;
    gate?.complete();
  }

  @override
  Future<List<Note>> getNotesByStatus(NoteStatus status) async {
    final gate = _refreshGate;
    if (gate != null) {
      gatedGetCalls += 1;
      await gate.future;
    }
    return super.getNotesByStatus(status);
  }
}

class _FakeThemeModeStore implements ThemeModeStore {
  _FakeThemeModeStore(this.mode);

  ThemeMode mode;
  Object? writeError;
  Completer<void>? writeGate;
  int writeCalls = 0;

  @override
  Future<ThemeMode> readMode() async => mode;

  @override
  Future<void> writeMode(ThemeMode mode) async {
    writeCalls += 1;
    await writeGate?.future;
    if (writeError case final error?) throw error;
    this.mode = mode;
  }
}
