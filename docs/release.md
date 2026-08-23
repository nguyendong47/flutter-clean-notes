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
| Android release signing | Debug signing configuration | `android/app/build.gradle.kts` | Blocking for distribution. |
| Apple signing team | No development team recorded | Xcode project settings | Blocking for device/archive distribution. |
| Dependency lock | `pubspec.lock` is ignored and untracked | `.gitignore` | Owner decision required before a reproducible release. |

## Local release gates

Run from the repository root in PowerShell on the exact release commit:

```powershell
flutter --version
flutter doctor -v
flutter pub get
dart run build_runner build --delete-conflicting-outputs
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --concurrency=1
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

The app schedules reminder notifications with `exactAllowWhileIdle`. The Android
plugin contributes `POST_NOTIFICATIONS` to the merged manifest, but app code has
no explicit Android runtime-permission request and no exact-alarm permission is
declared. Apple initialization uses the plugin's default alert, sound, and badge
permission requests during app startup. Treat the timing and UX of these prompts,
and reminder delivery itself, as unapproved until the following gates pass:

- [ ] **[OWNER: Android Engineering/Product]** Decide whether exact timing is a
  core feature and whether `SCHEDULE_EXACT_ALARM` or `USE_EXACT_ALARM` is eligible
  under the target Android version and current store policy. Implement the chosen
  fallback for denied/unavailable exact scheduling and inspect the merged release
  manifest rather than only the source manifest.
- [ ] **[OWNER: Android Engineering/QA]** Implement and verify Android 13+
  notification permission UX plus allowed, denied, revoked, reboot, battery, and
  exact-alarm states on physical devices.
- [ ] **[OWNER: Apple Engineering/QA]** Decide whether the current startup-time
  authorization request is acceptable; implement the approved iOS notification
  permission UX and verify denied/revoked states, scheduling, tap/open, cold
  launch, and App Store capability/privacy declarations on physical devices.
- [ ] **[OWNER: Product/Legal]** Approve lock-screen title/content behavior or
  require redaction/settings before release.

## Dependencies, SBOM, and lockfile

- [ ] **[OWNER: Engineering/Release]** Decide and document the lockfile policy.
  For an application release, prefer tracking `pubspec.lock`; if it remains
  untracked, record the resolved file and artifact hash in the release evidence.
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
