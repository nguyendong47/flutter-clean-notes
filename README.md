# Clean Notes

Clean Notes is a local-first note-taking app with a responsive Aurora
Glass interface. Notes use a local SQLite database as their primary app store;
user-initiated sharing, backup import, and reminder notifications cross the app
boundary as described in the [technical privacy draft](docs/privacy.md).

`Clean Notes` is the user-facing product name. The repository and Dart package
retain `flutter-clean-notes` and `flutter_clean_notes`; platform identifiers and
binary names remain separate release decisions. See the
[branding guide](docs/branding.md) for the identity contract and launcher asset
provenance.

## Features

- Markdown editing and preview with `flutter_markdown_plus 1.0.12`, formatting
  controls, colors, tags, and pinning. Preview images are inert, and only
  `note://` links navigate inside the app; note content cannot open or fetch
  network, file, data, or other external URIs.
- Title, body, color, tags, and reminder make up the editor's unsaved-change
  snapshot. Top-bar Back, system Back, and direct route pops require explicit
  **Discard changes** while dirty, **Keep editing** is the safe default, and a
  clean iOS edge-back gesture remains native.
- Responsive Home, Search, Library, and More surfaces with filtering and sorting.
- Archive, Trash, restore, permanent deletion, and Undo for reversible mutations.
- Reminder creation and scheduling on Android, iOS, and macOS, with tap/open
  handling and Android snooze actions. Web, Windows, and Linux identify
  scheduling as unavailable instead of offering **Add reminder**; a previously
  stored reminder can still be cleared. Schema v7 persists generation-tagged
  schedule/cancel commands atomically for reminder-bearing adds, reminder changes
  or clears, permanent deletion/cleanup, and accepted snooze; it serializes
  native delivery and selectively reconciles pending notifications after startup.
  Initialization failures never block the first frame, and failed commands remain
  durable for a later operation or relaunch. Platform permission, delivery,
  process-death, and reboot behavior remain physical-device release gates.
- Text and Markdown export of Active and Archive notes (Trash excluded),
  all-status JSON backup, and append-as-Active JSON import with reminders cleared.
  JSON import/export is capped at 10 MiB UTF-8 and bounded by semantic and JSON
  structure limits. Native targets use the OS share surface; Web uses Web Share
  when available or downloads `notes.txt`, `notes.md`, or `notes_backup.json`,
  with no mail-draft fallback.
- System, light, and dark themes. The saved mode is resolved before the first
  app frame; missing, invalid, or unreadable preferences fall back to system.
- A bundled `/privacy` disclosure reachable from More without an additional
  network request after the app has loaded.
- Accessibility behavior for semantic headings/routes, live status and error
  announcements, scaled text through 3x, high contrast, and reduced motion.
- Aurora native launch screens on Android and iOS in light and dark mode;
  Android 12 resources are included and Web native splash generation is disabled.
- Web release builds keep Flutter engine and dynamic font-fallback requests on
  the deployment origin. They bundle official Roboto plus the five Noto shards
  exercised by editor QA, with source, hashes, and OFL provenance. This is not a
  complete Unicode corpus: another unsupported glyph can return a same-origin 404
  and render as tofu, but it cannot fall back to a third-party font CDN. See the
  [Roboto provenance](assets/fonts/README.md) and
  [fallback provenance](web/fallback_fonts/README.md).

## Project Sync

The [Project Sync / Handoff](docs/superpowers/handoff.md) is the current source
for active work, verified evidence, limitations, and the continuation path. The
[Aurora specification](docs/superpowers/specs/2026-08-17-notes-ui-ux-redesign-design.md)
is the product contract; its
[implementation plan](docs/superpowers/plans/2026-08-17-aurora-glass-redesign.md)
is a historical implementation recipe, not a live progress tracker.

## Architecture

The app uses feature-first Clean Architecture under `lib/features/notes/`:

| Area | Responsibility |
| --- | --- |
| `presentation/` | Flutter pages/widgets, Riverpod state, and testable platform gateways |
| `domain/` | Notes entities, use cases, and repository abstractions |
| `data/` | SQLite models/datasource and repository implementations |
| `lib/app/` | Routing, theme, notifications, and app-level wiring |
| `lib/main.dart` | Flutter bootstrap and one preloaded `ProviderContainer` handed to `UncontrolledProviderScope` |

Dependencies flow from presentation to domain; data implements interfaces owned
by domain. See [AGENTS.md](AGENTS.md) for contributor constraints and the
platform-specific SQLite factory rules.

### Local database by platform

Native targets store notes in local SQLite. Windows, Linux, and macOS open the
database from the application-support directory through sqflite FFI. On Web,
`lib/main.dart` selects `databaseFactoryFfiWeb`, and the release must serve the
tracked `web/sqflite_sw.js` worker and `web/sqlite3.wasm` asset with correct MIME
types. Browser notes persist in IndexedDB for the same origin: changing the
scheme, host, or port selects a different store, and clearing that origin's site
data removes its notes. Use JSON export before clearing storage when recovery is
required.

The current schema is v7. It retains v6's explicit `json:<JSON array>` tag
encoding and adds `notes.reminderGeneration` plus `reminder_outbox`. Note and
outbox changes share one SQLite transaction; the native notification side effect
is acknowledged only when the exact command generation is still current.

## Set up and run

`pubspec.yaml` is the source of truth for the Dart SDK constraint, app version,
and dependencies. Install a compatible Flutter SDK and the toolchain for the
target platform, then run:

```powershell
flutter doctor
flutter pub get --enforce-lockfile
flutter devices
$deviceId = 'emulator-5554'
flutter run -d $deviceId
```

Replace `emulator-5554` with the intended ID printed by `flutter devices`. Omit
`-d $deviceId` only when Flutter can select that target without ambiguity. No
external database service is required.

Android builds pin Android Gradle Plugin 8.12.3, Gradle 8.14, and Kotlin 2.2.20 and require JDK
17 or newer. The Gradle wrapper verifies the official 8.14 distribution with
SHA-256
`efe9a3d147d948d7528a9887fa35abcf24ca1a43ad06439996490f77569b02d1`.
Keep machine-specific JDK paths out of tracked Gradle properties; in particular,
do not commit `org.gradle.java.home`. Flutter uses Android Studio's bundled JDK
by default; confirm its selected Java runtime with `flutter doctor -v`. If
Flutter cannot find a compatible JDK, select one in local developer
configuration with `flutter config --jdk-dir="<jdk-path>"`. For direct Gradle
commands, set `JAVA_HOME` locally or choose the Gradle JDK in Android Studio.

## Common commands

| Task | Command |
| --- | --- |
| Resolve pinned dependencies | `flutter pub get --enforce-lockfile` |
| Run the app | `$deviceId = 'emulator-5554'; flutter run -d $deviceId` |
| Analyze and lint | `flutter analyze` |
| Run automated tests | `flutter test --concurrency=1` |
| Run Android smoke test | `$deviceId = 'emulator-5554'; flutter test integration_test/aurora_smoke_test.dart -d $deviceId` |
| Regenerate Riverpod code | `dart run build_runner build` |
| Build Web release with local engine resources | `flutter build web --release --no-web-resources-cdn` |

Run code generation after changing a file containing `@riverpod`, review the
resulting diff, and commit the corresponding `.g.dart` changes.

## Continuous integration

`.github/workflows/quality.yml` runs on pull requests and pushes to `main` with
read-only repository permission, concurrency cancellation, and timeouts. It
downloads checksum-verified Flutter `3.41.4` (revision
`ff37bef603469fb030f2b72995ab929ccfc227f0`) and Temurin 17 where required. The
Ubuntu job enforces locked resolution, generated-code drift, format, fatal
analysis, serial tests, a Web release with locally bundled engine resources,
Android debug, and a clean tree. The Windows
job runs SQLite FFI/migration tests, a Windows release build, and the same clean-
tree check. This workflow is configured, but no hosted run for the current
unpublished branch is claimed; attach the exact-run result before relying on it
as release evidence.

## Readiness documentation

- [Branding](docs/branding.md) - product name, palette, launcher sources, and regeneration guardrails.
- [Privacy and data flow](docs/privacy.md) — technical disclosure and owner decisions.
- [Release readiness](docs/release.md) — store submission, signing, policy, and rollback gates; it is separate from branch merge readiness.
- [QA matrix](docs/qa.md) — repeatable automated, device, accessibility, and upgrade checks.
- [Product & Feature Roadmap](docs/roadmap.md) — competitive benchmark, long-term vision, and feature roadmap.
- [Project Sync / Handoff](docs/superpowers/handoff.md) — current project status and evidence.
