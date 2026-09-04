# Aurora Glass continuation handoff

This document is for the next coding agent taking over `flutter-clean-notes`.

## Snapshot

- Integrated branch: `main`
- Aurora merge commit: `26c0d97` (fast-forward from `feat/aurora-glass-redesign`)
- Post-merge test-stability fix: `test/features/notes/presentation/note_metadata_sheet_test.dart`
- The local `feat/aurora-glass-redesign` branch and linked worktree were removed after integration; never force-push.
- Product scope: Aurora Glass responsive UI, durable reminders, offline Web
  resources, privacy disclosure, release hardening, and project QA contracts.

## What is already integrated

The candidate contains the reviewed Home, Editor, Search, Library, Reminder,
privacy, accessibility, Web-font, native splash, transfer-limit, database,
notification, CI, and release corrections. The detailed product contract is in
`docs/superpowers/specs/2026-08-17-notes-ui-ux-redesign-design.md`; repeatable
verification procedures are in `docs/qa.md`; store gates are in
`docs/release.md`.

## Remaining engineering gates

Run these from a clean detached checkout of the final candidate (serially):

```text
flutter pub get --enforce-lockfile
dart run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed lib test integration_test tool
flutter analyze --no-pub --fatal-infos --fatal-warnings
flutter test --no-pub --concurrency=1
flutter build web --release --no-pub --no-web-resources-cdn
flutter build windows --release --no-pub
```

Android signing is intentionally fail-closed and uses ephemeral credentials:

```text
dart run tool/verify_android_release_signing.dart --build-positive-release-artifacts
```

Set `JAVA_HOME`, `CLEAN_NOTES_ANDROID_SDK_ROOT`, `CLEAN_NOTES_FLUTTER_ROOT`,
and `CLEAN_NOTES_BUNDLETOOL_JAR` to the local toolchain paths first. Run the
Android smoke test from `integration_test/aurora_smoke_test.dart` on an API 36
emulator. Store publication still needs real Android/iOS identities,
credentials, URLs, metadata, and Apple/macOS archive evidence.

## Safe integration rules

Before merging, preserve the user's dirty root files and protected trees:
`.metadata`, `AGENTS.md`, `CLAUDE.md`, `.claude/skills/`, `.claude/settings.local.json`,
`.superpowers/`, and any ignored root build artifacts. Back up exact hashes,
stash only the tracked user edits, move ignored collision files out of the way,
run `git merge --ff-only <candidate>`, then reapply the user stash without
dropping it. Verify the protected hashes and `git status` afterward.

Run GitNexus `detect_changes` before each candidate commit and run a final
`detect_changes(scope: compare, base_ref: main)` after indexing the merged
candidate. Do not claim hosted CI or store approval without external evidence.

## Cleanup boundary

The merge and cleanup are complete. The root still intentionally contains the
user's dirty `.metadata`, `AGENTS.md`, and `CLAUDE.md`, untracked `.claude/skills`,
`.superpowers`, and `worktrees.txt`. The pre-merge stash remains as
`user-root-changes-before-aurora-ff-20260905`; ignored build-artifact originals
and the feature worktree's protected skills are in
`H:\\source\\flutter-clean-notes-merge-backup-20260905`.
