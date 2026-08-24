import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_search_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/search_focus_request.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/glass_note_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/in_memory_note_repository.dart';
import '../../../helpers/note_fixtures.dart';

void main() {
  testWidgets('empty query shows a focused search invitation and suggestions', (
    tester,
  ) async {
    await _pumpSearch(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
    );

    expect(find.text('Search'), findsOneWidget);
    expect(find.text('Search your thoughts'), findsOneWidget);
    expect(find.text('Suggested tags'), findsOneWidget);
    expect(find.byKey(const Key('suggested-tag-work')), findsOneWidget);
    expect(find.text(sampleNote.title), findsNothing);

    final fieldSemantics = find.bySemanticsLabel(
      RegExp(r'^Search notes and tags$'),
    );
    expect(fieldSemantics, findsOneWidget);
    final semanticsData = tester
        .getSemantics(fieldSemantics)
        .getSemanticsData();
    expect(semanticsData.label, 'Search notes and tags');
    expect(semanticsData.hasAction(SemanticsAction.tap), isTrue);
    expect(
      tester.getSize(find.byKey(const Key('notes-search-field'))).height,
      greaterThanOrEqualTo(52),
    );
    expect(
      tester.getSize(find.byKey(const Key('notes-search-filter'))).height,
      greaterThanOrEqualTo(44),
    );
  });

  testWidgets('normalizes title, content, and tag search text', (tester) async {
    await _pumpSearch(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
    );
    final field = find.byKey(const Key('notes-search-field'));

    await tester.enterText(field, '  AURORA  ');
    await tester.pumpAndSettle();
    expect(find.text('Aurora design'), findsOneWidget);
    expect(find.text('Design follow-up'), findsNothing);

    await tester.enterText(field, 'MOBILE MOCKUPS');
    await tester.pumpAndSettle();
    expect(find.text('Design follow-up'), findsOneWidget);
    expect(find.text('Aurora design'), findsNothing);

    await tester.enterText(field, 'PERSONAL');
    await tester.pumpAndSettle();
    expect(find.text('Personal errands'), findsOneWidget);
    expect(find.text('Design follow-up'), findsNothing);
  });

  testWidgets('no match offers query-only clear and restores field focus', (
    tester,
  ) async {
    final container = await _pumpSearch(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
    );
    container.read(selectedTagProvider.notifier).select('work');
    await tester.enterText(
      find.byKey(const Key('notes-search-field')),
      'missing phrase',
    );
    await tester.pumpAndSettle();

    expect(find.text('No notes match “missing phrase”'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Clear search'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Reset filters'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Clear search'));
    await tester.pump();
    await tester.pump();

    expect(container.read(searchQueryProvider), isEmpty);
    expect(container.read(selectedTagProvider), 'work');
    expect(
      tester
          .widget<SearchBar>(find.byKey(const Key('notes-search-field')))
          .focusNode
          ?.hasFocus,
      isTrue,
    );
    expect(find.text('Search your thoughts'), findsOneWidget);
  });

  testWidgets('filter tags and sort choices update visible result order', (
    tester,
  ) async {
    final notes = [
      _note(1, 'Alpha project', const ['work'], DateTime.utc(2026, 1, 1)),
      _note(2, 'Zulu project', const ['work'], DateTime.utc(2026, 1, 3)),
      _note(3, 'Middle project', const ['personal'], DateTime.utc(2026, 1, 2)),
    ];
    await _pumpSearch(
      tester,
      repository: InMemoryNoteRepository.seeded(notes),
      size: const Size(600, 1000),
    );
    await tester.enterText(
      find.byKey(const Key('notes-search-field')),
      'project',
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('notes-search-filter')));
    await tester.pumpAndSettle();
    final filterSemantics = tester
        .getSemantics(find.bySemanticsLabel('Search filters, 0 active'))
        .getSemanticsData();
    expect(filterSemantics.flagsCollection.isExpanded, Tristate.isTrue);

    final workTag = find.byKey(const Key('filter-tag-work'));
    await tester.tap(workTag);
    await tester.pump();
    expect(
      tester.getSemantics(workTag).flagsCollection.isSelected,
      Tristate.isTrue,
    );

    final titleZa = find.byKey(const Key('sort-option-titleZA'));
    await tester.tap(titleZa);
    await tester.pump();
    expect(
      tester.getSemantics(titleZa).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(tester.getSize(titleZa).height, greaterThanOrEqualTo(48));

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    final closedFilter = find.bySemanticsLabel('Search filters, 2 active');
    expect(closedFilter, findsOneWidget);
    expect(
      tester.getSemantics(closedFilter).flagsCollection.isExpanded,
      Tristate.isFalse,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('notes-search-filter-badge')),
        matching: find.text('2'),
      ),
      findsOneWidget,
    );
    expect(find.text('Middle project'), findsNothing);
    expect(find.text('Zulu project'), findsOneWidget);
    expect(find.text('Alpha project'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Zulu project')).dy,
      lessThan(tester.getTopLeft(find.text('Alpha project')).dy),
    );
  });

  testWidgets(
    'Reset filters restores matching notes in newest order and clears badge',
    (tester) async {
      final notes = [
        _note(1, 'Alpha project', const ['work'], DateTime.utc(2026, 1, 1)),
        _note(2, 'Zulu project', const ['work'], DateTime.utc(2026, 1, 3)),
        _note(3, 'Middle project', const [
          'personal',
        ], DateTime.utc(2026, 1, 2)),
        _note(4, 'Blocked thought', const [
          'blocked',
        ], DateTime.utc(2026, 1, 4)),
      ];
      await _pumpSearch(
        tester,
        repository: InMemoryNoteRepository.seeded(notes),
        size: const Size(600, 1000),
      );
      await tester.enterText(
        find.byKey(const Key('notes-search-field')),
        'project',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notes-search-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-tag-blocked')));
      await tester.tap(find.byKey(const Key('sort-option-titleZA')));
      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('notes-search-filter-badge')),
        findsOneWidget,
      );
      expect(find.textContaining('No notes match'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Reset filters'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('notes-search-filter-badge')), findsNothing);
      expect(
        tester
            .widget<SearchBar>(find.byKey(const Key('notes-search-field')))
            .controller
            ?.text,
        'project',
      );
      expect(find.text('Blocked thought'), findsNothing);
      expect(find.text('Zulu project'), findsOneWidget);
      expect(find.text('Middle project'), findsOneWidget);
      expect(find.text('Alpha project'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Zulu project')).dy,
        lessThan(tester.getTopLeft(find.text('Middle project')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Middle project')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha project')).dy),
      );
    },
  );

  testWidgets('tapping a full-width result opens the selected note', (
    tester,
  ) async {
    Note? opened;
    await _pumpSearch(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
      onOpenNote: (note) => opened = note,
    );
    await tester.enterText(
      find.byKey(const Key('notes-search-field')),
      'Aurora',
    );
    await tester.pumpAndSettle();

    final resultCard = find.byKey(const Key('search-result-note-1'));
    expect(
      tester.getSize(resultCard).width,
      tester.getSize(find.byKey(const Key('notes-search-field'))).width,
    );
    await tester.tap(find.bySemanticsLabel('Open note Aurora design'));
    await tester.pump();
    expect(opened, same(sampleNote));
  });

  testWidgets(
    'archive and trash wait for persistence then disappear with working Undo',
    (tester) async {
      for (final scenario in <({String action, NoteStatus status})>[
        (action: 'Archive', status: NoteStatus.archived),
        (action: 'Move to trash', status: NoteStatus.trashed),
      ]) {
        final repository = _GatedStatusRepository(sampleNotes);
        await _pumpSearch(
          tester,
          repository: repository,
          size: const Size(600, 1000),
        );
        await tester.enterText(
          find.byKey(const Key('notes-search-field')),
          'follow-up',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('More actions for Design follow-up'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(scenario.action).last);
        await tester.pump();

        expect(find.text('Design follow-up'), findsOneWidget);
        expect(_statusOf(repository, 2), NoteStatus.active);
        expect(find.text('Undo'), findsNothing);
        expect(find.byType(SnackBar), findsNothing);

        repository.release();
        await tester.pumpAndSettle();

        expect(_statusOf(repository, 2), scenario.status);
        expect(find.text('Design follow-up'), findsNothing);
        expect(find.text('Undo'), findsOneWidget);
        expect(
          tester.widget<SnackBar>(find.byType(SnackBar)).behavior,
          SnackBarBehavior.floating,
        );

        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();

        expect(_statusOf(repository, 2), NoteStatus.active);
        expect(find.text('Design follow-up'), findsOneWidget);
      }
    },
  );

  testWidgets(
    'archive and trash failures keep results and show only neutral copy',
    (tester) async {
      for (final action in ['Archive', 'Move to trash']) {
        final repository = _GatedStatusRepository(
          sampleNotes,
          failure: StateError('sensitive storage failure'),
        );
        await _pumpSearch(
          tester,
          repository: repository,
          size: const Size(600, 1000),
        );
        await tester.enterText(
          find.byKey(const Key('notes-search-field')),
          'follow-up',
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byTooltip('More actions for Design follow-up'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(action).last);
        await tester.pump();

        expect(find.text('Design follow-up'), findsOneWidget);
        expect(find.text('Undo'), findsNothing);
        repository.release();
        await tester.pumpAndSettle();

        expect(_statusOf(repository, 2), NoteStatus.active);
        expect(find.text('Design follow-up'), findsOneWidget);
        expect(find.text('Undo'), findsNothing);
        expect(
          find.text('Could not update this note. Try again.'),
          findsOneWidget,
        );
        expect(find.textContaining('sensitive storage failure'), findsNothing);
      }
    },
  );

  testWidgets(
    'committed archive and trash refresh failures warn once and Undo restores',
    (tester) async {
      for (final scenario
          in <({String action, NoteStatus status, String successMessage})>[
            (
              action: 'Archive',
              status: NoteStatus.archived,
              successMessage: 'Note archived',
            ),
            (
              action: 'Move to trash',
              status: NoteStatus.trashed,
              successMessage: 'Note moved to trash',
            ),
          ]) {
        final repository = InMemoryNoteRepository.seeded(sampleNotes);
        final container = await _pumpSearch(
          tester,
          repository: repository,
          size: const Size(600, 1000),
        );
        await tester.enterText(
          find.byKey(const Key('notes-search-field')),
          'follow-up',
        );
        await tester.pumpAndSettle();
        final refreshFailure = StateError('note refresh failed');
        repository.getError = refreshFailure;

        await tester.tap(find.byTooltip('More actions for Design follow-up'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(scenario.action).last);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));

        expect(_statusOf(repository, 2), scenario.status);
        expect(
          find.text('Design follow-up'),
          findsOneWidget,
          reason: 'The failed refresh keeps the cached active card visible.',
        );
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          find.text(
            '${scenario.successMessage}. '
            'Could not refresh notes; showing saved notes.',
          ),
          findsOneWidget,
        );
        expect(find.text('Undo'), findsOneWidget);
        expect(
          find.byKey(const Key('notes-search-cached-error')),
          findsNothing,
        );
        expect(
          find.text('Could not update this note. Try again.'),
          findsNothing,
        );
        expect(find.textContaining('note refresh'), findsNothing);
        expect(find.textContaining('StateError'), findsNothing);

        repository.getError = null;
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();

        expect(_statusOf(repository, 2), NoteStatus.active);
        expect(find.text('Design follow-up'), findsOneWidget);

        repository.getError = refreshFailure;
        container.invalidate(notesProvider);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('notes-search-cached-error')),
          findsOneWidget,
        );
      }
    },
  );

  testWidgets(
    'committed pin refresh failure leaves one sanitized cached notice',
    (tester) async {
      final repository = InMemoryNoteRepository.seeded(sampleNotes);
      final container = await _pumpSearch(
        tester,
        repository: repository,
        size: const Size(600, 1000),
      );
      await tester.enterText(
        find.byKey(const Key('notes-search-field')),
        'follow-up',
      );
      await tester.pumpAndSettle();
      repository.getError = StateError(r'C:\private\notes.db refresh failed');

      await tester.tap(find.byTooltip('More actions for Design follow-up'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pin note').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        repository.notes.singleWhere((note) => note.id == 2).isPinned,
        isTrue,
      );
      expect(container.read(notesProvider).hasError, isTrue);
      expect(container.read(notesProvider).hasValue, isTrue);
      expect(
        find.byKey(const Key('notes-search-cached-error')),
        findsOneWidget,
      );
      expect(
        find.text('Could not refresh notes. Showing saved notes.'),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(find.textContaining('notes.db'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
    },
  );

  testWidgets(
    'busy result keeps its card-local progress when sort reorders the list',
    (tester) async {
      final notes = [
        _note(1, 'Alpha project', const ['work'], DateTime.utc(2026, 1, 3)),
        _note(2, 'Zulu project', const ['work'], DateTime.utc(2026, 1, 1)),
      ];
      final repository = _GatedStatusRepository(notes);
      final container = await _pumpSearch(
        tester,
        repository: repository,
        size: const Size(600, 1000),
      );
      await tester.enterText(
        find.byKey(const Key('notes-search-field')),
        'project',
      );
      await tester.pumpAndSettle();

      const alphaKey = ValueKey('search-result-note-1');
      const zuluKey = ValueKey('search-result-note-2');
      final list = tester.widget<ListView>(
        find.byKey(const PageStorageKey('notes-search-scroll')),
      );
      final delegate = list.childrenDelegate as SliverChildBuilderDelegate;
      expect(delegate.findChildIndexCallback, isNotNull);
      expect(delegate.findChildIndexCallback!(alphaKey), 5);
      expect(delegate.findChildIndexCallback!(zuluKey), 6);

      await tester.tap(find.byTooltip('More actions for Alpha project'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Archive').last);
      await tester.pump();

      expect(find.byKey(const Key('notes-search-loading')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(alphaKey),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      container.read(sortOrderProvider.notifier).set(NoteSort.titleZA);
      await tester.pump();

      final reorderedList = tester.widget<ListView>(
        find.byKey(const PageStorageKey('notes-search-scroll')),
      );
      final reorderedDelegate =
          reorderedList.childrenDelegate as SliverChildBuilderDelegate;
      expect(reorderedDelegate.findChildIndexCallback!(zuluKey), 5);
      expect(reorderedDelegate.findChildIndexCallback!(alphaKey), 6);
      expect(find.byKey(const Key('notes-search-loading')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(alphaKey),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(zuluKey),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsNothing,
      );

      repository.release();
      await tester.pumpAndSettle();
    },
  );

  testWidgets('rapid query changes never retain duplicate result keys', (
    tester,
  ) async {
    final container = await _pumpSearch(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
    );
    final field = find.byKey(const Key('notes-search-field'));
    const result = Key('search-result-note-1');
    Key? animatedStateKey() => tester
        .widget<AnimatedSwitcher>(
          find.byKey(const Key('notes-search-switcher')),
        )
        .child
        ?.key;

    await tester.enterText(field, 'Aurora');
    await tester.pumpAndSettle();
    expect(find.byKey(result), findsOneWidget);
    expect(animatedStateKey(), const ValueKey('results'));

    await tester.enterText(field, 'design');
    await tester.pump(const Duration(milliseconds: 60));
    await tester.enterText(field, 'Aurora');
    await tester.pump(const Duration(milliseconds: 60));
    container.read(selectedTagProvider.notifier).select('design');
    container.read(sortOrderProvider.notifier).set(NoteSort.titleZA);
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.byKey(result), findsOneWidget);
    expect(animatedStateKey(), const ValueKey('results'));
  });

  testWidgets('large result sets build only a viewport-bounded card subset', (
    tester,
  ) async {
    final notes = List.generate(
      250,
      (index) => _note(
        index + 1,
        'Viewport result $index',
        const ['large'],
        DateTime.utc(2026, 1, 1).add(Duration(minutes: index)),
      ),
    );
    await _pumpSearch(tester, repository: InMemoryNoteRepository.seeded(notes));

    await tester.enterText(
      find.byKey(const Key('notes-search-field')),
      'viewport',
    );
    await tester.pumpAndSettle();

    final builtCards = find.byType(GlassNoteCard).evaluate().length;
    expect(find.text('250 results'), findsOneWidget);
    expect(builtCards, greaterThan(0));
    expect(builtCards, lessThan(25));
  });

  testWidgets(
    'query and filter changes expose exactly one live result status',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final container = await _pumpSearch(
        tester,
        repository: InMemoryNoteRepository.seeded(sampleNotes),
      );
      final field = find.byKey(const Key('notes-search-field'));

      await tester.enterText(field, 'design');
      await tester.pumpAndSettle();
      _expectSingleLiveSearchStatus(tester, '2 results');
      expect(find.text('2 results'), findsOneWidget);

      container.read(selectedTagProvider.notifier).select('design');
      await tester.pump();
      _expectSingleLiveSearchStatus(tester, '1 result');
      expect(find.text('1 result'), findsOneWidget);

      await tester.enterText(field, 'missing phrase');
      await tester.pump();
      _expectSingleLiveSearchStatus(tester, 'No notes match your search');
      expect(find.textContaining('No notes match'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('provider updates synchronize text and preserve selection once', (
    tester,
  ) async {
    final container = await _pumpSearch(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
    );
    final controller = tester
        .widget<SearchBar>(find.byKey(const Key('notes-search-field')))
        .controller!;
    var emissions = 0;
    final subscription = container.listen<String>(
      searchQueryProvider,
      (previous, next) => emissions++,
    );
    addTearDown(subscription.close);

    container.read(searchQueryProvider.notifier).setQuery('draft query');
    await tester.pump();
    expect(controller.text, 'draft query');
    expect(emissions, 1);

    controller.selection = const TextSelection(baseOffset: 1, extentOffset: 5);
    emissions = 0;
    container.read(searchQueryProvider.notifier).setQuery('provider update');
    await tester.pump();

    expect(controller.text, 'provider update');
    expect(
      controller.selection,
      const TextSelection(baseOffset: 1, extentOffset: 5),
    );
    expect(emissions, 1);
  });

  testWidgets('indexed restoration does not focus until one-shot request', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
    );
    final searchBar = tester.widget<SearchBar>(
      find.byKey(const Key('notes-search-field'), skipOffstage: false),
    );
    expect(searchBar.focusNode?.hasFocus, isFalse);

    await tester.tap(find.widgetWithText(FilledButton, 'Open search'));
    expect(searchBar.focusNode?.hasFocus, isFalse);
    await tester.pump();

    expect(searchBar.focusNode?.hasFocus, isTrue);
    expect(find.text('Search'), findsOneWidget);
  });

  testWidgets(
    'cached refresh error preserves search state and Retry clears it',
    (tester) async {
      final repository = InMemoryNoteRepository.seeded([
        _note(1, 'Alpha project', const ['work'], DateTime.utc(2026, 1, 1)),
        _note(2, 'Zulu project', const ['work'], DateTime.utc(2026, 1, 3)),
        _note(3, 'Middle project', const [
          'personal',
        ], DateTime.utc(2026, 1, 2)),
      ]);
      final container = await _pumpSearch(
        tester,
        repository: repository,
        size: const Size(320, 900),
        textScaler: const TextScaler.linear(1.5),
      );
      final searchField = find.byKey(const Key('notes-search-field'));

      await tester.enterText(searchField, 'project');
      container.read(selectedTagProvider.notifier).select('work');
      container.read(sortOrderProvider.notifier).set(NoteSort.titleZA);
      await tester.pumpAndSettle();

      repository.getError = StateError(
        r'C:\Users\private\Documents\notes.db unavailable',
      );
      container.invalidate(notesProvider);
      await tester.pumpAndSettle();

      final cachedState = container.read(notesProvider);
      expect(cachedState.hasError, isTrue);
      expect(cachedState.hasValue, isTrue);
      final notice = find.byKey(const Key('notes-search-cached-error'));
      expect(notice, findsOneWidget);
      expect(
        find.text('Could not refresh notes. Showing saved notes.'),
        findsOneWidget,
      );
      expect(tester.getSemantics(notice).flagsCollection.isLiveRegion, isTrue);
      final retry = find.byKey(const Key('notes-search-cached-error-retry'));
      expect(retry, findsOneWidget);
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('notes.db'), findsNothing);
      expect(find.textContaining('StateError'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.widget<SearchBar>(searchField).controller?.text, 'project');
      expect(container.read(selectedTagProvider), 'work');
      expect(container.read(sortOrderProvider), NoteSort.titleZA);
      expect(find.text('Middle project'), findsNothing);
      expect(find.text('Zulu project'), findsOneWidget);
      expect(find.text('Alpha project'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Zulu project')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha project')).dy),
      );

      await tester.tap(retry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(notice, findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      expect(container.read(notesProvider).hasError, isTrue);
      expect(find.textContaining('notes.db'), findsNothing);

      repository.getError = null;
      await tester.tap(retry);
      await tester.pumpAndSettle();

      expect(container.read(notesProvider), isA<AsyncData<List<Note>>>());
      expect(notice, findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(tester.takeException(), isNull);
      expect(tester.widget<SearchBar>(searchField).controller?.text, 'project');
      expect(container.read(selectedTagProvider), 'work');
      expect(container.read(sortOrderProvider), NoteSort.titleZA);
      expect(find.text('Middle project'), findsNothing);
      expect(find.text('Zulu project'), findsOneWidget);
      expect(find.text('Alpha project'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Zulu project')).dy,
        lessThan(tester.getTopLeft(find.text('Alpha project')).dy),
      );
    },
  );

  testWidgets('loading search results announces one contextual live region', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final deferred = _DeferredNoteRepository(sampleNotes);
    await _pumpSearch(tester, repository: deferred, settle: false);
    await tester.pump();

    _expectStableSearchChrome();
    expect(find.byKey(const Key('notes-search-loading')), findsOneWidget);
    final loading = find.bySemanticsLabel('Loading search results');
    expect(loading, findsOneWidget);
    final loadingNode = tester.getSemantics(loading);
    expect(loadingNode.getSemanticsData().flagsCollection.isLiveRegion, isTrue);
    expect(loadingNode.childrenCountInTraversalOrder, 0);

    deferred.release();
    await tester.pumpAndSettle();
    semantics.dispose();
  });

  testWidgets(
    'keeps chrome stable for loading, initial error, and pre-write failure',
    (tester) async {
      final deferred = _DeferredNoteRepository(sampleNotes);
      await _pumpSearch(tester, repository: deferred, settle: false);
      await tester.pump();
      _expectStableSearchChrome();
      expect(find.byKey(const Key('notes-search-loading')), findsOneWidget);

      deferred.release();
      await tester.pumpAndSettle();
      expect(find.text('Search your thoughts'), findsOneWidget);

      final failed = InMemoryNoteRepository.seeded(const [])
        ..getError = StateError('read failed');
      await _pumpSearch(tester, repository: failed);
      _expectStableSearchChrome();
      expect(find.text('Could not load notes'), findsOneWidget);
      expect(find.text('Please try again in a moment.'), findsOneWidget);
      expect(find.textContaining('connection'), findsNothing);
      expect(find.textContaining('read failed'), findsNothing);
      expect(
        find.text('Could not refresh notes. Showing saved notes.'),
        findsNothing,
      );
      final retry = find.widgetWithText(FilledButton, 'Try again');
      expect(retry, findsOneWidget);

      await tester.tap(retry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Could not refresh notes. Try again.'), findsOneWidget);
      expect(find.textContaining('read failed'), findsNothing);

      final cached = InMemoryNoteRepository.seeded(sampleNotes);
      final container = await _pumpSearch(tester, repository: cached);
      cached.updateError = StateError('write failed');
      final before = container.read(notesProvider).requireValue;
      await expectLater(
        container.read(notesProvider.notifier).togglePin(before.first),
        throwsStateError,
      );
      await tester.pumpAndSettle();

      final state = container.read(notesProvider);
      expect(state, isA<AsyncData<List<Note>>>());
      expect(state.value, same(before));
      expect(state.hasError, isFalse);
      _expectStableSearchChrome();
      expect(find.text('Search your thoughts'), findsOneWidget);
      expect(
        find.text('Could not refresh notes. Showing saved notes.'),
        findsNothing,
      );
      expect(find.textContaining('write failed'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    },
  );

  testWidgets('distinguishes a completely empty notebook with a create path', (
    tester,
  ) async {
    await _pumpSearch(
      tester,
      repository: InMemoryNoteRepository.seeded(const []),
    );

    expect(find.text('No notes yet'), findsOneWidget);
    final create = find.widgetWithText(FilledButton, 'Create note');
    expect(create, findsOneWidget);
    expect(tester.getSize(create).height, greaterThanOrEqualTo(48));
    expect(find.text('Search your thoughts'), findsNothing);
  });

  testWidgets('adapts at 320 with scaled text in both Aurora themes', (
    tester,
  ) async {
    final responsiveNotes = [
      sampleNote.copyWith(
        title: 'A long searchable title that needs room to wrap naturally',
        content: 'A long searchable body for the narrow mobile result.',
        tags: const ['a very long planning category', 'accessibility'],
      ),
    ];

    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await _pumpSearch(
        tester,
        repository: InMemoryNoteRepository.seeded(responsiveNotes),
        size: const Size(320, 900),
        textScaler: const TextScaler.linear(1.5),
        themeMode: mode,
      );
      await tester.enterText(
        find.byKey(const Key('notes-search-field')),
        'searchable',
      );
      await tester.pumpAndSettle();

      expect(
        tester.getSize(find.byKey(const Key('notes-search-field'))).width,
        moreOrLessEquals(288),
      );
      expect(find.textContaining('A long searchable title'), findsOneWidget);
      expect(find.byType(SafeArea), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$mode');
    }
  });

  testWidgets('uses immediate state changes when animations are disabled', (
    tester,
  ) async {
    await _pumpSearch(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
    );
    expect(
      tester
          .widget<AnimatedSwitcher>(
            find.byKey(const Key('notes-search-switcher')),
          )
          .duration,
      const Duration(milliseconds: 200),
    );

    await _pumpSearch(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
      disableAnimations: true,
    );
    expect(
      tester
          .widget<AnimatedSwitcher>(
            find.byKey(const Key('notes-search-switcher')),
          )
          .duration,
      Duration.zero,
    );
  });

  testWidgets('filter sheet reflows above keyboard and safe area', (
    tester,
  ) async {
    final notes = [
      sampleNote.copyWith(
        tags: const [
          'a very long planning category',
          'a second lengthy category',
          'accessibility',
        ],
      ),
    ];
    await _pumpSearch(
      tester,
      repository: InMemoryNoteRepository.seeded(notes),
      size: const Size(320, 700),
      textScaler: const TextScaler.linear(1.5),
      themeMode: ThemeMode.dark,
      viewInsets: const EdgeInsets.only(bottom: 240),
    );

    await tester.tap(find.byKey(const Key('notes-search-filter')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('note-filter-sheet')), findsOneWidget);
    expect(find.byType(SafeArea), findsWidgets);
    expect(find.byKey(const Key('filter-tag-accessibility')), findsOneWidget);
    final done = find.widgetWithText(FilledButton, 'Done');
    await tester.ensureVisible(done);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(done).bottom,
      lessThanOrEqualTo(tester.view.physicalSize.height - 240),
    );
    expect(tester.takeException(), isNull);

    await tester.tap(done);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('note-filter-sheet')), findsNothing);
  });

  for (final textScale in [2.0, 3.0]) {
    testWidgets(
      'filter footer stacks full-width actions at 320 with ${textScale}x text and keyboard',
      (tester) async {
        // Mutation caught: returning to a fixed-height horizontal footer clips
        // enlarged labels and can leave the Done action behind the keyboard.
        await _pumpSearch(
          tester,
          repository: InMemoryNoteRepository.seeded(sampleNotes),
          size: const Size(320, 640),
          textScaler: TextScaler.linear(textScale),
          themeMode: ThemeMode.dark,
          viewInsets: const EdgeInsets.only(bottom: 200),
        );

        await tester.tap(find.byKey(const Key('notes-search-filter')));
        await tester.pumpAndSettle();

        final clear = find.widgetWithText(OutlinedButton, 'Clear filters');
        final done = find.widgetWithText(FilledButton, 'Done');
        await tester.ensureVisible(done);
        await tester.pumpAndSettle();

        final clearRect = tester.getRect(clear);
        final doneRect = tester.getRect(done);
        expect(clearRect.width, moreOrLessEquals(doneRect.width));
        expect(clearRect.height, greaterThanOrEqualTo(48));
        expect(doneRect.height, greaterThanOrEqualTo(48));
        expect(clearRect.bottom + 8, lessThanOrEqualTo(doneRect.top));
        expect(clearRect.overlaps(doneRect), isFalse);
        expect(
          clearRect.contains(tester.getRect(find.text('Clear filters')).center),
          isTrue,
        );
        expect(
          doneRect.contains(tester.getRect(find.text('Done')).center),
          isTrue,
        );
        expect(doneRect.bottom, lessThanOrEqualTo(440.1));
        expect(tester.takeException(), isNull);
      },
    );
  }
}

Future<ProviderContainer> _pumpSearch(
  WidgetTester tester, {
  required InMemoryNoteRepository repository,
  Size size = const Size(375, 900),
  TextScaler textScaler = TextScaler.noScaling,
  ThemeMode themeMode = ThemeMode.light,
  bool disableAnimations = false,
  EdgeInsets viewInsets = EdgeInsets.zero,
  ValueChanged<Note>? onOpenNote,
  bool settle = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AuroraTheme.light(),
        darkTheme: AuroraTheme.dark(),
        themeMode: themeMode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: textScaler,
            disableAnimations: disableAnimations,
            viewInsets: viewInsets,
          ),
          child: child!,
        ),
        home: NotesSearchPage(onOpenNote: onOpenNote),
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();

  return ProviderScope.containerOf(
    tester.element(find.byType(NotesSearchPage)),
  );
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required InMemoryNoteRepository repository,
}) async {
  tester.view.physicalSize = const Size(375, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AuroraTheme.light(),
        home: const _IndexedSearchHarness(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _expectStableSearchChrome() {
  expect(find.text('Search'), findsOneWidget);
  expect(find.byKey(const Key('notes-search-field')), findsOneWidget);
  expect(find.byKey(const Key('notes-search-filter')), findsOneWidget);
}

void _expectSingleLiveSearchStatus(WidgetTester tester, String label) {
  final status = find.byKey(const Key('notes-search-status'));
  expect(status, findsOneWidget);
  final data = tester.getSemantics(status).getSemanticsData();
  expect(data.label, label);
  expect(data.flagsCollection.isLiveRegion, isTrue);
  expect(
    find.descendant(
      of: find.byType(NotesSearchPage),
      matching: find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.liveRegion == true,
      ),
    ),
    findsOneWidget,
  );
}

NoteStatus _statusOf(InMemoryNoteRepository repository, int id) {
  return repository.notes.singleWhere((note) => note.id == id).status;
}

Note _note(int id, String title, List<String> tags, DateTime createdAt) {
  return Note(
    id: id,
    title: title,
    content: '$title details',
    color: 0xFF6757D9,
    createdAt: createdAt,
    tags: tags,
  );
}

class _IndexedSearchHarness extends ConsumerStatefulWidget {
  const _IndexedSearchHarness();

  @override
  ConsumerState<_IndexedSearchHarness> createState() =>
      _IndexedSearchHarnessState();
}

class _IndexedSearchHarnessState extends ConsumerState<_IndexedSearchHarness> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: _index,
      children: [
        Center(
          child: FilledButton(
            onPressed: () {
              setState(() => _index = 1);
              ref.read(searchFocusRequestProvider.notifier).requestFocus();
            },
            child: const Text('Open search'),
          ),
        ),
        const NotesSearchPage(),
      ],
    );
  }
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

class _GatedStatusRepository extends InMemoryNoteRepository {
  _GatedStatusRepository(super.notes, {this.failure}) : super.seeded();

  final Object? failure;
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<int> setNoteStatus(int id, NoteStatus status) async {
    await _gate.future;
    if (failure case final error?) throw error;
    return super.setNoteStatus(id, status);
  }
}
