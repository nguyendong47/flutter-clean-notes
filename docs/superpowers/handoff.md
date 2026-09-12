# Project Sync / Handoff

| Field | Snapshot |
| --- | --- |
| Date | 2026-09-11 |
| Branch | `feat/home-screen-widgets` |
| Production-code tip before this documentation commit | `2cf686a` (`feat(widgets): enhance launch coordinator lifecycle and finalize Android AppWidget configurations`) |
| Product state | Phase 1 Home Screen Widgets (Android AppWidgets 4x1 Quick Actions & 4x2/4x4 Pinned Note/Checklist, iOS deep linking scheme, SQLite sync service, deep link routing) fully implemented and verified on physical device |
| Engineering merge readiness | **Ready**: exact-commit full gate passed (661/661 serial tests, clean analysis, zero codegen drift, physical Android device QA) |
| Store readiness | **Blocked** by external identity/signing/policy/artifact/device evidence and the macOS/Xcode/CocoaPods gate |

The SHA above is the production-code baseline immediately before the documentation
commit containing this file; it is not labeled a final candidate. This handoff is
the only tracked source for volatile branch state, checkpoint-specific evidence,
and the exact continuation path. The
[Home Screen Widgets specification](specs/2026-09-11-home-screen-widgets-design.md)
and [Aurora specification](specs/2026-08-17-notes-ui-ux-redesign-design.md) remain
the stable product/UX contracts, the
[Widgets plan](plans/2026-09-11-home-screen-widgets.md) and
[Aurora plan](plans/2026-08-17-aurora-glass-redesign.md) remain the ordered
implementation recipes, [QA](../qa.md) owns repeatable evidence procedures, and
[Release readiness](../release.md) owns store gates. Engineering integration does
not approve an unchecked store gate.

## Current implementation checkpoint

Tasks 0-9 closed at `3dfa0ee`. Use `git log 3dfa0ee..736d3a0` for authoritative
history. Major later checkpoints are:

| Commit | Result |
| --- | --- |
| `6671ffd..af921c1` | Whole-branch correctness, accessibility, data-integrity, notification, identity, backup-policy, and Android build/signing corrections. |
| `3cfcbc6` | Persistent same-origin Web SQLite using the tracked worker/WASM runtime. |
| `2fd7d1c` | Schema v6 and deterministic explicit `json:` tag migration. |
| `9285707` | Fail-closed Android signing-source isolation and artifact verification. |
| `a313112` | Bundled offline `/privacy` route and More entry. |
| `3bc2d26` | Aurora Android/iOS light/dark native splash; Web splash disabled. |
| `6ffe286` | 10 MiB export/import ceiling and semantic/depth/structural JSON bounds. |
| `3712364` | Deterministic Ubuntu/Windows quality workflow with pinned SDK checksums. |
| `51798b1` | `path_provider_foundation 2.5.1` pin for Apple native-asset/IPA mitigation. |
| `2d89d16` | Schema v7, atomic note/outbox transactions, and serialized exact-generation coordinator. |
| `1cdf3b3` | Shared provider wiring, startup selective reconciliation, v2 payload/action handling, and durable snooze. |
| `cdd3dd5` | Corrective hardening for cold-action recovery, permission policy, and stale UI reminder merges. |
| `69e3b77` | Windows CI coverage for schema-v7 datasource, migration, outbox, and process-death suites. |
| `f1f6352` | Made the Web build JavaScript-safe and canonicalized local Flutter engine resources with `--no-web-resources-cdn`. |
| `736d3a0` | Bundled Roboto and the five QA-covered Noto fallback shards, with Flutter dynamic fallback pinned to the deployment origin. |
| `bc48f19` | Added `home_widget: ^0.9.4` dependency and updated lockfile. |
| `3889f7c` | Implemented `WidgetLaunchCoordinator` and deep link routing for `clean-notes://`. |
| `e4ef5b3` | Implemented `WidgetSyncPayload`, `WidgetSyncGateway`, and `WidgetSyncService`. |
| `550b9f8` | Wired `WidgetSyncService` into `NotesNotifier` with full mutation coverage and integration test. |
| `a88dad9` | Implemented Android AppWidgets (`QuickActionsWidget`, `PinnedNoteWidget`) and iOS deep linking scheme. |
| `2cf686a` | Enhanced `WidgetLaunchCoordinator` lifecycle resume observer, 2s deduplication, and physical device verification screenshots. |
| `eb0672a` | Fixed `RemoteViews` inflation crash in `widget_pinned_note.xml` by replacing `<View>` divider with `<FrameLayout>`, verified live on Android emulator. |
| `d6393b6` | Implemented interactive checklist toggle on Android AppWidget (`ChecklistToggleReceiver` optimistic UI update in ~20ms, unawaited background registration, full visual touch verification on emulator, 671/671 tests passed). |
| `HEAD` | Completed Phase 1.2 Home Screen Widget Experience Upgrade: added quick checklist action on 4x1 QuickActionsWidget (`clean-notes://new?template=checklist` directly opening note editor with `- [ ] ` pre-populated), extended PinnedNoteWidget to 8-row checklist view, and implemented multi-widget note binding in SharedPreferences. 672/672 serial tests passed. |

## Evidence and its scope

Evidence must remain attached to the commit or component checkpoint that produced
it. Do not promote these results into an exact-final-candidate claim:

- The final outbox source checkpoint passed **604/604** serial tests, and an
  independent focused gate passed **220/220** with clean analysis and no P0-P2
  review finding. Its three commits were cherry-picked as `2d89d16`, `1cdf3b3`,
  and `cdd3dd5`.
- The Apple dependency checkpoint passed **577/577** serial tests, analysis, and
  Web/Windows/Android builds before cherry-pick as `51798b1`. It still requires
  one `flutter clean` before the next Apple archive plus macOS/Xcode/CocoaPods,
  IPA, and physical-device evidence.
- The CI checkpoint was reviewed with local workflow lint/shell checks and its
  baseline gates, but no hosted GitHub Actions run exists for this unpublished
  branch. `.github/workflows/quality.yml` must not be described as passing hosted
  CI until the exact run is attached.
- At `f1f6352`, the focused notification suite passed **71/71**, analysis and
  actionlint were clean, and the release Web build completed with local CanvasKit.
  This closes the observed JavaScript integer/compiler failure but remains a
  focused component checkpoint, not the fresh final gate.
- `736d3a0` adds executable Web asset/font contracts plus source, hash, and OFL
  provenance. A focused Chrome run at 320x740 exercised Home -> Create with
  `Hello 👨‍👩‍👧‍👦 雪界 العربية`: all five fallback shards returned 200 from the app
  origin, with no external request, console error, failed request, or horizontal
  overflow. Save/Search, Library, Dark theme, and bundled Privacy also passed
  without a new request. This checkpoint does not prove complete Unicode coverage
  or the final browser matrix.
- Earlier Web browser and Android signing/security evidence remains useful for
  those correction checkpoints only. Later reminder, CI, dependency, Web-font,
  and docs changes require fresh exact-commit reruns.
- No fresh full-suite count, complete final build matrix, final Web browser run,
  final Android smoke/signing run, final SBOM/advisory/secret scan, or final
  GitNexus comparison is recorded for the post-documentation candidate.

`pubspec.lock` is tracked application input. Final proof must use
`flutter pub get --enforce-lockfile`, run `dart run build_runner build`, and show
zero unexplained `.g.dart` drift.

## Durable behavior now implemented

- SQLite schema is v7. V6 retains deterministic `json:<JSON array>` tag storage;
  v7 adds `notes.reminderGeneration` and `reminder_outbox`. A v6 upgrade starts
  existing notes at generation 0 with an empty outbox; startup reconciliation
  selectively covers current reminders. Fresh/reopened v7 preserves pending work.
- Reminder-bearing add, reminder-changing update/clear, permanent delete/cleanup,
  and accepted snooze commit the note state and one replacement schedule/cancel
  command in the same SQLite transaction; other note mutations enqueue none. The
  coordinator serializes drain, cancels before schedule, rechecks supersession,
  and acknowledges only the exact current generation. Native failure leaves the
  command durable; expired schedules become cancellations.
- Startup compares native pending notifications with SQLite and drains with
  `existingOnly`: no permission prompt, no `cancelAll`, and no global reset.
  A legacy/v1 pending notification is preserved only while its SQLite note remains
  generation 0 with a non-null reminder, even if expired; an advanced note is
  reconciled from its current SQLite generation/reminder state. V2 generation
  guards audit/snooze; Open routes by note ID for v2/v1/legacy, and legacy snooze
  requires a generation-0 note whose reminder is still present.
- Snooze runs through the serialized NotesNotifier mutation path and refreshes
  cached notes even when native drain fails. Editor and metadata surfaces apply a
  three-way reminder merge so stale UI state cannot overwrite concurrent snooze.
- Text/Markdown exports include Active plus Archive and exclude Trash; JSON uses
  every status. Import appends Active copies with fresh IDs and cleared reminders.
  JSON import/export shares the 10 MiB UTF-8 and semantic/structure limits. Native
  targets use the OS share surface; Web uses Web Share or download with no mail
  fallback.
- Once the app is loaded, the bundled `/privacy` route needs no additional
  network request. Accessibility contracts cover
  semantic headings/routes, live status/error announcements, and 3x text. Android
  and iOS have Aurora light/dark native splash resources, including Android 12;
  Web native splash remains disabled.
- The canonical Web release command uses `--no-web-resources-cdn`; the artifact
  selects same-origin CanvasKit/engine resources, bundles official Roboto, and
  points dynamic fallback at same-origin Noto shards instead of a third-party
  font CDN. Five shards cover the editor QA sample; this is not a complete Unicode
  corpus, so another unsupported glyph may return a same-origin 404 and render as
  tofu but cannot egress. The deployment server, CSP, and same-origin database
  assets remain required, so this is not an offline first-install claim.

## Store readiness blockers

Engineering integration may complete while these remain open. No Play Store,
App Store, or desktop-store submission is approved until the exact signed artifact
closes every applicable item in [Release readiness](../release.md):

- permanent owner-approved Android application ID, Apple bundle ID/team/
  certificates/provisioning, platform identities, version/build, upload/signing
  credentials, Play App Signing/App Store Connect setup, and artifact custody;
- active public privacy and support URLs, approved Data Safety/Apple privacy
  answers, developer identity/contact, listing copy/assets, ratings, export
  compliance, regions, and support commitments;
- signed AAB and IPA/archive inspection, plus approved desktop signing/notarization
  where those targets ship;
- physical Android and Apple permission, notification, open/snooze, process-death,
  reboot, share/import, upgrade, background, cold-launch, and accessibility proof;
- Android OEM backup-exclusion transfer proof and 16 KiB page-size artifact/device
  proof; and
- macOS-hosted Apple proof. Locked resolution must keep
  `path_provider_foundation 2.5.1` and exclude `objective_c`; run one
  `flutter clean` before the next Apple archive, then validate with the approved
  Flutter/Xcode/CocoaPods toolchain and on physical devices.

Kotlin Gradle Plugin `2.2.20` remains in the affected range for
CVE-2026-53914. The reviewed KAPT incremental-cache path is not reached because
the project has no KAPT/processors and sets `kotlin.incremental=false`; this is
reachability-based acceptance, not patched status. Engineering/Release owns it,
it expires `2026-09-30`, and stable `2.4.20+` plus full revalidation is the exit.

## Suggested continuation skills

- `superpowers:verification-before-completion` for fresh exact-commit evidence;
- `superpowers:requesting-code-review` and `gitnexus-pr-review` for final review;
- `gitnexus-impact-analysis` before any corrective symbol edit and `gitnexus-cli`
  for re-index/change comparison;
- Flutter static-analysis, widget/integration-test, and responsive-layout skills
  for observed regressions; and
- browser control for final same-origin Web persistence/accessibility QA.

## Exact continuation path

1. In a new clean worktree at the documentation commit containing this handoff,
   run locked resolution,
   code generation/drift, format, fatal analysis, the serial full suite, a local-
   resource Web release, Windows release and Android builds, Android signing
   verifier, security/SBOM scans, and clean-tree checks. Record fresh output; do
   not reuse counts above.
2. Run Web same-origin persistence/accessibility/privacy/transfer QA, including
   local CanvasKit, bundled Roboto/Noto fallback, no-Google-font network evidence,
   and the documented same-origin-404/tofu boundary. Run Android smoke twice, cold-
   launch/splash, and feasible reminder scenarios. Capture console/device evidence
   and terminate the test emulator cleanly.
3. Re-index GitNexus, run `detect_changes` against `main`, resolve every unexpected
   impact through fresh impact analysis and focused RED/GREEN tests, and obtain
   independent code/specification reviews. Repeat every affected gate.
4. Fast-forward the reviewed commit to local `main` with the protected-change
   procedure, byte-verify the user's root worktree content, and run the merged
   demo. Do not push.
5. Keep store submission blocked until the owner, signing, policy, Apple, device,
   artifact, and unexpired risk-disposition gates above are attached to the exact
   signed candidate.
