import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
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
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_reminder_gateway_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/search_focus_request.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/library_segmented_control.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/note_filter_sheet.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/notes_bottom_bar.dart';
import '../helpers/fake_note_reminder_gateway.dart';
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

  testWidgets(
    'card menu is a root modal that dismisses before shell navigation',
    (tester) async {
      // Mutations caught: omitting useRootNavigator, letting the shell receive
      // a barrier tap, or retaining the popup route with its Home branch.
      final harness = await _pumpRouter(
        tester,
        repository: InMemoryNoteRepository.seeded(sampleNotes),
      );
      final originalUri = harness.router.routeInformationProvider.value.uri;
      final searchCenter = tester.getCenter(
        find.bySemanticsLabel('Search tab').hitTestable(),
      );

      await tester.tap(find.byTooltip('More actions for Aurora design'));
      await tester.pumpAndSettle();

      final archiveAction = find.text('Archive');
      expect(archiveAction, findsOneWidget);
      expect(
        Navigator.of(tester.element(archiveAction)),
        same(rootNavigatorKey.currentState),
      );
      expect(harness.router.routeInformationProvider.value.uri, originalUri);
      for (final label in const [
        'Notes tab',
        'Search tab',
        'Create new note',
        'Library tab',
        'More actions',
      ]) {
        expect(find.bySemanticsLabel(label).hitTestable(), findsNothing);
      }

      await tester.tapAt(searchCenter);
      await tester.pumpAndSettle();
      expect(archiveAction, findsNothing);
      expect(_path(harness.router), '/');
      expect(rootNavigatorKey.currentState!.canPop(), isFalse);

      await tester.tap(find.bySemanticsLabel('Search tab'));
      await tester.pumpAndSettle();
      expect(_path(harness.router), '/search');
      await tester.tap(find.bySemanticsLabel('Notes tab'));
      await tester.pumpAndSettle();
      expect(_path(harness.router), '/');
      expect(archiveAction, findsNothing);
    },
  );

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
      expect(find.text('Please try again.'), findsOneWidget);
      expect(find.textContaining('connection'), findsNothing);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_rounded), findsNothing);
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

  for (final state in ['loading', 'error', 'not-found']) {
    testWidgets('compact unresolved $state route fits at 2x text', (
      tester,
    ) async {
      late final InMemoryNoteRepository repository;
      _DeferredNoteRepository? deferred;
      var settle = true;
      var location = '/note/1';
      switch (state) {
        case 'loading':
          deferred = _DeferredNoteRepository(sampleNotes);
          repository = deferred;
          settle = false;
        case 'error':
          repository = InMemoryNoteRepository.seeded(sampleNotes)
            ..getError = StateError('load failed');
        case 'not-found':
          repository = InMemoryNoteRepository.seeded(sampleNotes);
          location = '/note/404';
      }
      await _pumpRouter(
        tester,
        repository: repository,
        initialLocation: location,
        settle: settle,
        size: const Size(640, 320),
        textScaler: const TextScaler.linear(2),
        viewPadding: const EdgeInsets.only(top: 20, bottom: 16),
      );
      if (!settle) await tester.pump();

      expect(find.byKey(Key('existing-note-$state')), findsOneWidget);
      expect(tester.takeException(), isNull);

      deferred?.release();
      if (deferred != null) await tester.pumpAndSettle();
    });
  }

  testWidgets(
    'resolved editor retains draft and preview scroll through loading and error',
    (tester) async {
      final longDraft = List.generate(
        80,
        (index) => 'Unsaved routed draft line $index',
      ).join('\n\n');
      final repository = _RefreshControlledRepository([
        sampleNote.copyWith(content: 'Persisted route content'),
        ...sampleNotes.skip(1),
      ]);
      final harness = await _pumpRouter(
        tester,
        repository: repository,
        initialLocation: '/note/1',
      );
      await tester.enterText(
        find.byKey(const Key('editor-body-field')),
        longDraft,
      );
      await tester.tap(find.byKey(const Key('editor-preview-toggle')));
      await tester.pump();
      final previewScrollable = find.descendant(
        of: find.byKey(const Key('editor-preview')),
        matching: find.byType(Scrollable),
      );
      final previewPosition = tester
          .state<ScrollableState>(previewScrollable)
          .position;
      previewPosition.jumpTo(previewPosition.maxScrollExtent / 2);
      await tester.pump();
      final retainedOffset = previewPosition.pixels;
      expect(retainedOffset, greaterThan(0));

      repository.holdRefresh();
      harness.container.invalidate(notesProvider);
      await tester.pump();
      await tester.pump();

      expect(find.byType(AddEditNotePage), findsOneWidget);
      expect(find.byKey(const Key('existing-note-loading')), findsNothing);
      expect(
        tester.state<ScrollableState>(previewScrollable).position.pixels,
        moreOrLessEquals(retainedOffset),
      );

      repository.getError = StateError('later refresh failed');
      repository.releaseRefresh();
      await tester.pumpAndSettle();

      expect(find.byType(AddEditNotePage), findsOneWidget);
      expect(find.byKey(const Key('existing-note-error')), findsNothing);
      expect(
        tester.state<ScrollableState>(previewScrollable).position.pixels,
        moreOrLessEquals(retainedOffset),
      );
      await tester.tap(find.byKey(const Key('editor-preview-toggle')));
      await tester.pump();
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('editor-body-field')))
            .controller
            ?.text,
        longDraft,
      );
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
    'Search filter is a root modal that preserves URI and blocks shell controls',
    (tester) async {
      // Mutation caught: presenting filters on the Search branch navigator,
      // which leaves the root shell controls reachable above the route modal.
      final harness = await _pumpRouter(
        tester,
        repository: InMemoryNoteRepository.seeded(sampleNotes),
      );

      await tester.tap(find.bySemanticsLabel('Search tab'));
      await tester.pumpAndSettle();
      expect(_path(harness.router), '/search');
      final originalUri = harness.router.routeInformationProvider.value.uri;

      await tester.tap(find.byKey(const Key('notes-search-filter')));
      await tester.pumpAndSettle();

      final sheet = find.byType(NoteFilterSheet);
      expect(sheet, findsOneWidget);
      expect(
        Navigator.of(tester.element(sheet)),
        same(rootNavigatorKey.currentState),
      );
      expect(harness.router.routeInformationProvider.value.uri, originalUri);
      expect(_path(harness.router), '/search');
      for (final label in const [
        'Notes tab',
        'Search tab',
        'Create new note',
        'Library tab',
        'More actions',
      ]) {
        expect(find.bySemanticsLabel(label).hitTestable(), findsNothing);
      }

      await tester.tap(find.widgetWithText(FilledButton, 'Done'));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(_path(harness.router), '/search');
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

  testWidgets('direct editor Done falls back to Notes', (tester) async {
    final harness = await _pumpRouter(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
      initialLocation: '/note/1',
    );

    await tester.tap(find.byKey(const Key('editor-done-button')));
    await tester.pumpAndSettle();
    expect(_path(harness.router), '/');
  });

  for (final routeCase in const <({String origin, bool direct})>[
    (origin: '/', direct: true),
    (origin: '/search', direct: false),
  ]) {
    testWidgets(
      '${routeCase.direct ? 'direct' : 'pushed'} editor blocks system pop until save finishes',
      (tester) async {
        final repository = _DeferredUpdateRepository(sampleNotes);
        final harness = await _pumpRouter(
          tester,
          repository: repository,
          initialLocation: routeCase.direct ? '/note/1' : routeCase.origin,
        );
        if (!routeCase.direct) {
          harness.router.push('/note/1');
          await tester.pumpAndSettle();
        }

        await tester.tap(find.byKey(const Key('editor-done-button')));
        await repository.entered.future;
        await tester.pump();
        await tester.binding.handlePopRoute();
        await tester.pump();

        expect(
          _path(harness.router),
          routeCase.direct ? '/note/1' : routeCase.origin,
        );
        expect(find.byType(AddEditNotePage), findsOneWidget);

        repository.release();
        await tester.pumpAndSettle();
        expect(_path(harness.router), routeCase.origin);
        expect(find.byType(AddEditNotePage), findsNothing);
      },
    );
  }

  testWidgets(
    'pushed partial save defers one pop and refetches the persisted note',
    (tester) async {
      final repository = InMemoryNoteRepository.seeded(sampleNotes);
      final gateway = FakeNoteReminderGateway()
        ..scheduleError = StateError('notification failed');
      final harness = await _pumpRouter(
        tester,
        repository: repository,
        initialLocation: '/search',
        gateway: gateway,
      );
      harness.router.push('/note/1');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('editor-title-field')),
        'Persisted before pushed close',
      );

      await tester.tap(find.byKey(const Key('editor-done-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor-save-error')), findsOneWidget);
      expect(repository.notes, hasLength(sampleNotes.length));
      expect(repository.notes.first.title, 'Persisted before pushed close');

      await tester.tap(find.byKey(const Key('editor-back-button')));
      expect(
        find.byType(AddEditNotePage),
        findsOneWidget,
        reason: 'A partial-save pushed route closes from the post-frame branch',
      );
      await tester.pumpAndSettle();

      expect(find.byType(AddEditNotePage), findsNothing);
      expect(find.byType(NotesSearchPage), findsOneWidget);
      expect(_path(harness.router), '/search');
      expect(rootNavigatorKey.currentState!.canPop(), isFalse);
      expect(harness.container.read(notesProvider).hasError, isFalse);
      expect(harness.container.read(notesProvider).value, hasLength(5));
      expect(
        harness.container.read(notesProvider).value!.first.title,
        'Persisted before pushed close',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('keyboard activation preserves selected destination focus', (
    tester,
  ) async {
    final previousStrategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy = previousStrategy,
    );
    final harness = await _pumpRouter(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
    );
    final libraryControl = tester.widget<InkWell>(
      find.byKey(const Key('notes-bottom-bar-library-control')),
    );
    expect(libraryControl.focusNode, isNotNull);
    libraryControl.focusNode!.requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(_path(harness.router), '/library');
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const Key('notes-bottom-bar-library-control')),
          )
          .focusNode
          ?.hasFocus,
      isTrue,
    );
  });

  testWidgets('keyboard overlay actions transfer focus off the shell', (
    tester,
  ) async {
    final previousStrategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy = previousStrategy,
    );
    await _pumpRouter(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
    );

    final createNode = tester
        .widget<FloatingActionButton>(
          find.byKey(const Key('notes-bottom-bar-create-control')),
        )
        .focusNode!;
    createNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(AddEditNotePage), findsOneWidget);
    expect(createNode.hasFocus, isFalse);
    expect(
      FocusScope.of(tester.element(find.byType(AddEditNotePage))).hasFocus,
      isTrue,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final moreNode = tester
        .widget<InkWell>(find.byKey(const Key('notes-bottom-bar-more-control')))
        .focusNode!;
    moreNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('more-actions-sheet'));
    expect(sheet, findsOneWidget);
    expect(moreNode.hasFocus, isFalse);
    expect(FocusScope.of(tester.element(sheet)).hasFocus, isTrue);
  });

  testWidgets('Search keeps shell clearance after keyboard resizes body', (
    tester,
  ) async {
    await _pumpRouter(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
      initialLocation: '/search',
      viewInsets: const EdgeInsets.only(bottom: 240),
    );

    final list = tester.widget<ListView>(
      find.descendant(
        of: find.byType(NotesSearchPage),
        matching: find.byType(ListView),
      ),
    );
    final pageRect = tester.getRect(find.byType(NotesSearchPage));
    expect(pageRect.height, tester.view.physicalSize.height - 240);
    expect(list.padding!.resolve(TextDirection.ltr).bottom, 120);
  });

  for (final routeCase in const <({String path, String label})>[
    (path: '/', label: 'Notes'),
    (path: '/search', label: 'Search'),
    (path: '/library', label: 'Library'),
  ]) {
    for (final textScale in [1.0, 2.0, 3.0]) {
      testWidgets(
        '${routeCase.label} content clears the safe-area shell at ${textScale}x',
        (tester) async {
          await _pumpRouter(
            tester,
            repository: InMemoryNoteRepository.seeded(_clearanceNotes),
            initialLocation: routeCase.path,
            size: const Size(320, 640),
            textScaler: TextScaler.linear(textScale),
            viewPadding: const EdgeInsets.only(bottom: 34),
          );

          if (routeCase.path == '/search') {
            final searchList = find.descendant(
              of: find.byType(NotesSearchPage),
              matching: find.byType(ListView),
            );
            await tester.scrollUntilVisible(
              find.byKey(const Key('notes-search-field')),
              120,
              scrollable: find
                  .descendant(of: searchList, matching: find.byType(Scrollable))
                  .first,
            );
            await tester.enterText(
              find.byKey(const Key('notes-search-field')),
              'clearance',
            );
            await tester.pumpAndSettle();
          }

          final scrollView = switch (routeCase.path) {
            '/' => find.descendant(
              of: find.byType(NotesHomePage),
              matching: find.byType(CustomScrollView),
            ),
            '/search' => find.descendant(
              of: find.byType(NotesSearchPage),
              matching: find.byType(ListView),
            ),
            _ => find.descendant(
              of: find.byType(NotesLibraryPage),
              matching: find.byType(CustomScrollView),
            ),
          };
          await _jumpToEnd(tester, scrollView);

          final regionRect = tester.getRect(
            find.byKey(const Key('notes-bottom-bar-region')),
          );
          final fullBarRect = tester.getRect(find.byType(NotesBottomBar));
          final target = switch (routeCase.path) {
            '/' => find.byKey(const ValueKey('note-card-115')),
            '/search' => find.byKey(const ValueKey('search-result-note-115')),
            _ => find.widgetWithText(FilledButton, 'Browse notes'),
          };

          expect(
            regionRect.height,
            textScale == 3
                ? greaterThan(NotesBottomBar.expandedRegionHeight)
                : textScale > 1.5
                ? greaterThan(92)
                : 92,
          );
          expect(fullBarRect.height - regionRect.height, 34);
          expect(target, findsOneWidget);
          expect(
            tester.getRect(target).bottom,
            lessThanOrEqualTo(regionRect.top),
            reason: '${routeCase.label} content must stop above the bar region',
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('expanded Search content clears keyboard with bottom safe area', (
    tester,
  ) async {
    await _pumpRouter(
      tester,
      repository: InMemoryNoteRepository.seeded(_clearanceNotes),
      initialLocation: '/search',
      size: const Size(320, 640),
      textScaler: const TextScaler.linear(2),
      viewPadding: const EdgeInsets.only(bottom: 34),
      viewInsets: const EdgeInsets.only(bottom: 240),
    );
    await tester.enterText(
      find.byKey(const Key('notes-search-field')),
      'clearance',
    );
    await tester.pumpAndSettle();
    final scrollView = find.descendant(
      of: find.byType(NotesSearchPage),
      matching: find.byType(ListView),
    );
    await _jumpToEnd(tester, scrollView);

    final pageRect = tester.getRect(find.byType(NotesSearchPage));
    final regionRect = tester.getRect(
      find.byKey(const Key('notes-bottom-bar-region')),
    );
    final fullBarRect = tester.getRect(find.byType(NotesBottomBar));
    final lastResult = find.byKey(const ValueKey('search-result-note-115'));
    final obstructionTop = pageRect.bottom < regionRect.top
        ? pageRect.bottom
        : regionRect.top;

    expect(pageRect.height, 400);
    expect(regionRect.height, greaterThan(92));
    expect(fullBarRect.height - regionRect.height, 12);
    expect(lastResult, findsOneWidget);
    expect(
      tester.getRect(lastResult).bottom,
      lessThanOrEqualTo(obstructionTop),
    );
    expect(tester.takeException(), isNull);
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
        final shellScaffold = tester.widget<Scaffold>(
          find.ancestor(
            of: find.byKey(const Key('notes-bottom-bar-region')),
            matching: find.byType(Scaffold),
          ),
        );
        expect(shellScaffold.extendBody, isTrue);
        expect(barRegion.height, greaterThanOrEqualTo(92));
        expect(bottomPadding, greaterThanOrEqualTo(120));
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
  FakeNoteReminderGateway? gateway,
  String initialLocation = '/',
  bool settle = true,
  bool manageTeardown = true,
  Size size = const Size(375, 812),
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
  EdgeInsets viewPadding = EdgeInsets.zero,
  EdgeInsets viewInsets = EdgeInsets.zero,
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
      noteReminderGatewayProvider.overrideWithValue(
        gateway ?? FakeNoteReminderGateway(),
      ),
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
        builder: (context, child) {
          final bottomPadding = (viewPadding.bottom - viewInsets.bottom)
              .clamp(0.0, double.infinity)
              .toDouble();
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: textScaler,
              padding: EdgeInsets.only(
                top: viewPadding.top,
                bottom: bottomPadding,
              ),
              viewPadding: viewPadding,
              viewInsets: viewInsets,
            ),
            child: child!,
          );
        },
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

Future<void> _jumpToEnd(WidgetTester tester, Finder scrollView) async {
  final scrollable = find.descendant(
    of: scrollView,
    matching: find.byType(Scrollable),
  );
  final position = tester.state<ScrollableState>(scrollable.first).position;
  for (var attempt = 0; attempt < 12; attempt++) {
    position.jumpTo(position.maxScrollExtent);
    await tester.pumpAndSettle();
    if ((position.maxScrollExtent - position.pixels).abs() < 0.5) return;
  }
  throw TestFailure('Scroll extent did not settle at its end');
}

final _clearanceNotes = List<Note>.unmodifiable(
  List.generate(
    16,
    (index) => Note(
      id: 100 + index,
      title: 'Clearance note $index',
      content: 'Enough content to verify the composed shell viewport.',
      color: 0xFF6757D9,
      createdAt: DateTime.utc(2026, 8, 23).subtract(Duration(minutes: index)),
      tags: const ['clearance'],
    ),
  ),
);

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

class _RefreshControlledRepository extends InMemoryNoteRepository {
  _RefreshControlledRepository(super.notes) : super.seeded();

  Completer<void>? _refreshGate;

  void holdRefresh() => _refreshGate = Completer<void>();

  void releaseRefresh() => _refreshGate?.complete();

  @override
  Future<List<Note>> getNotesByStatus(NoteStatus status) async {
    final gate = _refreshGate;
    if (gate != null) await gate.future;
    return super.getNotesByStatus(status);
  }
}

class _DeferredUpdateRepository extends InMemoryNoteRepository {
  _DeferredUpdateRepository(super.notes) : super.seeded();

  final entered = Completer<void>();
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<int> updateNote(Note note) async {
    if (!entered.isCompleted) entered.complete();
    await _gate.future;
    return super.updateNote(note);
  }
}
