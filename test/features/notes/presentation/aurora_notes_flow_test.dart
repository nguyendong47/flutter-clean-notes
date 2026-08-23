import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_clean_notes/app/app_providers.dart';
import 'package:flutter_clean_notes/app/notification_service.dart';
import 'package:flutter_clean_notes/app/router.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/add_edit_note_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_home_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_search_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_reminder_gateway_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/main.dart';
import '../../../helpers/fake_note_reminder_gateway.dart';
import '../../../helpers/in_memory_note_repository.dart';
import '../../../helpers/note_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
    'Home shows a pinned note once and Search keeps query, tag, and scroll after editing',
    (tester) async {
      // Mutation caught: rendering pinned notes again in the ordinary collection,
      // or rebuilding the Search branch when an editor returns.
      final notes = [
        sampleNote,
        ...List.generate(
          14,
          (index) => Note(
            id: 100 + index,
            title: 'Aurora result $index',
            content: 'Searchable work content $index',
            color: sampleNote.color,
            createdAt: sampleNote.createdAt.add(Duration(minutes: index)),
            tags: const ['work'],
          ),
        ),
      ];
      final harness = await _pumpApp(
        tester,
        repository: InMemoryNoteRepository.seeded(notes),
      );

      expect(find.byKey(const Key('pinned-note-card-1')), findsOneWidget);
      expect(find.bySemanticsLabel('Open note Aurora design'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Search tab'));
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('notes-search-field'));
      expect(field, findsOneWidget);
      await tester.enterText(field, 'Aurora result');
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('notes-search-filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('filter-tag-work')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      final results = find.descendant(
        of: find.byType(NotesSearchPage),
        matching: find.byType(ListView),
      );
      await tester.drag(results, const Offset(0, -260));
      await tester.pumpAndSettle();
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: results, matching: find.byType(Scrollable)).first,
      );
      final result = find.bySemanticsLabel('Open note Aurora result 4');
      await tester.ensureVisible(result);
      await tester.pumpAndSettle();
      final offset = scrollable.position.pixels;
      expect(offset, greaterThan(0));

      await tester.tap(result);
      await tester.pumpAndSettle();
      expect(find.byType(AddEditNotePage), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('editor-title-field')),
        'Aurora result 4 edited',
      );
      await tester.tap(find.byKey(const Key('editor-done-button')));
      await tester.pumpAndSettle();

      expect(_path(harness.router), '/search');
      expect(harness.container.read(searchQueryProvider), 'Aurora result');
      expect(harness.container.read(selectedTagProvider), 'work');
      final currentResults = find.descendant(
        of: find.byType(NotesSearchPage),
        matching: find.byType(Scrollable),
      );
      final currentScrollable = tester.state<ScrollableState>(
        currentResults.first,
      );
      expect(currentScrollable.position.pixels, moreOrLessEquals(offset));

      currentScrollable.position.jumpTo(0);
      await tester.pumpAndSettle();
      final returnedField = find.byKey(const Key('notes-search-field'));
      expect(returnedField, findsOneWidget);
      expect(tester.getRect(returnedField).isEmpty, isFalse);
      expect(
        tester.widget<SearchBar>(returnedField).controller?.text,
        'Aurora result',
      );

      await tester.tap(find.byKey(const Key('notes-search-filter')));
      await tester.pumpAndSettle();
      expect(
        tester
            .getSemantics(find.byKey(const Key('filter-tag-work')))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      final editedResult = find.bySemanticsLabel(
        'Open note Aurora result 4 edited',
      );
      await tester.scrollUntilVisible(
        editedResult,
        200,
        scrollable: currentResults.first,
      );
      expect(editedResult, findsOneWidget);
      expect(harness.container.read(searchQueryProvider), 'Aurora result');
      expect(
        harness.container
            .read(notesProvider)
            .value
            ?.any((note) => note.title == 'Aurora result 4 edited'),
        isTrue,
      );
    },
  );

  testWidgets('Library restore reaches Home and Trash undo remains available', (
    tester,
  ) async {
    // Mutation caught: status mutation refreshes only the Library projection or
    // removes the Undo action before the user can recover a trash operation.
    final harness = await _pumpApp(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
    );
    await tester.tap(find.bySemanticsLabel('Library tab'));
    await tester.pumpAndSettle();

    await _chooseCardAction(tester, 'Archived launch notes', 'Restore');
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Notes tab'));
    await tester.pumpAndSettle();
    expect(_path(harness.router), '/');
    expect(
      harness.container
          .read(notesProvider)
          .value
          ?.any((note) => note.id == 4 && note.status == NoteStatus.active),
      isTrue,
    );
    await _scrollHomeToEnd(tester);
    expect(
      find.bySemanticsLabel('Open note Archived launch notes'),
      findsOneWidget,
    );

    await _chooseCardAction(tester, 'Archived launch notes', 'Move to trash');
    await tester.pumpAndSettle();
    expect(find.text('Undo'), findsOneWidget);
    expect(
      harness.container
          .read(notesProvider)
          .requireValue
          .singleWhere((note) => note.id == 4)
          .status,
      NoteStatus.trashed,
    );
    expect(
      find.bySemanticsLabel('Open note Archived launch notes'),
      findsNothing,
    );
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(
      harness.container
          .read(notesProvider)
          .requireValue
          .singleWhere((note) => note.id == 4)
          .status,
      NoteStatus.active,
    );
    expect(
      find.bySemanticsLabel('Open note Archived launch notes'),
      findsOneWidget,
    );
  });

  testWidgets(
    'New-note save stays routed until persistence completes and adds one Home card',
    (tester) async {
      // Mutation caught: popping an editor before addNote completes or dispatching
      // the save callback twice while its persistence Future is pending.
      final repository = _DeferredAddRepository();
      final harness = await _pumpApp(tester, repository: repository);
      await tester.tap(find.bySemanticsLabel('Create new note'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('editor-title-field')),
        'Saved exactly once',
      );
      await tester.tap(find.byKey(const Key('editor-done-button')));
      await tester.tap(find.byKey(const Key('editor-done-button')));
      await repository.entered.future;
      await tester.pump();

      expect(find.byType(AddEditNotePage), findsOneWidget);
      expect(repository.saveRequests, 1);
      expect(repository.addCalls, 0);
      expect(find.byKey(const Key('editor-save-progress')), findsOneWidget);
      repository.release();
      await tester.pumpAndSettle();

      expect(_path(harness.router), '/');
      expect(
        find.bySemanticsLabel('Open note Saved exactly once'),
        findsOneWidget,
      );
      expect(repository.addCalls, 1);
    },
  );

  testWidgets(
    'real MyApp applies and persists Dark from More without changing route',
    (tester) async {
      // Mutation caught: wiring More outside MyApp's theme provider, changing
      // the shell URI, or updating the rendered theme without persisting it.
      tester.view.physicalSize = const Size(375, 812);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = _FakeThemeModeStore(ThemeMode.light);
      final container = ProviderContainer(
        overrides: [
          themeModeStoreProvider.overrideWithValue(store),
          noteRepositoryProvider.overrideWithValue(
            InMemoryNoteRepository.seeded(sampleNotes),
          ),
          noteReminderGatewayProvider.overrideWithValue(
            FakeNoteReminderGateway(),
          ),
          notificationServiceProvider.overrideWithValue(
            NotificationService(plugin: FlutterLocalNotificationsPlugin()),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(appThemeProvider.future);
      final router = container.read(routerProvider);

      await tester.pumpWidget(
        UncontrolledProviderScope(container: container, child: const MyApp()),
      );
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
      });
      await tester.pumpAndSettle();
      final uriBefore = router.routeInformationProvider.value.uri;
      expect(
        Theme.of(tester.element(find.bySemanticsLabel('Notes tab'))).brightness,
        Brightness.light,
      );

      await tester.tap(find.bySemanticsLabel('More actions'));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri, uriBefore);
      await tester.tap(find.byKey(const Key('theme-mode-dark')));
      await tester.pumpAndSettle();

      expect(container.read(appThemeProvider).requireValue, ThemeMode.dark);
      expect(store.writeCalls, 1);
      expect(store.mode, ThemeMode.dark);
      expect(
        Theme.of(
          tester.element(find.byKey(const Key('more-actions-sheet'))),
        ).brightness,
        Brightness.dark,
      );
      expect(router.routeInformationProvider.value.uri, uriBefore);

      container.invalidate(appThemeProvider);
      expect(await container.read(appThemeProvider.future), ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(store.readCalls, 2);
      expect(
        Theme.of(
          tester.element(find.byKey(const Key('more-actions-sheet'))),
        ).brightness,
        Brightness.dark,
      );
    },
  );

  testWidgets(
    'clearing a reminder persists across reload and cancels without scheduling',
    (tester) async {
      // Mutation caught: updateNote scheduling a stale reminder after metadata
      // clears it, or leaving the old value only in provider state.
      final gateway = FakeNoteReminderGateway();
      final repository = InMemoryNoteRepository.seeded([sampleNote]);
      final harness = await _pumpApp(
        tester,
        repository: repository,
        gateway: gateway,
        initialLocation: '/note/1',
      );
      await tester.tap(find.byKey(const Key('editor-metadata-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('metadata-clear-reminder')));
      await tester.tap(find.byKey(const Key('metadata-apply')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('editor-done-button')));
      await tester.pumpAndSettle();

      expect(gateway.cancelled, [1]);
      expect(gateway.scheduled, isEmpty);
      expect(repository.notes.single.reminder, isNull);
      harness.container.invalidate(notesProvider);
      await harness.container.read(notesProvider.future);
      expect(
        harness.container.read(notesProvider).value?.single.reminder,
        isNull,
      );
    },
  );
}

Future<_AppHarness> _pumpApp(
  WidgetTester tester, {
  required InMemoryNoteRepository repository,
  FakeNoteReminderGateway? gateway,
  String initialLocation = '/',
}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      noteRepositoryProvider.overrideWithValue(repository),
      noteReminderGatewayProvider.overrideWithValue(
        gateway ?? FakeNoteReminderGateway(),
      ),
      notificationServiceProvider.overrideWithValue(
        NotificationService(plugin: FlutterLocalNotificationsPlugin()),
      ),
    ],
  );
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
  if (initialLocation != '/') router.go(initialLocation);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (container: container, router: router);
}

String _path(GoRouter router) => router.routeInformationProvider.value.uri.path;

Future<void> _chooseCardAction(
  WidgetTester tester,
  String title,
  String action,
) async {
  await tester.tap(find.byTooltip('More actions for $title'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

Future<void> _scrollHomeToEnd(WidgetTester tester) async {
  final scrollable = tester.state<ScrollableState>(
    find
        .descendant(
          of: find.byType(NotesHomePage),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
  await tester.pumpAndSettle();
}

typedef _AppHarness = ({ProviderContainer container, GoRouter router});

class _DeferredAddRepository extends InMemoryNoteRepository {
  _DeferredAddRepository() : super.seeded(const []);

  final entered = Completer<void>();
  final _gate = Completer<void>();
  int saveRequests = 0;

  void release() => _gate.complete();

  @override
  Future<int> addNote(Note note) async {
    saveRequests += 1;
    if (!entered.isCompleted) entered.complete();
    await _gate.future;
    return super.addNote(note);
  }
}

class _FakeThemeModeStore implements ThemeModeStore {
  _FakeThemeModeStore(this.mode);

  ThemeMode mode;
  int readCalls = 0;
  int writeCalls = 0;

  @override
  Future<ThemeMode> readMode() async {
    readCalls += 1;
    return mode;
  }

  @override
  Future<void> writeMode(ThemeMode mode) async {
    writeCalls += 1;
    this.mode = mode;
  }
}
