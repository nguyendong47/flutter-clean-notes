# Aurora Glass continuation handoff

This document is for the next coding agent taking over `flutter-clean-notes`.

## Snapshot

- Integrated branch: `main`
- Aurora merge commit: `26c0d97` (fast-forward from `feat/aurora-glass-redesign`)
- Post-merge test-stability fix: `test/features/notes/presentation/note_metadata_sheet_test.dart`
- The local `feat/aurora-glass-redesign` branch and linked worktree were removed after integration; never force-push.
- Product scope: Aurora Glass responsive UI, durable reminders, offline Web
  resources, privacy disclosure, release hardening, and project QA contracts.

Latest local verification after merge: `flutter analyze --no-pub` passed with
no issues; `flutter test --no-pub --concurrency=1` passed `637/637` after the
date-picker test was made deterministic.

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

The full release build matrix, signing verifier, emulator smoke run, final
GitNexus re-index/compare, and external store gates were not run in this
handoff session. Treat them as pending rather than inferred from host tests.

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

## 2026-09-05 verification session

Ran the remaining engineering gates from `docs/next-agent-prompt.md` against
HEAD `d4eceec` on `H:\source\flutter-clean-notes` (Windows host):

| Gate | Result | Evidence |
|------|--------|----------|
| `flutter pub get --enforce-lockfile` | PASS | lockfile satisfied |
| `dart run build_runner build --delete-conflicting-outputs` | PASS | 7 outputs regenerated, no unexpected drift |
| `dart format --set-exit-if-changed` | PASS | 117 files, 0 changed |
| `flutter analyze --fatal-infos --fatal-warnings` | PASS | 0 issues (71.8s) |
| `flutter test --concurrency=1` | PASS | 637/637 (3m12s) |
| `flutter build web --release --no-web-resources-cdn` | PASS | 70.6s |
| `flutter build windows --release` | PASS | 92.2s |
| `dart run tool/verify_android_release_signing.dart --build-positive-release-artifacts` | PASS | 35/35 checks; `PROOF_COMMIT=d4eceecc3711b1671160f5c9758e5cc438375d5d`, APK/AAB app id `dev.codex.cleannotes.contract`, cert sha256 `622d76651dcecb8ccc44d1d8ccdd7a91cc0b8d0865cc4146f1dd1bf404503885`; ephemeral credentials deleted (`ARTIFACTS_RETAINED=false`) |
| `integration_test/aurora_smoke_test.dart` on `emulator-5554` (Medium_Phone_API_36.1, API 36) | PASS (2 runs) | Run 1 (fresh install): `+1: All tests passed!` (18s). Then `adb -s emulator-5554 shell am force-stop com.example.flutter_clean_notes` and re-ran without reinstalling: run 2 (cold launch): `+1: All tests passed!` (19s). Emulator shut down after both runs to free RAM. |
| GitNexus `detect_changes(scope: compare, base_ref: main)` | PASS (CLI fallback) | MCP tool `mcp__gitnexus__detect_changes` failed with `LadybugDB unavailable ... Database file version: 43, Current build storage version: 42` — the running MCP server binary is older than the CLI that just re-indexed; needs an MCP server restart to clear. Used `node .gitnexus/run.cjs detect-changes --scope compare --base-ref main --repo .` instead: 3 files / 19 symbols changed (AGENTS.md, CLAUDE.md sections only), 0 affected processes, risk LOW. |
| Web browser matrix (`docs/qa.md` Web row) | PASS (Chrome, local static server) | Served `build/web` on `localhost:8765` via `python -m http.server`, loaded in Chrome (chrome-devtools MCP). All 18 network requests were same-origin (`localhost:8765`); no request to `fonts.gstatic.com` or any third-party Flutter/Google CDN. Reached empty state cleanly (no DB error). Typed `Hello 👨‍👩‍👧‍👦 雪界 العربية` into the editor — emoji, Han, and Arabic glyphs rendered; the 4 corresponding fallback shards (`notosanssymbols`, `notocoloremoji`, `notosanssc` x2, `notosansarabic`) loaded from `/fallback_fonts/`, same-origin. One console issue: "A form field element should have an id or name attribute" (cosmetic a11y lint, not functional). |
| Secret scan (`gitleaks 8.30.1`, installed via scoop) | DONE — no real leaks | `gitleaks git .` (212 commits) and `gitleaks dir .` (886 MB working tree, incl. untracked) both ran clean of real secrets. 7 raw hits, all confirmed false positives: `docs/next-agent-prompt.md:97` and 3 `.gitnexus/lbug` hits matched the Vietnamese phrase "dependency/advisory" against the `generic-api-key` entropy rule; `.gitnexus/meta.json`/`.gitnexus/gitnexus.json` matched a SHA-256 hash of the literal filename `android/key.properties.example` (a content hash, not a credential); `.superpowers/brainstorm/.../state/server-info` matched a local dev-server session token on `localhost`. `.gitnexus/*` is excluded via `.git/info/exclude`; neither it nor `.superpowers/` is tracked (`git ls-files` empty for both). |
| Dependency-advisory scan (`osv-scanner 2.5.1`, installed via scoop) | DONE — 0 vulnerabilities | `osv-scanner scan source --lockfile=pubspec.lock .` scanned 167 pub packages against the OSV database; JSON report `results: []`. Does not cover the already-tracked `docs/release.md` Kotlin/Gradle-plugin risk (`GHSA-r937-wjx7-w2jp` / CVE-2026-53914) since that's a build-toolchain dependency, not a `pub` package — that risk remains open per its existing entry. Formal SBOM generation still not done. |
| Hosted CI run, App Store/Play Store submission | PENDING | Requires external credentials, store accounts, and a hosted CI run for the exact commit — unavailable in this session. |

Toolchain used for the signing verifier: `JAVA_HOME=C:\Program Files\Android\Android Studio\jbr`,
`CLEAN_NOTES_ANDROID_SDK_ROOT=C:\Users\nguye\AppData\Local\Android\Sdk`,
`CLEAN_NOTES_FLUTTER_ROOT=C:\flutter`,
`CLEAN_NOTES_BUNDLETOOL_JAR=C:\Users\nguye\AppData\Local\CleanNotesToolchain\bundletool-all-1.18.3.jar`
(sha256 verified against the pinned `a099cfa1...` value before use).

Working tree after this session: same protected dirty files as before
(`.metadata`, `AGENTS.md`, `CLAUDE.md`, `.claude/skills/`, `.superpowers/`,
`worktrees.txt`) plus new untracked `docs/agents/issue-tracker.md` and
`docs/agents/domain.md` (added by `mattpocock-skills:setup-matt-pocock-skills`,
unrelated to Aurora). No repo files were modified by the verification gates
themselves; `flutter test`/`build`/verifier runs only touch `build/`, which is
gitignored. Stash `user-root-changes-before-aurora-ff-20260905` and the
`H:\source\flutter-clean-notes-merge-backup-20260905` backup were not touched.

## Cleanup boundary

The merge and cleanup are complete. The root still intentionally contains the
user's dirty `.metadata`, `AGENTS.md`, and `CLAUDE.md`, untracked `.claude/skills`,
`.superpowers`, and `worktrees.txt`. The pre-merge stash remains as
`user-root-changes-before-aurora-ff-20260905`; ignored build-artifact originals
and the feature worktree's protected skills are in
`H:\\source\\flutter-clean-notes-merge-backup-20260905`.
