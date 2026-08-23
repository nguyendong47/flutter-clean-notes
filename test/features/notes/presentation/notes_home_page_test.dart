import 'dart:async';
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_home_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/notes_state_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/in_memory_note_repository.dart';
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
    final repository = _DeferredNoteRepository(sampleNotes);
    await _pumpHome(tester, repository: repository, settle: false);
    await tester.pump();

    _expectStableChrome();
    expect(find.byType(NotesSkeleton), findsOneWidget);
    expect(find.byKey(const Key('notes-skeleton-card-0')), findsOneWidget);
    expect(find.byKey(const Key('notes-skeleton-card-3')), findsOneWidget);

    repository.release();
    await tester.pumpAndSettle();
    expect(find.byType(NotesSkeleton), findsNothing);
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
    final retry = find.widgetWithText(FilledButton, 'Try again');
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));

    repository.getError = null;
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(find.byType(NotesEmptyState), findsOneWidget);
  });

  testWidgets('cached error keeps notes visible and announces one snackbar', (
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

    _expectStableChrome();
    expect(find.text(sampleNote.title), findsOneWidget);
    expect(find.byType(NotesErrorState), findsNothing);
    expect(find.textContaining('write failed'), findsOneWidget);
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
    final restoreError = StateError('restore failed');
    repository.statusError = restoreError;

    await tester.tap(find.text('Undo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(_statusOf(repository, 2), NoteStatus.archived);
    expect(container.read(notesProvider).error, same(restoreError));
    _expectStableChrome();
    expect(find.text(sampleNote.title), findsOneWidget);
    expect(find.textContaining('restore failed'), findsOneWidget);
  });

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
            size: const Size(600, 1100),
            columns: 2,
            contentWidth: 552,
            mode: ThemeMode.dark,
          ),
          (
            size: const Size(900, 1200),
            columns: 2,
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
}

Future<ProviderContainer> _pumpHome(
  WidgetTester tester, {
  required InMemoryNoteRepository repository,
  Size size = const Size(375, 1000),
  TextScaler textScaler = TextScaler.noScaling,
  ThemeMode themeMode = ThemeMode.light,
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
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
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

void _expectStableChrome() {
  expect(find.byKey(const Key('notes-home-header')), findsOneWidget);
  expect(find.byKey(const Key('notes-home-search')), findsOneWidget);
  expect(find.text('Search notes'), findsOneWidget);
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
