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

- Markdown editing and preview with formatting controls, colors, tags, and pinning.
- Responsive Home, Search, Library, and More surfaces with filtering and sorting.
- Archive, Trash, restore, permanent deletion, and Undo for reversible mutations.
- Reminder scheduling with tap/open handling and Android snooze actions; platform
  permission, delivery, and relaunch behavior remain release-gated.
- Text and Markdown export of Active and Archive notes (Trash excluded),
  all-status JSON backup, and append-as-Active JSON import with reminders cleared.
- System, light, and dark themes.
- Accessibility behavior for scaled text, high contrast, and reduced motion.

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
| `lib/main.dart` | Flutter bootstrap and `ProviderScope` |

Dependencies flow from presentation to domain; data implements interfaces owned
by domain. See [AGENTS.md](AGENTS.md) for contributor constraints and the desktop
FFI/mobile SQLite initialization split.

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

Android builds use Android Gradle Plugin 8.11.1 and require JDK 17 or newer.
Keep machine-specific JDK paths out of tracked Gradle properties. Flutter uses
Android Studio's bundled JDK by default; confirm its selected Java runtime with
`flutter doctor -v`. If Flutter cannot find a compatible JDK, select one in
local developer configuration with `flutter config --jdk-dir="<jdk-path>"`.
For direct Gradle commands, set `JAVA_HOME` locally or choose the Gradle JDK in
Android Studio instead of editing `android/gradle.properties`.

## Common commands

| Task | Command |
| --- | --- |
| Resolve pinned dependencies | `flutter pub get --enforce-lockfile` |
| Run the app | `$deviceId = 'emulator-5554'; flutter run -d $deviceId` |
| Analyze and lint | `flutter analyze` |
| Run automated tests | `flutter test --concurrency=1` |
| Run Android smoke test | `$deviceId = 'emulator-5554'; flutter test integration_test/aurora_smoke_test.dart -d $deviceId` |
| Regenerate Riverpod code | `dart run build_runner build` |

Run code generation after changing a file containing `@riverpod`, review the
resulting diff, and commit the corresponding `.g.dart` changes.

## Readiness documentation

- [Branding](docs/branding.md) - product name, palette, launcher sources, and regeneration guardrails.
- [Privacy and data flow](docs/privacy.md) — technical disclosure and owner decisions.
- [Release readiness](docs/release.md) — store, signing, policy, and rollback gates.
- [QA matrix](docs/qa.md) — repeatable automated, device, accessibility, and upgrade checks.
- [Project Sync / Handoff](docs/superpowers/handoff.md) — current project status and evidence.
