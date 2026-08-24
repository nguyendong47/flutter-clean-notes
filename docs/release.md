# Release Readiness

This is the tracked store/submission release checklist. Check an item only when
its evidence is attached to the release record for the exact commit and version
being shipped. Engineering branch merge readiness is recorded separately in the
[Project Sync / Handoff](superpowers/handoff.md); merging a reviewed branch does
not approve, waive, or complete any unchecked store gate here. Current
identifiers and versions are observations from the checked-in files, not
approved production values.

## Current identity snapshot

| Setting | Checked-in value | Source | Status |
| --- | --- | --- | --- |
| User-facing product name | `Clean Notes` | Flutter app title and platform display metadata | Selected consistently in source; store-name availability and owner approval remain external gates. |
| Launcher identity | Aurora folded-note mark | `assets/branding/`, `pubspec.yaml`, and generated platform catalogs | Versioned for all configured targets; final device/store rendering evidence remains required. |
| App version | `1.0.0+1` | `pubspec.yaml` | Placeholder until release owner approves a monotonically increasing version/build. |
| Android application ID | Unconfigured debug fallback `com.example.flutter_clean_notes`; release value external | `android/app/build.gradle.kts` | Release prebuild rejects the template ID. With a valid release ID, debug uses `<release-id>.debug` and profile uses `<release-id>.profile`; profile is debug-signed. An owner-approved stable release ID is still required. |
| Apple bundle ID | `com.example.flutterCleanNotes` | `ios/Runner.xcodeproj/project.pbxproj` | Template identifier; replace before signing/store submission. |
| macOS bundle ID | `com.example.flutterCleanNotes` | `macos/Runner/Configs/AppInfo.xcconfig` | Template identifier; replace or record macOS as non-shipping. |
| Windows identity | Binary `flutter_clean_notes`; company `com.example` | `windows/CMakeLists.txt`, `windows/runner/Runner.rc` | Template metadata; replace or record Windows as non-shipping. |
| Linux application ID | `com.example.flutter_clean_notes` | `linux/CMakeLists.txt` | Template identifier; replace or record Linux as non-shipping. |
| Android release signing | External release-only signing configuration with upload-certificate pin | `android/app/build.gradle.kts` and `android/key.properties.example` | Release signing never falls back to the debug key. Debug and profile remain debug-signed and runnable; profile is isolated with `.profile`. Release prebuild rejects missing inputs, unsafe repository topology, mismatched certificates, and Android debug certificates; owner key custody and candidate evidence remain blocking. |
| Apple signing team | No development team recorded | Xcode project settings | Blocking for device/archive distribution. |
| Dependency lock | Tracked application resolution | `pubspec.lock` | Keep pinned; review and commit every intentional resolution change. |

## Local release gates

Run from the repository root in PowerShell on the exact release commit:

```powershell
flutter --version
flutter doctor -v
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
$deviceId = 'emulator-5554'
flutter test integration_test/aurora_smoke_test.dart -d $deviceId
git diff --check
git status --short
```

- [ ] **[OWNER: Engineering]** Record command output, Flutter/Dart versions,
  commit SHA, OS, and device/toolchain versions.
- [ ] **[OWNER: Engineering]** Code generation produces only expected `.g.dart`
  changes; the final release worktree is clean.
- [ ] **[OWNER: QA]** Complete [the QA matrix](qa.md) on every shipping platform
  and attach the required screenshots/logs.
- [ ] **[OWNER: Security]** Scan the resolved dependency set and release artifacts;
  record tool name/version, database timestamp, findings, and disposition.

Android gates require JDK 17 or newer, Android Gradle Plugin `8.12.3`, Kotlin
`2.2.20`, and the
checksum-pinned Gradle `8.14-all` wrapper. `android/gradle.properties` must not
track a machine-specific `org.gradle.java.home`; select the JDK through process
`JAVA_HOME` instead. Verify these invariants again after integrating this work
with any Android build-hygiene change.

### Hosted CI evidence

`.github/workflows/quality.yml` is configured for pull requests and pushes to
`main`, with read-only contents permission, concurrency cancellation, timeouts,
checksum-verified Flutter `3.41.4`/Dart `3.11.1`, and checksum-verified Temurin
`17.0.20+8` on Ubuntu. Ubuntu enforces locked resolution, generated-code drift,
format, fatal analysis, serial tests, local-resource Web release, Android debug,
and clean tree.
Windows enforces datasource/migration tests, Windows release, and clean tree.

- [ ] **[OWNER: Engineering/Release]** Attach a successful hosted run for the
  exact release commit, including its URL and both job logs. Configuration review
  or local parity is not a hosted pass; no current unpublished-branch run is
  claimed here.

Build only the platforms approved for the release. Typical artifact commands are
`flutter build appbundle --release`, `flutter build ipa --release` (macOS/Xcode
required), `flutter build windows --release`, `flutter build macos --release`,
`flutter build linux --release`, and
`flutter build web --release --no-web-resources-cdn`. Archive the
exact commands and hashes of submitted artifacts.

Web is a supported release candidate when the exact release build includes same-
origin Flutter engine resources, `sqflite_sw.js`, `sqlite3.wasm`, bundled Roboto,
and the five QA-covered Noto fallback shards; points `fontFallbackBaseUrl` at the
deployment origin; makes no third-party Flutter CDN, `fonts.gstatic.com`, or other
Google font request in the tested flow; and passes the browser runtime and
persistence checks in [the QA matrix](qa.md). The fallback set is intentionally
not a complete Unicode corpus: an unbundled glyph may return a same-origin 404 and
render as tofu but must not egress. Retain the recorded
[Roboto provenance](../assets/fonts/README.md)
and [fallback provenance](../web/fallback_fonts/README.md). Candidate support does
not by itself approve Web as a shipping target; record product/release-owner
approval, deployment origin, and deployed CSP with the release evidence.

Apple dependency resolution and build proof must run on macOS with Flutter
`3.41.4`, Xcode, and CocoaPods. Let Flutter generate any missing platform
`Podfile` during the macOS-hosted build and inspect the resulting pod resolution;
do not fabricate or copy a Podfile from Windows. Follow the
[Apple CocoaPods QA gate](qa.md#apple-cocoapods-gate) before approving iOS or
macOS as a shipping target.

## Identity, signing, and versioning

### Android release configuration

The repository contains no release key or usable credential. Debug builds remain
runnable with the template application ID when the release application ID is
absent or invalid. When a valid external release ID is present, debug packages
`<release-id>.debug`; it never shares the production ID. Profile always packages
the selected base ID with `.profile` and uses the Android debug signer, so it
never shares either the production ID or upload signer. Every release build
depends on `validateReleaseConfiguration`, which rejects a missing or placeholder
application ID, a missing/unreadable or repository-local keystore, missing
credentials, an alias without a private key, a certificate that does not match
the approved SHA-256 fingerprint, and any Android debug certificate before
signing. During settings evaluation, before the Android app plugin is applied,
the build rejects every `android.injected.signing.*` name supplied through
project/user `gradle.properties`, `-P`, `ORG_GRADLE_PROJECT_*`,
`-Dorg.gradle.project.*`, or raw `-D`. This prevents Android Gradle Plugin
signing overrides from replacing the checked identity, keystore, certificate
pin, or debug/profile signer. The guard emits one constant error without
printing the property name or value, including when the value is malformed for
a typed Android option. Because the guard is settings-wide, a forbidden
injected-signing source blocks debug, profile, IDE sync, and help as well as
release. Without a forbidden override, missing or unusable release
configuration still leaves those non-release operations usable. The release
build type references only the `release` signing config and never falls back to
the debug key. The Kotlin namespace and `MainActivity`
package remain `com.example.flutter_clean_notes`; only the packaged application
ID is externally overridden.

Use either of these external inputs:

1. Copy `android/key.properties.example` to the ignored
   `android/key.properties`, replace every placeholder, and keep the keystore
   outside the repository. A relative `storeFile` in this file resolves from the
   properties file's directory. Set `uploadCertificateSha256` to the 64-hex-digit
   SHA-256 fingerprint of the owner-approved upload certificate for `keyAlias`.
2. Supply direct process environment variables named
   `CLEAN_NOTES_APPLICATION_ID`, `CLEAN_NOTES_STORE_FILE`,
   `CLEAN_NOTES_STORE_PASSWORD`, `CLEAN_NOTES_KEY_ALIAS`,
   `CLEAN_NOTES_KEY_PASSWORD`, and `CLEAN_NOTES_UPLOAD_CERT_SHA256`. Inject these
   exact names directly from the CI secret manager. Do not translate them into
   Gradle `-P` properties or `ORG_GRADLE_PROJECT_*` variables. A relative
   `CLEAN_NOTES_STORE_FILE` resolves from `android/`.

Each direct environment value takes precedence over its corresponding properties
file value. A present but blank direct value is invalid and never falls back to
the file. When all six direct values are nonblank, the properties file and
`CLEAN_NOTES_KEY_PROPERTIES_FILE` selector are not read or validated; an unused,
malformed lower-precedence file cannot block a complete direct configuration.
Otherwise, `CLEAN_NOTES_KEY_PROPERTIES_FILE` may select an alternative properties
file outside the repository; a relative selector resolves from `android/`, and a
blank selector selects the default. The only allowed in-repository properties
file is the exact ignored `android/key.properties`. If that default path is a
symbolic link, its canonical target must be outside every protected
repository/worktree root; a link back to tracked or sibling-worktree content is
rejected. The keystore itself must always be outside the repository's canonical
common Git root and every registered linked or sibling worktree. Root ignore
rules cover `key.properties`, `.jks`, `.keystore`, `.p12`, and `.pfx` material
regardless of folder. Unreadable or malformed Git/worktree topology blocks
release validation but does not break debug, profile, IDE sync, or help tasks.

Java properties treat backslashes as escapes. On Windows, use forward slashes,
for example `storeFile=C:/Users/name/secure/upload-keystore.jks`, or double every
backslash, for example `storeFile=C:\\Users\\name\\secure\\upload-keystore.jks`.
The file is read as UTF-8. Do not put real values in command history, tracked
Gradle files, CI logs, or the example. Do not pass passwords with `-P` and do not
persist them with `setx`. After the owner selects the permanent application ID,
do not change it between store updates.

Before using owner credentials, run the executable contract check. It resolves
the exact `HEAD` commit with a trusted absolute Git executable, clones that
commit without hard links into a system-temporary directory, runs locked
dependency resolution there, and performs every build against that isolated
snapshot. Uncommitted working-tree content is not part of the proof. It resolves
Java, `jar`, `keytool`, `jarsigner`, Flutter, `apkanalyzer`, and `apksigner` from the
absolute external roots supplied below, replaces `PATH` with trusted entries,
and removes inherited Git, Gradle, and JVM hook/configuration sources. Git
commands ignore system/global configuration and attributes, disable inherited
hook paths and filesystem-monitor hooks, and use only the verifier's explicit
Git controls. All inherited `CLEAN_NOTES_*` signing inputs are removed before
dependency resolution or build subprocesses start; contract builds then receive
only their explicit ephemeral inputs. Wrapper bootstrap and every Gradle/Flutter
subprocess use a fresh system-temporary `GRADLE_USER_HOME`.

The verifier requires `.gitattributes`, `android/gradlew`,
`android/gradlew.bat`, `android/gradle/wrapper/gradle-wrapper.jar`, and its
properties file to be tracked, regular files matching the exact candidate. It
hashes their already-read bytes in-process, pins both launcher hashes and line
endings (`LF` for `gradlew` and wrapper properties, `CRLF` for `gradlew.bat`),
validates the JAR against Gradle 8.14's published SHA-256
(`7d3a4ac4...96172`), and requires the Gradle 8.14 all-ZIP checksum
(`efe9a3d1...b02d1`). It then executes a verified wrapper copy outside the source
snapshot, not a mutable repository launcher. Do not restore the Flutter-template
ignore rules for `gradlew`, `gradlew.bat`, or `gradle-wrapper.jar`.

The default command runs fail-closed validation and inspects real unconfigured and
configured debug/profile APKs. It verifies their packaged application IDs and
certificates, including the `.profile` suffix and debug signer, and proves that
unconfigured `assembleRelease` and `bundleRelease` cannot proceed. Add
`--build-positive-release-artifacts` to run those checks and build a synthetic-key
release APK plus AAB. It runs trusted, absolute Flutter `build apk` and
`build appbundle` release commands so Flutter generates a production-only plugin
registrant. Inside the isolated exact-commit clone, the candidate Gradle launcher
is temporarily replaced with a minimal shim that launches the pinned wrapper JAR
with the trusted Java executable and forwards Flutter's arguments without batch
`call` reparsing. The verifier checks both the shim and snapshot
before and after each build, restores the original launcher byte-for-byte, and
rejects any tracked candidate mutation. It reads each fresh
release artifact's application ID, signing-certificate SHA-256, and file SHA-256;
it also validates and inspects the AAB with pinned bundletool `1.18.3`, strict
`jarsigner`, and `keytool`. Strict verification uses the expected upload
keystore and alias as explicit trust material and supplies its temporary
password only through a scrubbed subprocess environment, never a command-line
argument. The positive proof appends a permitted metadata file to a signed AAB
fixture and requires strict signature verification to reject the new unsigned
entry. Use
`--build-positive-release-artifacts-only` only when the fail-closed checks were
already recorded for the exact commit and only the two positive artifacts need
regeneration. Neither synthetic artifact is a store candidate. All credentials,
source clones, Gradle state, APKs, and AABs are deleted before PASS; the verifier
prints `ARTIFACTS_RETAINED=false` and never writes or overwrites canonical
repository build outputs.
The two positive-build flags are mutually exclusive. The full fail-closed suite
requires Windows so its Java-properties path case cannot be silently omitted;
on another host it exits nonzero instead of reporting a complete PASS. The
positive-only artifact mode remains available after a full exact-commit result
has already been recorded.

Every Gradle invocation uses `--no-daemon`; cleanup never executes a wrapper that
could have failed its integrity checks. Non-Flutter contract tasks invoke the
pinned wrapper JAR with trusted Java directly and revalidate the full snapshot
immediately before and after every process.

Set all required absolute external tool roots before running the verifier.
`JAVA_HOME` must identify JDK 17 or newer; the Android Studio JBR is acceptable.
`CLEAN_NOTES_BUNDLETOOL_JAR` is required by either positive mode and must identify
the pinned bundletool `1.18.3` JAR. Do not rely on machine-specific paths in
tracked files.

```powershell
$env:JAVA_HOME = 'C:\path\to\jdk-17-or-newer'
$env:CLEAN_NOTES_ANDROID_SDK_ROOT = 'C:\path\to\Android\Sdk'
$env:CLEAN_NOTES_FLUTTER_ROOT = 'C:\path\to\flutter'
$env:CLEAN_NOTES_BUNDLETOOL_JAR = 'C:\path\to\bundletool-all-1.18.3.jar'
dart run tool/verify_android_release_signing.dart
dart run tool/verify_android_release_signing.dart --build-positive-release-artifacts
```

For the real certificate fingerprint, let `keytool` prompt for the store password
instead of including it in shell history:

```powershell
keytool -list -v -keystore C:/secure/upload-keystore.jks -alias upload
```

Build and inspect the exact candidate:

```powershell
# These variables are populated in memory by the approved secret-manager step.
$env:CLEAN_NOTES_APPLICATION_ID = $releaseApplicationId
$env:CLEAN_NOTES_STORE_FILE = $releaseStoreFile
$env:CLEAN_NOTES_STORE_PASSWORD = $releaseStorePassword
$env:CLEAN_NOTES_KEY_ALIAS = $releaseKeyAlias
$env:CLEAN_NOTES_KEY_PASSWORD = $releaseKeyPassword
$env:CLEAN_NOTES_UPLOAD_CERT_SHA256 = $releaseCertificateSha256
try {
  flutter build appbundle --release
} finally {
  Remove-Item Env:\CLEAN_NOTES_APPLICATION_ID -ErrorAction SilentlyContinue
  Remove-Item Env:\CLEAN_NOTES_STORE_FILE -ErrorAction SilentlyContinue
  Remove-Item Env:\CLEAN_NOTES_STORE_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:\CLEAN_NOTES_KEY_ALIAS -ErrorAction SilentlyContinue
  Remove-Item Env:\CLEAN_NOTES_KEY_PASSWORD -ErrorAction SilentlyContinue
  Remove-Item Env:\CLEAN_NOTES_UPLOAD_CERT_SHA256 -ErrorAction SilentlyContinue
}
```

Record the artifact SHA-256, packaged application ID, signing-certificate
SHA-256, and comparison with the Play Console upload certificate. Remove any
process-scoped secret environment variables when the build finishes.

- [ ] **[OWNER: Product/Release]** Approve the app/store name and unique Android
  and Apple identifiers; `Clean Notes` is the checked-in display name, but store
  availability and ownership are not implied. Update associated services, tests,
  and store records.
- [ ] **[OWNER: Product/Design/QA]** Approve the launcher and display identity on
  every shipping platform using [the branding contract](branding.md). Keep
  `flutter_launcher_icons` pinned to `0.14.4`; if icons are regenerated, review
  all outputs and restore the documented iOS project settings before signing.
- [ ] **[OWNER: Release]** Set the marketing version and monotonically increasing
  build number in `pubspec.yaml`; confirm generated Android/iOS metadata matches.
- [ ] **[OWNER: Release/Security]** Supply the owner-approved Android application
  ID and upload key through the external contract above, document secure custody,
  backup, and rotation, and prove the exact candidate is signed by the approved
  upload certificate rather than the debug certificate.
- [ ] **[OWNER: Apple Release]** Select the Apple team, certificates, provisioning,
  capabilities, bundle ID, and App Store Connect record; archive and validate a
  signed build.
- [ ] **[OWNER: macOS Release]** Approve and replace the macOS bundle ID, product
  name, copyright, signing, entitlements, and notarization identity, or attach an
  owner-approved non-shipping rationale to the release record.
- [ ] **[OWNER: Windows Release]** Approve and replace the Windows binary/product,
  company, copyright, package/publisher identity, and signing configuration, or
  attach an owner-approved non-shipping rationale to the release record.
- [ ] **[OWNER: Linux Release]** Approve and replace the Linux application ID,
  binary/desktop metadata, package identity, and distribution signing policy, or
  attach an owner-approved non-shipping rationale to the release record.
- [ ] **[OWNER: Release]** Install signed release artifacts on clean devices and
  verify upgrade from the last public version without data loss.

## Apple toolchain and CocoaPods

- [ ] **[OWNER: Apple Engineering]** On macOS, pin Flutter `3.41.4` and record
  Xcode, Ruby, and CocoaPods versions. Run the one-time `flutter clean` required
  after adopting the Apple dependency pin, resolve dependencies with
  `flutter pub get --enforce-lockfile`, then run the iOS release build without
  signing and with `--no-pub`; allow Flutter to generate the missing `Podfile`,
  then inspect pod/plugin resolution, iOS deployment target `15.0`, generated
  files, and `git status` against the exact candidate.
- [ ] **[OWNER: Apple Engineering/Security]** Verify locked resolution uses
  `path_provider_foundation 2.5.1`, excludes `objective_c`, and registers
  `PathProviderPlugin`. The pin mitigates the `2.6.0` native-asset/IPA regressions
  tracked by [Flutter issue 186794](https://github.com/flutter/flutter/issues/186794)
  and [Flutter issue 187752](https://github.com/flutter/flutter/issues/187752); it
  does not replace a clean Xcode/CocoaPods build, signed archive validation, or
  physical-device launch test.
- [ ] **[OWNER: Apple Engineering]** If macOS ships, run the corresponding macOS
  Flutter/CocoaPods build on macOS and verify the checked-in deployment target,
  plugin integration, entitlements, and generated dependency state.
- [ ] **[OWNER: Apple Engineering/Release]** Resolve the generated-file policy
  before freezing the candidate, then produce the signed archive/device evidence.
  A Podfile fabricated on Windows and a Windows-only Flutter analysis are both
  invalid substitutes for this gate.

## Store listing and policy

- [ ] **[OWNER: Product/Marketing]** Approve name, short/long descriptions,
  category, keywords, icon, screenshots, support URL, and release notes for every
  locale and form factor being submitted. The support and privacy destinations
  must be active and owner-approved; keep submission blocked instead of shipping
  placeholder or unreachable URLs.
- [ ] **[OWNER: Product/Legal]** Complete content/age ratings, export-compliance
  answers, regional availability, terms, and support commitments.
- [ ] **[OWNER: Product/Legal]** Convert the
  [technical privacy draft](privacy.md) into approved public disclosures and
  store data-safety/privacy answers. Resolve every owner decision in that draft.
- [ ] **[OWNER: Product/Legal/QA]** Approve and verify transfer disclosure:
  native targets use the OS share surface; Web uses Web Share or file download
  without mail fallback; JSON import/export is capped at 10 MiB UTF-8 plus the
  documented semantic, nesting, and structural limits.
- [ ] **[OWNER: Accessibility/QA]** Record accessibility evidence and any known
  limitations represented in the listing or release notes. Include 3x text,
  semantic headings/routes, live loading/success/error announcements, screen-
  reader traversal, high contrast, and reduced motion.
- [ ] **[OWNER: Product/Legal/QA]** Verify More opens the bundled `/privacy`
  disclosure without an additional network request after the app has loaded and
  its copy matches the approved public privacy/data-safety answers. The bundled
  page does not replace the active public privacy and support URLs required by
  the stores.
- [ ] **[OWNER: Product/Design/QA]** Capture light/dark cold-launch evidence for
  Android before 12, Android 12+, iPhone, and iPad. Verify the Aurora native
  splash hands off without a stale template frame or flash. Web splash generation
  is intentionally disabled and must not be represented as a native launch screen.

## Notifications and platform permissions

Reminder creation/scheduling is implemented only for Android, iOS, and macOS.
Web, Windows, and Linux must ship without **Add reminder**, with an accessible
unavailable disclosure and a clear-only path for any stored reminder. Do not
claim scheduling support for those targets or submit notification capability
declarations for behavior the app does not expose.

On supported targets, optional notification initialization must not block app
startup. The next schedule/cancel operation retries one coalesced initialization
attempt, recovers on success, and otherwise returns only a sanitized unavailable
failure. Schema v7 commits a generation-tagged schedule/cancel command with each
reminder-bearing add, reminder-changing update/clear, permanent delete/cleanup,
or accepted snooze; other note mutations enqueue nothing. It serially drains
commands and selectively reconciles native pending
notifications after startup without requesting permission or globally resetting
them. Reminder delivery remains blocked from release until every applicable
gate below has fresh evidence for the signed candidate. These are required
outcomes, not claims that the current branch or generated manifest already
satisfies them.

- [ ] **[OWNER: Product/QA]** Approve the support matrix and verify Web, Windows,
  and Linux expose no scheduling action, announce unavailable status accessibly,
  and can clear a stored reminder without attempting a new schedule.
- [ ] **[OWNER: Android Engineering]** Attach the release merged-manifest excerpt
  proving it contains `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`,
  `ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver`, and
  `com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver`.
- [ ] **[OWNER: Android Engineering/Product]** Request notification permission
  contextually from the reminder flow, not at unrelated app startup. On a fresh
  install, verify denial leaves note saving usable and a later reminder attempt
  can grant permission and schedule successfully.
- [ ] **[OWNER: Android Engineering]** Use `inexactAllowWhileIdle` for reminders.
  Prove the source and merged release manifest contain neither
  `SCHEDULE_EXACT_ALARM` nor `USE_EXACT_ALARM`, and confirm no exact-alarm store
  policy declaration is submitted.
- [ ] **[OWNER: Android Engineering/QA]** Configure Android snooze actions with
  `showsUserInterface: true` and verify open plus 5/15/30/60-minute snooze on a
  physical device. This setting routes Snooze through the app UI and main-isolate
  notification callback, so no background callback is required. The
  `ActionBroadcastReceiver` remains mandatory and must satisfy the merged-manifest
  gate above.
- [ ] **[OWNER: Android Engineering/QA]** On a signed physical-device build,
  schedule after fresh-install denial/grant, terminate the process, reboot the
  device, and capture delivery plus open/snooze evidence. Record timing variance
  expected from inexact scheduling and verify denied/revoked states fail safely.
- [ ] **[OWNER: Apple Engineering/QA]** Verify notification authorization is
  requested contextually from the reminder flow and never by unrelated startup.
  Verify denied/revoked states, scheduling, tap/open, cold launch, and App Store
  capability/privacy declarations on physical devices.
  Apple verification covers tap/open only unless Darwin notification categories
  are added in a future release; Android snooze expectations do not apply.
- [ ] **[OWNER: Product/Legal]** Approve the generic lock-screen reminder copy,
  private-visibility behavior, actions, and platform override disclosure.
- [ ] **[OWNER: Engineering/QA]** Prove the schema-v7 durable outbox, exact-
  generation acknowledgement, cancel-before-schedule, selective startup audit,
  and process-kill recovery cases in
  [QA](qa.md#durable-reminder-recovery-gate). The implementation blocker is
  closed in source; signed physical-device/plugin/OS evidence remains a release
  gate and must not be replaced by unit tests.
- [ ] **[OWNER: Release/Engineering]** Confirm whether any beta, sideload, or
  public build ever scheduled reminders. For a true first release, clear old
  internal QA installs. Otherwise, prove upgrade behavior with pending reminders
  on signed devices. Open routes legacy/v1/v2 payloads by note ID. Startup
  conservatively preserves a legacy/v1 pending notification only while its SQLite
  note is still generation 0 with a non-null reminder—even if expired. It cancels
  missing-note or cleared-reminder entries and reconciles an advanced note from
  its current SQLite generation/reminder state. Verify this behavior against every
  distributed baseline.

## Android backup and native compatibility

- [ ] **[OWNER: Android Engineering/QA]** Inspect the signed candidate's merged
  manifest and packaged data-extraction rules. `allowBackup` and legacy full
  backup must be disabled; both cloud-backup and device-transfer sections must
  exclude every supported storage domain with no includes.
- [ ] **[OWNER: Android QA]** On API 30 or lower and API 31+, prove clearing or
  uninstalling does not restore private notes through managed cloud backup, then
  recover synthetic notes through the public JSON export/import flow.
- [ ] **[OWNER: Android QA]** Test an Android 12+ physical OEM
  device-to-device transfer source/destination pair. Explicit exclusions mitigate
  the platform/OEM caveat but do not replace physical evidence.
- [ ] **[OWNER: Product/Support]** Approve clear user guidance: Android managed
  backup is disabled, manual JSON is the app-supported recovery path, and clearing
  storage, uninstalling, or losing the device can lose notes without a retained
  export.
- [ ] **[OWNER: Android Engineering/QA]** Run the current official 16 KB page-size
  compatibility check over every native library in the exact signed artifact.
  Prove ELF and ZIP alignment and exercise the candidate on a 16 KB page-size
  device or official equivalent environment; record tools, versions, logs, and
  artifact hash.

## Dependencies, SBOM, and lockfile

- [ ] **[OWNER: Engineering/Release]** Keep `pubspec.lock` tracked, prove
  `flutter pub get --enforce-lockfile` leaves the candidate clean, record its
  SHA-256, and review every intentional dependency-resolution diff.
- [ ] **[OWNER: Security]** Generate an SBOM from the exact resolved dependency
  graph and native artifacts in an approved format; a `flutter pub deps --json`
  inventory alone is not a formal SBOM.
- [ ] **[OWNER: Security/Engineering]** Review direct and transitive licenses,
  advisories, end-of-life dependencies, and platform plugin permissions. Record
  accepted risks with expiry and owner.
- [ ] **[OWNER: Engineering]** Confirm the removed EOL
  `sqlite3_flutter_libs` shim remains absent from the lockfile and packaged
  artifacts. Verify SQLite FFI on each shipping desktop target through
  `sqflite_common_ffi` and its current native asset path.

### Time-bounded Kotlin risk acceptance

| Field | Recorded disposition |
| --- | --- |
| Advisory | [GHSA-r937-wjx7-w2jp / CVE-2026-53914](https://github.com/advisories/GHSA-r937-wjx7-w2jp) reports Kotlin before `2.4.20` affected by unsafe deserialization in build-cache metadata. This project pins Kotlin Gradle Plugin `2.2.20`, so the version remains affected and is **not patched**. |
| Reviewed reachability | The [upstream fix](https://github.com/JetBrains/kotlin/commit/bf51df665b458fda7c3eaf436c4d88dc119d7ec6) targets KAPT incremental-cache deserialization. This project applies no KAPT plugin or annotation processors and sets `kotlin.incremental=false`, so the reviewed KAPT path is not exercised by the checked-in build. Gradle build caching remains enabled; this record does not claim otherwise. |
| Disposition | Temporarily accepted for the current engineering candidate, subject to the owner and expiry below. This is reachability-based risk acceptance, not a claim that the dependency is fixed. |
| Owner | Engineering / Release |
| Expiry | `2026-09-30` |
| Required exit | Before expiry, upgrade to a Flutter/AGP-compatible stable Kotlin `2.4.20` or later and rerun locked resolution, Android builds, the complete signing verifier, full automated tests, SBOM/advisory scans, and exact-candidate review. If that cannot be completed, renew or reject the risk explicitly; silence or an expired record blocks release. |

## Rollback and recovery

- [ ] **[OWNER: Release]** Preserve the last approved signed artifact, symbols,
  store metadata, source SHA, dependency resolution, and signing access.
- [ ] **[OWNER: Data/Engineering]** Prove database upgrades from schema versions
  1 through 6 to current version 7, including the deterministic `json:` tag
  rewrite, JSON-looking legacy literals, generation-0 initialization, empty v6-to-
  v7 outbox, and no-op preservation of a pending v7 command. There is no
  documented downgrade migration; treat rollback from v7 to a binary expecting
  an older schema as unsafe until tested.
- [ ] **[OWNER: Product/Support]** Document user backup guidance, known import
  limitations, Android's manual-JSON recovery model, incident communication,
  support intake, and recovery steps.
- [ ] **[OWNER: Release]** Define stop-rollout criteria and store-console actions:
  pause staged rollout, halt submission, or submit a fixed higher build. The app
  has no documented remote kill switch or server-side rollback path.

Release approval is complete only when all applicable boxes are checked, every
non-applicable item has an owner-approved rationale, blockers are closed, and the
release record identifies the exact signed artifact submitted to each store.
