# Flutter Clean Notes — Home Screen Widgets Implementation Plan

| Metadata | Value |
| --- | --- |
| Date | 2026-09-11 |
| Status | Proposed implementation plan |
| Spec | [`docs/superpowers/specs/2026-09-11-home-screen-widgets-design.md`](../specs/2026-09-11-home-screen-widgets-design.md) |
| Goal | Implement Android AppWidget and iOS WidgetKit for Clean Notes |

---

## 1. Architecture Guardrails & Boundaries

- **Local-First Boundary**: Widgets only display data synchronized from the local SQLite database. No external network requests.
- **Clean Architecture Layers**:
  - `domain`: `WidgetSyncPayload`, `WidgetSyncGateway` interface.
  - `data`: `LocalWidgetSyncGateway` implementing communication with `home_widget`.
  - `presentation`: Deep-link routing hooks in `main.dart` / GoRouter, provider wiring in `note_providers.dart`.
- **Code Generation**: Run `dart run build_runner build` after any `@riverpod` edits and verify zero drift.
- **GitNexus Impact Analysis**: Run `impact` before editing code symbols, and `detect_changes` before committing each task.

---

## 2. Ordered Implementation Tasks

### Task 1: Dependency & Project Configuration
- **Files**: `pubspec.yaml`
- **Action**: Add `home_widget` dependency. Run `flutter pub get` and commit lockfile diff.
- **Gate**: `flutter pub get --enforce-lockfile` passes; `flutter analyze` clean.

### Task 2: Deep Link Routing & Scheme Handler
- **Files**: `lib/main.dart`, `lib/app/router/app_router.dart` (or routes configuration), `test/app/widget_deep_link_test.dart`
- **Action**:
  - Register `clean-notes://` URI handler.
  - Parse deep links (`clean-notes://new`, `clean-notes://search`, `clean-notes://note?id={id}`).
  - Handle initial app launch from widget via `HomeWidget.initiallyLaunchedFromHomeWidget()`.
- **Gate**: Run focused deep link tests; verify routes resolve accurately.

### Task 3: Domain & Data Sync Engine (`WidgetSyncService`)
- **Files**:
  - `lib/features/notes/domain/entities/widget_sync_payload.dart`
  - `lib/features/notes/domain/services/widget_sync_service.dart`
  - `lib/features/notes/data/services/home_widget_sync_gateway.dart`
  - `test/features/notes/domain/services/widget_sync_service_test.dart`
- **Action**:
  - Model `WidgetSyncPayload` containing pinned note title, text preview, checklist items, color, and note ID.
  - Parse checklist markdown (`- [ ]` / `- [x]`) into structured items.
  - Implement serialization to key-value pairs for `home_widget`.
- **Gate**: `flutter test test/features/notes/domain/services/widget_sync_service_test.dart` passes.

### Task 4: Provider Wiring & Note Mutation Integration
- **Files**:
  - `lib/features/notes/presentation/providers/note_providers.dart`
  - `test/features/notes/presentation/providers/widget_sync_integration_test.dart`
- **Action**:
  - Listen to `notesProvider` changes; on any commit (add, update, delete, pin), asynchronously sync the latest pinned note payload to `home_widget`.
- **Gate**: `dart run build_runner build`; serial tests pass with 0 warnings.

### Task 5: Android Platform Implementation (AppWidgets)
- **Files**:
  - `android/app/src/main/AndroidManifest.xml`
  - `android/app/src/main/res/xml/quick_actions_widget_info.xml`
  - `android/app/src/main/res/xml/pinned_note_widget_info.xml`
  - `android/app/src/main/res/layout/widget_quick_actions.xml`
  - `android/app/src/main/res/layout/widget_pinned_note.xml`
  - `android/app/src/main/kotlin/.../QuickActionsWidget.kt`
  - `android/app/src/main/kotlin/.../PinnedNoteWidget.kt`
- **Action**:
  - Create AppWidget providers for Android.
  - Implement Aurora-styled layouts for Quick Actions (4x1) and Pinned Note (4x2 / 4x4).
  - Configure PendingIntents mapping to `clean-notes://` deep links.
- **Gate**: `flutter build apk --debug` builds successfully; widget shows in Android widget picker.

### Task 6: iOS Platform Implementation (WidgetKit)
- **Files**:
  - `ios/Runner/Info.plist`
  - `ios/CleanNotesWidget/...` (SwiftUI Widget bundle)
- **Action**:
  - Configure App Groups and URL Scheme in iOS project.
  - Implement SwiftUI views for Quick Actions and Pinned Note widgets.
- **Gate**: Code compiles without error on iOS toolchain.

### Task 7: Physical Device Visual QA & Verification
- **Action**:
  - Launch app on connected real Android device (`192.168.1.7:44317`).
  - Add Quick Capture and Pinned Note widgets to Home Screen.
  - Test tapping: New note, Search, Note link.
  - Capture screenshot evidence via ADB screencap and save to `docs/screenshots/widget_home_screen.png`.
- **Gate**: Visual inspection confirms padding, theming, and responsiveness meet Aurora design standards.

### Task 8: Full-Suite Gate & Merge Readiness
- **Action**:
  - Run `dart format --output=none --set-exit-if-changed lib test`.
  - Run `flutter analyze --fatal-infos --fatal-warnings`.
  - Run `flutter test --concurrency=1`.
  - Run GitNexus `detect_changes`.
- **Gate**: All checks 100% green; working tree clean.
