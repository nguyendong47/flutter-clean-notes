# Session handoff — Android build fix, iOS interactive checklist, App Group QA gotcha, 2026-09-26

Continuation of `docs/agents/session-handoff-2026-09-24.md` (same machine migration). Read that one first if starting cold — this one assumes it.

## What's done this session (commits, newest first)

1. `1e54d5d` docs(qa): add iOS Home Screen Widget visual QA screenshots (light + dark, real synced data)
2. `c441919` docs: roadmap — iOS checklist interactivity gap closed
3. `fa094f0` feat(widgets): interactive checklist toggling on the iOS widget (AppIntents, iOS 17+)
4. `d413e31` chore(android): removed dead `PIN_QUICK_ACTIONS`/`PIN_PINNED_NOTE` code; fixed Android builds on this machine (Gradle/JDK mismatch)

Also this session: installed `engrim` (cross-session memory tool) globally, wired into both Claude Code and Antigravity (`engrim setup --claude` + `engrim setup --agy`) — was mentioned in CLAUDE.md as already set up but wasn't on this Mac. `engrim doctor` shows Claude Code hooks valid; Antigravity has some secondary items still unresolved (Codex CLI hooks, OpenCode) — not blocking, those aren't used on this project.

Created GitHub issue #1 tracking the still-open "test on a real iOS device" item (only simulator-verified so far).

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
