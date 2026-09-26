# Session handoff — Android build fix, iOS interactive checklist, App Group QA gotcha, 2026-09-26

Continuation of `docs/agents/session-handoff-2026-09-24.md` (same machine migration). Read that one first if starting cold — this one assumes it.

## What's done this session (commits, newest first)

1. `17bfa5f` test(ios): cross-process App Group sharing verification tooling (entitlements checker + integration test + shell script)
2. `9bef626` fix(test): update 2 iOS contract tests that had been silently broken since the widget extension was added
3. `1e54d5d` docs(qa): add iOS Home Screen Widget visual QA screenshots (light + dark, real synced data)
4. `c441919` docs: roadmap — iOS checklist interactivity gap closed
5. `fa094f0` feat(widgets): interactive checklist toggling on the iOS widget (AppIntents, iOS 17+)
6. `d413e31` chore(android): removed dead `PIN_QUICK_ACTIONS`/`PIN_PINNED_NOTE` code; fixed Android builds on this machine (Gradle/JDK mismatch)

Also this session: installed `engrim` (cross-session memory tool) globally, wired into both Claude Code and Antigravity (`engrim setup --claude` + `engrim setup --agy`) — was mentioned in CLAUDE.md as already set up but wasn't on this Mac. `engrim doctor` shows Claude Code hooks valid; Antigravity has some secondary items still unresolved (Codex CLI hooks, OpenCode) — not blocking, those aren't used on this project.

Created GitHub issue #1 tracking the still-open "test on a real iOS device" item (only simulator-verified so far).

## Real bugs found in this session's second half (Telegram two-way + more test hardening)

### 8. Telegram plugin inbound messages need the CLI's `--channels` flag — not a bug
Spent a long time debugging why Telegram messages sent *to* the bot never
surfaced in the session (outbound replies worked fine throughout). Traced it
all the way down to the plugin's own `handleInbound()` in server.ts correctly
receiving the message, passing the allowlist gate, and firing Telegram's
"typing..." indicator (confirmed visually via a screenshot of Telegram
Desktop) — i.e. everything up to and including the plugin's own
`mcp.notification({method: 'notifications/claude/channel', ...})` call ran
correctly. The notification was being silently dropped after that. Root
cause: Claude Code's "Channels" feature (research preview) requires the
session to be launched with an explicit `--channels` flag naming the server
— being listed in `.mcp.json`/the plugin config is not enough; without the
flag inbound relay is silently a no-op while outbound tools still work fine
(matches the observed symptom exactly). Fix:
```
claude --resume <session-id> --channels plugin:telegram@claude-plugins-official
```
Neither `/reload-plugins` nor killing/respawning the MCP server subprocess
fixes this — only relaunching the CLI with the flag does. Multiple
`anthropics/claude-code` GitHub issues (#38534 and similar) report this same
"typing indicator fires, message never arrives" symptom, mostly closed as
not-a-bug for the same missing-flag reason.

### 9. `codesign -d --entitlements` is the wrong tool for iOS Simulator builds — always shows empty, even on correctly-working ones
This one cost real time and produced a false alarm: verifying the new
`tool/verify_ios_widget_entitlements.dart` (added this session,
commit `17bfa5f`) against a build already independently confirmed to have
working cross-process App Group sharing (verified functionally, real data
round-tripped through the shared container) — `codesign -d --entitlements -
--xml Runner.app` still returned an empty `<dict></dict>`. This is not
specific to `--no-codesign` builds (which genuinely lack entitlements) — a
plain `flutter build ios --simulator` or a `flutter run`-produced build
*also* shows empty via `codesign -d`, despite having correct, working
entitlements. Reason: for iOS Simulator ad-hoc/local signing, Xcode embeds
real entitlements into the Mach-O `__TEXT,__entitlements` section (what
`launchd_sim` actually reads), not into the code-signature's own entitlements
blob that `codesign -d --entitlements` inspects — that blob is reliably
empty for simulator builds regardless of correctness. **Any future
entitlements check for this project's iOS Simulator builds must read via
`otool -s __TEXT __entitlements <path/to/executable-inside-the-bundle>`**
(see `tool/verify_ios_widget_entitlements.dart`'s
`_parseOtoolEntitlementsSections` for the hex-dump parsing) — confirmed this
correctly distinguishes a `--no-codesign` build (no section at all) from a
working one (section present, decodes to the real entitlements plist XML).

### 10. Two iOS contract tests had been silently broken since the widget extension was added, unnoticed
`test/app/display_identity_contract_test.dart` and
`test/app/ios_deployment_target_contract_test.dart` both hardcoded
assumptions from before `ios/CleanNotesWidgetExtension` existed (single
bundle id project-wide; exactly 3 `IPHONEOS_DEPLOYMENT_TARGET` declarations
project-wide). Once the extension target was added (commit `81b6ff7`,
earlier this session) both assumptions became false, but nobody ran these
two specific tests in isolation afterward to notice — the full-suite runs
this session apparently didn't surface it clearly at a glance among 670+
other tests. Fixed in `9bef626` by updating both to allowlist the extension
target's legitimate additions rather than loosening the checks generally.
**Lesson: after adding a new native target to the iOS project, specifically
check `test/app/*contract_test.dart` files — they encode assumptions about
project structure that a new target can silently invalidate.**

## Real bugs found this session

### 1. Android builds were completely broken on this Mac — Gradle/JDK mismatch
`flutter build apk` / any gradlew invocation failed with a bare, unhelpful error:
```
* What went wrong:
25.0.3
BUILD FAILED
```
Root cause: this project pins Gradle 8.14, which doesn't support Java 25 — and Android Studio's bundled JBR (the JDK Flutter used by default via `flutter config --jdk-dir`, set up in the 09-21/24 session) is Java 25.0.3. **Fix**: `brew install openjdk@21`, then
`flutter config --jdk-dir="/opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk/Contents/Home"`.
This is a machine-local fix (not a repo change) — if this machine's JDK 21 install ever gets removed/upgraded, this will break again with the same cryptic error; the fix is always "point `flutter config --jdk-dir` at a Gradle-8.14-compatible JDK (21 LTS is safe), not whatever Android Studio bundles."

### 2. `xcrun simctl install` does NOT register the app's App Group with the simulator
This is the big one — spent most of this session's manual QA time chasing it. Symptom: the iOS widget (`PinnedNoteWidget`) would build, install, launch, and route deep links correctly, but **always** rendered its empty-state ("no pinned note") no matter what was pinned in the app, even after confirming via the app's own UI that a note was pinned.

Root cause, confirmed by direct inspection: the shared container the whole feature depends on
(`~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Containers/Shared/AppGroup/*/.com.apple.mobile_container_manager.metadata.plist`, matched by `MCMMetadataIdentifier == group.com.cleannotes.app`)
**did not exist at all** after installing via `flutter build ios --simulator [--no-codesign]` +
manual `xcrun simctl install <path>` + `xcrun simctl launch`. `UserDefaults(suiteName:
"group.com.cleannotes.app")` doesn't crash or return nil in that state — it silently degrades to
a non-shared, per-process suite, so the app and the widget extension each read/write their own
copy and never see each other's data. `codesign -d --entitlements - --xml Runner.app` also came
back as an **empty `<dict></dict>`** for both the main app and the widget extension in that
install path — i.e. entitlements aren't even embedded, regardless of whether `--no-codesign` was
passed.

**Fix for manual QA**: use `flutter run -d <simulator-udid>` (not a manual build+simctl-install
cycle) to actually exercise this feature. Confirmed by direct comparison — after `flutter run`,
the same App Group container path exists and is populated with real data
(`widget_has_pinned`, `widget_pinned_title`, etc. all correctly reflect what's pinned in the app).
The two widget screenshots added in `1e54d5d` were captured this way.

**Open question, not investigated further**: whether `xcodebuild test`/`xcodebuild build` (as
opposed to `flutter run`) also correctly registers the App Group, or whether the earlier XCTest in
`fa094f0` "succeeded" partly because `@testable import Runner` calls
`ToggleChecklistItemIntent.perform()` **in-process** (same test binary), which doesn't exercise
true cross-process App Group sharing the way a real widget-extension-process + host-app-process
pair does. The XCTest is real evidence the *toggle logic and SQLite persistence* work; it is
**not** independent proof that cross-process UserDefaults sharing works — that was only actually
proven by the `flutter run` + real widget-on-home-screen check done in this session, manually.
If this needs re-verifying in an automated way later, that distinction matters.

## iOS Simulator UI automation, continued (see 09-24 handoff for the basics)

- `xcrun simctl uninstall` / a fresh install from `flutter run` **wipes both the SQLite database
  and any home-screen widget placement**. Any QA pass that uninstalls/reinstalls needs to redo
  both: recreate+pin a note, and re-add both widgets to the home screen (long-press empty space →
  `+` → search "Clean Notes" → pick widget → swipe through its size variants with the pagination
  dots → "Thêm tiện ích"). There is no CLI shortcut for widget placement.
- **DeviceHub (this machine's Simulator UI replacement) repeatedly lost frontmost focus to VS
  Code during this session**, with no clear trigger identified — clicks/pastes meant for the
  simulator landed in VS Code instead at least three times. No damage occurred (VS Code's Welcome
  tab isn't editable, and nothing was ever executed in its terminal), but **always verify
  frontmost app immediately before a click that types/pastes anything**
  (`osascript -e 'tell application "System Events" to name of first process whose frontmost is
  true'` should print `DeviceHub`), not just once at the start of a sequence — this cost a lot of
  time this session from repeated silent misfires.
- Screen coordinate math: DeviceHub's window can be on either the Mac's main display (1x, image
  pixels == point coordinates 1:1) or the secondary display (2x/Retina in this setup — image
  pixels are 2x the point coordinates). Don't assume the scale factor; check the captured image's
  actual pixel dimensions against the requested `-R w,h` before computing click coordinates.
- Typing reliability: plain AppleScript `keystroke "some string"` drops characters under load,
  especially punctuation (`[`, `]`, `x` were observed dropping mid-string) — use `cliclick t:"..."`
  for typed text, or better, `pbcopy` + Cmd+V paste for anything with special characters or
  multi-line content (most reliable of the three methods tried).
- `cliclick c:x,y` (quick click) sometimes doesn't register on a SwiftUI `Button`/`Link` inside a
  widget — `cliclick dd:x,y` + a short sleep (100-300ms) + `cliclick du:x,y` (explicit press-hold-
  release) was more reliable when a plain click silently did nothing.

## Housekeeping done, don't redo

- `engrim` installed via `pipx install engrim` (not system `pip3` — that's PEP-668-blocked on this
  Mac's system Python 3.9.6) and wired for both Claude Code and Antigravity.
- `~/.claude/keybindings.json` created with `shift+enter` bound to `chat:newline` in the `Chat`
  context (user asked for this so Shift+Enter inserts a newline instead of submitting). Note this
  is a **global Claude Code preference**, not a project setting — it isn't in this repo and won't
  show up in `git status`.
- Dead code removed from `MainActivity.kt` (`PIN_QUICK_ACTIONS`/`PIN_PINNED_NOTE` intent handling)
  — confirmed via grep there was no caller anywhere (Dart or Android) before removing.

## Open questions / decisions for the user

- Same three carried over from 09-24 handoff, still open: real iOS device QA (now tracked as
  GitHub issue #1), and whether `docs/screenshots/` should also get an Android-vs-iOS *interactive
  checklist tap* screenshot (not just static display) — not captured this session either.
- New: is it worth hardening the actual `ToggleChecklistItemIntent`/App Group cross-process
  sharing with an automated test that doesn't rely on `@testable import` in-process invocation
  (see the "open question" above)? Nobody has proven this end-to-end except by hand this session.

---

## Part 2 (later same day): Realtime Dictation (Phase 2A) — full brainstorm → spec → plan →
## implementation → review → QA cycle, then pushed to origin/main

User picked up interaction via Telegram partway through Part 1 above; stayed on Telegram for all of
Part 2. Went through `superpowers:brainstorming` → `superpowers:writing-plans` →
`superpowers:executing-plans` (Native execution: Claude drives the loop in-session, dispatching each
task's actual code/test authorship to Google Antigravity via `agy-delegate`, per this project's
CLAUDE.md convention) end to end for one feature, plus a mandatory final whole-branch review and a
real device/simulator QA pass. This is the fullest exercise of that whole pipeline on this project
to date — worth reading in full if picking up related work.

### What shipped (commits, oldest first — this is the actual chronological build order)

1. `2b052dc`..`f02322b` (Part 1, already listed above)
2. `512bf41` docs(spec): design spec, `docs/superpowers/specs/2026-09-26-realtime-dictation-design.md`
3. (plan doc) `docs/superpowers/plans/2026-09-26-realtime-dictation.md` — committed as part of `512bf41`
4. `16b7588` feat(dictation): deps (`speech_to_text`, `permission_handler`) + iOS/Android permission
   declarations — done directly (not delegated), config-only
5. `9030073` fix(plan): a self-review-missed bug in the plan doc itself (see "Real bugs" below)
6. `1af379c` feat(dictation): `DictationService` core logic (delegated to Antigravity)
7. `e4295f2` feat(dictation): `dictationServiceProvider` (delegated)
8. `7455a44` feat(dictation): `DictationMicButton` widget (delegated)
9. `507f08f` feat(dictation): wired into `EditorFormattingBar`, `enabled` propagation added beyond
   the plan's literal text (delegated)
10. `e9c19f0` fix(dictation): 7 real defects found by an independent whole-branch review, all fixed
    (delegated as one comprehensive fix-pass brief)
11. `47ffc1e` docs(qa): 7 real-device/simulator screenshots (done directly, hands-on QA)

All pushed to `origin/main` (`f02322b..47ffc1e`) — this project has no feature-branch convention,
every commit above landed straight on `main`, confirmed again this session.

### Real bugs / gotchas found this half of the session

#### 11. A plan document can have its own bugs — self-review is not infallible
The written plan's Task 2 code block declared `SpeechRecognizer.initialize()` with no parameters in
one place while every other reference to it (the Interfaces bullet, the fake, the call site) already
used the `onStatus`/`onError` version — a leftover from an earlier editing pass that survived the
plan's own "self-review" step. Caught only when about to dispatch Task 2, not during writing-plans
itself. **Lesson: re-grep a plan for internal signature consistency right before dispatching each
task, not just once at the end of writing it** — a plan is a program too, and program edits drift
inconsistent the same way code does.

#### 12. `node` is not on PATH on this Mac — also affects `agy-delegate`'s `relay.mjs`, not just GitNexus
Already documented for GitNexus in CLAUDE.md/earlier handoffs; same fix applies to
`.claude/skills/agy-delegate/scripts/relay.mjs`: `node scripts/relay.mjs ...` fails with
`command not found: node` (exit 127) — use `bun scripts/relay.mjs ...` instead, same arguments. Bun
runs it fine as a drop-in. Worth checking whether `agy-delegate`'s own docs should mention this
Mac-specific fallback the way CLAUDE.md already does for GitNexus.

#### 13. GitNexus `detect-changes` reports CRITICAL/100+ affected-processes for small, correct,
#### well-tested widget-lifecycle changes once a new widget is wired into the app's real tree
First seen after wiring `DictationMicButton` into `EditorFormattingBar` (previously a self-contained,
unreferenced widget — Task 4 — showed only LOW/medium risk; the moment Task 5 wired it into
`EditorFormattingBar` → `AddEditNotePage` → the app root, EVERY subsequent change to that widget's
internals, however small, showed CRITICAL risk with 140+ "affected processes" whose actual targets
(`ScheduleReminder`, `CopyWith`, `HandleNotificationResponse`, `_isValidGeneration`...) have zero
plausible dependency on note-editor UI code. Root-caused (partially by direct `grep`, partially
confirmed independently by the whole-branch reviewer using `impact` directly) to GitNexus's dynamic-
dispatch/name-based fallback resolution folding a generically-named override (first seen:
`didUpdateWidget`, later: any changed method on a class reachable from `Main`/`BootstrapApplication`)
into the SAME graph node as other unrelated overrides/methods elsewhere in the app that happen to
share a name or sit "near" the entry point in the walk — the graph's own index log already
self-reports this class of imprecision ("candidate set exceeded the cap; no partial CALLS emitted",
"guessed/refused by language"). **Confirmed via two independent investigations (this session's own,
and a fresh reviewer's) that this is a structural over-linking artifact, not a real dependency** —
but per CLAUDE.md ("never ignore HIGH/CRITICAL... never use riskSharedAxes to waive it"), this was
never silently dismissed: investigated each time, ruling documented in the plan's ledger (now
deleted along with the rest of the workspace — see the commit messages of `507f08f` and `e9c19f0`
for the summarized version), and surfaced to the user. **Lesson for future work on any widget that's
part of the main app tree (not a leaf/orphan): expect CRITICAL/100+ from `detect-changes` on
routine internal changes once wired in; don't skip investigating it, but don't expect it to mean
what it usually means either.**

#### 14. `speech_to_text`'s real API behaves very differently from what a plan (or a naive fake)
#### assumes — an independent whole-branch review (fresh Opus subagent, verified against the actual
#### pub-cache plugin source, not just this feature's own tests) found 7 real defects that 695
#### passing tests completely missed:
- **Critical**: `speech_to_text` sends the FULL cumulative transcript on every partial result (not
  just new words) — the original implementation inserted each result as brand-new text, so real
  dictation duplicated text on every session (`"hello"` → `"hello world"` → final produced
  `"hellohello worldhello world, how are you"` in the note body). Fixed with span-tracking
  replace-in-place insertion.
- **Important**: the underlying `stt.SpeechToText` is a process-wide singleton whose real
  `initialize()` silently no-ops (doesn't rewire callbacks) on the second+ call — since
  `dictationServiceProvider` is autoDispose, every second+ note-editor session got a
  `DictationService` whose OS-status/error callbacks were dead. Fixed by directly reassigning
  `_speech.statusListener`/`_speech.errorListener` after every `initialize()` call, not just relying
  on the plugin's own (short-circuiting) logic.
- **Important x5**: no re-entrancy guard across `start()`'s awaits (rapid double-tap raced two
  sessions); `dispose()` during an in-flight `start()` didn't cancel/prevent "listening"; a denied-
  permission snackbar only fired once (repeat taps looked like silent no-ops); permanent denial
  (Settings-only fix) was indistinguishable from ordinary/retriable denial, showing the wrong "tap
  to retry" message; a missing on-device language model surfaced as a generic error instead of
  "unavailable".
- **Lesson, stated explicitly by the reviewer and worth repeating for any future plugin-wrapping
  work on this project: test fakes that are more forgiving than the real plugin hide real bugs.**
  `FakeSpeechRecognizer`'s original design (single result per call, always-fresh listener wiring,
  no re-entrancy) didn't match `speech_to_text`'s actual documented/observed behavior at all — the
  fix pass's first step was making the fakes realistic (cumulative results, singleton short-circuit
  simulation) *before* fixing anything, and only then did the real bugs reproduce as failing tests.
  **When wrapping a native plugin behind an interface for testability, verify the fake's behavior
  against the plugin's actual documented semantics, not just against what makes the interface easy
  to implement.**

#### 15. iOS Simulator's CoreAudio can genuinely deadlock/crash an app that calls
#### `AVAudioEngine`-based APIs (which `speech_to_text.listen()` does under the hood) — not a code bug
During manual QA (iPhone 17 simulator, iOS 27.0, via DeviceHub): first attempt to actually start
listening (after granting both real permission dialogs) produced this in the device log —
```
AVAudioIONodeImpl.mm:235 Engine@0x...: associating with audio session (0x0), error -10879
AudioToolboxCore: Initialize: RPC timeout. Apparently deadlocked. Aborting now.
```
— and the whole app was killed (kicked to the iOS home screen, Flutter's `flutter run` debug
connection dropped with "Lost connection to device"). This is a known category of iOS Simulator
limitation (CoreAudio/AVAudioEngine audio-session init hanging when the simulator's virtual
microphone isn't properly routed to real host audio — likely fixable via macOS System Settings →
Privacy & Security → Microphone granting access to `DeviceHub`/`Simulator`, not confirmed this
session, abandoned after one side-quest attempt at navigating System Settings ate too much time for
too little certainty of success). **On a second relaunch+retry, the identical underlying failure did
NOT crash the app the second time — it was caught cleanly by `DictationService.start()`'s
catch-all and surfaced as the correct, real, localized "Dictation stopped due to an error" snackbar,
then returned cleanly to a tappable idle mic.** This inconsistency (crash once, graceful failure the
next time, same root cause) is itself worth knowing: don't assume a single crash means the code is
broken, and don't assume a single graceful run means the simulator issue is gone — it's
intermittent. **Real, actual speech recognition (not just the permission flow and error-path UI) was
never verified this session** — this needs a real device or a properly audio-routed simulator, and
is the same class of gap as the already-open GitHub issue #1 (real iOS device QA) from the widget
feature. Consider filing a dedicated issue for "verify actual dictation transcription accuracy on a
real device" rather than folding it into #1, since the failure modes are different (permission
flow ≠ live audio transcription).

### What DID get proven for real on-device (not just by test) this session
- The real iOS microphone permission dialog renders with the exact `Info.plist`-declared copy,
  correctly Vietnamese-localized by the OS.
- The real iOS speech-recognition permission dialog (separate, second prompt) also renders
  correctly — confirms `PlatformPermissionRequester`'s two-permission iOS flow runs for real, not
  just against fakes.
- Light and dark theme both render correctly for the note editor and the mic control.
- A genuine native `listen()` failure is caught and degrades gracefully (see #15 above) — proven
  with a real failure, not `FakeSpeechRecognizer.simulateError()`.
- 7 screenshots committed: `docs/screenshots/ios_dictation_{light,dark}_{home,editor_idle}.png`,
  `ios_dictation_permission_{microphone,speech}.png`, `ios_dictation_error_state.png`.

### Housekeeping done, don't redo (Part 2)

- `docs/superpowers/plans/2026-09-26-realtime-dictation.md`'s SDD workspace
  (`.superpowers/sdd/2026-09-26-realtime-dictation/`) was deleted after the plan finished — its
  ledger (rulings, deferred minors, review verdict) is summarized into this doc and the commit
  messages of `507f08f`/`e9c19f0`/`47ffc1e`; don't expect to find it on disk anymore.
- `docs/roadmap.md`'s Phase 2 entry should probably be updated to reflect Phase 2A (Realtime
  Dictation) shipped — not done this session, flagging as a small follow-up.

### Open questions / decisions for the user (Part 2)

- Real-device verification of actual dictation accuracy/behavior — genuinely unverified, see #15.
- Whether to pursue Phase 2B (Audio Memo: recording, Whisper, AI summary) — the user has previously
  and explicitly deferred this pending an available AI/LLM API for this project; unchanged this
  session.
- Deferred minors from the whole-branch review, not fixed (low-risk, reported to user, see
  `e9c19f0`'s commit message and the (now-deleted) ledger for the full list): default `ListenMode`
  vs `ListenMode.dictation`; silence surfaces as a user-facing error instead of quietly returning to
  idle; the mic control doesn't visually match the formatting bar's other controls (48dp sizing,
  accent color while listening, toggled semantics for screen readers); no space inserted between
  separate dictation utterances; one narrow race (`enabled` flipping false while `start()` is still
  in its permission/init phase, not yet `listening`) not covered by the general dispose-safety fix.
