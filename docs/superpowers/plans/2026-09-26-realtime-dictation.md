# Realtime Dictation (Phase 2A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user dictate note text by voice via the OS's built-in speech recognizer, inserted live into the note editor's existing text field.

**Architecture:** A new `DictationService` (plain Dart, no Flutter/Riverpod import) wraps a small `SpeechRecognizer` interface (real plugin implementation isolated behind it) and a `PermissionRequester` interface, exposing `Stream<DictationState>` and `Stream<String>` that a new `DictationMicButton` widget consumes via a Riverpod provider. No new domain entities, database tables, or repositories — this is presentation-layer only, writing into the same `TextEditingController` normal typing already uses.

**Tech Stack:** `speech_to_text` (OS speech recognition, added via `flutter pub add`), `permission_handler` (mic + speech permission requests), existing `flutter_riverpod`/`riverpod_annotation` stack.

**Spec:** [`docs/superpowers/specs/2026-09-26-realtime-dictation-design.md`](../specs/2026-09-26-realtime-dictation-design.md)

## Global Constraints

- Locale for recognition always matches the app's current UI locale (`context.locale`, from `easy_localization` — supported: `en`, `vi`). No language picker.
- No audio file is ever recorded or stored to disk — only live recognized text.
- Dictation is strictly additive: it must never block or interfere with normal keyboard typing in the same field, and any error must degrade to "mic unavailable," never to a broken editor.
- Automatic punctuation quality is whatever the OS recognizer provides — do not add custom punctuation post-processing.
- `flutter analyze --fatal-infos --fatal-warnings` and `dart format --output=none --set-exit-if-changed lib test` must stay clean after every task.
- Run `dart run build_runner build --delete-conflicting-outputs` after any `@riverpod` change and verify zero drift before each task's gate.
- GitNexus: run `impact` before editing any existing symbol (`EditorFormattingBar` in Task 5), and `detect_changes --scope all` before every commit, per this project's CLAUDE.md.

## Review Focus

- **Permission permanently denied** (user denied mic access and won't be re-prompted by the OS): mic icon must stay tappable and explain how to fix it, not silently do nothing forever. (Task 2)
- **Locale with no on-device recognizer available** (e.g. `vi` missing on some Android OEM builds): mic icon must show a disabled/unavailable state, not crash or hang on tap. (Task 2, Task 4)
- **Rapid double-tap of the mic button** (start-while-starting, stop-while-stopping): must not leave the service in an inconsistent state or throw. (Task 2)
- **Cursor moves or user types while dictation is actively inserting text**: new recognized text must insert at the *current* selection, not a stale cached position from when listening started. (Task 5)
- **Widget disposed while a listening session is active** (user backs out of the note editor mid-dictation): the service and its stream subscriptions must be torn down cleanly, no "used after dispose" errors, no orphaned platform listening session. (Task 3, Task 5)

---

## 1. Ordered Implementation Tasks

### Task 1: Dependencies & Platform Permission Declarations

**Files:**
- Modify: `pubspec.yaml`
- Modify: `ios/Runner/Info.plist`
- Modify: `android/app/src/main/AndroidManifest.xml`

**Interfaces:**
- Produces: `speech_to_text` and `permission_handler` packages available to import in later tasks.

- [ ] **Step 1:** Run `flutter pub add speech_to_text permission_handler` from the project root — this resolves and pins the correct current versions itself; do not hand-write version numbers into `pubspec.yaml`.
- [ ] **Step 2:** Run `flutter pub get` and confirm it completes without error; `pubspec.lock` diff should show exactly these two new packages (plus their transitive deps).
- [ ] **Step 3:** Add to `ios/Runner/Info.plist`, inside the existing top-level `<dict>` (follow the existing key style already in that file — see the `CFBundleURLTypes` block added in a prior widget-feature commit for formatting reference):
  ```xml
  <key>NSMicrophoneUsageDescription</key>
  <string>Clean Notes needs microphone access to let you dictate notes by voice.</string>
  <key>NSSpeechRecognitionUsageDescription</key>
  <string>Clean Notes uses on-device speech recognition to turn your voice into note text.</string>
  ```
- [ ] **Step 4:** Add to `android/app/src/main/AndroidManifest.xml`, alongside any existing `<uses-permission>` entries (add the block if none exist yet, as a sibling of the `<application>` tag, inside `<manifest>`):
  ```xml
  <uses-permission android:name="android.permission.RECORD_AUDIO" />
  ```
- [ ] **Step 5: Gate.** Run:
  ```bash
  flutter analyze --fatal-infos --fatal-warnings
  flutter test --concurrency=1
  ```
  Both must be clean/green — this task changes no Dart behavior yet, so nothing should fail.
- [ ] **Step 6:** `node .gitnexus/run.cjs detect-changes --scope all --repo .` (or `bun` if `node` is unavailable on this machine — check `CLAUDE.md` for the current fallback). Confirm risk is low/clean before committing.
- [ ] **Step 7: Commit.**
  ```bash
  git add pubspec.yaml pubspec.lock ios/Runner/Info.plist android/app/src/main/AndroidManifest.xml
  git commit -m "feat(dictation): add speech_to_text/permission_handler deps and platform permission declarations"
  ```

---

### Task 2: `DictationService` — Core Logic, Fully Testable, No Flutter Import

**Files:**
- Create: `lib/features/notes/presentation/services/dictation_service.dart`
- Create: `test/helpers/fake_speech_recognizer.dart`
- Create: `test/helpers/fake_permission_requester.dart`
- Test: `test/features/notes/presentation/services/dictation_service_test.dart`

**Interfaces:**
- Produces:
  - `enum DictationState { idle, listening, permissionDenied, unavailable, error }` — `permissionDenied` and `unavailable` are deliberately distinct: per the spec's error-handling table, a permission denial must leave the mic tappable to retry, while a genuinely unavailable recognizer (no on-device model for the locale) must disable it. Collapsing these into one state would make both cases behave like the more restrictive one.
  - `abstract interface class SpeechRecognizer { Future<bool> initialize({required void Function(String status) onStatus, required void Function(String message) onError}); Future<void> listen({required void Function(String text, bool isFinal) onResult, required String localeId}); Future<void> stop(); Future<void> cancel(); bool get isListening; }`
  - `abstract interface class PermissionRequester { Future<bool> requestMicrophoneAndSpeech(); }`
  - `class DictationService` with `Stream<DictationState> get stateStream`, `Stream<String> get recognizedTextStream`, `DictationState get currentState`, `Future<void> start({required String localeId})`, `Future<void> stop()`, `void dispose()`.
- Consumes: nothing from earlier tasks (this is the foundation).

`initialize()` takes `onStatus`/`onError` callbacks (not called at construction time, wired once up front) so `DictationService` finds out when the OS ends a listening session on its own (silence timeout, phone call interrupt, etc.) — not just when *it* calls `stop()`. This is required by this plan's Review Focus item on OS-initiated session end; without it, `DictationService`'s state would stay stuck on `listening` forever after the OS silently stopped listening underneath it.

This task's production implementations of `SpeechRecognizer`/`PermissionRequester` (wrapping the real `speech_to_text` and `permission_handler` packages) are written here as real code, based on those packages' well-established, long-stable API shape (`SpeechToText().initialize(onStatus:, onError:)`, `.listen(onResult:, localeId:)` where the result callback receives an object with `.recognizedWords`/`.finalResult`, `.stop()`, `.cancel()`, `.isListening`; `permission_handler`'s `Permission.microphone.request()`/`Permission.speech.request()`). **Before treating Step 5 below as done, verify these method names/shapes against whatever version `flutter pub add` actually resolved** (check `.dart_tool/package_config.json` for the resolved version, then that version's package source in the pub cache) — the shape has been stable for a long time but must not be assumed blindly. Only the two `Platform*` classes below need adjusting if it has drifted; `SpeechRecognizer`/`PermissionRequester`'s own signatures (defined by this task) stay exactly as specified, since Tasks 3-5 depend on those, not on the third-party plugin's API directly. Neither this task's own tests nor Task 4/5's widget tests exercise the real plugin (only the fakes, via dependency injection) — that's inherently untestable in CI and is what Task 6's manual/visual QA is for.

- [ ] **Step 1: Write the failing tests.** Create `test/helpers/fake_speech_recognizer.dart`:
  ```dart
  import 'dart:async';

  import 'package:flutter_clean_notes/features/notes/presentation/services/dictation_service.dart';

  class FakeSpeechRecognizer implements SpeechRecognizer {
    bool initializeResult = true;
    bool _isListening = false;
    String? lastLocaleId;
    int listenCalls = 0;
    int stopCalls = 0;
    int cancelCalls = 0;
    void Function(String text, bool isFinal)? _onResult;
    void Function(String status)? _onStatus;
    void Function(String message)? _onError;

    @override
    Future<bool> initialize({
      required void Function(String status) onStatus,
      required void Function(String message) onError,
    }) async {
      _onStatus = onStatus;
      _onError = onError;
      return initializeResult;
    }

    @override
    Future<void> listen({
      required void Function(String text, bool isFinal) onResult,
      required String localeId,
    }) async {
      listenCalls += 1;
      lastLocaleId = localeId;
      _onResult = onResult;
      _isListening = true;
    }

    @override
    Future<void> stop() async {
      stopCalls += 1;
      _isListening = false;
    }

    @override
    Future<void> cancel() async {
      cancelCalls += 1;
      _isListening = false;
    }

    @override
    bool get isListening => _isListening;

    /// Test helper: simulate the recognizer emitting a result.
    void emitResult(String text, {bool isFinal = false}) {
      _onResult?.call(text, isFinal);
    }

    /// Test helper: simulate the OS ending the session on its own (silence
    /// timeout, interruption, etc.) — mirrors speech_to_text's "notListening"
    /// status callback, which fires without any explicit stop()/cancel() call.
    void simulateOsEndedSession() {
      _isListening = false;
      _onStatus?.call('notListening');
    }

    /// Test helper: simulate a recognizer error mid-session.
    void simulateError(String message) {
      _isListening = false;
      _onError?.call(message);
    }
  }
  ```
  Create `test/helpers/fake_permission_requester.dart`:
  ```dart
  import 'package:flutter_clean_notes/features/notes/presentation/services/dictation_service.dart';

  class FakePermissionRequester implements PermissionRequester {
    FakePermissionRequester({this.granted = true});

    bool granted;
    int requestCalls = 0;

    @override
    Future<bool> requestMicrophoneAndSpeech() async {
      requestCalls += 1;
      return granted;
    }
  }
  ```
  Create `test/features/notes/presentation/services/dictation_service_test.dart`:
  ```dart
  import 'package:flutter_test/flutter_test.dart';

  import 'package:flutter_clean_notes/features/notes/presentation/services/dictation_service.dart';

  import '../../../../helpers/fake_permission_requester.dart';
  import '../../../../helpers/fake_speech_recognizer.dart';

  void main() {
    late FakeSpeechRecognizer recognizer;
    late FakePermissionRequester permissions;
    late DictationService service;

    setUp(() {
      recognizer = FakeSpeechRecognizer();
      permissions = FakePermissionRequester();
      service = DictationService(
        recognizer: recognizer,
        permissions: permissions,
      );
    });

    tearDown(() => service.dispose());

    test('starts idle', () {
      expect(service.currentState, DictationState.idle);
    });

    test('start() requests permission, initializes, and begins listening', () async {
      final states = <DictationState>[];
      service.stateStream.listen(states.add);

      await service.start(localeId: 'vi_VN');

      expect(permissions.requestCalls, 1);
      expect(recognizer.listenCalls, 1);
      expect(recognizer.lastLocaleId, 'vi_VN');
      expect(service.currentState, DictationState.listening);
      expect(states, contains(DictationState.listening));
    });

    test('permission denied moves to permissionDenied without calling listen', () async {
      permissions.granted = false;

      await service.start(localeId: 'en_US');

      expect(recognizer.listenCalls, 0);
      expect(service.currentState, DictationState.permissionDenied);
    });

    test('permission denied leaves start() retriable (not stuck)', () async {
      permissions.granted = false;
      await service.start(localeId: 'en_US');
      expect(service.currentState, DictationState.permissionDenied);

      permissions.granted = true;
      await service.start(localeId: 'en_US');

      expect(recognizer.listenCalls, 1);
      expect(service.currentState, DictationState.listening);
    });

    test('recognizer.initialize() returning false moves to unavailable', () async {
      recognizer.initializeResult = false;

      await service.start(localeId: 'en_US');

      expect(recognizer.listenCalls, 0);
      expect(service.currentState, DictationState.unavailable);
    });

    test('recognized text is forwarded on the text stream', () async {
      final received = <String>[];
      service.recognizedTextStream.listen(received.add);

      await service.start(localeId: 'en_US');
      recognizer.emitResult('hello', isFinal: false);
      recognizer.emitResult('hello world', isFinal: true);
      await Future<void>.delayed(Duration.zero);

      expect(received, ['hello', 'hello world']);
    });

    test('stop() calls through to the recognizer and returns to idle', () async {
      await service.start(localeId: 'en_US');
      await service.stop();

      expect(recognizer.stopCalls, 1);
      expect(service.currentState, DictationState.idle);
    });

    test('calling start() twice while already listening is a no-op the second time', () async {
      await service.start(localeId: 'en_US');
      await service.start(localeId: 'en_US');

      expect(recognizer.listenCalls, 1, reason: 'must not start a second overlapping session');
    });

    test('calling stop() while idle is a safe no-op', () async {
      await service.stop();

      expect(recognizer.stopCalls, 0);
      expect(service.currentState, DictationState.idle);
    });

    test('dispose() cancels an in-progress session and closes streams', () async {
      await service.start(localeId: 'en_US');

      service.dispose();

      expect(recognizer.cancelCalls, 1);
      expect(
        () => service.recognizedTextStream.listen((_) {}),
        throwsStateError,
        reason: 'stream must be closed after dispose',
      );
    });

    test('OS ending the session on its own returns state to idle', () async {
      final states = <DictationState>[];
      await service.start(localeId: 'en_US');
      service.stateStream.listen(states.add);

      recognizer.simulateOsEndedSession();
      await Future<void>.delayed(Duration.zero);

      expect(service.currentState, DictationState.idle);
      expect(states, contains(DictationState.idle));
    });

    test('a mid-session recognizer error moves to error state without throwing', () async {
      await service.start(localeId: 'en_US');

      recognizer.simulateError('recognizer failed');
      await Future<void>.delayed(Duration.zero);

      expect(service.currentState, DictationState.error);
    });

    test('recognizer.listen() throwing is caught and surfaces as error, not an uncaught exception', () async {
      recognizer.initializeResult = true;
      final throwingRecognizer = _ThrowingListenRecognizer();
      final throwingService = DictationService(
        recognizer: throwingRecognizer,
        permissions: permissions,
      );
      addTearDown(throwingService.dispose);

      await throwingService.start(localeId: 'en_US');

      expect(throwingService.currentState, DictationState.error);
    });
  }

  class _ThrowingListenRecognizer implements SpeechRecognizer {
    @override
    Future<bool> initialize({
      required void Function(String status) onStatus,
      required void Function(String message) onError,
    }) async => true;

    @override
    Future<void> listen({
      required void Function(String text, bool isFinal) onResult,
      required String localeId,
    }) async {
      throw StateError('platform recognizer blew up');
    }

    @override
    Future<void> stop() async {}

    @override
    Future<void> cancel() async {}

    @override
    bool get isListening => false;
  }
  ```

- [ ] **Step 2: Run tests to verify they fail** (the service doesn't exist yet):
  ```bash
  flutter test test/features/notes/presentation/services/dictation_service_test.dart
  ```
  Expected: FAIL — `Target of URI doesn't exist: '.../dictation_service.dart'`.

- [ ] **Step 3: Write the implementation.** Create `lib/features/notes/presentation/services/dictation_service.dart`:
  ```dart
  import 'dart:async';

  /// `permissionDenied` (mic/speech permission not granted — retriable, the
  /// mic control must stay tappable) and `unavailable` (no on-device
  /// recognizer for this locale, or the plugin failed to initialize — not
  /// retriable without a locale/OS change, the mic control should disable)
  /// are deliberately separate states; see the spec's error-handling table.
  enum DictationState { idle, listening, permissionDenied, unavailable, error }

  /// Abstraction over the on-device speech recognizer (real implementation
  /// wraps the `speech_to_text` plugin). Kept minimal and owned by this file
  /// so [DictationService] and its tests never depend on the third-party
  /// package's own API surface directly.
  abstract interface class SpeechRecognizer {
    Future<bool> initialize();

    Future<void> listen({
      required void Function(String text, bool isFinal) onResult,
      required String localeId,
    });

    Future<void> stop();

    Future<void> cancel();

    bool get isListening;
  }

  /// Abstraction over requesting the OS permissions dictation needs
  /// (microphone, plus speech-recognition on iOS). Real implementation wraps
  /// `permission_handler`.
  abstract interface class PermissionRequester {
    Future<bool> requestMicrophoneAndSpeech();
  }

  class DictationService {
    DictationService({
      SpeechRecognizer? recognizer,
      PermissionRequester? permissions,
    }) : _recognizer = recognizer ?? PlatformSpeechRecognizer(),
         _permissions = permissions ?? PlatformPermissionRequester();

    final SpeechRecognizer _recognizer;
    final PermissionRequester _permissions;

    final _stateController = StreamController<DictationState>.broadcast();
    final _textController = StreamController<String>.broadcast();

    DictationState _state = DictationState.idle;
    DictationState get currentState => _state;
    bool _initialized = false;

    Stream<DictationState> get stateStream => _stateController.stream;
    Stream<String> get recognizedTextStream => _textController.stream;

    void _setState(DictationState state) {
      _state = state;
      if (!_stateController.isClosed) _stateController.add(state);
    }

    Future<void> start({required String localeId}) async {
      if (_state == DictationState.listening) return;

      try {
        final granted = await _permissions.requestMicrophoneAndSpeech();
        if (!granted) {
          // Distinct from `unavailable`: a denial is retriable (the user can
          // grant it next time, or from Settings), so the mic button must
          // stay tappable — see this file's `DictationState` doc comment.
          _setState(DictationState.permissionDenied);
          return;
        }

        if (!_initialized) {
          final ready = await _recognizer.initialize(
            onStatus: _handleStatus,
            onError: _handleError,
          );
          if (!ready) {
            _setState(DictationState.unavailable);
            return;
          }
          _initialized = true;
        }

        await _recognizer.listen(
          localeId: localeId,
          onResult: (text, isFinal) {
            if (!_textController.isClosed) _textController.add(text);
          },
        );
        _setState(DictationState.listening);
      } catch (_) {
        // The platform recognizer can throw for reasons that don't map to a
        // clean `onError` callback (e.g. a locale it doesn't support at all).
        // Never let that escape as an uncaught exception into the caller —
        // dictation is additive and must degrade to "unavailable" instead.
        _setState(DictationState.error);
      }
    }

    void _handleStatus(String status) {
      // speech_to_text reports 'notListening'/'done' when the OS ends a
      // session on its own (silence timeout, interruption) — not just when
      // *we* call stop(). Only react to it while we think we're listening,
      // so our own stop()'s explicit state transition isn't double-handled.
      if (_state == DictationState.listening &&
          (status == 'notListening' || status == 'done')) {
        _setState(DictationState.idle);
      }
    }

    void _handleError(String message) {
      _setState(DictationState.error);
    }

    Future<void> stop() async {
      if (_state != DictationState.listening) return;
      await _recognizer.stop();
      _setState(DictationState.idle);
    }

    void dispose() {
      if (_recognizer.isListening) {
        unawaited(_recognizer.cancel());
      }
      _stateController.close();
      _textController.close();
    }
  }

  class PlatformSpeechRecognizer implements SpeechRecognizer {
    final stt.SpeechToText _speech = stt.SpeechToText();

    @override
    Future<bool> initialize({
      required void Function(String status) onStatus,
      required void Function(String message) onError,
    }) {
      return _speech.initialize(
        onStatus: onStatus,
        onError: (error) => onError(error.errorMsg),
      );
    }

    @override
    Future<void> listen({
      required void Function(String text, bool isFinal) onResult,
      required String localeId,
    }) {
      return _speech.listen(
        localeId: localeId,
        onResult: (result) => onResult(result.recognizedWords, result.finalResult),
      );
    }

    @override
    Future<void> stop() => _speech.stop();

    @override
    Future<void> cancel() => _speech.cancel();

    @override
    bool get isListening => _speech.isListening;
  }

  class PlatformPermissionRequester implements PermissionRequester {
    @override
    Future<bool> requestMicrophoneAndSpeech() async {
      final micStatus = await Permission.microphone.request();
      if (!micStatus.isGranted) return false;
      if (!Platform.isIOS) return true;
      final speechStatus = await Permission.speech.request();
      return speechStatus.isGranted;
    }
  }
  ```
  Required imports for the two classes above (add to the top of this file):
  ```dart
  import 'dart:io' show Platform;

  import 'package:permission_handler/permission_handler.dart';
  import 'package:speech_to_text/speech_to_text.dart' as stt;
  ```
  **Verification required before treating this step as done:** `speech_to_text`'s `initialize`/`listen`/`stop`/`cancel`/`isListening` and `permission_handler`'s `Permission.microphone`/`Permission.speech` have been stable across this package's recent major versions, but confirm against whatever version `flutter pub add` actually resolved in Task 1 (check `.dart_tool/package_config.json`, then that version's source in the pub cache) before moving on — in particular confirm `SpeechRecognitionError` actually exposes `.errorMsg` and `SpeechRecognitionResult` exposes `.recognizedWords`/`.finalResult` on the resolved version. Adjust only these two classes' internals if it has drifted; every other file in this plan does not depend on this package's API shape at all.

- [ ] **Step 4: Run tests to verify the fake-backed tests pass:**
  ```bash
  flutter test test/features/notes/presentation/services/dictation_service_test.dart
  ```
  Expected: all PASS (the two `Platform*` classes are never constructed by these tests, since `DictationService` is always given fakes in `setUp`; a real device/simulator smoke check of `Platform*` themselves is not possible in this step — that's Task 6).

- [ ] **Step 5: Re-run plus analyze:**
  ```bash
  flutter analyze --fatal-infos --fatal-warnings
  dart format --output=none --set-exit-if-changed lib test
  ```
  All clean.

- [ ] **Step 6: Gate + detect-changes + commit.**
  ```bash
  node .gitnexus/run.cjs detect-changes --scope all --repo .
  git add lib/features/notes/presentation/services/dictation_service.dart \
          test/helpers/fake_speech_recognizer.dart \
          test/helpers/fake_permission_requester.dart \
          test/features/notes/presentation/services/dictation_service_test.dart
  git commit -m "feat(dictation): add DictationService with fake-testable speech recognizer/permission abstractions"
  ```

---

### Task 3: Riverpod Provider

**Files:**
- Create: `lib/features/notes/presentation/providers/dictation_service_provider.dart`
- Test: `test/features/notes/presentation/providers/dictation_service_provider_test.dart`

**Interfaces:**
- Consumes: `DictationService` from Task 2 (constructor `DictationService({SpeechRecognizer? recognizer, PermissionRequester? permissions})`, method `void dispose()`).
- Produces: `dictationServiceProvider` (an autoDispose `@riverpod` provider returning `DictationService`), importable as `import 'package:flutter_clean_notes/features/notes/presentation/providers/dictation_service_provider.dart';` giving access to `dictationServiceProvider`.

**Known gotcha to build the test around (already hit elsewhere in this codebase — see `test/features/notes/presentation/add_edit_note_page_test.dart`'s `_pumpEditor` and this project's session-handoff docs):** an autoDispose provider read via `container.read(x)` before `pumpWidget` can get disposed and silently rebuild if nothing is listening to it yet. If this provider is read that way in a test, add `container.listen(dictationServiceProvider, (_, _) {});` right after the read, before `pumpWidget`, exactly like `add_edit_note_page_test.dart` already does for its own providers.

- [ ] **Step 1: Write the failing test.** Create `test/features/notes/presentation/providers/dictation_service_provider_test.dart`:
  ```dart
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';

  import 'package:flutter_clean_notes/features/notes/presentation/providers/dictation_service_provider.dart';
  import 'package:flutter_clean_notes/features/notes/presentation/services/dictation_service.dart';

  void main() {
    test('provides a DictationService and disposes it when the container is disposed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(dictationServiceProvider);
      container.listen(dictationServiceProvider, (_, _) {});

      expect(service, isA<DictationService>());
      expect(service.currentState, DictationState.idle);

      container.dispose();

      // A disposed DictationService closes its streams; listening after
      // dispose must throw, proving dispose() actually ran via ref.onDispose.
      expect(
        () => service.recognizedTextStream.listen((_) {}),
        throwsStateError,
      );
    });
  }
  ```
- [ ] **Step 2: Run to verify it fails** (provider file doesn't exist):
  ```bash
  flutter test test/features/notes/presentation/providers/dictation_service_provider_test.dart
  ```
  Expected: FAIL — missing URI.
- [ ] **Step 3: Implement.** Create `lib/features/notes/presentation/providers/dictation_service_provider.dart`:
  ```dart
  import 'package:riverpod_annotation/riverpod_annotation.dart';

  import 'package:flutter_clean_notes/features/notes/presentation/services/dictation_service.dart';

  part 'dictation_service_provider.g.dart';

  @riverpod
  DictationService dictationService(Ref ref) {
    final service = DictationService();
    ref.onDispose(service.dispose);
    return service;
  }
  ```
- [ ] **Step 4:** Run codegen and verify no drift:
  ```bash
  dart run build_runner build --delete-conflicting-outputs
  ```
- [ ] **Step 5: Run the test to verify it passes:**
  ```bash
  flutter test test/features/notes/presentation/providers/dictation_service_provider_test.dart
  ```
- [ ] **Step 6: Gate.**
  ```bash
  flutter analyze --fatal-infos --fatal-warnings
  dart format --output=none --set-exit-if-changed lib test
  node .gitnexus/run.cjs detect-changes --scope all --repo .
  ```
- [ ] **Step 7: Commit.**
  ```bash
  git add lib/features/notes/presentation/providers/dictation_service_provider.dart \
          lib/features/notes/presentation/providers/dictation_service_provider.g.dart \
          test/features/notes/presentation/providers/dictation_service_provider_test.dart
  git commit -m "feat(dictation): add dictationServiceProvider (autoDispose)"
  ```

---

### Task 4: `DictationMicButton` Widget

**Files:**
- Create: `lib/features/notes/presentation/widgets/dictation_mic_button.dart`
- Test: `test/features/notes/presentation/widgets/dictation_mic_button_test.dart`

**Interfaces:**
- Consumes: `dictationServiceProvider` (Task 3), `DictationState`/`DictationService` (Task 2).
- Produces: `DictationMicButton` widget, constructor `DictationMicButton({required TextEditingController controller, super.key})`. Emits recognized text into `controller` at `controller.selection`'s current start offset, replacing nothing (pure insertion), and advances the selection past the inserted text so repeated partial results don't overlap-insert.

- [ ] **Step 1: Write the failing widget test.** Create `test/features/notes/presentation/widgets/dictation_mic_button_test.dart`:
  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';

  import 'package:flutter_clean_notes/features/notes/presentation/providers/dictation_service_provider.dart';
  import 'package:flutter_clean_notes/features/notes/presentation/services/dictation_service.dart';
  import 'package:flutter_clean_notes/features/notes/presentation/widgets/dictation_mic_button.dart';

  import '../../../../helpers/fake_permission_requester.dart';
  import '../../../../helpers/fake_speech_recognizer.dart';

  Future<FakeSpeechRecognizer> _pump(
    WidgetTester tester,
    TextEditingController controller,
  ) async {
    final recognizer = FakeSpeechRecognizer();
    final container = ProviderContainer(
      overrides: [
        dictationServiceProvider.overrideWith(
          (ref) => DictationService(
            recognizer: recognizer,
            permissions: FakePermissionRequester(),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(dictationServiceProvider, (_, _) {});

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(body: DictationMicButton(controller: controller)),
        ),
      ),
    );
    return recognizer;
  }

  void main() {
    testWidgets('tapping the mic icon starts listening', (tester) async {
      final controller = TextEditingController();
      final recognizer = await _pump(tester, controller);

      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pump();

      expect(recognizer.listenCalls, 1);
    });

    testWidgets('recognized text is inserted into the controller at the cursor', (tester) async {
      final controller = TextEditingController(text: 'Hello ');
      controller.selection = const TextSelection.collapsed(offset: 6);
      final recognizer = await _pump(tester, controller);

      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pump();
      recognizer.emitResult('world');
      await tester.pump();

      expect(controller.text, 'Hello world');
    });

    testWidgets('tapping again while listening stops', (tester) async {
      final controller = TextEditingController();
      final recognizer = await _pump(tester, controller);

      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();

      expect(recognizer.stopCalls, 1);
    });

    testWidgets('unavailable (no recognizer for locale) disables the button', (tester) async {
      final controller = TextEditingController();
      final recognizer = FakeSpeechRecognizer()..initializeResult = false;
      final container = ProviderContainer(
        overrides: [
          dictationServiceProvider.overrideWith(
            (ref) => DictationService(
              recognizer: recognizer,
              permissions: FakePermissionRequester(),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(dictationServiceProvider, (_, _) {});

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: DictationMicButton(controller: controller)),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pump();

      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.onPressed, isNull);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('permission denied shows a snackbar but leaves the button tappable', (tester) async {
      final controller = TextEditingController();
      final container = ProviderContainer(
        overrides: [
          dictationServiceProvider.overrideWith(
            (ref) => DictationService(
              recognizer: FakeSpeechRecognizer(),
              permissions: FakePermissionRequester(granted: false),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.listen(dictationServiceProvider, (_, _) {});

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(body: DictationMicButton(controller: controller)),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pump();

      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.onPressed, isNotNull, reason: 'permission denial must stay retriable, not permanently disabled');
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('a mid-session recognizer error shows a snackbar', (tester) async {
      final controller = TextEditingController();
      final recognizer = await _pump(tester, controller);

      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pump();
      recognizer.simulateError('boom');
      await tester.pump();

      expect(find.byType(SnackBar), findsOneWidget);
    });
  }
  ```
- [ ] **Step 2: Run to verify it fails** (widget doesn't exist):
  ```bash
  flutter test test/features/notes/presentation/widgets/dictation_mic_button_test.dart
  ```
- [ ] **Step 3: Implement.** Create `lib/features/notes/presentation/widgets/dictation_mic_button.dart`:
  ```dart
  import 'dart:async';

  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:easy_localization/easy_localization.dart';

  import 'package:flutter_clean_notes/features/notes/presentation/providers/dictation_service_provider.dart';
  import 'package:flutter_clean_notes/features/notes/presentation/services/dictation_service.dart';

  class DictationMicButton extends ConsumerStatefulWidget {
    const DictationMicButton({required this.controller, super.key});

    final TextEditingController controller;

    @override
    ConsumerState<DictationMicButton> createState() => _DictationMicButtonState();
  }

  class _DictationMicButtonState extends ConsumerState<DictationMicButton> {
    DictationState _state = DictationState.idle;
    DictationService? _service;
    StreamSubscription<DictationState>? _stateSub;
    StreamSubscription<String>? _textSub;

    @override
    Widget build(BuildContext context) {
      final service = ref.watch(dictationServiceProvider);
      _subscribeIfNeeded(service);

      return IconButton(
        tooltip: _state == DictationState.unavailable
            ? 'editor.dictationUnavailable'.tr()
            : 'editor.dictation'.tr(),
        icon: Icon(
          _state == DictationState.listening
              ? Icons.mic_rounded
              : Icons.mic_none_rounded,
        ),
        onPressed: _state == DictationState.unavailable
            ? null
            : () => _toggle(service),
      );
    }

    // Subscribing manually (instead of nesting StreamBuilders around the
    // returned widget) is deliberate: this widget's job on a text event is to
    // mutate `widget.controller` — a *side effect* — not just to re-render.
    // Doing that inside a StreamBuilder's `builder` callback runs it during
    // this widget's own build phase, which can trigger "setState()/
    // markNeedsBuild() called during build" once the sibling TextField
    // listening to the same controller reacts synchronously. Subscribing in
    // (effectively) initState and reacting via setState/side-effect callbacks
    // keeps stream reactions strictly post-build.
    void _subscribeIfNeeded(DictationService service) {
      if (identical(_service, service)) return;
      _stateSub?.cancel();
      _textSub?.cancel();
      _service = service;
      _state = service.currentState;
      _stateSub = service.stateStream.listen(_handleState);
      _textSub = service.recognizedTextStream.listen(_insertText);
    }

    void _handleState(DictationState state) {
      final previous = _state;
      if (!mounted) return;
      setState(() => _state = state);
      if (state == DictationState.error && previous != DictationState.error) {
        _showSnackBar('editor.dictationError'.tr());
      } else if (state == DictationState.unavailable &&
          previous != DictationState.unavailable) {
        _showSnackBar('editor.dictationUnavailable'.tr());
      } else if (state == DictationState.permissionDenied &&
          previous != DictationState.permissionDenied) {
        _showSnackBar('editor.dictationPermissionDenied'.tr());
      }
    }

    void _showSnackBar(String message) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }

    void _insertText(String text) {
      final controller = widget.controller;
      final selection = controller.selection;
      final offset = selection.isValid ? selection.start : controller.text.length;
      final newText = controller.text.replaceRange(offset, offset, text);
      controller.value = controller.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: offset + text.length),
      );
    }

    Future<void> _toggle(DictationService service) async {
      if (_state == DictationState.listening) {
        await service.stop();
      } else {
        await service.start(localeId: _speechLocaleId(context.locale));
      }
    }

    @override
    void dispose() {
      _stateSub?.cancel();
      _textSub?.cancel();
      super.dispose();
    }
  }

  /// Maps this app's supported UI locales (`en`, `vi` — see `main.dart`'s
  /// `supportedLocales`) to the region-qualified locale ID the OS speech
  /// recognizer actually expects (e.g. `vi_VN`, not bare `vi` —
  /// `context.locale.toString()` alone only gives the bare language code
  /// easy_localization tracks, which speech_to_text does not accept).
  /// Extend this map if `main.dart`'s supportedLocales grows.
  String _speechLocaleId(Locale locale) {
    switch (locale.languageCode) {
      case 'vi':
        return 'vi_VN';
      case 'en':
      default:
        return 'en_US';
    }
  }
  ```
- [ ] **Step 4: Run to verify pass:**
  ```bash
  flutter test test/features/notes/presentation/widgets/dictation_mic_button_test.dart
  ```
- [ ] **Step 5:** Add the four new translation keys used above (`editor.dictation`, `editor.dictationUnavailable`, `editor.dictationError`, `editor.dictationPermissionDenied`) to both `assets/translations/en.json` and `assets/translations/vi.json`, matching the existing `editor.*` key structure already in those files (see `editor.bold`, `editor.italic` for placement/style). Suggested copy: en `"dictation": "Dictate", "dictationUnavailable": "Dictation unavailable", "dictationError": "Dictation stopped due to an error", "dictationPermissionDenied": "Microphone access is needed for dictation — tap to try again"`; vi `"dictation": "Đọc chính tả", "dictationUnavailable": "Không thể đọc chính tả", "dictationError": "Đọc chính tả đã dừng do lỗi", "dictationPermissionDenied": "Cần quyền micro để đọc chính tả — nhấn để thử lại"`.
- [ ] **Step 6: Gate.**
  ```bash
  flutter analyze --fatal-infos --fatal-warnings
  dart format --output=none --set-exit-if-changed lib test
  node .gitnexus/run.cjs detect-changes --scope all --repo .
  ```
- [ ] **Step 7: Commit.**
  ```bash
  git add lib/features/notes/presentation/widgets/dictation_mic_button.dart \
          test/features/notes/presentation/widgets/dictation_mic_button_test.dart \
          assets/translations/en.json assets/translations/vi.json
  git commit -m "feat(dictation): add DictationMicButton widget"
  ```

---

### Task 5: Wire Into `EditorFormattingBar`

**Files:**
- Modify: `lib/features/notes/presentation/widgets/editor_formatting_bar.dart`
- Modify: `test/features/notes/presentation/editor_formatting_bar_test.dart`

**Interfaces:**
- Consumes: `DictationMicButton(controller: ...)` (Task 4).
- Produces: `EditorFormattingBar` now renders a mic control alongside its existing Bold/Italic/Strikethrough/Code/etc. controls, in the same list.

**Before editing:** run GitNexus impact analysis on `EditorFormattingBar` first, per this project's CLAUDE.md ("MUST run impact analysis before editing"):
```bash
node .gitnexus/run.cjs impact "EditorFormattingBar" --direction upstream --repo .
```
Confirm risk is LOW/expected (it's a small, leaf presentation widget used from the note editor) before proceeding; stop and flag it if it comes back HIGH/CRITICAL or UNKNOWN.

- [ ] **Step 1: Write the failing test.** Add a new test to `test/features/notes/presentation/editor_formatting_bar_test.dart` (append to the existing file, following its existing pump-helper conventions already in that file):
  ```dart
  testWidgets('renders a dictation mic control alongside formatting controls', (tester) async {
    final controller = TextEditingController();
    await pumpFormattingBar(tester, controller: controller); // use this file's existing pump helper

    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
  });
  ```
  (Adjust the helper call to match whatever this file's existing pump helper is actually named/shaped — read the file first; do not invent a helper that doesn't exist.)
- [ ] **Step 2: Run to verify it fails:**
  ```bash
  flutter test test/features/notes/presentation/editor_formatting_bar_test.dart
  ```
- [ ] **Step 3: Implement.** In `lib/features/notes/presentation/widgets/editor_formatting_bar.dart`, import `dictation_mic_button.dart` and add `DictationMicButton(controller: controller)` into the existing `controls` list (position: after the existing formatting icon controls, before any trailing spacer/divider already in that list — match whatever ordering reads most naturally next to the existing controls when you have the file open).
- [ ] **Step 4: Run to verify pass:**
  ```bash
  flutter test test/features/notes/presentation/editor_formatting_bar_test.dart
  ```
- [ ] **Step 5:** Run the full existing `add_edit_note_page_test.dart` suite too, since this widget is embedded there — confirm nothing regressed:
  ```bash
  flutter test test/features/notes/presentation/add_edit_note_page_test.dart
  ```
- [ ] **Step 6: Gate.**
  ```bash
  flutter analyze --fatal-infos --fatal-warnings
  flutter test --concurrency=1
  dart format --output=none --set-exit-if-changed lib test
  node .gitnexus/run.cjs detect-changes --scope all --repo .
  ```
- [ ] **Step 7: Commit.**
  ```bash
  git add lib/features/notes/presentation/widgets/editor_formatting_bar.dart \
          test/features/notes/presentation/editor_formatting_bar_test.dart
  git commit -m "feat(dictation): wire DictationMicButton into EditorFormattingBar"
  ```

---

### Task 6: Manual/Visual QA & Merge Readiness

**Files:** none (verification only).

- [ ] **Step 1:** On a real device or simulator/emulator for each platform, add a note, tap the mic icon, and confirm: permission prompt appears on first use; recognized text appears live in the body; tapping again stops cleanly; backgrounding the app mid-dictation doesn't crash on return.
- [ ] **Step 2:** Repeat with the app's locale set to both `vi` and `en` (Settings → language, or however this project's existing locale switcher works) to confirm dictation follows the UI locale as designed.
- [ ] **Step 3:** Capture screenshots (mic idle / listening / unavailable states, at least one platform, light + dark) into `docs/screenshots/`, following this project's established pre-release visual QA rule (`docs/qa.md`) and the naming convention already used by prior widget-feature screenshots in that directory.
- [ ] **Step 4: Full-suite gate.**
  ```bash
  dart format --output=none --set-exit-if-changed lib test
  flutter analyze --fatal-infos --fatal-warnings
  flutter test --concurrency=1
  node .gitnexus/run.cjs detect-changes --scope all --repo .
  ```
  All green; working tree clean except the new screenshots.
- [ ] **Step 5: Commit the screenshots.**
  ```bash
  git add docs/screenshots/
  git commit -m "docs(qa): add Realtime Dictation visual QA screenshots"
  ```
