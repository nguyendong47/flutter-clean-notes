# Quality Assurance Matrix

Use this matrix for every release candidate. A run is complete only when evidence
identifies the exact commit, app version/build, Flutter/Dart version, platform/OS,
device or simulator, viewport, text scale, theme, accessibility settings, and
result. File defects with reproduction steps and link them from the release record.

## Automated gate

Run from the repository root in PowerShell:

Set the verifier's required absolute external tool roots first. `JAVA_HOME` must
identify JDK 17 or newer (the Android Studio JBR is acceptable), and the
bundletool path must identify the pinned `1.18.3` JAR.

```powershell
flutter pub get --enforce-lockfile
$env:JAVA_HOME = 'C:\path\to\jdk-17-or-newer'
$env:CLEAN_NOTES_ANDROID_SDK_ROOT = 'C:\path\to\Android\Sdk'
$env:CLEAN_NOTES_FLUTTER_ROOT = 'C:\path\to\flutter'
$env:CLEAN_NOTES_BUNDLETOOL_JAR = 'C:\path\to\bundletool-all-1.18.3.jar'
dart run tool/verify_android_release_signing.dart --build-positive-release-artifacts
dart run build_runner build
git diff --exit-code -- '*.g.dart'
dart format --output=none --set-exit-if-changed lib test integration_test tool
flutter analyze
flutter test --concurrency=1
flutter build web --release --no-web-resources-cdn
$deviceId = 'emulator-5554'
flutter test integration_test/aurora_smoke_test.dart -d $deviceId
git diff --check
git status --short
```

For focused reruns, use paths rather than cached test counts, for example:

```powershell
flutter test test/features/notes/presentation/aurora_accessibility_test.dart
flutter test test/features/notes/presentation/aurora_notes_flow_test.dart
flutter test test/features/notes/presentation/notes_transfer_provider_test.dart
flutter test test/features/notes/data/datasources/local_note_datasource_migration_test.dart
flutter test test/features/notes/data/reminder_outbox_process_death_test.dart test/features/notes/domain/services/reminder_coordinator_test.dart
flutter test test/notification_service_test.dart test/app/notification_routing_test.dart
```

Passing widget/unit tests does not replace physical-device, native share-sheet,
notification permission, installed-app upgrade, or store-build evidence.
Run the Android smoke test twice as separate fresh-install runs; the Flutter test
runner uninstalls the test app after each run. Each run must pass and verify before
exit that its test-created note was permanently removed through the public Trash,
then **Delete forever** flow. These runs do not prove retained-state behavior
between invocations. Replace the sample device ID with the intended Android device
printed by `flutter devices`.

### Hosted CI contract

`.github/workflows/quality.yml` runs for pull requests and pushes to `main` with
`contents: read`, concurrency cancellation, and job timeouts. Its Ubuntu job
downloads checksum-verified Temurin `17.0.20+8` and Flutter `3.41.4` at revision
`ff37bef603469fb030f2b72995ab929ccfc227f0`, then enforces locked resolution,
generated-code drift, formatting, fatal analyzer findings, the serial test suite,
  local-resource Web release, Android debug APK, and a clean tree. Its Windows job downloads the
checksum-verified same Flutter revision, runs the SQLite datasource/migration
tests, builds Windows release, and enforces a clean tree.

The workflow file and local/action-lint review are not a hosted pass. Before
release, attach the GitHub run URL, exact commit, job logs, and artifacts for a
successful run. The current unpublished branch has no hosted result to claim.

## Devices and configurations

Test every approved shipping platform. If a row is not shipping, record the
product/release owner and decision instead of silently omitting it.

| Target | Minimum evidence |
| --- | --- |
| Android | One supported low/small device and one current large device; physical-device fresh-install notification denial/grant, process-death/reboot delivery, open/snooze, share/import, upgrade, background, and cold-launch evidence. Include an Android 12+ OEM source/destination pair for device-to-device backup exclusion and a 16 KB page-size device or official equivalent environment for the final release artifact. |
| iOS/iPadOS | One supported iPhone and one iPad size; physical-device notification authorization/delivery and tap/open, share/import, upgrade, background, and cold-launch evidence. Snooze is not expected without Darwin notification categories. |
| Windows | Signed or release-mode desktop run covering SQLite FFI, file picker/share behavior, resizing, keyboard, restart, and upgrade. Reminder scheduling is unsupported: verify **Add reminder** is absent, the unavailable disclosure is accessible, and a stored reminder can be cleared. |
| macOS | Signed or release-mode desktop run covering SQLite FFI, supported reminder scheduling and transient initialization recovery, picker/share, resizing, keyboard, restart, and upgrade. |
| Linux | Release-mode run covering SQLite FFI, picker/share behavior, resizing, keyboard, restart, and upgrade. Reminder scheduling is unsupported; verify the same unavailable/clear-only behavior as Windows. |
| Web (supported candidate) | Build with `flutter build web --release --no-web-resources-cdn`, then run Chrome and Edge from the intended origin. Verify the artifact selects same-origin CanvasKit/engine resources, loads bundled Roboto, points dynamic fallback at same-origin `fallback_fonts/`, and serves `sqflite_sw.js`, `sqlite3.wasm`, font/OFL, and engine assets with correct MIME types under the deployment CSP. In the editor, enter `Hello 👨‍👩‍👧‍👦 雪界 العربية`; verify the five bundled Noto shards load locally, glyphs render, and no request reaches a third-party Flutter CDN, `fonts.gstatic.com`, or another Google font endpoint. The fallback set is intentionally incomplete: separately confirm an unbundled glyph can only return a same-origin 404 and render as tofu, never egress. First load must reach the empty/content state without a database error; create, edit, search, archive, restore, and delete must work; IndexedDB must persist across reload and browser restart on the same origin; and responsive, keyboard, accessibility, share/import, cleared-site-data, and unsupported-reminder disclosure/clear-only behavior must be recorded. Deployment still requires its chosen server and CSP; do not call this offline first-install evidence. |

The branch has historical Playwright evidence after `3cfcbc6`: Web create,
search, Library, theme, responsive layout, same-origin restart persistence, and
console monitoring passed with zero observed console errors. This is useful
engineering evidence, not exact-candidate release evidence; rerun the complete
Web row against the final commit and deployment origin.

### Apple CocoaPods gate

Run Apple dependency bootstrap and build proof on macOS with the pinned Flutter
`3.41.4`, Xcode, and CocoaPods toolchain. Flutter `3.41.4` generates a missing
platform `Podfile` during the appropriate macOS-hosted Flutter build; do not
fabricate, copy, or hand-maintain a substitute from Windows.

```bash
flutter --version
pod --version
flutter clean
flutter pub get --enforce-lockfile
flutter build ios --release --no-codesign --no-pub
# Run only when macOS is an approved shipping target.
flutter build macos --release --no-pub
```

`path_provider_foundation` is pinned to `2.5.1` because `2.6.0` can introduce the
affected `objective_c` native-asset/IPA path. Run the one-time `flutter clean`
shown above before locked resolution and the next Apple archive after adopting
the pin; otherwise a stale `objective_c.framework` can survive in build output.
Verify the lockfile resolves `path_provider_foundation 2.5.1`, excludes
`objective_c`, and the generated registrant uses `PathProviderPlugin`.

Record Flutter, Xcode, Ruby, and CocoaPods versions; inspect the generated
`Podfile`, resolved pods/lock state, plugin integration, and `git status`. Verify
iOS keeps deployment target `15.0`, macOS keeps its approved deployment target,
and the exact candidate has no unexplained generated-file drift. Resolve whether
generated dependency files belong in the candidate before calling the worktree
clean. A successful Windows analysis/build cannot substitute for this gate, and
the final signed Apple archive/device evidence remains separate.

Within the approved set, cover these layout/accessibility combinations:

| Dimension | Required values |
| --- | --- |
| Viewport | Compact phone around 320 logical px, typical phone, large phone, tablet/large window, and a narrow resized desktop window |
| Orientation | Portrait and landscape; include the 640 x 320 class used by editor regression tests |
| Text scaling | Default, 1.5x, 2.0x, and 3.0x (or the platform's nearest exposed values) |
| Appearance | Light and dark; system theme switching while the app is running and after relaunch |
| Accessibility | High contrast on/off and reduced motion on/off where the platform exposes them |
| Input | Touch, keyboard traversal/activation, pointer/hover on desktop, and screen-reader traversal on at least Android and Apple targets |

Run the full critical path once at default settings and once at the most
constrained combination: compact/landscape, 3.0x text, high contrast, and reduced
motion. Pairwise coverage may be used for the remaining combinations only when
the release record shows which pair covers each value.

Verify each page announces one useful semantic heading after route changes,
interactive controls remain labeled and reachable, selected/expanded/busy states
are exposed, and loading, success, empty, and error changes use live regions
without duplicate announcements. Exercise Retry and dismissal with a screen
reader, not only the semantics debugger.

## Branding and launcher identity

Use the identity and asset contract in [branding.md](branding.md). On every
shipping target, verify the launcher/home-screen icon, task switcher, app window,
notification source, install/uninstall surfaces, and system settings all show the
approved `Clean Notes` name and Aurora mark. Inspect 32 px and 48 px renderings,
Android legacy and adaptive masks, iOS/iPadOS catalog sizes, web regular and
maskable icons, Windows ICO sizes, and macOS catalog sizes. Confirm there is no
clipping, unintended outer rounded-square plate, alpha halo, stale Flutter icon,
or stale `Aurora Notes`/template name.

Regenerate icons only through the pinned configuration, then review the full
binary/catalog diff and the iOS project-setting warning in the branding guide.
The second generator run must be byte-stable after any necessary iOS setting
restoration.

## Native launch screen

On Android before 12, Android 12+, iOS, and iPadOS, cold-launch the exact release
artifact in light and dark system appearance. Verify the Aurora mark, matching
background, aspect ratio, no stale Flutter/default frame, no flash between native
launch and the first Flutter frame, and no clipping across phone/tablet sizes.
Capture at least one cold-launch video per appearance and target class. On Web,
verify no generated `flutter_native_splash` overlay appears because Web splash is
disabled; normal browser loading behavior is separate.

## Surface matrix

For every surface, verify loading, populated, empty, initial-error, and
cached-data-with-refresh-error states when applicable. Confirm no overflow,
clipping, obscured controls, duplicate announcements, lost focus, or unreachable
action at every required layout.

| Surface | Core checks |
| --- | --- |
| Home | Pinned/unpinned ordering, tag filter, sort/filter sheet, create/open, active-empty vs whole-notebook-empty copy, scroll retention, archive/trash/pin, Undo, and retry. |
| Search | Initial focus, title/content/tag matching, clear, suggestions, filters/sort, no-match, open result, archive/trash and Undo, keyboard/safe-area reflow, and retained query/state after navigation. |
| Library | Archive/Trash segments, selection retention, restore, archive-to-trash, permanent-delete confirmation, cancel/focus return, busy/duplicate protection, failures, and Undo where offered. |
| More | Theme persistence, tag counts/removal confirmation, nested sheet/back/focus order, text/Markdown/JSON export, JSON import, cancellation, busy-state blocking, and truthful success/failure copy. |
| Privacy | After the app has loaded, take the client offline and open the bundled `/privacy` route from More; verify it makes no additional network request, semantic page/card headings, accurate storage/reminder/transfer/retention/network copy, scroll reachability at 3x text, accessible Back, and return to the originating shell state. |
| Editor | Create/edit, empty validation, Markdown formatting and preview, metadata/color/tags, future reminder validation, save/cancel/back, keyboard insets, linked/deep-open note, persistence failures, retry, and relaunch persistence. |

## Mutations, Undo, and failure injection

For pin, archive, trash, restore, permanent delete, tag removal, save, import, and
reminder schedule/cancel:

1. Trigger the operation once and rapidly attempt it again; only one durable
   mutation should occur.
2. Verify busy state, navigation blocking where required, focus, and accessible
   status announcement.
3. Use a test double or controlled platform/database failure before persistence;
   cached content and drafts must remain usable and retry must not duplicate data.
4. Use a post-commit refresh failure; the UI must not invite a destructive retry
   of a mutation that already committed.
5. Exercise every offered Undo action before and after its display timeout and
   verify the restored status/order after a fresh database read or relaunch.

## Backup import and export

- Before tapping a transfer row, verify its visible and screen-reader disclosure:
  text/Markdown include Active and Archive while excluding Trash; JSON includes
  Active, Archive, and Trash; import appends Active copies and clears reminders.
- On native targets, export text and Markdown through the real OS share surface.
  On Web, exercise both Web Share and the download fallback and verify `notes.txt`
  and `notes.md` are created without opening a mail draft. Inspect the result;
  verify Active and Archive notes, Unicode, Markdown characters, commas in tags,
  and empty fields, and prove Trash content is absent.
- On native targets, export JSON through the real OS share surface. On Web,
  exercise Web Share and download fallback for `notes_backup.json`, with no mail
  draft. Verify Active, Archive, and Trash are all present with colors, pin state,
  timestamps, reminders, and status.
- Inspect JSON against the fields listed in [privacy.md](privacy.md), then import
  into a clean database. Verify title, content, tags, color, creation time, and pin
  state are retained; imported entries must receive fresh IDs, active status, and
  no reminder. Treat this as append-as-copy behavior, not a byte-for-byte restore.
  Repeat in a populated database and confirm fresh IDs avoid conflicts.
- Verify cancel/dismiss/unavailable share results and chooser/picker failures.
- Import valid UTF-8 with and without BOM, malformed JSON, wrong top-level type,
  invalid/missing fields, empty file, wrong extension, multiple-file attempt,
  exactly 10 MiB, and one UTF-8 byte over 10 MiB. Exercise 10,000/10,001 notes,
  32/33 fields, field-name 128/129, title 32 Ki/plus one, body 5 Mi/plus one,
  256/257 tags per note, 50,000/50,001 total tags, tag 1,024/1,025, JSON depth
  64/65, structural complexity, and unknown nested list/map values. Export at
  each applicable boundary too; over-limit export must fail before platform
  share/download handoff. No partial import may remain after a failed row.
- Treat exported files as sensitive test evidence; use synthetic notes and remove
  device/cloud copies when the test record is complete.
- On Android API 30 or lower and API 31+, create notes, export a JSON backup,
  clear storage or uninstall, reinstall, and verify no app-private notes return
  through managed cloud backup. Import the retained JSON and prove the expected
  copies recover through the public UI.
- On an Android 12+ physical OEM source/destination pair, exercise the vendor's
  device-to-device migration. Verify the app's databases, preferences, files,
  and device-protected domains do not transfer. Record the devices, OS builds,
  transfer method, and evidence because manifest/rule inspection alone cannot
  guarantee OEM behavior.
- Inspect the merged release manifest and packaged data-extraction rules: backup
  must be disabled and both cloud-backup and device-transfer sections must
  exclude every Android storage domain without includes. Treat any missing rule
  or automatically restored note as a release blocker.
- Inspect platform temporary/cache storage where tooling permits after Markdown
  and JSON sharing. Record any materialized share copies and their OS/plugin
  cleanup behavior; the app currently has no explicit cleanup job for them.

## Reminders and notifications

Use this implemented support matrix; a platform-owner decision may remove a
shipping target but must not silently expand scheduling support:

| Platform | Scheduling | Required behavior |
| --- | --- | --- |
| Android | Supported | Contextual permission, delivery/open, Android snooze, cancellation, and process/reboot evidence. |
| iOS | Supported | Contextual permission, delivery/open, cancellation, and process/reboot evidence; no snooze without Darwin categories. |
| macOS | Supported | Contextual permission, delivery/open, cancellation, relaunch, and transient initialization-recovery evidence. |
| Web | Unsupported | No **Add reminder** action; accessible unavailable disclosure; a stored reminder remains visible and clearable. |
| Windows | Unsupported | Same unavailable/clear-only behavior as Web. |
| Linux | Unsupported | Same unavailable/clear-only behavior as Web. |

On a supported platform, force the optional notification plugin's first
initialization to fail. Verify the app still renders its first frame, diagnostic
copy exposes no native exception details, and the next schedule/cancel operation
coalesces one initialization retry. A successful retry must complete the
operation; a repeated failure must return only the sanitized unavailable error.

On physical Android and Apple devices, test permission not-determined, allowed,
denied, and later-revoked states. Android reminder evidence must use
`inexactAllowWhileIdle`; verify the release manifest has no exact-alarm permission
and the store submission makes no exact-alarm policy declaration.

- Schedule a future reminder; verify time-zone/local-time behavior, displayed
  title/body, lock-screen exposure, sound/priority, and delivery with the app in
  foreground, background, and terminated states.
- Tap the notification from each state. The intended persisted note must open
  exactly once; back navigation and any previous Home/Search/Library origin must
  remain coherent.
- On Android, start from a fresh install, deny permission, confirm note saving
  remains usable, then grant from a later reminder attempt and schedule. Terminate
  the process and reboot before delivery; verify open and 5/15/30/60-minute snooze
  actions intentionally launch the app/UI and produce one coherent navigation
  result. Record acceptable timing variance from inexact scheduling.
- On Apple platforms, verify tap/open from foreground, background, and terminated
  states. Do not record Android snooze as an Apple requirement unless a future
  release adds and documents Darwin notification categories.
- Verify cancellation after editing/removing a reminder, deletion cancellation,
  time-zone change, and app relaunch on each shipping platform.
- Verify past/equal-time reminders and notes without persisted IDs fail safely.
- Record platform/version cases where scheduled delivery or notification actions are
  unsupported, denied, or degraded; the user-facing behavior must match the
  release decision.
- On Web, Windows, and Linux, import or open a fixture containing a stored
  reminder. Verify details show the saved value and **Clear reminder**, never
  **Add reminder**; applying the clear must update SQLite without attempting a
  new schedule.
- If any prior beta, sideload, or public build reached users, add an upgrade case
  pairing legacy/v1 pending notifications with SQLite notes at generation 0 and
  at an advanced generation. Verify legacy/v1/v2 deliveries open the intended
  note by ID. The audit must cancel a legacy notification whose note is missing or
  reminder is cleared, conservatively preserve it when the SQLite note remains
  generation 0 with a non-null reminder—even when expired—and correct an advanced
  note from its current SQLite generation/reminder state. Legacy snooze works only
  while the SQLite generation remains 0 and the reminder is non-null.

### Durable reminder recovery gate

Schema v7 commits one current `reminder_outbox` command with each reminder-
affecting change: reminder-bearing add, reminder-changing update/clear, permanent
delete/cleanup, or accepted snooze. Other note mutations do not enqueue reminder
work. Platform schedule/cancel remains a separate native side effect, so release
evidence must prove the durable bridge rather than claim cross-system atomicity:

1. For a reminder-bearing add, reminder-changing update/clear, permanent delete,
   Trash cleanup, and accepted Android snooze, inject a transaction failure and
   prove neither the note change nor its replacement command partially commits.
   Also prove pin/status/tag/import and unchanged-reminder updates enqueue nothing.
2. Inject native failure after the SQLite commit. Prove the visible committed
   note/delete result remains truthful and the exact generation command remains
   pending. Terminate before an in-memory retry, relaunch, and prove startup or a
   later operation drains it.
3. Supersede a schedule with an update/cancel while the older native call is in
   flight. Prove the coordinator rechecks generation and cannot acknowledge or
   reschedule over the newer command. Every schedule must cancel the note's old
   native notification first; an expired schedule must result in cancellation.
4. Seed missing, stale, orphaned, current v2, and legacy/v1 pending notifications
   paired with SQLite notes at generation 0 and at an advanced generation. Startup
   must audit selectively, use `existingOnly` without a permission prompt, avoid
   global `cancelAll`/reset behavior, correct expired v2/outbox and advanced-note
   work, and preserve legacy/v1 only while the SQLite note remains generation 0
   with a non-null reminder, even if expired.
5. Exercise `note:v2:<id>:<generation>` open/snooze actions after updates and
   process death. Open must route by note ID even when its payload generation is
   stale; a stale-generation snooze must not change SQLite. An accepted snooze
   must update the reminder and outbox generation durably, and the UI cache must
   refresh even if native drain then fails.

Repeat the supported paths on signed physical devices across permission denial,
force-stop, process death, reboot, and OS upgrade. Automated process-restart tests
are necessary engineering evidence but do not prove plugin/OEM persistence.

## Android release artifact

Build the exact signed candidate AAB and inspect its merged manifest, resources,
launcher assets, ABIs, and native libraries rather than relying only on source
files. Record target/min SDK values, permissions, receivers, backup attributes,
data-extraction rules, signing identity, artifact SHA-256, and inspection-tool
versions.

Before owner credentials are available, run the signing verifier with
`JAVA_HOME`, `CLEAN_NOTES_ANDROID_SDK_ROOT`, and `CLEAN_NOTES_FLUTTER_ROOT` set to
absolute external roots. Positive modes also require
`CLEAN_NOTES_BUNDLETOOL_JAR` pointing to the pinned bundletool `1.18.3` JAR. The
verifier resolves `HEAD` with a trusted absolute Git executable, clones that
exact commit without hard links into a system-temporary directory, runs locked
dependency resolution there, and performs all Gradle and Flutter work against
the isolated snapshot. Uncommitted working-tree content is outside the proof.
It uses absolute Java, `jar`, `keytool`, `jarsigner`, Flutter, `apkanalyzer`, and
`apksigner` paths, a reduced trusted `PATH`, sanitized Git/JVM environments, and
a fresh system-temporary `GRADLE_USER_HOME`. The Git environment must ignore
system/global config and attributes and disable inherited hook and filesystem-
monitor paths before cloning or inspecting the candidate.

The default mode must prove both `:app:assembleRelease` and
`:app:bundleRelease` fail at `validateReleaseConfiguration` without usable
inputs. It verifies missing and blank direct inputs, complete direct-environment
precedence and bypass of an unused malformed properties file, relative and
Windows path handling, upload-certificate mismatch, debug-key rejection, and
containment of the canonical common Git root plus every linked or sibling
worktree. Repository-topology failures must block release validation while
debug, profile, IDE sync, and help tasks remain usable. The verifier must inspect
fresh unconfigured and configured debug/profile APKs: debug uses either the
template ID or `<release-id>.debug`; profile uses `<base-id>.profile` and the
debug signer, never the upload signer. It must also prove ignored credential
patterns, the shipped placeholder behavior, symlink boundaries, and fail-closed
missing or malformed linked-worktree metadata.

Add `--build-positive-release-artifacts` for the same checks plus a synthetic-key
release APK and AAB, or use `--build-positive-release-artifacts-only` only after
the default results were recorded for the exact commit. The verifier must read
the real packaged application ID, signing-certificate SHA-256, and artifact
SHA-256 from both outputs. Trusted, absolute Flutter release builds must generate
a production-only Android plugin registrant. In the isolated exact-commit clone,
a temporary minimal launcher shim must launch the pinned wrapper JAR with trusted
Java and forward Flutter's Gradle arguments without batch `call` reparsing. The
verifier must check the shim and snapshot
before and after each build, restore the original launcher byte-for-byte, and
reject any tracked candidate mutation. It validates and reads the AAB with
pinned bundletool, strict `jarsigner`, and `keytool`. Strict verification must
use the expected upload keystore and alias as explicit trust material, pass the
temporary password only through a scrubbed subprocess environment, and accept
only exit status `0`. It must prove that appending an otherwise permitted
metadata entry after signing is rejected with the exact unsigned-entry strict
status. It inspects the APK with
`apkanalyzer` and `apksigner`. The full gate must run on Windows; a
non-Windows host must report the Windows path proof as incomplete/nonzero.
Conflicting positive modes must exit with usage status `64` before any build
starts. Synthetic artifacts are never store candidates. The verifier must delete
its exact-commit clone, credentials, Gradle state, APK, and AAB before PASS,
report `ARTIFACTS_RETAINED=false`, and leave canonical repository build outputs
unchanged.
All Gradle invocations must use `--no-daemon`; cleanup must not execute a wrapper
after any integrity failure. Non-Flutter contract tasks must invoke the pinned
wrapper JAR with trusted Java directly and revalidate the complete snapshot before
and after every process.

Require `.gitattributes`, `android/gradlew`, `android/gradlew.bat`,
`android/gradle/wrapper/gradle-wrapper.jar`, and its properties file to be
tracked regular files matching the exact candidate. The verifier must hash the
already-read bytes in-process, match both launcher hashes and the official Gradle
8.14 wrapper-JAR SHA-256, pin the Gradle 8.14 all-distribution SHA-256, and enforce
the committed `LF`/`CRLF` line-ending contract. All wrapper tasks must run through
the verified temporary wrapper snapshot, not a mutable repository launcher.

Run Android gates with JDK 17 or newer, Android Gradle Plugin `8.12.3`, Kotlin
`2.2.20`, and the
checksum-pinned Gradle `8.14-all` wrapper. Reject a final tree that tracks
`org.gradle.java.home`; set process `JAVA_HOME` instead. For the candidate, use
only the ignored `android/key.properties` contract or direct `CLEAN_NOTES_*`
process environment described in
[release readiness](release.md#android-release-configuration). Do not use Gradle
`-P` or `ORG_GRADLE_PROJECT_*` for signing inputs. Verify direct values override
file values, a complete six-value direct configuration bypasses the unused file,
relative file-based keystore paths resolve from the selected properties file,
and relative direct-environment paths resolve from `android/`. Prove inherited
`CLEAN_NOTES_*` signing values are absent from dependency-resolution and build
subprocesses. Prove that every `android.injected.signing.*` name supplied by a
project/user `gradle.properties` file, `-P`, `ORG_GRADLE_PROJECT_*`,
`-Dorg.gradle.project.*`, or raw `-D` fails during settings evaluation, before
Android Gradle Plugin configuration, with one constant error that exposes
neither the name nor a malformed value. This forbidden input intentionally
blocks every task; separately prove that normal missing or unusable release
configuration still leaves debug, profile, and help/configuration usable.
Inspect the
packaged application ID and signing certificate from both the exact candidate
APK and finished AAB. The release ID must be the owner-approved non-template
value; debug must use `<release-id>.debug`, and profile must use
`<release-id>.profile` with the debug signer. The release certificate must match
the pinned approved upload-certificate SHA-256 and must not match a debug
keystore. Redact passwords and private paths from retained logs.

Run the current official Android 16 KB page-size compatibility check against
every packaged native library, then install and exercise the candidate on a 16 KB
page-size device or official equivalent environment. Both ELF segment alignment
and APK/AAB ZIP alignment must pass; a successful ordinary emulator launch is
not equivalent evidence. Recheck after any dependency or toolchain change.

The resolved dependency inventory must not contain the removed EOL
`sqlite3_flutter_libs` shim. Prove desktop SQLite FFI still opens and persists on
each shipping desktop target through `sqflite_common_ffi` and its current native
asset path.

## Database upgrades v1-v7

`test/features/notes/data/datasources/local_note_datasource_migration_test.dart`
creates physical SQLite files at schema versions v1 through v6, opens them
through the v7 datasource, and verifies representative rows after migration. It
also creates and reopens v7 databases. Maintain every legacy fixture plus fresh
and no-op v7 coverage whenever persistence changes:

| Start | Expected v7 result |
| --- | --- |
| v1 | Adds `isPinned`, `tags`, `status`, nullable `reminder`, `reminderGeneration = 0`, and an empty outbox; legacy rows survive and empty tags store as `json:[]`. |
| v2 | Adds `tags`, `status`, nullable `reminder`, generation 0, and an empty outbox; existing pin values survive and tags use the v6 representation. |
| v3 | Adds `status`, nullable `reminder`, generation 0, and an empty outbox; comma-delimited tags are preserved in order and rewritten with the `json:` prefix. |
| v4 | Adds nullable `reminder`, generation 0, and an empty outbox; active/archive/trash values survive and tags are rewritten deterministically. |
| v5 | Preserves every rich field, adds generation 0 and an empty outbox, and rewrites each comma-delimited tag value to `json:<JSON array>`. JSON-looking legacy text is literal data: `[]`, `["urgent"]`, and `json:["already"]` become individual tag strings rather than being guessed as encoded arrays. |
| v6 | Preserves v6 tag bytes and every row, adds `reminderGeneration = 0`, and creates an empty `reminder_outbox`; startup reconciliation, not schema migration, selectively covers existing reminders. |
| v7 | Fresh creation has the exact current note/outbox schema. Reopen/no-op coverage preserves note bytes, generation values, and pending commands without mutation. |

The v6 decoder recognizes JSON only after the explicit `json:` prefix. The
v1-v5 migration must never reinterpret unprefixed JSON-looking text, and an
already prefix-looking v5 value remains one literal legacy tag before it is
encoded into the new representation.

This automated physical-file proof covers migration mechanics in the host test
environment. For every approved Android, iOS, desktop, and Web database path,
still install/run the old fixture build, create representative notes, replace it
with the candidate build, then verify schema version 7, row count, tag order and
literal values, all other fields/statuses, reminder behavior, search, export,
mutation, and persistence after relaunch. On Web, keep the same origin for the
upgrade and verify IndexedDB across reload and browser restart. Also test fresh
v7 creation, a second no-op v7 open, preservation of a pending v7 command,
interrupted/failed upgrade recovery, low storage, and backup before any
destructive recovery. Downgrade from v7 is
unsupported until separate evidence proves it.

## Evidence and exit criteria

Store release evidence in the release system, not an ignored local directory.
Use stable names such as `<commit>-<platform>-<device>-<surface>-<state>` and
attach screenshots/video, console logs, test output, artifact hashes, and defect
links. Synthetic data must be visible in captures; exclude real notes and secrets.

QA approval requires:

- every automated gate exits zero with no unexpected generated or modified files;
- every applicable matrix row has evidence for the exact signed candidate;
- database upgrade, native share/import, and physical reminder paths pass on each
  approved platform class;
- accessibility blockers, crashes, data loss, duplicate mutations, and unresolved
  severity-one/severity-two defects are zero; and
- lower-severity known limitations have an owner, disposition, and release-note or
  store-disclosure decision.
