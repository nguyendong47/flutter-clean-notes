# Release Readiness

This is the tracked release checklist. Check an item only when its evidence is
attached to the release record for the exact commit and version being shipped.
Current identifiers and versions are observations from the checked-in files,
not approved production values.

## Current identity snapshot

| Setting | Checked-in value | Source | Status |
| --- | --- | --- | --- |
| App version | `1.0.0+1` | `pubspec.yaml` | Placeholder until release owner approves a monotonically increasing version/build. |
| Android application ID | `com.example.flutter_clean_notes` | `android/app/build.gradle.kts` | Template identifier; replace before store submission. |
| Apple bundle ID | `com.example.flutterCleanNotes` | `ios/Runner.xcodeproj/project.pbxproj` | Template identifier; replace before signing/store submission. |
| macOS bundle ID | `com.example.flutterCleanNotes` | `macos/Runner/Configs/AppInfo.xcconfig` | Template identifier; replace or record macOS as non-shipping. |
| Windows identity | Binary `flutter_clean_notes`; company `com.example` | `windows/CMakeLists.txt`, `windows/runner/Runner.rc` | Template metadata; replace or record Windows as non-shipping. |
| Linux application ID | `com.example.flutter_clean_notes` | `linux/CMakeLists.txt` | Template identifier; replace or record Linux as non-shipping. |
| Android release signing | Debug signing configuration | `android/app/build.gradle.kts` | Blocking for distribution. |
| Apple signing team | No development team recorded | Xcode project settings | Blocking for device/archive distribution. |
| Dependency lock | Tracked application resolution | `pubspec.lock` | Keep pinned; review and commit every intentional resolution change. |

## Local release gates

Run from the repository root in PowerShell on the exact release commit:

```powershell
flutter --version
flutter doctor -v
flutter pub get --enforce-lockfile
dart run build_runner build
dart format --output=none --set-exit-if-changed lib test integration_test
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

Build only the platforms approved for the release. Typical artifact commands are
`flutter build appbundle --release`, `flutter build ipa --release` (macOS/Xcode
required), `flutter build windows --release`, `flutter build macos --release`,
and `flutter build linux --release`. Archive the exact commands and hashes of
submitted artifacts.

## Identity, signing, and versioning

- [ ] **[OWNER: Product/Release]** Approve the app/store name and unique Android
  and Apple identifiers; update associated services, tests, and store records.
- [ ] **[OWNER: Release]** Set the marketing version and monotonically increasing
  build number in `pubspec.yaml`; confirm generated Android/iOS metadata matches.
- [ ] **[OWNER: Release/Security]** Configure an Android upload/release key outside
  the repository, document secure custody and rotation, and prove the release
  artifact is not debug-signed.
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

## Store listing and policy

- [ ] **[OWNER: Product/Marketing]** Approve name, short/long descriptions,
  category, keywords, icon, screenshots, support URL, and release notes for every
  locale and form factor being submitted.
- [ ] **[OWNER: Product/Legal]** Complete content/age ratings, export-compliance
  answers, regional availability, terms, and support commitments.
- [ ] **[OWNER: Product/Legal]** Convert the
  [technical privacy draft](privacy.md) into approved public disclosures and
  store data-safety/privacy answers. Resolve every owner decision in that draft.
- [ ] **[OWNER: Accessibility/QA]** Record accessibility evidence and any known
  limitations represented in the listing or release notes.

## Notifications and platform permissions

Reminder delivery is blocked from release until every applicable gate below has
fresh evidence for the signed candidate. These are required outcomes, not claims
that the current branch or generated manifest already satisfies them.

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

## Rollback and recovery

- [ ] **[OWNER: Release]** Preserve the last approved signed artifact, symbols,
  store metadata, source SHA, dependency resolution, and signing access.
- [ ] **[OWNER: Data/Engineering]** Prove database upgrades from schema versions
  1, 2, 3, and 4 to current version 5. There is no documented downgrade migration;
  treat rollback to a binary expecting an older schema as unsafe until tested.
- [ ] **[OWNER: Product/Support]** Document user backup guidance, known import
  limitations, incident communication, support intake, and recovery steps.
- [ ] **[OWNER: Release]** Define stop-rollout criteria and store-console actions:
  pause staged rollout, halt submission, or submit a fixed higher build. The app
  has no documented remote kill switch or server-side rollback path.

Release approval is complete only when all applicable boxes are checked, every
non-applicable item has an owner-approved rationale, blockers are closed, and the
release record identifies the exact signed artifact submitted to each store.
