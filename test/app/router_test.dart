import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_clean_notes/app/notification_service.dart';
import 'package:flutter_clean_notes/app/app_providers.dart';
import 'package:flutter_clean_notes/app/router.dart';
import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/add_edit_note_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_home_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_library_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_search_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/search_focus_request.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/library_segmented_control.dart';
import '../helpers/in_memory_note_repository.dart';
import '../helpers/note_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('router resolves shell branches and root editor routes', (
    tester,
  ) async {
    final harness = await _pumpRouter(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
    );

    expect(_path(harness.router), '/');
    expect(find.byType(NotesHomePage), findsOneWidget);
    expect(find.byType(NotesPage), findsNothing);
    expect(find.byType(FloatingActionButton), findsOneWidget);

    harness.router.go('/search');
    await tester.pumpAndSettle();
    expect(_path(harness.router), '/search');
    expect(find.byType(NotesSearchPage), findsOneWidget);

    harness.router.go('/library');
    await tester.pumpAndSettle();
    expect(_path(harness.router), '/library');
    expect(find.byType(NotesLibraryPage), findsOneWidget);

    harness.router.go('/note/new');
    await tester.pumpAndSettle();
    expect(_path(harness.router), '/note/new');
    expect(find.byType(AddEditNotePage), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.byType(AddEditNotePage))),
      same(rootNavigatorKey.currentState),
    );

    harness.router.go('/note/1');
    await tester.pumpAndSettle();
    expect(_path(harness.router), '/note/1');
    expect(find.byType(AddEditNotePage), findsOneWidget);
    expect(find.text('Aurora design'), findsOneWidget);

    harness.router.go('/note/not-a-number');
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('existing-note-not-found')), findsOneWidget);
    expect(find.byType(AddEditNotePage), findsNothing);
  });

  testWidgets('bottom create opens a root editor and returns to its branch', (
    tester,
  ) async {
    final harness = await _pumpRouter(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
      initialLocation: '/library',
    );

    await tester.tap(find.bySemanticsLabel('Create new note'));
    await tester.pumpAndSettle();

    expect(find.byType(AddEditNotePage), findsOneWidget);
    expect(
      Navigator.of(tester.element(find.byType(AddEditNotePage))),
      same(rootNavigatorKey.currentState),
    );
    expect(_path(harness.router), '/library');

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(AddEditNotePage), findsNothing);
    expect(find.byType(NotesLibraryPage), findsOneWidget);
    expect(_path(harness.router), '/library');
  });

  testWidgets('note cards open root editors from every shell branch', (
    tester,
  ) async {
    final harness = await _pumpRouter(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
    );

    await tester.tap(find.bySemanticsLabel('Open note Aurora design'));
    await tester.pumpAndSettle();
    _expectRootEditor(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(_path(harness.router), '/');

    await tester.tap(find.bySemanticsLabel('Search tab'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('notes-search-field')),
      'Aurora',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Open note Aurora design'));
    await tester.pumpAndSettle();
    _expectRootEditor(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(_path(harness.router), '/search');

    await tester.tap(find.bySemanticsLabel('Library tab'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Open note Archived launch notes'));
    await tester.pumpAndSettle();
    _expectRootEditor(tester);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(_path(harness.router), '/library');
  });

  testWidgets('Library empty action returns to the preserved Notes branch', (
    tester,
  ) async {
    final activeNotes = _manyNotes()
        .where((note) => note.status == NoteStatus.active)
        .toList();
    final harness = await _pumpRouter(
      tester,
      repository: InMemoryNoteRepository.seeded(activeNotes),
    );
    final homeScrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(NotesHomePage),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.drag(
      find.descendant(
        of: find.byType(NotesHomePage),
        matching: find.byType(CustomScrollView),
      ),
      const Offset(0, -420),
    );
    await tester.pumpAndSettle();
    final homeOffset = homeScrollable.position.pixels;
    expect(homeOffset, greaterThan(0));

    await tester.tap(find.bySemanticsLabel('Library tab'));
    await tester.pumpAndSettle();
    expect(find.text('No archived notes'), findsOneWidget);
    await tester.tap(find.text('Browse notes'));
    await tester.pumpAndSettle();

    expect(_path(harness.router), '/');
    expect(find.byType(NotesHomePage), findsOneWidget);
    expect(homeScrollable.position.pixels, moreOrLessEquals(homeOffset));
  });

  testWidgets(
    'existing-note route distinguishes loading error retry and missing',
    (tester) async {
      final deferred = _DeferredNoteRepository(sampleNotes);
      final loadingHarness = await _pumpRouter(
        tester,
        repository: deferred,
        initialLocation: '/note/1',
        settle: false,
      );
      await tester.pump();
      expect(find.byKey(const Key('existing-note-loading')), findsOneWidget);
      expect(find.byType(AddEditNotePage), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(_path(loadingHarness.router), '/');
      deferred.release();
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      loadingHarness.container.dispose();

      final failing = InMemoryNoteRepository.seeded(sampleNotes)
        ..getError = StateError('load failed');
      final errorHarness = await _pumpRouter(
        tester,
        repository: failing,
        initialLocation: '/note/1',
        manageTeardown: false,
      );
      expect(find.byKey(const Key('existing-note-error')), findsOneWidget);
      final retry = find.byKey(const Key('existing-note-retry'));
      expect(retry, findsOneWidget);
      expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));
      failing.getError = null;
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(find.byType(AddEditNotePage), findsOneWidget);
      expect(find.text('Aurora design'), findsOneWidget);

      errorHarness.router.go('/note/404');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('existing-note-not-found')), findsOneWidget);
      expect(find.byType(AddEditNotePage), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      errorHarness.container.dispose();
    },
  );

  testWidgets(
    'first Home search request focuses once and shell restore does not',
    (tester) async {
      final harness = await _pumpRouter(
        tester,
        repository: InMemoryNoteRepository.seeded(sampleNotes),
      );
      expect(_path(harness.router), '/');
      expect(find.byType(NotesHomePage), findsOneWidget);
      expect(find.byType(NotesSearchPage, skipOffstage: false), findsOneWidget);
      expect(
        find.byKey(const Key('notes-home-search'), skipOffstage: false),
        findsOneWidget,
      );
      expect(harness.container.read(searchFocusRequestProvider), 0);

      await tester.tap(find.byKey(const Key('notes-home-search')));
      await tester.pumpAndSettle();

      expect(_path(harness.router), '/search');
      expect(harness.container.read(searchFocusRequestProvider), 1);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue,
      );

      await tester.tap(find.bySemanticsLabel('Notes tab'));
      await tester.pumpAndSettle();
      await tester.tap(find.bySemanticsLabel('Search tab'));
      await tester.pumpAndSettle();

      expect(harness.container.read(searchFocusRequestProvider), 1);
      expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isFalse,
      );
    },
  );

  testWidgets(
    'branch query filter section and scroll survive switching and reselect',
    (tester) async {
      final repository = InMemoryNoteRepository.seeded(_manyNotes());
      final harness = await _pumpRouter(tester, repository: repository);

      final homeScrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(NotesHomePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.drag(
        find.descendant(
          of: find.byType(NotesHomePage),
          matching: find.byType(CustomScrollView),
        ),
        const Offset(0, -420),
      );
      await tester.pumpAndSettle();
      final homeOffset = homeScrollable.position.pixels;
      expect(homeOffset, greaterThan(0));

      await tester.tap(find.bySemanticsLabel('Search tab'));
      await tester.pumpAndSettle();
      expect(_path(harness.router), '/search');
      expect(find.byType(NotesSearchPage), findsOneWidget);
      expect(
        find.byKey(const Key('notes-search-field'), skipOffstage: false),
        findsOneWidget,
      );
      await tester.enterText(
        find.byKey(const Key('notes-search-field')),
        'State note',
      );
      harness.container.read(selectedTagProvider.notifier).select('work');
      await tester.pumpAndSettle();
      final searchScrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(NotesSearchPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.drag(find.byType(ListView), const Offset(0, -420));
      await tester.pumpAndSettle();
      final searchOffset = searchScrollable.position.pixels;
      expect(searchOffset, greaterThan(0));

      await tester.tap(find.bySemanticsLabel('Library tab'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trash'));
      await tester.pumpAndSettle();
      final libraryScrollable = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(NotesLibraryPage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.drag(
        find.descendant(
          of: find.byType(NotesLibraryPage),
          matching: find.byType(CustomScrollView),
        ),
        const Offset(0, -360),
      );
      await tester.pumpAndSettle();
      final libraryOffset = libraryScrollable.position.pixels;
      expect(libraryOffset, greaterThan(0));

      await tester.tap(find.bySemanticsLabel('Search tab'));
      await tester.pumpAndSettle();
      expect(find.textContaining('State note'), findsWidgets);
      expect(harness.container.read(searchQueryProvider), 'State note');
      expect(searchScrollable.position.pixels, moreOrLessEquals(searchOffset));
      expect(harness.container.read(selectedTagProvider), 'work');

      await tester.tap(find.bySemanticsLabel('Search tab'));
      await tester.pumpAndSettle();
      expect(searchScrollable.position.pixels, moreOrLessEquals(searchOffset));

      await tester.tap(find.bySemanticsLabel('Library tab'));
      await tester.pumpAndSettle();
      expect(
        libraryScrollable.position.pixels,
        moreOrLessEquals(libraryOffset),
      );
      libraryScrollable.position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LibrarySegmentedControl>(
              find.byType(LibrarySegmentedControl, skipOffstage: false),
            )
            .selected,
        LibrarySection.trash,
      );

      await tester.tap(find.bySemanticsLabel('Library tab'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<LibrarySegmentedControl>(
              find.byType(LibrarySegmentedControl, skipOffstage: false),
            )
            .selected,
        LibrarySection.trash,
      );

      await tester.tap(find.bySemanticsLabel('Notes tab'));
      await tester.pumpAndSettle();
      expect(homeScrollable.position.pixels, moreOrLessEquals(homeOffset));

      await tester.tap(find.bySemanticsLabel('Notes tab'));
      await tester.pumpAndSettle();
      expect(homeScrollable.position.pixels, moreOrLessEquals(homeOffset));
    },
  );

  testWidgets(
    'More is a root modal, keeps URI, blocks bar, and dismisses first',
    (tester) async {
      final harness = await _pumpRouter(
        tester,
        repository: InMemoryNoteRepository.seeded(sampleNotes),
      );
      await harness.container.read(appThemeProvider.future);
      await tester.pumpAndSettle();
      final originalUri = harness.router.routeInformationProvider.value.uri;

      await tester.tap(find.bySemanticsLabel('More actions'));
      await tester.pumpAndSettle();

      final sheet = find.byKey(const Key('more-actions-sheet'));
      expect(sheet, findsOneWidget);
      expect(
        Navigator.of(tester.element(sheet)),
        same(rootNavigatorKey.currentState),
      );
      expect(harness.router.routeInformationProvider.value.uri, originalUri);

      expect(find.bySemanticsLabel('Search tab').hitTestable(), findsNothing);
      expect(_path(harness.router), '/');
      expect(sheet, findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(_path(harness.router), '/');
    },
  );

  testWidgets('editor back returns to Search and Library origin branches', (
    tester,
  ) async {
    final harness = await _pumpRouter(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
      initialLocation: '/search',
    );
    harness.router.push('/note/1');
    await tester.pumpAndSettle();
    expect(find.byType(AddEditNotePage), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(_path(harness.router), '/search');

    harness.router.go('/library');
    await tester.pumpAndSettle();
    harness.router.push('/note/1');
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_path(harness.router), '/library');
  });

  testWidgets('direct editor AppBar back falls back to Notes', (tester) async {
    final harness = await _pumpRouter(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
      initialLocation: '/note/1',
    );

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(_path(harness.router), '/');
    expect(find.byType(NotesHomePage), findsOneWidget);
  });

  testWidgets('direct editor system back falls back to Notes', (tester) async {
    final harness = await _pumpRouter(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
      initialLocation: '/note/1',
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_path(harness.router), '/');
  });

  testWidgets('direct editor save falls back to Notes', (tester) async {
    final harness = await _pumpRouter(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
      initialLocation: '/note/1',
    );

    await tester.tap(find.byIcon(Icons.save));
    await tester.pumpAndSettle();
    expect(_path(harness.router), '/');
  });

  for (final theme in <ThemeData>[AuroraTheme.light(), AuroraTheme.dark()]) {
    testWidgets(
      'compact ${theme.brightness.name} shell reserves 112 pixels and does not overflow',
      (tester) async {
        final errors = <FlutterErrorDetails>[];
        final previousErrorHandler = FlutterError.onError;
        FlutterError.onError = errors.add;
        addTearDown(() => FlutterError.onError = previousErrorHandler);
        final harness = await _pumpRouter(
          tester,
          repository: InMemoryNoteRepository.seeded(sampleNotes),
          initialLocation: '/search',
          size: const Size(320, 640),
          theme: theme,
        );

        final barRegion = tester.getSize(
          find.byKey(const Key('notes-bottom-bar-region')),
        );
        final list = tester.widget<ListView>(
          find.descendant(
            of: find.byType(NotesSearchPage),
            matching: find.byType(ListView),
          ),
        );
        final bottomPadding = list.padding!.resolve(TextDirection.ltr).bottom;
        expect(barRegion.height + bottomPadding, greaterThanOrEqualTo(112));
        expect(find.byType(FloatingActionButton), findsOneWidget);
        expect(find.byType(NotesPage), findsNothing);
        expect(_path(harness.router), '/search');
        expect(errors, isEmpty);
      },
    );
  }
}

typedef _RouterHarness = ({
  ProviderContainer container,
  GoRouter router,
  NotificationService notificationService,
});

Future<_RouterHarness> _pumpRouter(
  WidgetTester tester, {
  required InMemoryNoteRepository repository,
  String initialLocation = '/',
  bool settle = true,
  bool manageTeardown = true,
  Size size = const Size(375, 812),
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final notificationService = NotificationService(
    plugin: FlutterLocalNotificationsPlugin(),
  );
  final container = ProviderContainer(
    overrides: [
      noteRepositoryProvider.overrideWithValue(repository),
      notificationServiceProvider.overrideWithValue(notificationService),
    ],
  );
  final router = container.read(routerProvider);
  if (initialLocation != '/') router.go(initialLocation);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: theme ?? AuroraTheme.light(),
        darkTheme: AuroraTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
  if (settle) await tester.pumpAndSettle();

  if (manageTeardown) {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    });
  }
  return (
    container: container,
    router: router,
    notificationService: notificationService,
  );
}

String _path(GoRouter router) => router.routeInformationProvider.value.uri.path;

void _expectRootEditor(WidgetTester tester) {
  expect(find.byType(AddEditNotePage), findsOneWidget);
  expect(
    Navigator.of(tester.element(find.byType(AddEditNotePage))),
    same(rootNavigatorKey.currentState),
  );
}

List<Note> _manyNotes() {
  return [
    for (var index = 0; index < 28; index++)
      Note(
        id: 100 + index,
        title: 'State note $index',
        content: 'Scrollable search result $index',
        color: 0xFF6757D9,
        createdAt: DateTime.utc(2026, 8, 20).subtract(Duration(hours: index)),
        tags: const ['work'],
      ),
    for (var index = 0; index < 18; index++)
      Note(
        id: 200 + index,
        title: 'Archived state $index',
        content: 'Archived result $index',
        color: 0xFF2DB9A8,
        createdAt: DateTime.utc(2026, 8, 19).subtract(Duration(hours: index)),
        status: NoteStatus.archived,
      ),
    for (var index = 0; index < 18; index++)
      Note(
        id: 300 + index,
        title: 'Trash state $index',
        content: 'Trash result $index',
        color: 0xFF8D91A8,
        createdAt: DateTime.utc(2026, 8, 18).subtract(Duration(hours: index)),
        status: NoteStatus.trashed,
      ),
  ];
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
