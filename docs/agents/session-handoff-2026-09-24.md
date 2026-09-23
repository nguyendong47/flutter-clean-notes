# Session handoff — macOS machine migration + Phase 1 widget completion, 2026-09-21 → 2026-09-24

## Where things are

- **Branch/worktree**: `main`, at `/Volumes/AI_Models/source/flutter-clean-notes` on this Mac (no worktrees active — the stale `worktree-vietnamese-localization` worktree from the old Windows machine was pruned and its already-merged branch deleted this session).
- **Remote**: `origin` = `https://github.com/nguyendong47/flutter-clean-notes.git`. Local is pushed and in sync with `origin/main` as of commit `1c8cbad`.
- This was the **first session on this Mac** — the project was copied from a Windows machine by dragging the folder (not `git clone`), which caused most of this session's early work (see "Housekeeping" below).

## What's done this session (commits, newest first)

1. `1c8cbad` fix(widgets): append `homeWidget=true` query marker to iOS widget deep links
2. `0403ba1` fix(widgets): resolve FLUTTER_BUILD_NAME/NUMBER for the iOS widget extension (install-time bug)
3. `81b6ff7` feat(widgets): implement iOS WidgetKit extension (Task 6 of the widget plan)
4. `6378021` chore(ios,macos): commit CocoaPods scaffolding (first-time Podfile/xcconfig on this repo) + `.claude/settings.json`
5. `bc184b0` fix(test): resolve macOS `/var` symlink before creating launcher-shim test fixtures
6. `9a9d510` fix(widgets): route widget search deep-link through the shell branch correctly (finished pre-existing WIP found uncommitted on the copied working tree)
7. `7c24e44` chore(env): normalize line endings (CRLF→LF) + refresh macOS-local toolchain state

**Plan status** (`docs/superpowers/plans/2026-09-11-home-screen-widgets.md`): Tasks 1–6 now all done (Android was already done pre-session; iOS WidgetKit — Task 6 — finished this session). Task 7 (physical device visual QA) is done for Android (screenshots already in `docs/screenshots/`) but only *simulator*-verified for iOS — **no real iPhone has run this yet**, and no iOS screenshots were saved into the repo (see "Open questions" below). Task 8 (full-suite gate) is green: `flutter analyze --fatal-infos --fatal-warnings` clean, `flutter test --concurrency=1` 673/673 pass, GitNexus `detect-changes` risk `low`.

`docs/roadmap.md` and this doc are the only uncommitted change as of writing this — commit them together with this handoff.

## Real bugs found this session — read before touching iOS widget code again

### 1. GitNexus index was stale/broken after the machine copy
`.gitnexus/gitnexus.json` had `repoPath: "H:\\source\\flutter-clean-notes"` (the old Windows path) baked in. Any `analyze --index-only` failed with `Storage path is in state "invalid_storage"`. **Fix**: delete `.gitnexus/` entirely and run `bunx gitnexus@latest analyze` fresh (not `--index-only` — the runner script itself doesn't exist until a full analyze regenerates it). **This machine has no `node`/`npm`/`npx`, only `bun`** — always invoke the runner as `bun .gitnexus/run.cjs ...`, never `node .gitnexus/run.cjs ...` (that will fail with "command not found").

### 2. `git commit --amend --no-edit` grabs the *entire current index*, not just the author
Fixing the git author identity (`git config --global user.name/user.email` then `git commit --amend --reset-author --no-edit`) accidentally swept up unrelated files that were *also* staged at the time (the widget fix commit's files got merged into the housekeeping commit). **Lesson**: never `--amend` when anything else might be staged; if you must, `git reset --soft HEAD^` and re-commit each logical group with an explicit pathspec (`git commit -m "..." -- path1 path2`) rather than trusting a bare `git commit`/`--amend` to scope itself.

### 3. macOS `/var` → `/private/var` symlink breaks a security check in test fixtures only
`tool/src/android_release_signing_support.dart`'s `_stableLauncherParent()` intentionally rejects any launcher parent directory reached through a symlink (anti-tampering). Two tests in `test/app/android_release_signing_support_test.dart` built their fixture via raw `Directory.systemTemp.createTemp(...)`, whose path traverses the `/var`→`/private/var` symlink that exists on every stock macOS install — tripping the same rejection the check is *supposed* to trigger for real tampering. Production code (`resolveSystemTemporaryDirectory()`) already resolves symlinks first and was never affected. **Never weaken `_stableLauncherParent`** — fix call sites to resolve `Directory.systemTemp.resolveSymbolicLinksSync()` before creating fixtures under it, same as production does.

### 4. New Xcode target created via the `xcodeproj` gem needs its own xcconfig wiring, or Info.plist substitutions silently vanish
`ios/CleanNotesWidgetExtension`'s target was created programmatically (`ios/configure_widget_extension.rb`, using the `xcodeproj` Ruby gem — **installed globally via `gem install xcodeproj` using Homebrew's Ruby (`/opt/homebrew/bin/ruby`/`/opt/homebrew/bin/gem`)**, not the system Ruby, specifically so Xcode project mutations don't require hand-editing `project.pbxproj` as text). It compiled and even `flutter build ios --simulator --no-codesign` succeeded — but installing the built app failed with `Invalid placeholder attributes` / `Failed to create app extension placeholder`. Root cause: the new target had no `baseConfigurationReference` to any `.xcconfig`, so `$(FLUTTER_BUILD_NAME)`/`$(FLUTTER_BUILD_NUMBER)` (defined only in `ios/Flutter/Generated.xcconfig`) were undefined, and **Xcode silently drops an Info.plist key whose substitution variable is undefined** rather than erroring — producing a bundle with no `CFBundleShortVersionString`/`CFBundleVersion` at all, which the app-extension-placeholder validator rejects at *install* time, not build time. **`flutter build` succeeding is not sufficient evidence a new target works — always also `xcrun simctl install <device> <path/to/Runner.app>` and check its exit code.** Fixed by adding `ios/CleanNotesWidgetExtension/{Debug,Release,Profile}.xcconfig` each containing `#include "../Flutter/Generated.xcconfig"`, wired onto the target's three build configs via the same gem.

### 5. `home_widget` (iOS) silently ignores any URL without a `homeWidget` query parameter
`HomeWidgetPlugin.swift`'s `isWidgetUrl()` only forwards a URL to Dart (`WidgetLaunchCoordinator`) if it has a query item named `homeWidget`. The widget's SwiftUI `Link`/`.widgetURL()` calls used plain `clean-notes://search` etc. — syntactically valid, opens the app (the `clean-notes://` scheme itself is registered fine in `Info.plist`), but the plugin drops it on the floor before Dart ever sees it, so nothing navigates. This is **the package's documented convention, not a bug in it** — every widget-originated URL must carry `?homeWidget=true` (or `&homeWidget=true` if other query params already exist). Verified fixed by actually tapping the on-screen widget via simulator UI automation (see below), not just re-reading the code.

### 6. Antigravity's own "done" report is not evidence — literally, this session
One delegation run (initial iOS WidgetKit build) returned `status: completed, exitCode: 0` but its `finalMessage` was just "I have started `flutter build ios`... I will wait for it to complete" repeated seven times with no actual confirmation either way. The build in question had in fact already produced working files on disk (verified independently), but **the report itself was useless** — this is exactly why the project's delegation policy says never trust the self-report; always independently re-run the verification commands yourself before believing a task is done.

### 7. iOS Simulator UI automation, if you need it again
Set up this session for visual QA (tapping the actual home-screen widget, not just code review):
- **`cliclick`** (`brew install cliclick`) — reliable simulated mouse clicks. Plain AppleScript `click at {x,y}` via System Events does **not** work reliably (fails with error -25204); use `cliclick c:x,y` for a quick tap, or `cliclick dd:x,y` + `sleep 0.15-0.3` + `cliclick du:x,y` for a press-hold-release (needed at least once — a bare `c:` tap didn't register on a widget `Link`, a held tap did).
- Requires **Accessibility** *and* **Screen Recording** permission granted to whatever terminal app runs Claude Code, via System Settings → Privacy & Security. Both had to be granted manually mid-session (no way to script granting them).
- **Xcode 27 no longer ships a standalone `Simulator.app`** — it's replaced by `DeviceHub.app`, at `/Applications/Xcode.app/Contents/Applications/DeviceHub.app`. `open -a Simulator` fails.
- To compute tap coordinates: `osascript -e 'tell application "System Events" to tell process "DeviceHub" to get {position, size} of window 1'` gives the window's origin/size in **global point coordinates spanning all displays** (not per-display). For a Retina display, `screencapture -x -R <x>,<y>,<w>,<h>` (same point coordinates) returns an image at **2x pixel resolution** — divide captured-image pixel coordinates by 2 and add the window origin to get the click target.
- **Always capture a specific window region (`-R` with freshly-queried coordinates), never a blind full-display `screencapture`.** This Mac has a second monitor that, at least once this session, was showing an unrelated remote-desktop session (a different work project entirely) instead of the expected Simulator window — a blind capture would have exposed unrelated/sensitive content. One such accidental capture happened; the file was deleted immediately without further inspection. Also: re-query the window position before each click if any time has passed — it can drift, and the display can go to a screensaver/lock overlay that a stale capture won't show you (wiggle the mouse and recapture if an image looks wrong).
- `xcrun simctl uninstall`/`install` **removes any home-screen widget placement** — after any reinstall, the widget must be manually re-added (long-press → + → search "Clean Notes") before further visual QA. No CLI shortcut exists for adding a widget to the home screen; it requires a real long-press-and-drag gesture.

## Housekeeping already done, don't redo

- **Toolchain installed on this Mac**: Flutter 3.47.5 (`brew install --cask flutter`), Android Studio + SDK (GUI setup, licenses accepted), Xcode 27.0 (`xcode-select` switched, `xcodebuild -runFirstLaunch` run), CocoaPods (`brew install cocoapods`), `gh` CLI 2.101.0 authenticated as `nguyendong47` (`gh auth login` + `gh auth setup-git` — this is what git push now uses), `bun` 1.4.2, `cliclick` 5.1, the `xcodeproj` Ruby gem (via Homebrew's Ruby, for safe Xcode project scripting).
- `flutter doctor` is fully green (Android toolchain, Xcode/CocoaPods, Chrome, macOS desktop all ✓).
- Git identity set globally: `user.name=nguyendong47`, `user.email=dongnguyenvan.it@gmail.com` — matches the project's established commit history.
- `.gitattributes` now has `* text=auto eol=lf` and `core.autocrlf` is set to `false` — a future copy from Windows shouldn't reintroduce the CRLF mess this session had to clean up (265 files were pure line-ending noise; do not assume a big diff after a machine copy means real changes — check with `git diff --ignore-cr-at-eol` or `--numstat` first before mass-reverting).
- Telegram channel is configured and working: bot token in `~/.claude/channels/telegram/.env`, `dmPolicy: allowlist`, only `senderId 6425647768` (the user) allowed. `/telegram:access`/`/telegram:configure` skills manage it. **Gotcha**: the `AskUserQuestion` tool only renders in the terminal, not Telegram — send a parallel `reply` message manually if a decision point matters on both channels.
- `.claude/settings.local.json` stays untracked (per-machine, not meant to be committed) — this is expected, not a leftover to clean up.

## Open questions / decisions for the user

1. **No physical iOS device has run this build** — only the `iPhone 17` simulator. If a real device is available, worth a real Task-7-style pass (Dynamic Island/notch layouts, real WidgetKit refresh timing, actual home-screen placement persistence).
2. **No iOS screenshots were saved into `docs/screenshots/`** — the visual QA this session used ad-hoc files in `/tmp` (cleaned up after). If the project wants iOS visual evidence archived the way Android's is (`docs/screenshots/home_screen_phase1_2.png` etc.), that capture should be redone deliberately and committed.
3. **Interactive checklist toggling is iOS-only-missing by design for v1** (Android has it via `ChecklistToggleReceiver`, iOS checklist is tap-to-open, read-only in the widget itself) — flagged in `docs/roadmap.md` now, but confirm this is an acceptable permanent scope decision vs. a follow-up task (would need iOS 17+ AppIntents work).
4. **`engrim`** is mentioned in this branch's `CLAUDE.md` as globally wired into Claude Code — it is **not** installed on this Mac (`which engrim` → not found). That CLAUDE.md line describes the old Windows machine's setup; either install `engrim` fresh here if the user wants cross-session memory back, or update the doc to stop claiming it's available.
5. `android/.../MainActivity.kt`'s new `PIN_QUICK_ACTIONS`/`PIN_PINNED_NOTE` intent handling (added in `9a9d510`, mirroring pre-existing WIP) has no Dart-side caller yet — dead code until an "Add widget" button is built, or worth removing if it's not planned.
