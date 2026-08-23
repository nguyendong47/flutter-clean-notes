import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_search_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/search_focus_request.dart';
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
        .getSemantics(find.bySemanticsLabel('Filter search results'))
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

    expect(find.text('Middle project'), findsNothing);
    expect(find.text('Zulu project'), findsOneWidget);
    expect(find.text('Alpha project'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Zulu project')).dy,
      lessThan(tester.getTopLeft(find.text('Alpha project')).dy),
    );
  });

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
    'keeps chrome stable for loading, initial error, and cached error',
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
      expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);

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
