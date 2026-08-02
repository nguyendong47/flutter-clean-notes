# Handoff / Project Status

Flutter note-taking app: Clean Architecture + Riverpod (codegen) + sqflite. Dart SDK `^3.11.1`.
All requested **features are implemented** and `flutter analyze` reports **No issues found**.

## Run / build
- Analyze/lint: `flutter analyze`
- Regenerate codegen (REQUIRED after editing any `@riverpod` file): `dart run build_runner build --delete-conflicting-outputs`
- Run: `flutter run` (desktop needs FFI DB init; handled in `main.dart`)
- No tests exist yet.

## Architecture (follow existing patterns)
- Feature-first under `lib/features/notes/` split into `data/`, `domain/`, `presentation/`.
  Flow: presentation -> domain -> data. Domain must NOT depend on data (`NoteRepository` is abstract).
- Providers use `@riverpod` codegen (see `note_providers.dart`, `app/app_providers.dart`).
- App-level theme provider: `lib/app/app_providers.dart`.

## Schema (sqlite, DB version = 5)
- Current schema created by `local_note_datasource.dart` `_createDB`. Migrations are in `_upgradeDB`
  (oldVersion<2..<5). Version history:
  - v1 base, v2 `isPinned`, v3 `tags` (CSV text), v4 `status` (0=active,1=archived,2=trashed), v5 `reminder` (nullable datetime ISO).
- `getNotes()` returns only `status=active`; `getNotesByStatus` fetches others. DB ordered by `isPinned DESC, createdAt DESC`.

## Implemented feature phases (all DONE)
1. Search — `searchQueryProvider` + `filteredNotesProvider` (title/content, case-insensitive).
2. Pin — `isPinned`, `NotesNotifier.togglePin`, pinned shown first.
3. Tags — `tags: List<String>` (stored CSV), `selectedTagProvider`/`allTagsProvider`, tag chips filter, edit with chips.
4. Archive/Trash — `NoteStatus` enum, mode-aware `NotesNotifier` (`noteModeProvider`), segmented Notes|Archive|Trash, card overflow menu (unarchive/restore/trash/delete-forever).
5. Rich text — markdown authoring toolbar + `flutter_markdown` Edit/Preview toggle on editor page.
6. Dark mode — persisted `appThemeProvider` (`shared_preferences`), toggle icon, light+dark themes.
7. Export — share **as text** + **JSON backup file** via `share_plus` (appbar menu).
8. Reminders — `Note.reminder` picker (date+time), shown on card (overdue -> red).

Dependencies added: `flutter_markdown`, `share_plus`, `shared_preferences`, `cross_file`.

## UI/UX pass (DONE)
- Theme tokens (navy seed `#1E3A8A`, scaffold `#F8FAFC`, Material 3, floating snackbar).
- Responsive grid via `LayoutBuilder` (2/3/4 cols). Removed dead search appbar icon.
- NoteCard: InkWell ripple, animated pin, 44px targets, cleaned footer + overflow menu.
- Editor: swatch check indicator, 44px toolbar, full-page scroll + scrollable preview.
- Empty states with icon. UI kept pastel per-card colors.

## Known limitations / next ideas (NOT done)
- OS-level reminder **notifications** NOT wired (would need `flutter_local_notifications` + platform manifests). In-app due-date indicators only.
- No `test/` files yet.
- DB migrations are additive; existing user notes preserved across upgrades.

## How to continue
Open a new opencode session in this repo and/or read this file. Ask for the next feature (e.g., OS notifications, tests, tags-as-🔎 improvements) and follow the same patterns above. Remember to run build_runner + flutter analyze before finishing.