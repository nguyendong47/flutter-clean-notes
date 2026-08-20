# AGENTS.md

Flutter note-taking app using feature-first Clean Architecture, Riverpod code generation, and local SQLite. Treat `pubspec.yaml` as the dependency and SDK source of truth, `lib/` as the runtime source of truth, and `test/` as the test source of truth.

## Setup and verification

- Resolve dependencies after checkout with `flutter pub get`.
- Run the app with `flutter run`.
- Run static analysis with `flutter analyze` and the full test suite with `flutter test`.
- Add focused tests under the matching `test/` subtree and run them during implementation. Do not cache test counts in this file; inspect the test tree and current command output.
- Run `git diff --check` before staging. Follow the GitNexus gates in the managed block below before editing code symbols or committing.

## Architecture boundaries

- Keep note functionality under `lib/features/notes/`, split into `presentation/`, `domain/`, and `data/`.
- Dependency direction is `presentation -> domain` and `data -> domain`. The domain layer owns `NoteRepository`; it must not import data or presentation implementations.
- Put feature wiring in annotated providers such as `lib/features/notes/presentation/providers/note_providers.dart`. Add feature UI under `lib/features/<feature>/presentation/` and app-wide services, theme, routing, or primitives under `lib/app/`.
- `lib/main.dart` owns process bootstrap: Flutter binding setup, desktop sqflite FFI initialization, notification initialization, `ProviderScope`, persisted theme selection, Aurora themes, and router wiring.

## Riverpod code generation

- Providers use `riverpod_annotation` and generated `.g.dart` files rather than hand-written provider declarations.
- After editing a file containing `@riverpod`, run `dart run build_runner build --delete-conflicting-outputs`, inspect the generated diff, and commit the matching generated file.
- Import and consume the generated provider name; never edit generated `.g.dart` files manually.

## Database and platform constraints

- The SQLite schema is version 5. Keep `_createDB`, `_upgradeDB`, model serialization, and migration coverage aligned when persistence changes.
- `lib/main.dart` initializes the global FFI database factory on Windows, Linux, and macOS. `local_note_datasource.dart` also initializes FFI and opens the desktop database through `databaseFactoryFfi`; its non-desktop branch uses regular `openDatabase`. Preserve this split.
- Reminder scheduling is initialized before `runApp`. Changes to note persistence must preserve notification scheduling, cancellation, snooze, and nullable-reminder behavior.

## Aurora Glass work

- The canonical product and UX contract is the [Aurora Glass specification](docs/superpowers/specs/2026-08-17-notes-ui-ux-redesign-design.md); the ordered implementation contract is the [Aurora plan](docs/superpowers/plans/2026-08-17-aurora-glass-redesign.md).
- Read the [Project Sync / Handoff](docs/superpowers/handoff.md) before continuing. It is the sole owner of the active branch, task state, task commits, checkpoint-specific deviations, verification evidence, and exact next step.
- Keep light and dark themes equal, mobile widths primary, controls accessible, motion optional, and glass subordinate to readable content. Detailed tokens and acceptance criteria stay in the specification.

## Documentation ownership

- `README.md` is the discoverable project entry point and documentation index.
- This file owns contributor and agent workflow, architecture boundaries, code generation, and platform constraints.
- `docs/superpowers/handoff.md` is the only tracked source for current task state, commits, checkpoint deviations, and operational evidence. Update it after each Aurora task commit or session handoff.
- The Aurora specification owns approved design requirements and the stable task-to-design-surface mapping. The plan owns task instructions and order; neither records current completion state.
- `.superpowers/sdd/2026-08-17-aurora-glass-redesign/` is ignored local execution evidence. When present, update its ledger and task reports, but do not treat it as tracked documentation available in every clone.

## Style

- `analysis_options.yaml` includes stock `flutter_lints`; follow analyzer output and existing formatting.
- Prefer focused widgets, narrow provider interfaces, and tests of public behavior. Preserve unrelated user changes and generated artifacts outside the active task.

<!-- gitnexus:start -->
# GitNexus — Code Intelligence

This project is indexed by GitNexus as **flutter-clean-notes** (1638 symbols, 2688 relationships, 71 execution flows). Use the GitNexus MCP tools to understand code, assess impact, and navigate safely.

> Index stale? Run `node .gitnexus/run.cjs analyze` from the project root — it auto-selects an available runner. No `.gitnexus/run.cjs` yet? `npx gitnexus analyze` (npm 11 crash → `npm i -g gitnexus`; #1939).

## Always Do

- **MUST run impact analysis before editing any symbol.** Before modifying a function, class, or method, run `impact({target: "symbolName", direction: "upstream"})` and report the blast radius (direct callers, affected processes, risk level) to the user.
- **MUST run `detect_changes()` before committing** to verify your changes only affect expected symbols and execution flows. For regression review, compare against the default branch: `detect_changes({scope: "compare", base_ref: "main"})`.
- **MUST warn the user** if impact analysis returns HIGH or CRITICAL risk before proceeding with edits.
- When exploring unfamiliar code, use `query({search_query: "concept"})` to find execution flows instead of grepping. It returns process-grouped results ranked by relevance.
- When you need full context on a specific symbol — callers, callees, which execution flows it participates in — use `context({name: "symbolName"})`.
- For security review, `explain({target: "fileOrSymbol"})` lists taint findings (source→sink flows; needs `analyze --pdg`).

## Never Do

- NEVER edit a function, class, or method without first running `impact` on it.
- NEVER ignore HIGH or CRITICAL risk warnings from impact analysis.
- NEVER rename symbols with find-and-replace — use `rename` which understands the call graph.
- NEVER commit changes without running `detect_changes()` to check affected scope.

## Resources

| Resource | Use for |
|----------|---------|
| `gitnexus://repo/flutter-clean-notes/context` | Codebase overview, check index freshness |
| `gitnexus://repo/flutter-clean-notes/clusters` | All functional areas |
| `gitnexus://repo/flutter-clean-notes/processes` | All execution flows |
| `gitnexus://repo/flutter-clean-notes/process/{name}` | Step-by-step execution trace |

## CLI

| Task | Read this skill file |
|------|---------------------|
| Understand architecture / "How does X work?" | `.claude/skills/gitnexus/gitnexus-exploring/SKILL.md` |
| Blast radius / "What breaks if I change X?" | `.claude/skills/gitnexus/gitnexus-impact-analysis/SKILL.md` |
| Trace bugs / "Why is X failing?" | `.claude/skills/gitnexus/gitnexus-debugging/SKILL.md` |
| Rename / extract / split / refactor | `.claude/skills/gitnexus/gitnexus-refactoring/SKILL.md` |
| Tools, resources, schema reference | `.claude/skills/gitnexus/gitnexus-guide/SKILL.md` |
| Index, status, clean, wiki CLI commands | `.claude/skills/gitnexus/gitnexus-cli/SKILL.md` |

<!-- gitnexus:end -->
