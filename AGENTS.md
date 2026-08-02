# AGENTS.md

Flutter note-taking app using Clean Architecture + Riverpod + sqflite. Dart SDK `^3.11.1`.

## Commands
- Analyze/lint: `flutter analyze`
- Run: `flutter run` (desktop apps need FFI DB init; see main.dart)
- Regenerate code: `dart run build_runner build --delete-conflicting-outputs`
- Tests: no test/ files exist yet. `flutter test` will pass trivially until you add tests.

## Architecture
- Feature-first Clean Architecture under `lib/features/notes/` split into `data/`, `domain/`, `presentation/`.
  Data flows: `presentation` (widgets/pages/providers) -> `domain` (entities/usecases/repositories) -> `data` (models/datasources).
  Domain must NOT depend on data (invert dependencies through abstract `NoteRepository`).
- Global wiring is in feature providers, e.g. `lib/features/notes/presentation/providers/note_providers.dart`; `main.dart` only boots `ProviderScope` + `MaterialApp`. Add new UI under `lib/features/<feature>/presentation/`.

## Codegen (important)
`flutter_riverpod` + `riverpod_annotation` codegen is used, not manual providers.
- After editing any file with `@riverpod`, run `dart run build_runner build --delete-conflicting-outputs` to regenerate `.g.dart` files, then import the generated provider (`noteRepositoryProvider` etc.).
- Committing stale `.g.dart` (e.g. `note_providers.g.dart`) without regenerating causes compile errors.

## DB quirk
`local_note_datasource.dart` branches on desktop (`Windows/Linux/macOS`) to call `sqfliteFfiInit()` + `databaseFactoryFfi.openDatabase(...)` directly, and uses the normal `openDatabase` on mobile/web. Keep this split working if you touch DB init. DB schema version is currently `1`.

## Style
- `analysis_options.yaml` uses stock `flutter_lints` (nothing custom enabled). Follow defaults; no project-specific lint overrides.