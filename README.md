# Flutter Clean Notes

Flutter Clean Notes is a local-first note-taking app built with Flutter, Riverpod, Clean Architecture, and SQLite. It supports Markdown notes, tags, colors, pinning, reminders, search and sorting, archive and trash workflows, theme selection, and note transfer.

## Project status

The Aurora Glass redesign is governed by the [design specification](docs/superpowers/specs/2026-08-17-notes-ui-ux-redesign-design.md) and [implementation plan](docs/superpowers/plans/2026-08-17-aurora-glass-redesign.md). See the [Project Sync / Handoff](docs/superpowers/handoff.md) for the active branch, current task, latest evidence, checkpoint deviations, and continuation path.

## Prerequisites

- A Flutter SDK whose bundled Dart SDK satisfies `^3.11.1` from `pubspec.yaml`.
- A working Flutter toolchain for the platform you intend to run. Use `flutter doctor` to identify missing platform components.

## Quick start

```text
flutter pub get
flutter run
```

The app stores notes locally; no external database service is required.

## Common commands

| Task | Command |
| --- | --- |
| Resolve dependencies | `flutter pub get` |
| Analyze and lint | `flutter analyze` |
| Run the full test suite | `flutter test` |
| Run the app | `flutter run` |
| Regenerate Riverpod code | `dart run build_runner build --delete-conflicting-outputs` |

Run code generation after changing a file that contains `@riverpod`, and commit the corresponding generated `.g.dart` update.

## Architecture

The app uses feature-first Clean Architecture under `lib/features/notes/`:

- `presentation/` contains pages, widgets, and Riverpod state.
- `domain/` contains entities, use cases, and repository abstractions.
- `data/` contains models, the SQLite datasource, and repository implementations.

Presentation calls the domain layer, while data implements domain-owned repository interfaces. App-level bootstrap, routing, notifications, and theme wiring live under `lib/main.dart` and `lib/app/`. Contributor rules and architecture details belong in [AGENTS.md](AGENTS.md); the Aurora product contract belongs in the [design specification](docs/superpowers/specs/2026-08-17-notes-ui-ux-redesign-design.md).

## Platform database note

Desktop targets use the sqflite FFI path, while the non-desktop database path uses regular sqflite. Keep both initialization paths working when changing startup or persistence code. [AGENTS.md](AGENTS.md#database-and-platform-constraints) is the authoritative workflow note.

## Documentation

| Document | Purpose |
| --- | --- |
| [AGENTS.md](AGENTS.md) | Contributor and agent workflow, architecture boundaries, verification, and code-generation rules |
| [Project Sync / Handoff](docs/superpowers/handoff.md) | Current implementation checkpoint, evidence, open work, and exact continuation path |
| [Aurora Glass design specification](docs/superpowers/specs/2026-08-17-notes-ui-ux-redesign-design.md) | Approved product and UX requirements plus implementation mapping |
| [Aurora Glass implementation plan](docs/superpowers/plans/2026-08-17-aurora-glass-redesign.md) | Task order, interfaces, implementation steps, and task-level verification |
