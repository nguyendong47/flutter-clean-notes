# Aurora Glass Mobile Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Replace the current notes interface with the approved mobile-first Aurora Glass experience while preserving all existing note, reminder, search, archive, trash, theme, and transfer behavior.

**Architecture:** Keep the domain, repository, SQLite datasource, Riverpod code generation, and go_router boundaries. Add a small app-level visual system, split presentation into focused pages/widgets, make NotesNotifier hold all note statuses, and keep platform operations behind testable presentation services.

**Tech Stack:** Flutter, Dart 3.11.1, Material 3, flutter_riverpod/riverpod_annotation, go_router, sqflite, flutter_markdown, share_plus, file_picker, flutter_staggered_grid_view 0.7.0, flutter_test.

## Global Constraints

- Dart SDK remains ^3.11.1.
- Domain code must not import presentation or data implementations.
- Riverpod providers use annotations and generated .g.dart files; never edit generated files manually.
- After every annotated-provider change, run 'dart run build_runner build --delete-conflicting-outputs'.
- Preserve desktop sqflite FFI initialization and the mobile database path split.
- The current SQLite schema is version 5; this redesign does not change it.
- Preserve every existing user feature and notification-service test.
- Light and dark themes are equal targets.
- Normal text contrast is at least 4.5:1; large text and non-text controls are at least 3:1.
- Interactive controls are at least 44×44 logical pixels, preferably 48×48.
- Motion generally stays between 180 and 260 milliseconds and respects reduced-motion preferences.
- Before editing each function, class, or method, run GitNexus impact with direction 'upstream'. Report direct callers, affected processes, and risk. Stop and warn before HIGH or CRITICAL changes.
- Before every commit, run GitNexus detect_changes with scope 'staged' and verify only the intended symbols and flows are affected.
- Stage only task files. Preserve the user's existing AGENTS.md, CLAUDE.md, .claude/skills, and .superpowers changes.

---

## File Structure

### App visual system

- Create 'lib/app/theme/aurora_theme.dart': Aurora color, typography, shape, and component themes.
- Create 'lib/app/widgets/aurora_background.dart': static light/dark aurora field.
- Create 'lib/app/widgets/glass_surface.dart': reusable accessible frosted surface with a no-blur fallback.
- Modify 'lib/main.dart': consume AuroraTheme instead of defining a private theme builder.

### Notes presentation state

- Create 'lib/features/notes/presentation/providers/note_filters.dart': pure status, query, tag, and sort transformations.
- Modify 'lib/features/notes/presentation/providers/note_providers.dart': load all statuses, expose derived collections, and preserve visible data through mutations.
- Modify 'lib/features/notes/domain/entities/note.dart': allow copyWith to explicitly clear a nullable reminder.

### Notes presentation widgets and pages

- Create 'lib/features/notes/presentation/widgets/glass_note_card.dart': async-aware card and note actions.
- Create 'lib/features/notes/presentation/widgets/notes_collection.dart': responsive pinned and masonry collections.
- Create 'lib/features/notes/presentation/widgets/notes_state_view.dart': skeleton, empty, and error states.
- Create 'lib/features/notes/presentation/pages/notes_home_page.dart': active-note home page.
- Create 'lib/features/notes/presentation/pages/notes_search_page.dart': focused search experience.
- Create 'lib/features/notes/presentation/pages/notes_library_page.dart': archived/trash segmented experience.
- Create 'lib/features/notes/presentation/widgets/more_actions_sheet.dart': theme, tag, import, and export entry points.
- Create 'lib/features/notes/presentation/widgets/tag_manager_sheet.dart': tag listing and removal.
- Create 'lib/features/notes/presentation/widgets/notes_bottom_bar.dart': four destinations plus central new-note action.
- Create 'lib/features/notes/presentation/pages/notes_shell_page.dart': navigation shell and More sheet.

### Transfer and editor

- Create 'lib/features/notes/presentation/services/note_export_formatter.dart': deterministic text, Markdown, and JSON encoding.
- Create 'lib/features/notes/presentation/services/notes_transfer_gateway.dart': injectable picker/share boundary.
- Create 'lib/features/notes/presentation/providers/notes_transfer_provider.dart': transfer orchestration and AsyncValue state.
- Create 'lib/features/notes/presentation/widgets/editor_formatting_bar.dart': Markdown formatting controls.
- Create 'lib/features/notes/presentation/widgets/note_metadata_sheet.dart': color, tags, and reminder editing.
- Modify 'lib/features/notes/presentation/pages/add_edit_note_page.dart': Aurora editor layout and awaited persistence.
- Modify 'lib/app/router.dart': stateful shell routes and existing editor deep links.

### Tests

- Create focused tests under 'test/app', 'test/features/notes/domain', 'test/features/notes/presentation', and 'test/helpers'.
- Create 'test/helpers/note_fixtures.dart': stable Note fixtures shared by presentation tests.
- Keep 'test/notification_service_test.dart' unchanged.

---

### Task 1: Aurora Theme and Glass Primitives

**Files:**
- Create: 'lib/app/theme/aurora_theme.dart'
- Create: 'lib/app/widgets/aurora_background.dart'
- Create: 'lib/app/widgets/glass_surface.dart'
- Modify: 'lib/main.dart'
- Test: 'test/app/aurora_theme_test.dart'
- Test: 'test/app/glass_surface_test.dart'

**Interfaces:**
- Produces: 'AuroraTheme.light()', 'AuroraTheme.dark()', 'AuroraBackground(child: Widget)', and 'GlassSurface(child:, borderRadius:, padding:, blur:, opacity:)'.
- Consumes: Flutter Material theme APIs only.

- [ ] **Step 1: Run impact analysis**

Run GitNexus impact on 'MyApp', 'MyApp.build', and '_buildTheme' in 'lib/main.dart'. Report risk before editing.

- [ ] **Step 2: Write failing theme tests**

~~~dart
test('Aurora themes provide equal Material 3 light and dark systems', () {
  final light = AuroraTheme.light();
  final dark = AuroraTheme.dark();

  expect(light.useMaterial3, isTrue);
  expect(dark.useMaterial3, isTrue);
  expect(light.brightness, Brightness.light);
  expect(dark.brightness, Brightness.dark);
  expect(light.colorScheme.primary, AuroraTheme.indigo);
  expect(dark.colorScheme.primary, AuroraTheme.darkIndigo);
  expect(light.navigationBarTheme.height, 72);
  expect(dark.navigationBarTheme.height, 72);
});
~~~

~~~dart
testWidgets('GlassSurface clips and blurs its child', (tester) async {
  await tester.pumpWidget(
    const MaterialApp(
      home: GlassSurface(
        child: Text('Glass content'),
      ),
    ),
  );

  expect(find.text('Glass content'), findsOneWidget);
  expect(find.byType(BackdropFilter), findsOneWidget);
  expect(find.byType(ClipRRect), findsWidgets);
});
~~~

- [ ] **Step 3: Run tests and verify the missing APIs fail**

Run: 'flutter test test/app/aurora_theme_test.dart test/app/glass_surface_test.dart'

Expected: FAIL because AuroraTheme and GlassSurface do not exist.

- [ ] **Step 4: Implement the visual tokens and primitives**

Use this public shape:

~~~dart
abstract final class AuroraTheme {
  static const indigo = Color(0xFF6757D9);
  static const darkIndigo = Color(0xFFA99BFF);
  static const mint = Color(0xFF2DB9A8);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: dark ? darkIndigo : indigo,
      brightness: brightness,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          dark ? const Color(0xFF0B1020) : const Color(0xFFF4F6FF),
      textTheme: Typography.material2021(platform: defaultTargetPlatform)
          .black
          .apply(
            bodyColor: dark ? const Color(0xFFF4F6FF) : const Color(0xFF17203B),
            displayColor: dark ? const Color(0xFFF4F6FF) : const Color(0xFF17203B),
          ),
      navigationBarTheme: const NavigationBarThemeData(height: 72),
    );
  }
}
~~~

GlassSurface must use ClipRRect → BackdropFilter → DecoratedBox, expose a semantic container, and use a theme-aware opaque fallback when MediaQuery.disableAnimations is true or blur is zero. AuroraBackground must use a non-animated Stack with two to three large radial/linear gradient decorations and SafeArea-aware content.

- [ ] **Step 5: Replace MyApp's private theme builder**

Set 'theme: AuroraTheme.light()' and 'darkTheme: AuroraTheme.dark()'. Remove '_seedColor' and '_buildTheme'. Do not change ProviderScope, notification initialization, router configuration, or FFI setup.

- [ ] **Step 6: Format and verify**

Run:

~~~text
dart format lib/app/theme lib/app/widgets lib/main.dart test/app
flutter test test/app/aurora_theme_test.dart test/app/glass_surface_test.dart
flutter analyze
~~~

Expected: all PASS.

- [ ] **Step 7: Detect changes and commit**

Stage only Task 1 files. Run GitNexus detect_changes(scope: 'staged'). Commit:

~~~text
git commit -m "feat: add aurora glass design foundation"
~~~

---

### Task 2: Reliable Note Collections and Mutation State

**Files:**
- Create: 'lib/features/notes/presentation/providers/note_filters.dart'
- Modify: 'lib/features/notes/presentation/providers/note_providers.dart'
- Modify: 'lib/features/notes/domain/entities/note.dart'
- Regenerate: 'lib/features/notes/presentation/providers/note_providers.g.dart'
- Create: 'test/helpers/in_memory_note_repository.dart'
- Create: 'test/helpers/note_fixtures.dart'
- Test: 'test/features/notes/domain/note_test.dart'
- Test: 'test/features/notes/presentation/note_filters_test.dart'
- Test: 'test/features/notes/presentation/notes_notifier_test.dart'

**Interfaces:**
- Produces: 'filterNotes({required List<Note> notes, required NoteStatus status, String query, String? tag, required NoteSort sort})'.
- Produces: 'notesByStatusProvider(NoteStatus)', 'homeNotesProvider', 'homeTagsProvider', and 'searchResultsProvider'.
- Produces: NotesNotifier state containing active, archived, and trashed notes together.
- Consumes: existing note use cases and NoteRepository.

- [ ] **Step 1: Run impact analysis**

Run upstream impact for 'Note.copyWith', 'NotesNotifier', 'NotesNotifier.build', 'filteredNotes', 'allTags', and every NotesNotifier mutation method. Warn before HIGH or CRITICAL risk.

- [ ] **Step 2: Write failing domain and filter tests**

~~~dart
test('copyWith can explicitly clear nullable persistence fields', () {
  final note = Note(
    id: 1,
    title: 'Reminder',
    content: '',
    color: 0,
    createdAt: DateTime(2026),
    reminder: DateTime(2026, 8, 18),
  );

  expect(note.copyWith(id: null, reminder: null).id, isNull);
  expect(note.copyWith(id: null, reminder: null).reminder, isNull);
  expect(note.copyWith().id, note.id);
  expect(note.copyWith().reminder, note.reminder);
});
~~~

~~~dart
test('filterNotes combines status query tag and sort', () {
  final result = filterNotes(
    notes: sampleNotes,
    status: NoteStatus.active,
    query: 'design',
    tag: 'work',
    sort: NoteSort.titleAZ,
  );

  expect(result.map((note) => note.title), ['Aurora design']);
});
~~~

- [ ] **Step 3: Write the failing notifier test**

Create InMemoryNoteRepository implementing every NoteRepository method with an in-memory list. Then:

~~~dart
test('notifier loads all statuses and preserves data on mutation failure', () async {
  final repository = InMemoryNoteRepository.seeded(sampleNotes);
  final container = ProviderContainer(
    overrides: [noteRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);

  final initial = await container.read(notesProvider.future);
  expect(initial, hasLength(sampleNotes.length));

  repository.updateError = StateError('write failed');
  await expectLater(
    container.read(notesProvider.notifier).togglePin(initial.first),
    throwsStateError,
  );

  expect(container.read(notesProvider).value, initial);
  expect(container.read(notesProvider).hasError, isTrue);
});
~~~

- [ ] **Step 4: Run tests and verify failure**

Run:

~~~text
flutter test test/features/notes/domain/note_test.dart
flutter test test/features/notes/presentation/note_filters_test.dart
flutter test test/features/notes/presentation/notes_notifier_test.dart
~~~

Expected: FAIL for explicit reminder clearing, missing filterNotes, and old notifier semantics.

- [ ] **Step 5: Implement explicit nullable copyWith**

Use a private sentinel:

~~~dart
static const _unset = Object();

Note copyWith({
  Object? id = _unset,
  String? title,
  String? content,
  int? color,
  DateTime? createdAt,
  bool? isPinned,
  List<String>? tags,
  NoteStatus? status,
  Object? reminder = _unset,
}) {
  return Note(
    id: identical(id, _unset) ? this.id : id as int?,
    title: title ?? this.title,
    content: content ?? this.content,
    color: color ?? this.color,
    createdAt: createdAt ?? this.createdAt,
    isPinned: isPinned ?? this.isPinned,
    tags: tags ?? this.tags,
    status: status ?? this.status,
    reminder: identical(reminder, _unset) ? this.reminder : reminder as DateTime?,
  );
}
~~~

- [ ] **Step 6: Implement pure filters and all-status state**

'filterNotes' must:

1. Filter by status.
2. Match a normalized query against title, content, or tags.
3. Apply an exact selected tag.
4. Copy before sorting so provider-owned lists are never mutated.
5. Sort with pinned notes first, then the selected NoteSort within each pin group.

Change NotesNotifier.build to fetch every NoteStatus with getNotesByStatusUsecaseProvider and concatenate the results. Add 'test/helpers/note_fixtures.dart' with deterministic 'sampleNote' and 'sampleNotes' values used by every later widget test. Replace repeated loading-state mutations with:

~~~dart
Future<void> _mutate(Future<void> Function() operation) async {
  final previous = state;
  try {
    await operation();
    state = AsyncData(await _fetchAllNotes());
  } catch (error, stackTrace) {
    state = AsyncError<List<Note>>(error, stackTrace).copyWithPrevious(previous);
    rethrow;
  }
}
~~~

Every mutation delegates through '_mutate'. Add family/derived providers for status, home, active-note tags, and search. Remove NoteMode from collection loading, but keep NoteModeNotifier and filteredNotesProvider as compatibility adapters for the legacy NotesPage until Task 7 replaces that page. The compatibility adapter filters the all-status list by the selected legacy mode so every intermediate commit still works.

- [ ] **Step 7: Regenerate and verify**

Run:

~~~text
dart run build_runner build --delete-conflicting-outputs
dart format lib/features/notes test/helpers test/features/notes
flutter test test/features/notes/domain/note_test.dart test/features/notes/presentation/note_filters_test.dart test/features/notes/presentation/notes_notifier_test.dart
flutter analyze
~~~

Expected: all PASS.

- [ ] **Step 8: Detect changes and commit**

Stage only Task 2 files, including regenerated .g.dart. Run GitNexus detect_changes(scope: 'staged'). Commit:

~~~text
git commit -m "refactor: stabilize note collections and mutations"
~~~

---

### Task 3: Aurora Home, Note Cards, and Stable States

**Files:**
- Modify: 'pubspec.yaml'
- Modify: 'pubspec.lock'
- Create: 'lib/features/notes/presentation/widgets/glass_note_card.dart'
- Create: 'lib/features/notes/presentation/widgets/notes_collection.dart'
- Create: 'lib/features/notes/presentation/widgets/notes_state_view.dart'
- Create: 'lib/features/notes/presentation/pages/notes_home_page.dart'
- Test: 'test/features/notes/presentation/glass_note_card_test.dart'
- Test: 'test/features/notes/presentation/notes_home_page_test.dart'

**Interfaces:**
- Consumes: GlassSurface, AuroraBackground, homeNotesProvider, homeTagsProvider, selectedTagProvider, sortOrderProvider, and NotesNotifier.
- Produces: 'GlassNoteCard' with Future<void> action callbacks and 'NotesHomePage'.

- [ ] **Step 1: Run impact analysis**

Run upstream impact on 'NoteCard', 'NotesPage', 'filteredNotes', 'SelectedTag', and 'SortOrder'. This task creates replacements but does not remove legacy widgets yet.

- [ ] **Step 2: Add the masonry dependency**

Run:

~~~text
flutter pub add flutter_staggered_grid_view:^0.7.0
~~~

Verify pubspec.lock resolves 0.7.0 and no unrelated dependency is upgraded.

- [ ] **Step 3: Write failing card tests**

~~~dart
testWidgets('card exposes semantics and local progress', (tester) async {
  final completer = Completer<void>();
  await tester.pumpWidget(
    MaterialApp(
      theme: AuroraTheme.light(),
      home: Scaffold(
        body: GlassNoteCard(
        note: sampleNote,
        onOpen: () {},
        onTogglePin: () => completer.future,
        onArchive: () async {},
        onTrash: () async {},
        onRestore: () async {},
        onDelete: () async {},
      ),
      ),
    ),
  );

  expect(find.bySemanticsLabel('Open note Sample'), findsOneWidget);
  await tester.tap(find.byTooltip('Pin note'));
  await tester.pump();
  expect(find.byType(CircularProgressIndicator), findsOneWidget);
  completer.complete();
  await tester.pumpAndSettle();
});
~~~

- [ ] **Step 4: Write failing home tests**

Test pinned notes appear before the masonry section, tags are selectable, the search surface calls 'onOpenSearch', loading shows skeletons without removing the page header, and an empty active collection shows an action-oriented message.

Use this constructor seam:

~~~dart
NotesHomePage({
  super.key,
  this.onOpenSearch,
  this.onCreateNote,
});
~~~

- [ ] **Step 5: Run tests and verify missing widgets fail**

Run:

~~~text
flutter test test/features/notes/presentation/glass_note_card_test.dart test/features/notes/presentation/notes_home_page_test.dart
~~~

Expected: FAIL because the new widgets do not exist.

- [ ] **Step 6: Implement card, collection, and state widgets**

GlassNoteCard must be StatefulWidget so each Future callback can show card-local progress. It must truncate previews, tint from note.color at restrained opacity, provide semantic labels/tooltips, and use PopupMenuButton for secondary actions.

NotesCollection must contribute a lazy sliver to the page's CustomScrollView:

~~~dart
SliverMasonryGrid.count(
  crossAxisCount: width < 360 ? 1 : 2,
  mainAxisSpacing: 12,
  crossAxisSpacing: 12,
  childCount: notes.length,
  itemBuilder: buildCard,
)
~~~

The outer page owns scrolling, and cards remain lazily built. NotesStateView provides 'NotesSkeleton', 'NotesEmptyState', and 'NotesErrorState(onRetry:)'.

- [ ] **Step 7: Implement NotesHomePage**

Build AuroraBackground → RefreshIndicator → CustomScrollView. Include date/greeting, search surface, tag chips, pinned section, all active notes, and bottom padding of at least 112 logical pixels for the future floating navigation.

Archive/trash actions await NotesNotifier methods and show an Undo SnackBar that calls restoreNote. Errors show a floating SnackBar and remain visible through preserved provider data.

- [ ] **Step 8: Verify and commit**

Run:

~~~text
dart format lib/features/notes/presentation test/features/notes/presentation
flutter test test/features/notes/presentation/glass_note_card_test.dart test/features/notes/presentation/notes_home_page_test.dart
flutter analyze
~~~

Stage Task 3 files. Run GitNexus detect_changes(scope: 'staged'). Commit:

~~~text
git commit -m "feat: build aurora notes home"
~~~

---

### Task 4: Focused Search Experience

**Files:**
- Create: 'lib/features/notes/presentation/pages/notes_search_page.dart'
- Create: 'lib/features/notes/presentation/widgets/note_filter_sheet.dart'
- Test: 'test/features/notes/presentation/notes_search_page_test.dart'

**Interfaces:**
- Consumes: searchQueryProvider, selectedTagProvider, sortOrderProvider, searchResultsProvider, homeTagsProvider, GlassNoteCard.
- Produces: 'NotesSearchPage(onOpenNote:)' and 'NoteFilterSheet'.

- [ ] **Step 1: Run impact analysis**

Run upstream impact on 'SearchQuery', 'SelectedTag', 'SortOrder', 'filteredNotes', and 'GlassNoteCard'.

- [ ] **Step 2: Write failing search tests**

~~~dart
testWidgets('search distinguishes empty query from no matches', (tester) async {
  final repository = InMemoryNoteRepository.seeded(sampleNotes);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AuroraTheme.light(),
        home: const NotesSearchPage(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  expect(find.text('Search your thoughts'), findsOneWidget);
  await tester.enterText(find.byType(SearchBar), 'missing phrase');
  await tester.pump();

  expect(find.text('No notes match “missing phrase”'), findsOneWidget);
  expect(find.text('Clear search'), findsOneWidget);
});
~~~

Also test title/content/tag matching, tag chips, sort selection, clear-search focus restoration, and semantic label 'Search notes and tags'.

- [ ] **Step 3: Run the test and verify failure**

Run: 'flutter test test/features/notes/presentation/notes_search_page_test.dart'

Expected: FAIL because NotesSearchPage is missing.

- [ ] **Step 4: Implement the focused search page**

Use an owned SearchController/TextEditingController synchronized to searchQueryProvider. Autofocus only when arriving from the home search action, not when the page is restored from an indexed shell. Show recent/suggested tags when query is empty, live results when non-empty, and NoteFilterSheet for tag/sort controls.

Use AnimatedSwitcher with a 200ms duration unless MediaQuery.disableAnimations is true.

- [ ] **Step 5: Verify and commit**

Run:

~~~text
dart format lib/features/notes/presentation test/features/notes/presentation
flutter test test/features/notes/presentation/notes_search_page_test.dart
flutter analyze
~~~

Stage Task 4 files, run GitNexus detect_changes(scope: 'staged'), and commit:

~~~text
git commit -m "feat: add focused notes search"
~~~

---

### Task 5: Archive and Trash Library

**Files:**
- Create: 'lib/features/notes/presentation/pages/notes_library_page.dart'
- Create: 'lib/features/notes/presentation/widgets/library_segmented_control.dart'
- Test: 'test/features/notes/presentation/notes_library_page_test.dart'

**Interfaces:**
- Consumes: notesByStatusProvider, NotesNotifier, GlassNoteCard, NotesStateView.
- Produces: 'NotesLibraryPage' and 'LibrarySection { archived, trash }'.

- [ ] **Step 1: Run impact analysis**

Run upstream impact on NotesNotifier.archiveNote, trashNote, restoreNote, deleteNote, cleanupTrash, notesByStatusProvider, and GlassNoteCard.

- [ ] **Step 2: Write failing library tests**

Test:

1. Archived is selected initially.
2. Switching to Trash changes the collection without route replacement.
3. Restore moves a note out of the current segment.
4. Permanent delete opens a confirmation dialog containing the note title.
5. Cancel keeps the note.
6. Confirm awaits delete completion.
7. Each empty segment has distinct explanatory copy.

~~~dart
expect(find.text('Delete “Old draft” forever?'), findsOneWidget);
expect(find.text('This action cannot be undone.'), findsOneWidget);
~~~

- [ ] **Step 3: Run the test and verify failure**

Run: 'flutter test test/features/notes/presentation/notes_library_page_test.dart'

Expected: FAIL because the library widgets are missing.

- [ ] **Step 4: Implement Library**

Use a local LibrarySection state and Material SegmentedButton wrapped in GlassSurface. The selected segment reads its status-derived provider. Restore uses NotesNotifier.restoreNote. Trash deletion uses an AlertDialog with Cancel and Delete forever. Archive-to-trash and restore actions show Undo only when the inverse operation is unambiguous.

Do not invoke cleanupTrash automatically. Retention remains explicit until a separate product rule defines scheduling.

- [ ] **Step 5: Verify and commit**

Run:

~~~text
dart format lib/features/notes/presentation test/features/notes/presentation
flutter test test/features/notes/presentation/notes_library_page_test.dart
flutter analyze
~~~

Stage Task 5 files, run GitNexus detect_changes(scope: 'staged'), and commit:

~~~text
git commit -m "feat: add archive and trash library"
~~~

---

### Task 6: More Sheet, Tag Management, and Safe Transfer

**Files:**
- Create: 'lib/features/notes/presentation/services/note_export_formatter.dart'
- Create: 'lib/features/notes/presentation/services/notes_transfer_gateway.dart'
- Create: 'lib/features/notes/presentation/providers/notes_transfer_provider.dart'
- Regenerate: 'lib/features/notes/presentation/providers/notes_transfer_provider.g.dart'
- Create: 'lib/features/notes/presentation/widgets/more_actions_sheet.dart'
- Create: 'lib/features/notes/presentation/widgets/tag_manager_sheet.dart'
- Modify: 'lib/features/notes/presentation/providers/note_providers.dart'
- Regenerate: 'lib/features/notes/presentation/providers/note_providers.g.dart'
- Test: 'test/features/notes/presentation/note_export_formatter_test.dart'
- Test: 'test/features/notes/presentation/notes_transfer_provider_test.dart'
- Test: 'test/features/notes/presentation/more_actions_sheet_test.dart'

**Interfaces:**
- Produces: 'NoteExportFormatter.toText', 'toMarkdown', 'toJson', and 'fromJson'.
- Produces: 'NotesTransferGateway.pickJsonText' and 'shareText/shareFile'.
- Produces: 'notesTransferProvider' AsyncNotifier and 'MoreActionsSheet'.
- Adds: 'NotesNotifier.removeTag(String tag)'.

- [ ] **Step 1: Run impact analysis**

Run upstream impact on NotesNotifier.importBackup, updateNote, allTags, AppTheme.setMode, and the export/import methods currently inside _NotesPageState.

- [ ] **Step 2: Write failing round-trip formatter tests**

~~~dart
test('JSON backup round-trips every persisted note field', () {
  final payload = NoteExportFormatter.toJson([sampleNote]);
  final restored = NoteExportFormatter.fromJson(payload).single;

  expect(restored.title, sampleNote.title);
  expect(restored.tags, sampleNote.tags);
  expect(restored.status, sampleNote.status);
  expect(restored.isPinned, sampleNote.isPinned);
  expect(restored.reminder, sampleNote.reminder);
});
~~~

Also test malformed top-level JSON, malformed note entries, empty text export, Markdown tags, and pipe/newline content.

- [ ] **Step 3: Write failing transfer and sheet tests**

Use FakeNotesTransferGateway to return JSON or throw. Verify the controller exposes loading/data/error, imports a valid backup through NotesNotifier, and preserves existing notes. Verify MoreActionsSheet has labeled rows for Theme, Manage tags, Export text, Backup JSON, Export Markdown, and Import backup.

- [ ] **Step 4: Run tests and verify failure**

Run:

~~~text
flutter test test/features/notes/presentation/note_export_formatter_test.dart test/features/notes/presentation/notes_transfer_provider_test.dart test/features/notes/presentation/more_actions_sheet_test.dart
~~~

Expected: FAIL because the services/providers/widgets do not exist.

- [ ] **Step 5: Implement deterministic transfer formats**

Encode JSON as a top-level list of NoteModel.fromEntity(note).toJson() maps so the exported format matches NoteModel.fromJson. Parse into NoteModel, then use copyWith(id: null, status: NoteStatus.active, reminder: null) during import. Throw FormatException with user-readable messages for invalid JSON shape or note fields.

The platform gateway owns FilePicker, XFile, and SharePlus. Tests override notesTransferGatewayProvider with a fake.

- [ ] **Step 6: Implement More and tag management**

MoreActionsSheet uses GlassSurface and safe-area padding. Theme selection calls AppTheme.setMode. Transfer rows await notesTransferProvider.notifier methods and render inline progress/error state.

Implement NotesNotifier.removeTag as one '_mutate' operation that updates every affected note without refreshing between individual updates. TagManagerSheet confirms removal and reports how many notes will change.

- [ ] **Step 7: Regenerate, verify, and commit**

Run:

~~~text
dart run build_runner build --delete-conflicting-outputs
dart format lib/features/notes/presentation test/features/notes/presentation
flutter test test/features/notes/presentation/note_export_formatter_test.dart test/features/notes/presentation/notes_transfer_provider_test.dart test/features/notes/presentation/more_actions_sheet_test.dart
flutter analyze
~~~

Stage Task 6 files, run GitNexus detect_changes(scope: 'staged'), and commit:

~~~text
git commit -m "feat: add safe note management and transfer"
~~~

---

### Task 7: Mobile Navigation Shell and Deep Links

**Files:**
- Create: 'lib/features/notes/presentation/widgets/notes_bottom_bar.dart'
- Create: 'lib/features/notes/presentation/pages/notes_shell_page.dart'
- Modify: 'lib/app/router.dart'
- Modify: 'lib/features/notes/presentation/pages/notes_page.dart'
- Test: 'test/features/notes/presentation/notes_shell_page_test.dart'
- Test: 'test/app/router_test.dart'

**Interfaces:**
- Consumes: NotesHomePage, NotesSearchPage, NotesLibraryPage, MoreActionsSheet, AddEditNotePage.
- Produces: StatefulShellRoute branches '/', '/search', and '/library'; editor routes remain '/note/new' and '/note/:id'.

- [ ] **Step 1: Run impact analysis**

Run upstream impact on routerProvider, NotesPage, MyApp.build, and each current GoRoute builder. Report any HIGH or CRITICAL risk before editing.

- [ ] **Step 2: Write failing bottom-bar and router tests**

Test four labeled destinations with 48×48 targets, central New note semantics, More opening a sheet without changing route, and go_router back behavior.

~~~dart
expect(find.bySemanticsLabel('Notes tab'), findsOneWidget);
expect(find.bySemanticsLabel('Search tab'), findsOneWidget);
expect(find.bySemanticsLabel('Create new note'), findsOneWidget);
expect(find.bySemanticsLabel('Library tab'), findsOneWidget);
expect(find.bySemanticsLabel('More actions'), findsOneWidget);
~~~

Router tests navigate '/', '/search', '/library', '/note/new', and an existing '/note/1'. Verify editor back returns to the originating shell branch.

- [ ] **Step 3: Run tests and verify failure**

Run:

~~~text
flutter test test/features/notes/presentation/notes_shell_page_test.dart test/app/router_test.dart
~~~

Expected: FAIL because shell navigation is missing.

- [ ] **Step 4: Implement the bottom bar**

NotesBottomBar accepts:

~~~dart
const NotesBottomBar({
  required int currentIndex,
  required ValueChanged<int> onDestinationSelected,
  required VoidCallback onCreate,
  required VoidCallback onMore,
});
~~~

Use GlassSurface, SafeArea, four labeled InkResponse/NavigationDestination controls, and a centered FloatingActionButton. Do not use emoji icons.

- [ ] **Step 5: Implement StatefulShellRoute**

Use StatefulShellRoute.indexedStack with branches for NotesHomePage, NotesSearchPage, and NotesLibraryPage. NotesShellPage calls 'navigationShell.goBranch(index, initialLocation: index == navigationShell.currentIndex)' for the first three destinations. More opens MoreActionsSheet. Create pushes '/note/new'.

Keep editor routes on the root navigator so they cover the shell. Preserve note lookup by id and the blank fallback only when no matching note exists.

Repurpose NotesPage as a compatibility wrapper around NotesHomePage or remove its router use after confirming no callers remain. Do not rename through text replacement; use GitNexus rename only if a symbol rename becomes necessary.

- [ ] **Step 6: Verify and commit**

Run:

~~~text
dart format lib/app/router.dart lib/features/notes/presentation test/app test/features/notes/presentation
flutter test test/features/notes/presentation/notes_shell_page_test.dart test/app/router_test.dart
flutter analyze
~~~

Stage Task 7 files, run GitNexus detect_changes(scope: 'staged'), and commit:

~~~text
git commit -m "feat: add mobile notes navigation shell"
~~~

---

### Task 8: Distraction-Free Aurora Editor

**Files:**
- Create: 'lib/features/notes/presentation/widgets/editor_formatting_bar.dart'
- Create: 'lib/features/notes/presentation/widgets/note_metadata_sheet.dart'
- Modify: 'lib/features/notes/presentation/pages/add_edit_note_page.dart'
- Test: 'test/features/notes/presentation/editor_formatting_bar_test.dart'
- Test: 'test/features/notes/presentation/note_metadata_sheet_test.dart'
- Test: 'test/features/notes/presentation/add_edit_note_page_test.dart'

**Interfaces:**
- Consumes: NotesNotifier.addNote/updateNote, GlassSurface, AuroraBackground, existing MarkdownBody and note:// links.
- Produces: awaited '_saveNote()' behavior, EditorFormattingBar, and NoteMetadataSheet.

- [ ] **Step 1: Run impact analysis**

Run upstream impact on AddEditNotePage, _AddEditNotePageState, _saveNote, _applyFormat, _toggleLinePrefix, _pickReminder, and _openLinkedNote.

- [ ] **Step 2: Extract formatting tests before extraction**

Test bold, italic, strike, inline code, quote, H1, H2, bullet, and checklist behavior against a TextEditingController. The public widget accepts the controller and exposes labeled 44×44 controls.

~~~dart
await tester.tap(find.byTooltip('Bold'));
expect(controller.text, '**selected**');
~~~

- [ ] **Step 3: Write metadata and editor failure tests**

Test selecting a tint, adding/removing tags, choosing/clearing a reminder, and returning NoteMetadataValue.

Editor tests must verify:

1. Empty content shows inline 'Add a title or some content'.
2. Done awaits persistence and shows progress.
3. Success pops only after completion.
4. Failure keeps the route open, preserves both controllers, and shows Retry.
5. Preview toggles Markdown without showing the editable body.
6. note:// links retain linked-note navigation.

- [ ] **Step 4: Run tests and verify failure**

Run:

~~~text
flutter test test/features/notes/presentation/editor_formatting_bar_test.dart test/features/notes/presentation/note_metadata_sheet_test.dart test/features/notes/presentation/add_edit_note_page_test.dart
~~~

Expected: FAIL because components and awaited save behavior are missing.

- [ ] **Step 5: Implement formatting and metadata components**

Move text-manipulation behavior without changing its output. NoteMetadataValue is immutable:

~~~dart
class NoteMetadataValue {
  const NoteMetadataValue({
    required this.color,
    required this.tags,
    required this.reminder,
  });

  final Color color;
  final List<String> tags;
  final DateTime? reminder;
}
~~~

NoteMetadataSheet works on a local copy and returns only when Apply is tapped. Clear reminder must return null.

- [ ] **Step 6: Redesign and harden AddEditNotePage**

Use AuroraBackground with a calm near-opaque editor GlassSurface. The top bar contains Back, Preview/Edit, metadata, and Done. Keep title/body first. Position EditorFormattingBar near the keyboard with AnimatedPadding based on MediaQuery.viewInsets.bottom.

Implement:

~~~dart
Future<void> _saveNote() async {
  if (_saving) return;
  final note = _buildValidatedNote();
  if (note == null) return;

  setState(() {
    _saving = true;
    _saveError = null;
  });
  try {
    final notifier = ref.read(notesProvider.notifier);
    if (widget.note == null) {
      await notifier.addNote(note);
    } else {
      await notifier.updateNote(note);
    }
    if (mounted) context.pop();
  } catch (error) {
    if (mounted) {
      setState(() {
        _saving = false;
        _saveError = 'Could not save this note. Try again.';
      });
    }
  }
}
~~~

Do not pop before the Future completes. Disable Done during save and expose Retry near the inline error.

- [ ] **Step 7: Verify and commit**

Run:

~~~text
dart format lib/features/notes/presentation test/features/notes/presentation
flutter test test/features/notes/presentation/editor_formatting_bar_test.dart test/features/notes/presentation/note_metadata_sheet_test.dart test/features/notes/presentation/add_edit_note_page_test.dart
flutter analyze
~~~

Stage Task 8 files, run GitNexus detect_changes(scope: 'staged'), and commit:

~~~text
git commit -m "feat: redesign the note editor"
~~~

---

### Task 9: Cross-Screen Accessibility, Responsive, and Regression Pass

**Files:**
- Modify only files identified by failing checks from Tasks 1–8.
- Create: 'test/features/notes/presentation/aurora_notes_flow_test.dart'
- Create: 'test/features/notes/presentation/aurora_accessibility_test.dart'

**Interfaces:**
- Consumes: the completed Aurora app.
- Produces: verified full user flows and accessibility guarantees.

- [ ] **Step 1: Run impact before any correction**

For every symbol needing a final correction, run upstream GitNexus impact first. Do not make opportunistic refactors.

- [ ] **Step 2: Write full-flow regression tests**

Using InMemoryNoteRepository, the stable note fixtures, and the real router, test:

1. Launch home with active and pinned notes.
2. Navigate to Search and open a result.
3. Save an edit and return to Search.
4. Navigate to Library, restore an archived note, and verify it appears on Home.
5. Open More and switch theme.
6. Open New note, save, and verify the new card.

Use stable ValueKeys on navigation destinations, note cards, editor fields, and primary actions where semantics alone are insufficient.

- [ ] **Step 3: Write accessibility and compact-width tests**

Pump at 360×640, 375×812, 390×844, and 768×1024. Repeat the compact case with textScaler 1.5. Assert no FlutterError overflow, all primary controls have semantics, and navigation remains reachable.

~~~dart
final errors = <FlutterErrorDetails>[];
final previous = FlutterError.onError;
FlutterError.onError = errors.add;
addTearDown(() => FlutterError.onError = previous);

await tester.binding.setSurfaceSize(const Size(360, 640));
await tester.pumpWidget(
  ProviderScope(
    overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    child: const MyApp(),
  ),
);
await tester.pumpAndSettle();
expect(errors, isEmpty);
~~~

- [ ] **Step 4: Run the new tests and correct only observed failures**

Run:

~~~text
flutter test test/features/notes/presentation/aurora_notes_flow_test.dart test/features/notes/presentation/aurora_accessibility_test.dart
~~~

If a failure occurs, add the smallest production correction and keep the regression assertion.

- [ ] **Step 5: Run UI/UX Pro Max delivery checks**

Read the installed 'ui-ux-pro-max/references/pro-rules.md' and verify:

- no emoji icons,
- contrast in light and dark modes,
- safe-area spacing,
- touch targets,
- semantic labels,
- reduced motion,
- visible loading/error/empty states,
- no glass-on-glass readability failures.

Use the in-app browser or Flutter screenshots to inspect at least the home, search, library, More sheet, editor, and dark-theme home screens.

- [ ] **Step 6: Run complete verification**

Run:

~~~text
dart run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
git diff --check
~~~

Expected: all commands exit 0.

- [ ] **Step 7: Detect final changes and commit**

Stage only Task 9 tests and required corrections. Run GitNexus detect_changes(scope: 'staged') and compare affected flows with the plan. Commit:

~~~text
git commit -m "test: verify aurora notes experience"
~~~

- [ ] **Step 8: Request final code review**

Invoke superpowers:requesting-code-review. Review the complete diff from the pre-redesign commit through Task 9 along standards and regression axes. Resolve findings through the original task implementer when possible, rerun full verification, and only then use superpowers:finishing-a-development-branch.
