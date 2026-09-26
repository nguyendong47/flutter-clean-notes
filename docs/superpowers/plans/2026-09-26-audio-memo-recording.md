# Audio Memo Recording & Playback (Phase 2B-i) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user record one or more voice memos and attach them to a note, played back in place with a waveform and standard player controls, from both an in-editor record control and a Home Screen Widget quick-record shortcut.

**Architecture:** A new `AudioRecordingService` (plain Dart, mirrors Phase 2A's `DictationService`) wraps the `record` plugin behind a `Recorder` interface, sharing Phase 2A's `PermissionRequester`/`DictationPermissionResult` types (extended with a mic-only method) rather than duplicating them. A new `AudioAttachmentRepository` owns the `note_audio_attachments` table and keeps the DB row, the audio file on disk, and an embed line (`![audio](attachment://<id>)`) in the note's Markdown text in sync. The note editor's existing Markdown preview renderer (`MarkdownBody.imageBuilder`, currently only used for a missing-image placeholder) is extended to render that embed as a real waveform/player block.

**Tech Stack:** `record` (recording), `just_audio` (playback), existing `flutter_riverpod`/`riverpod_annotation`, `sqflite`, `flutter_markdown_plus`.

**Spec:** [`docs/superpowers/specs/2026-09-26-audio-memo-recording-design.md`](../specs/2026-09-26-audio-memo-recording-design.md)

## Global Constraints

- Android and iOS only. The record control is statically disabled (not tappable-then-failing) on every other platform — a compile-time `isAudioRecordingSupported()` check, not a runtime state.
- Microphone permission is already declared on both platforms (Phase 2A added `NSMicrophoneUsageDescription` to `ios/Runner/Info.plist` and `RECORD_AUDIO` to `android/app/src/main/AndroidManifest.xml`) — this plan adds no new platform permission declarations.
- Recordings under 1 second are auto-discarded — no DB row, no file left behind, no embed inserted.
- A note can have multiple audio attachments.
- The embed syntax `![audio](attachment://<id>)` must remain valid, exportable plain Markdown — no non-Markdown syntax invented.
- `note_audio_attachments` columns are camelCase (`noteId`, `filePath`, `durationMs`, `waveformData`, `createdAt`), matching this codebase's existing `notes`/`reminder_outbox` tables — not snake_case. `noteId` is `INTEGER`, matching `notes.id`'s real type. No SQL `FOREIGN KEY`/`ON DELETE CASCADE` (this project never enables `PRAGMA foreign_keys`, so a declared FK would be silently unenforced) — cleanup is application-level.
- `flutter analyze --fatal-infos --fatal-warnings` and `dart format --output=none --set-exit-if-changed lib test` must stay clean after every task.
- Run `dart run build_runner build --delete-conflicting-outputs` after any `@riverpod` change and verify zero drift before each task's gate.
- GitNexus: run `impact` before editing any existing symbol (`PermissionRequester`/`dictation_service.dart` in Task 2, `NoteRepositoryImpl`/`local_note_datasource.dart` in Task 4, `EditorFormattingBar`/`AddEditNotePage`/`router.dart` in Task 7), and `detect_changes --scope all` (or `--scope staged` after a fresh `analyze --index-only` re-index, per this project's established lesson that new files need a re-index first) before every commit, per this project's CLAUDE.md.
- Verify `record`'s and `just_audio`'s actual resolved-version API shape before writing `PlatformRecorder`/the player widget (check `.dart_tool/package_config.json` then the pub cache source) — do not assume method names blindly, per this project's established convention from Phase 2A.

## Review Focus

- **Recording fails mid-session** (storage full, OS interruption, plugin error): must stop cleanly, discard the partial file, show an error, and never insert a broken or partial player block. (Task 3)
- **The underlying audio file goes missing or becomes unreadable** after a player block already exists (moved, deleted outside the app, corrupted): the player block must show the same "unavailable" state this app already ships for a missing Markdown image, never crash the whole note preview. (Task 7)
- **Rapid double-tap of the record button** (start-while-starting, stop-while-stopping): must not leave the service in an inconsistent state or throw — mirrors the exact race Phase 2A's independent review caught in `DictationService`. (Task 3)
- **Deleting a note that has audio attachments**: must not leave orphaned files or DB rows for the direct-delete path (the 30-day trash-sweep path is an explicit, documented non-goal of this plan, not silently missed). (Task 4)
- **Two attachments in the same note, one deleted while the other still plays**: deleting one must not affect the other's DB row, file, or embed line — each attachment's cleanup must be scoped by its own id, not by note id. (Task 4, Task 7)
- **Starting a recording on a brand-new, not-yet-saved note** (`AddEditNotePage`'s existing `_saveNote()` is an explicit, user-triggered "save and close" action — there is no autosave to piggyback on, and `note_audio_attachments.noteId` needs a real, persisted note id to reference): the note must be silently persisted (created, not shown as "saved" to the user, editor stays open) the first time recording starts on it, so the attachment has a stable id — and a second recording, or the user's own later explicit save, must update that same row rather than creating a duplicate note. (Task 7)

---

## 1. Ordered Implementation Tasks

### Task 1: Dependencies

**Files:**
- Modify: `pubspec.yaml`

**Interfaces:**
- Produces: `record` and `just_audio` packages available to import in later tasks.

- [ ] **Step 1:** Run `flutter pub add record just_audio` from the project root — resolves and pins current versions; do not hand-write version numbers.
- [ ] **Step 2:** Run `flutter pub get` and confirm it completes without error.
- [ ] **Step 3: Gate.**
  ```bash
  flutter analyze --fatal-infos --fatal-warnings
  flutter test --concurrency=1
  ```
  Both clean — this task changes no Dart behavior yet.
- [ ] **Step 4:** `bun .gitnexus/run.cjs detect-changes --scope all --repo .` (or `node` if available — check CLAUDE.md for the current fallback; this Mac needs `bun`). Confirm risk is low/clean.
- [ ] **Step 5: Commit.**
  ```bash
  git add pubspec.yaml pubspec.lock
  git commit -m "feat(audio-memo): add record/just_audio deps"
  ```

---

### Task 2: Mic-only permission on the shared `PermissionRequester`

**Files:**
- Modify: `lib/features/notes/presentation/services/dictation_service.dart`
- Modify: `test/helpers/fake_permission_requester.dart`
- Modify: `test/features/notes/presentation/services/dictation_service_test.dart` (regression only — no new test cases expected, just confirm nothing broke)

**Interfaces:**
- Consumes: nothing new.
- Produces: `PermissionRequester.requestMicrophone()` returning `Future<DictationPermissionResult>` — mic-only, no iOS speech-recognition request. `FakePermissionRequester.requestMicrophone()` returns the fake's existing `result` field (same one `requestMicrophoneAndSpeech()` already returns), so a test can drive either method identically via the existing `result`/`granted` fields.

**Before editing:** run GitNexus impact analysis on `PermissionRequester` first, per CLAUDE.md:
```bash
bun .gitnexus/run.cjs impact "PermissionRequester" --direction upstream --repo .
```
This interface is consumed by the already-shipped `DictationService` — confirm risk before proceeding; a new method added to an interface (not a changed signature on an existing one) should not affect existing callers, but confirm rather than assume.

- [ ] **Step 1: Write the failing test.** Add to `test/features/notes/presentation/services/dictation_service_test.dart` (new top-level test, not inside the existing `DictationService` `group`/`main` body — this exercises the fake directly, not `DictationService`, since `DictationService` itself never calls `requestMicrophone()`):
  ```dart
  test('FakePermissionRequester.requestMicrophone returns the configured result', () async {
    final permissions = FakePermissionRequester(
      result: DictationPermissionResult.permanentlyDenied,
    );

    final result = await permissions.requestMicrophone();

    expect(result, DictationPermissionResult.permanentlyDenied);
  });
  ```
- [ ] **Step 2: Run to verify it fails:**
  ```bash
  flutter test test/features/notes/presentation/services/dictation_service_test.dart
  ```
  Expected: FAIL — `requestMicrophone` is not defined on `FakePermissionRequester`/`PermissionRequester`.
- [ ] **Step 3: Implement.** In `dictation_service.dart`, add to the `PermissionRequester` interface:
  ```dart
  abstract interface class PermissionRequester {
    Future<DictationPermissionResult> requestMicrophoneAndSpeech();

    /// Requests only microphone access - no iOS speech-recognition permission.
    /// Used by features (like audio memo recording) that record raw audio and
    /// never transcribe it, so they must not trigger the speech-recognition
    /// consent prompt Phase 2A's dictation feature needs.
    Future<DictationPermissionResult> requestMicrophone();
  }
  ```
  Add to `PlatformPermissionRequester`:
  ```dart
  @override
  Future<DictationPermissionResult> requestMicrophone() async {
    final micStatus = await Permission.microphone.request();
    if (micStatus.isPermanentlyDenied) {
      return DictationPermissionResult.permanentlyDenied;
    }
    return micStatus.isGranted
        ? DictationPermissionResult.granted
        : DictationPermissionResult.denied;
  }
  ```
  In `test/helpers/fake_permission_requester.dart`, add:
  ```dart
  @override
  Future<DictationPermissionResult> requestMicrophone() async {
    requestCalls += 1;
    return result;
  }
  ```
- [ ] **Step 4: Run to verify pass, then run the full existing dictation suite for regressions:**
  ```bash
  flutter test test/features/notes/presentation/services/dictation_service_test.dart
  flutter test test/features/notes/presentation/widgets/dictation_mic_button_test.dart
  ```
  Expected: all PASS, including every pre-existing test (this is an additive interface change).
- [ ] **Step 5: Gate.**
  ```bash
  flutter analyze --fatal-infos --fatal-warnings
  dart format --output=none --set-exit-if-changed lib test
  bun .gitnexus/run.cjs analyze --index-only
  bun .gitnexus/run.cjs detect-changes --scope staged --repo .
  ```
- [ ] **Step 6: Commit.**
  ```bash
  git add lib/features/notes/presentation/services/dictation_service.dart \
          test/helpers/fake_permission_requester.dart
  git commit -m "feat(audio-memo): add mic-only PermissionRequester.requestMicrophone()"
  ```

---

### Task 3: `AudioRecordingService` — core logic, fully testable

**Files:**
- Create: `lib/features/notes/presentation/services/audio_recording_service.dart`
- Create: `test/helpers/fake_recorder.dart`
- Test: `test/features/notes/presentation/services/audio_recording_service_test.dart`

**Interfaces:**
- Consumes: `PermissionRequester`/`DictationPermissionResult` from `dictation_service.dart` (Task 2's `requestMicrophone()`).
- Produces:
  - `enum AudioRecordingState { idle, recording, permissionDenied, permissionPermanentlyDenied, unavailable, error }`
  - `class AudioRecordingResult { final String filePath; final int durationMs; final List<double> waveform; }`
  - `abstract interface class Recorder { Future<bool> start(); Future<AudioRecordingResult?> stop(); Future<void> cancel(); bool get isRecording; Stream<double> get amplitudeStream; }` — `stop()` returns `null` if the recording was under 1 second (auto-discarded) or otherwise unusable; `amplitudeStream` emits normalized `0.0-1.0` amplitude samples while recording, used to build the waveform live (verify this matches the resolved `record` package version's actual amplitude-stream API before finalizing `PlatformRecorder` in Step 3 below - adjust only `PlatformRecorder`'s internals if the shape has drifted, never this interface, since Tasks 5-7 depend on this interface exactly as specified).
  - `class AudioRecordingService` with `Stream<AudioRecordingState> get stateStream`, `AudioRecordingState get currentState`, `Future<void> start()`, `Future<AudioRecordingResult?> stop()`, `void dispose()`.
- Consumed by: Task 6 (`AudioRecordButton`).

`bool isAudioRecordingSupported()` (top-level function in this file, mirrors `dictation_mic_button.dart`'s `_speechLocaleId` free-function pattern): `!kIsWeb && (Platform.isAndroid || Platform.isIOS)`. This is a static platform check consumed directly by the widget layer (Task 6) to decide whether to render the record control as enabled at all - per the spec, unsupported-platform handling here is compile-time, unlike Phase 2A's runtime `unavailable` state for an unsupported locale.

This task's production `PlatformRecorder` (wrapping the real `record` plugin) is written as real code based on that plugin's well-established API shape (`AudioRecorder().hasPermission()`, `.start(RecordConfig(), path: ...)`, `.stop()` returning the recorded file's path, `.isRecording()`, `.onAmplitudeChanged(Duration interval)` returning a `Stream<Amplitude>` with a `.current` dB value normalized here to `0.0-1.0`). **Before treating Step 5 below as done, verify these method names/shapes against whatever version `flutter pub add` actually resolved** in Task 1 (check `.dart_tool/package_config.json`, then that version's source in the pub cache) - the shape has been stable but must not be assumed blindly. Only `PlatformRecorder`'s own internals need adjusting if it has drifted; `Recorder`'s interface (defined by this task) stays exactly as specified, since Task 6 depends on that, not on the plugin's own API directly. This task's own tests never exercise the real plugin (only `FakeRecorder`, via dependency injection) - inherently untestable in CI, which is what Task 9's manual/visual QA is for.

- [ ] **Step 1: Write the failing tests.** Create `test/helpers/fake_recorder.dart`:
  ```dart
  import 'dart:async';

  import 'package:flutter_clean_notes/features/notes/presentation/services/audio_recording_service.dart';

  class FakeRecorder implements Recorder {
    bool startResult = true;
    bool _isRecording = false;
    int startCalls = 0;
    int stopCalls = 0;
    int cancelCalls = 0;
    AudioRecordingResult? nextStopResult;
    final _amplitudeController = StreamController<double>.broadcast();

    @override
    Future<bool> start() async {
      startCalls += 1;
      _isRecording = startResult;
      return startResult;
    }

    @override
    Future<AudioRecordingResult?> stop() async {
      stopCalls += 1;
      _isRecording = false;
      return nextStopResult;
    }

    @override
    Future<void> cancel() async {
      cancelCalls += 1;
      _isRecording = false;
    }

    @override
    bool get isRecording => _isRecording;

    @override
    Stream<double> get amplitudeStream => _amplitudeController.stream;

    /// Test helper: simulate a live amplitude sample while recording.
    void emitAmplitude(double value) => _amplitudeController.add(value);

    /// Test helper: simulate the recorder throwing mid-operation.
    void throwOnNextCall(Object error) {
      _throwError = error;
    }

    Object? _throwError;
  }
  ```
  Create `test/features/notes/presentation/services/audio_recording_service_test.dart`:
  ```dart
  import 'package:flutter_test/flutter_test.dart';

  import 'package:flutter_clean_notes/features/notes/presentation/services/audio_recording_service.dart';
  import 'package:flutter_clean_notes/features/notes/presentation/services/dictation_service.dart';

  import '../../../../helpers/fake_permission_requester.dart';
  import '../../../../helpers/fake_recorder.dart';

  void main() {
    late FakeRecorder recorder;
    late FakePermissionRequester permissions;
    late AudioRecordingService service;

    setUp(() {
      recorder = FakeRecorder();
      permissions = FakePermissionRequester();
      service = AudioRecordingService(recorder: recorder, permissions: permissions);
    });

    tearDown(() => service.dispose());

    test('starts idle', () {
      expect(service.currentState, AudioRecordingState.idle);
    });

    test('start() requests mic permission and begins recording', () async {
      await service.start();

      expect(permissions.requestCalls, 1);
      expect(recorder.startCalls, 1);
      expect(service.currentState, AudioRecordingState.recording);
    });

    test('permission denied moves to permissionDenied without calling start', () async {
      permissions.result = DictationPermissionResult.denied;

      await service.start();

      expect(recorder.startCalls, 0);
      expect(service.currentState, AudioRecordingState.permissionDenied);
    });

    test('permission permanentlyDenied moves to permissionPermanentlyDenied', () async {
      permissions.result = DictationPermissionResult.permanentlyDenied;

      await service.start();

      expect(recorder.startCalls, 0);
      expect(service.currentState, AudioRecordingState.permissionPermanentlyDenied);
    });

    test('stop() returns the recorder result and returns to idle', () async {
      recorder.nextStopResult = const AudioRecordingResult(
        filePath: '/tmp/rec.m4a',
        durationMs: 5000,
        waveform: [0.1, 0.4, 0.2],
      );
      await service.start();

      final result = await service.stop();

      expect(result?.filePath, '/tmp/rec.m4a');
      expect(recorder.stopCalls, 1);
      expect(service.currentState, AudioRecordingState.idle);
    });

    test('stop() returning null (sub-1s recording) is treated as a discard, still returns to idle', () async {
      recorder.nextStopResult = null;
      await service.start();

      final result = await service.stop();

      expect(result, isNull);
      expect(service.currentState, AudioRecordingState.idle);
    });

    test('stop() while idle is a safe no-op returning null', () async {
      final result = await service.stop();

      expect(result, isNull);
      expect(recorder.stopCalls, 0);
    });

    test('calling start() twice while already recording is a no-op the second time', () async {
      await service.start();
      await service.start();

      expect(recorder.startCalls, 1, reason: 'must not start a second overlapping recording');
    });

    test('rapid concurrent start() calls run only one sequence', () async {
      final future1 = service.start();
      final future2 = service.start();

      await Future.wait([future1, future2]);

      expect(permissions.requestCalls, 1);
      expect(recorder.startCalls, 1);
      expect(service.currentState, AudioRecordingState.recording);
    });

    test('dispose() cancels an in-progress recording', () async {
      await service.start();

      service.dispose();

      expect(recorder.cancelCalls, 1);
      expect(
        () => service.stateStream.listen((_) {}),
        throwsStateError,
        reason: 'stream must be closed after dispose',
      );
    });

    test('recorder.start() throwing is caught and surfaces as error, not an uncaught exception', () async {
      final throwingRecorder = _ThrowingStartRecorder();
      final throwingService = AudioRecordingService(
        recorder: throwingRecorder,
        permissions: permissions,
      );
      addTearDown(throwingService.dispose);

      await throwingService.start();

      expect(throwingService.currentState, AudioRecordingState.error);
    });
  }

  class _ThrowingStartRecorder implements Recorder {
    @override
    Future<bool> start() async => throw StateError('platform recorder blew up');

    @override
    Future<AudioRecordingResult?> stop() async => null;

    @override
    Future<void> cancel() async {}

    @override
    bool get isRecording => false;

    @override
    Stream<double> get amplitudeStream => const Stream.empty();
  }
  ```
- [ ] **Step 2: Run to verify they fail** (the service doesn't exist yet):
  ```bash
  flutter test test/features/notes/presentation/services/audio_recording_service_test.dart
  ```
  Expected: FAIL - missing URI.
- [ ] **Step 3: Write the implementation.** Create `lib/features/notes/presentation/services/audio_recording_service.dart`:
  ```dart
  import 'dart:async';
  import 'dart:io';

  import 'package:flutter/foundation.dart' show kIsWeb;
  import 'package:path/path.dart' as p;
  import 'package:path_provider/path_provider.dart';
  import 'package:record/record.dart';

  import 'package:flutter_clean_notes/features/notes/presentation/services/dictation_service.dart';

  enum AudioRecordingState {
    idle,
    recording,
    permissionDenied,
    permissionPermanentlyDenied,
    unavailable,
    error,
  }

  /// True only on the platforms this feature supports (Android, iOS). Unlike
  /// Phase 2A's `unavailable` DictationState (a runtime fact - whether an
  /// on-device speech model exists for a locale), platform support for audio
  /// recording is a compile-time fact, so the record control is disabled at
  /// render time rather than reacting to a runtime state - see this plan's
  /// Global Constraints.
  bool isAudioRecordingSupported() =>
      !kIsWeb &&
      (defaultTargetPlatformIsAndroid() || defaultTargetPlatformIsIOS());

  // Kept as tiny named helpers (rather than importing dart:io Platform
  // directly here) so this file's only platform-check dependency is
  // documented in one place; both delegate to dart:io.
  bool defaultTargetPlatformIsAndroid() => !kIsWeb && Platform.isAndroid;
  bool defaultTargetPlatformIsIOS() => !kIsWeb && Platform.isIOS;

  final class AudioRecordingResult {
    const AudioRecordingResult({
      required this.filePath,
      required this.durationMs,
      required this.waveform,
    });

    final String filePath;
    final int durationMs;
    final List<double> waveform;
  }

  /// Abstraction over the platform audio recorder (real implementation wraps
  /// the `record` plugin). Kept minimal and owned by this file so
  /// [AudioRecordingService] and its tests never depend on the third-party
  /// package's own API surface directly.
  abstract interface class Recorder {
    Future<bool> start();

    /// Stops recording. Returns `null` if the recording was under 1 second
    /// (auto-discarded per this plan's Global Constraints) or otherwise
    /// unusable - never a broken/partial result.
    Future<AudioRecordingResult?> stop();

    Future<void> cancel();

    bool get isRecording;

    /// Normalized 0.0-1.0 amplitude samples while recording, used to build
    /// the waveform live rather than decoding the finished file afterward.
    Stream<double> get amplitudeStream;
  }

  class AudioRecordingService {
    AudioRecordingService({Recorder? recorder, PermissionRequester? permissions})
      : _recorder = recorder ?? PlatformRecorder(),
        _permissions = permissions ?? PlatformPermissionRequester();

    final Recorder _recorder;
    final PermissionRequester _permissions;

    final _stateController = StreamController<AudioRecordingState>.broadcast(
      sync: true,
    );

    AudioRecordingState _state = AudioRecordingState.idle;
    AudioRecordingState get currentState => _state;
    bool _disposed = false;
    bool _starting = false;

    Stream<AudioRecordingState> get stateStream {
      if (_disposed) {
        throw StateError('Cannot listen to stateStream after dispose');
      }
      return _GuardedStream(_stateController.stream, () => _disposed);
    }

    void _setState(AudioRecordingState state) {
      _state = state;
      if (!_stateController.isClosed) _stateController.add(state);
    }

    Future<void> start() async {
      if (_state == AudioRecordingState.recording || _starting) return;
      _starting = true;

      try {
        final permissionResult = await _permissions.requestMicrophone();
        if (_disposed) {
          unawaited(_recorder.cancel());
          return;
        }
        if (permissionResult == DictationPermissionResult.permanentlyDenied) {
          _setState(AudioRecordingState.permissionPermanentlyDenied);
          return;
        }
        if (permissionResult == DictationPermissionResult.denied) {
          _setState(AudioRecordingState.permissionDenied);
          return;
        }

        final started = await _recorder.start();
        if (_disposed) {
          unawaited(_recorder.cancel());
          return;
        }
        if (!started) {
          _setState(AudioRecordingState.unavailable);
          return;
        }
        _setState(AudioRecordingState.recording);
      } on UnsupportedError catch (_) {
        _setState(AudioRecordingState.unavailable);
      } catch (_) {
        _setState(AudioRecordingState.error);
      } finally {
        _starting = false;
      }
    }

    Future<AudioRecordingResult?> stop() async {
      if (_state != AudioRecordingState.recording) return null;
      final result = await _recorder.stop();
      _setState(AudioRecordingState.idle);
      return result;
    }

    void dispose() {
      _disposed = true;
      unawaited(_recorder.cancel());
      _stateController.close();
    }
  }

  class _GuardedStream<T> extends Stream<T> {
    _GuardedStream(this._source, this._isDisposed);

    final Stream<T> _source;
    final bool Function() _isDisposed;

    @override
    StreamSubscription<T> listen(
      void Function(T event)? onData, {
      Function? onError,
      void Function()? onDone,
      bool? cancelOnError,
    }) {
      if (_isDisposed()) {
        throw StateError('Cannot listen to stream after dispose');
      }
      return _source.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
    }
  }

  class PlatformRecorder implements Recorder {
    final AudioRecorder _recorder = AudioRecorder();
    String? _currentPath;
    DateTime? _startedAt;
    final _samples = <double>[];
    StreamSubscription<Amplitude>? _amplitudeSub;
    final _amplitudeController = StreamController<double>.broadcast();

    @override
    Future<bool> start() async {
      if (!await _recorder.hasPermission()) return false;
      final dir = await getApplicationDocumentsDirectory();
      final path = p.join(
        dir.path,
        'audio_memos',
        '${DateTime.now().microsecondsSinceEpoch}.m4a',
      );
      await Directory(p.dirname(path)).create(recursive: true);
      await _recorder.start(const RecordConfig(), path: path);
      _currentPath = path;
      _startedAt = DateTime.now();
      _samples.clear();
      _amplitudeSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 200))
          .listen((amp) {
            // dBFS is typically in [-45, 0]; normalize to 0.0-1.0.
            final normalized = ((amp.current + 45) / 45).clamp(0.0, 1.0);
            _samples.add(normalized);
            if (!_amplitudeController.isClosed) {
              _amplitudeController.add(normalized);
            }
          });
      return true;
    }

    @override
    Future<AudioRecordingResult?> stop() async {
      final path = await _recorder.stop();
      await _amplitudeSub?.cancel();
      _amplitudeSub = null;
      final startedAt = _startedAt;
      _startedAt = null;
      if (path == null || startedAt == null) return null;
      final durationMs = DateTime.now().difference(startedAt).inMilliseconds;
      if (durationMs < 1000) {
        await File(path).delete().catchError((_) => File(path));
        return null;
      }
      return AudioRecordingResult(
        filePath: path,
        durationMs: durationMs,
        waveform: List<double>.from(_samples),
      );
    }

    @override
    Future<void> cancel() async {
      await _amplitudeSub?.cancel();
      _amplitudeSub = null;
      if (await _recorder.isRecording()) {
        final path = await _recorder.stop();
        if (path != null) {
          await File(path).delete().catchError((_) => File(path));
        }
      }
    }

    @override
    bool get isRecording => false; // queried async via _recorder.isRecording();
    // not exposed synchronously - no caller in this plan needs a sync read.

    @override
    Stream<double> get amplitudeStream => _amplitudeController.stream;
  }
  ```
  **Verification required before treating this step as done:** confirm `record`'s resolved version actually exposes `AudioRecorder()`, `.hasPermission()`, `.start(RecordConfig(), path:)`, `.stop()` returning `Future<String?>`, `.isRecording()` returning `Future<bool>`, `.onAmplitudeChanged(Duration)` returning `Stream<Amplitude>` with an `Amplitude.current` double field (dBFS). Adjust only `PlatformRecorder`'s internals if any of this has drifted from the resolved version; `Recorder`'s interface and every other file in this plan do not depend on this package's API shape.
- [ ] **Step 4: Run tests to verify the fake-backed tests pass:**
  ```bash
  flutter test test/features/notes/presentation/services/audio_recording_service_test.dart
  ```
  Expected: all PASS (the two `Platform*` classes are never constructed by these tests).
- [ ] **Step 5: Gate.**
  ```bash
  flutter analyze --fatal-infos --fatal-warnings
  dart format --output=none --set-exit-if-changed lib test
  bun .gitnexus/run.cjs analyze --index-only
  bun .gitnexus/run.cjs detect-changes --scope staged --repo .
  ```
- [ ] **Step 6: Commit.**
  ```bash
  git add lib/features/notes/presentation/services/audio_recording_service.dart \
          test/helpers/fake_recorder.dart \
          test/features/notes/presentation/services/audio_recording_service_test.dart
  git commit -m "feat(audio-memo): add AudioRecordingService with fake-testable recorder abstraction"
  ```

---

### Task 4: DB migration + `AudioAttachmentRepository`

**Files:**
- Modify: `lib/features/notes/data/datasources/local_note_datasource.dart`
- Create: `lib/features/notes/data/repositories/audio_attachment_repository.dart`
- Modify: `lib/features/notes/data/repositories/note_repository_impl.dart`
- Test: `test/features/notes/data/repositories/audio_attachment_repository_test.dart`
- Modify: `test/features/notes/data/repositories/note_repository_impl_test.dart` (if it exists - check first; if not, check whatever test file already covers `NoteRepositoryImpl.deleteNote`, following that file's existing conventions)

**Interfaces:**
- Consumes: nothing from earlier tasks in this plan (independent of Tasks 2-3).
- Produces:
  - `note_audio_attachments` table (schema v8), columns exactly as in this plan's Global Constraints.
  - `abstract interface class AudioAttachmentRepository { Future<String> addAttachment({required int noteId, required String filePath, required int durationMs, required List<double> waveform}); Future<void> deleteAttachment(String id); Future<void> deleteAttachmentsForNote(int noteId); Future<List<AudioAttachment>> attachmentsForNote(int noteId); }`
  - `final class AudioAttachment { final String id; final int noteId; final String filePath; final int durationMs; final List<double> waveform; final DateTime createdAt; }`
  - Two pure helper functions (same file as `AudioAttachment`, or a small sibling file `audio_embed_syntax.dart` - implementer's choice, but must be exported from a stable, documented location since Task 6/7 import them): `String buildAudioEmbed(String attachmentId) => '![audio](attachment://$attachmentId)';` and `String removeAudioEmbed(String noteText, String attachmentId) => noteText.replaceAll('${buildAudioEmbed(attachmentId)}\n', '').replaceAll(buildAudioEmbed(attachmentId), '');` (handles both a trailing-newline and an end-of-text case).
- `NoteRepositoryImpl.deleteNote(int id)` is modified to also call `audioAttachmentRepository.deleteAttachmentsForNote(id)` **after** the note row is deleted (never before - if note deletion fails, attachments must not have already been removed), swallowing any individual attachment-cleanup failure (log via `debugPrint`, never let a secondary cleanup failure make the primary delete-note action report failure to the caller).

**Before editing:** run GitNexus impact analysis on both existing symbols first, per CLAUDE.md:
```bash
bun .gitnexus/run.cjs impact "NoteRepositoryImpl" --direction upstream --repo .
bun .gitnexus/run.cjs impact "LocalNoteDataSourceImpl" --direction upstream --repo .
```
`NoteRepositoryImpl` is consumed throughout the notes feature - confirm risk is LOW/expected for an additive constructor dependency and one new call inside `deleteNote` before proceeding; stop and flag it if either comes back HIGH/CRITICAL or UNKNOWN.

- [ ] **Step 1: Write the failing test.** Create `test/features/notes/data/repositories/audio_attachment_repository_test.dart` (mirror whatever existing test in `test/features/notes/data/repositories/` sets up a real in-memory/temp sqflite `Database` for `LocalNoteDataSourceImpl` - use that exact setup helper rather than inventing a new one; if none exists, use `sqflite_common_ffi`'s `databaseFactoryFfi` with `inMemoryDatabasePath`, matching `local_note_datasource.dart`'s own FFI usage):
  ```dart
  import 'package:flutter_test/flutter_test.dart';

  import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
  import 'package:flutter_clean_notes/features/notes/data/repositories/audio_attachment_repository.dart';
  import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';

  void main() {
    late LocalNoteDataSourceImpl dataSource;
    late AudioAttachmentRepositoryImpl repository;
    late int noteId;

    setUp(() async {
      dataSource = LocalNoteDataSourceImpl(); // adjust to this test file's real in-memory-DB construction pattern once copied from the sibling test it mirrors
      repository = AudioAttachmentRepositoryImpl(dataSource: dataSource);
      noteId = await dataSource.addNote(
        NoteModel(
          id: 0,
          title: 'Test',
          content: '',
          color: 0,
          createdAt: DateTime.now(),
        ),
      );
    });

    test('addAttachment persists a row retrievable by attachmentsForNote', () async {
      final id = await repository.addAttachment(
        noteId: noteId,
        filePath: '/tmp/rec.m4a',
        durationMs: 3000,
        waveform: [0.1, 0.2, 0.3],
      );

      final attachments = await repository.attachmentsForNote(noteId);

      expect(attachments, hasLength(1));
      expect(attachments.single.id, id);
      expect(attachments.single.filePath, '/tmp/rec.m4a');
      expect(attachments.single.durationMs, 3000);
      expect(attachments.single.waveform, [0.1, 0.2, 0.3]);
    });

    test('deleteAttachment removes only the targeted attachment', () async {
      final firstId = await repository.addAttachment(
        noteId: noteId,
        filePath: '/tmp/a.m4a',
        durationMs: 1000,
        waveform: const [],
      );
      final secondId = await repository.addAttachment(
        noteId: noteId,
        filePath: '/tmp/b.m4a',
        durationMs: 1000,
        waveform: const [],
      );

      await repository.deleteAttachment(firstId);
      final remaining = await repository.attachmentsForNote(noteId);

      expect(remaining.map((a) => a.id), [secondId]);
    });

    test('deleteAttachmentsForNote removes every attachment for that note only', () async {
      final otherNoteId = await dataSource.addNote(
        NoteModel(id: 0, title: 'Other', content: '', color: 0, createdAt: DateTime.now()),
      );
      await repository.addAttachment(noteId: noteId, filePath: '/tmp/a.m4a', durationMs: 1000, waveform: const []);
      await repository.addAttachment(noteId: otherNoteId, filePath: '/tmp/b.m4a', durationMs: 1000, waveform: const []);

      await repository.deleteAttachmentsForNote(noteId);

      expect(await repository.attachmentsForNote(noteId), isEmpty);
      expect(await repository.attachmentsForNote(otherNoteId), hasLength(1));
    });

    test('buildAudioEmbed and removeAudioEmbed round-trip', () {
      const id = 'abc-123';
      final embedded = 'Before\n${buildAudioEmbed(id)}\nAfter';

      final removed = removeAudioEmbed(embedded, id);

      expect(removed, 'Before\nAfter');
      expect(removed, isNot(contains('attachment://$id')));
    });
  }
  ```
- [ ] **Step 2: Run to verify it fails:**
  ```bash
  flutter test test/features/notes/data/repositories/audio_attachment_repository_test.dart
  ```
- [ ] **Step 3: Implement the migration.** In `local_note_datasource.dart`, bump `_schemaVersion` from `7` to `8`, add a table-name constant, add the table creation to `_createDB`, and add the upgrade branch to `_upgradeDB`:
  ```dart
  static const String _audioAttachmentsTable = 'note_audio_attachments';
  ```
  In `_createDB`, after the existing `await _createReminderOutbox(db);` line, add:
  ```dart
  await _createAudioAttachments(db);
  ```
  Add the new helper method (sibling to `_createReminderOutbox`):
  ```dart
  Future<void> _createAudioAttachments(Database db) async {
    await db.execute('''
      CREATE TABLE $_audioAttachmentsTable (
        id TEXT PRIMARY KEY,
        noteId INTEGER NOT NULL,
        filePath TEXT NOT NULL,
        durationMs INTEGER NOT NULL,
        waveformData TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX audio_attachments_note_id
      ON $_audioAttachmentsTable(noteId)
    ''');
  }
  ```
  In `_upgradeDB`, after the existing `if (oldVersion < 7) { ... }` block, add:
  ```dart
  if (oldVersion < 8) {
    await _createAudioAttachments(db);
  }
  ```
- [ ] **Step 4: Implement the repository.** Create `lib/features/notes/data/repositories/audio_attachment_repository.dart`:
  ```dart
  import 'dart:convert';
  import 'dart:io';

  import 'package:uuid/uuid.dart';

  import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';

  final class AudioAttachment {
    const AudioAttachment({
      required this.id,
      required this.noteId,
      required this.filePath,
      required this.durationMs,
      required this.waveform,
      required this.createdAt,
    });

    final String id;
    final int noteId;
    final String filePath;
    final int durationMs;
    final List<double> waveform;
    final DateTime createdAt;
  }

  String buildAudioEmbed(String attachmentId) => '![audio](attachment://$attachmentId)';

  String removeAudioEmbed(String noteText, String attachmentId) {
    final embed = buildAudioEmbed(attachmentId);
    return noteText.replaceAll('$embed\n', '').replaceAll(embed, '');
  }

  abstract interface class AudioAttachmentRepository {
    Future<String> addAttachment({
      required int noteId,
      required String filePath,
      required int durationMs,
      required List<double> waveform,
    });

    Future<void> deleteAttachment(String id);

    Future<void> deleteAttachmentsForNote(int noteId);

    Future<List<AudioAttachment>> attachmentsForNote(int noteId);
  }

  class AudioAttachmentRepositoryImpl implements AudioAttachmentRepository {
    AudioAttachmentRepositoryImpl({
      required LocalNoteDataSourceImpl dataSource,
      Uuid? uuid,
    }) : _dataSource = dataSource,
         _uuid = uuid ?? const Uuid();

    final LocalNoteDataSourceImpl _dataSource;
    final Uuid _uuid;

    @override
    Future<String> addAttachment({
      required int noteId,
      required String filePath,
      required int durationMs,
      required List<double> waveform,
    }) async {
      final id = _uuid.v4();
      await _dataSource.insertAudioAttachment(
        id: id,
        noteId: noteId,
        filePath: filePath,
        durationMs: durationMs,
        waveformData: jsonEncode(waveform),
        createdAt: DateTime.now().toIso8601String(),
      );
      return id;
    }

    @override
    Future<void> deleteAttachment(String id) async {
      final row = await _dataSource.getAudioAttachment(id);
      await _dataSource.deleteAudioAttachment(id);
      if (row != null) {
        await File(row['filePath'] as String).delete().catchError((_) => File(row['filePath'] as String));
      }
    }

    @override
    Future<void> deleteAttachmentsForNote(int noteId) async {
      final rows = await _dataSource.audioAttachmentsForNote(noteId);
      for (final row in rows) {
        await File(row['filePath'] as String).delete().catchError((_) => File(row['filePath'] as String));
      }
      await _dataSource.deleteAudioAttachmentsForNote(noteId);
    }

    @override
    Future<List<AudioAttachment>> attachmentsForNote(int noteId) async {
      final rows = await _dataSource.audioAttachmentsForNote(noteId);
      return rows
          .map(
            (row) => AudioAttachment(
              id: row['id'] as String,
              noteId: row['noteId'] as int,
              filePath: row['filePath'] as String,
              durationMs: row['durationMs'] as int,
              waveform: (jsonDecode(row['waveformData'] as String) as List)
                  .cast<num>()
                  .map((n) => n.toDouble())
                  .toList(),
              createdAt: DateTime.parse(row['createdAt'] as String),
            ),
          )
          .toList();
    }
  }
  ```
  Add these four small methods to `LocalNoteDataSourceImpl` in `local_note_datasource.dart` (the repository above calls them; keeping raw SQL inside the datasource, matching this file's existing single-responsibility-for-SQL convention):
  ```dart
  Future<void> insertAudioAttachment({
    required String id,
    required int noteId,
    required String filePath,
    required int durationMs,
    required String waveformData,
    required String createdAt,
  }) async {
    final db = await database;
    await db.insert(_audioAttachmentsTable, {
      'id': id,
      'noteId': noteId,
      'filePath': filePath,
      'durationMs': durationMs,
      'waveformData': waveformData,
      'createdAt': createdAt,
    });
  }

  Future<void> deleteAudioAttachment(String id) async {
    final db = await database;
    await db.delete(_audioAttachmentsTable, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAudioAttachmentsForNote(int noteId) async {
    final db = await database;
    await db.delete(_audioAttachmentsTable, where: 'noteId = ?', whereArgs: [noteId]);
  }

  Future<List<Map<String, Object?>>> audioAttachmentsForNote(int noteId) async {
    final db = await database;
    return db.query(_audioAttachmentsTable, where: 'noteId = ?', whereArgs: [noteId]);
  }

  Future<Map<String, Object?>?> getAudioAttachment(String id) async {
    final db = await database;
    final rows = await db.query(_audioAttachmentsTable, where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : rows.first;
  }
  ```
  Run `flutter pub add uuid` first if this project does not already depend on it - check `pubspec.yaml` before adding; this project may already have a UUID generator in use elsewhere (grep for `Uuid()`/`package:uuid` before assuming it needs adding).
- [ ] **Step 5: Wire cleanup into `NoteRepositoryImpl.deleteNote`.** In `note_repository_impl.dart`, add a constructor dependency and the cleanup call:
  ```dart
  class NoteRepositoryImpl implements NoteRepository {
    NoteRepositoryImpl({
      required this.localDataSource,
      required AudioAttachmentRepository audioAttachmentRepository,
      // ...existing constructor params unchanged...
    }) : _audioAttachmentRepository = audioAttachmentRepository;

    final AudioAttachmentRepository _audioAttachmentRepository;
    // ...existing fields unchanged...

    @override
    Future<int> deleteNote(int id) async {
      final deleted = await localDataSource.deleteNote(id);
      if (deleted == 1) {
        try {
          await _audioAttachmentRepository.deleteAttachmentsForNote(id);
        } catch (e) {
          // A secondary-cleanup failure must never make note deletion itself
          // fail from the caller's point of view - the note is already gone.
          debugPrint('audio attachment cleanup failed for note $id: $e');
        }
      }
      return deleted;
    }
  }
  ```
  Read the actual current constructor and `deleteNote` body first (`note_repository_impl.dart` may have more existing constructor params than shown above) - this step must merge into what's really there, not overwrite it. Add `import 'package:flutter/foundation.dart' show debugPrint;` if not already imported.
  Update wherever `NoteRepositoryImpl(...)` is constructed (its Riverpod provider - grep for `NoteRepositoryImpl(` to find every call site) to pass the new `audioAttachmentRepository` argument, constructing an `AudioAttachmentRepositoryImpl(dataSource: ...)` there using whatever `LocalNoteDataSourceImpl` instance that provider already has access to.
- [ ] **Step 6: Run to verify pass, plus the existing note-repository/deleteNote test(s) for regressions:**
  ```bash
  flutter test test/features/notes/data/repositories/audio_attachment_repository_test.dart
  flutter test test/features/notes/data/repositories/  # or the specific file covering NoteRepositoryImpl.deleteNote
  ```
- [ ] **Step 7: Gate.**
  ```bash
  flutter analyze --fatal-infos --fatal-warnings
  flutter test --concurrency=1
  dart format --output=none --set-exit-if-changed lib test
  bun .gitnexus/run.cjs analyze --index-only
  bun .gitnexus/run.cjs detect-changes --scope staged --repo .
  ```
- [ ] **Step 8: Commit.**
  ```bash
  git add lib/features/notes/data/datasources/local_note_datasource.dart \
          lib/features/notes/data/repositories/audio_attachment_repository.dart \
          lib/features/notes/data/repositories/note_repository_impl.dart \
          test/features/notes/data/repositories/audio_attachment_repository_test.dart
  git commit -m "feat(audio-memo): add note_audio_attachments (schema v8) and AudioAttachmentRepository"
  ```

---

### Task 5: Riverpod providers

**Files:**
- Create: `lib/features/notes/presentation/providers/audio_recording_service_provider.dart`
- Create: `lib/features/notes/presentation/providers/audio_attachment_repository_provider.dart`
- Test: `test/features/notes/presentation/providers/audio_recording_service_provider_test.dart`

**Interfaces:**
- Consumes: `AudioRecordingService` (Task 3), `AudioAttachmentRepositoryImpl`/`LocalNoteDataSourceImpl` (Task 4), `localNoteDataSourceProvider` (already exists - `lib/features/notes/presentation/providers/local_note_datasource_provider.dart`).
- Produces: `audioRecordingServiceProvider` (autoDispose `@riverpod` provider returning `AudioRecordingService`), `audioAttachmentRepositoryProvider` (`@riverpod` provider - NOT autoDispose, since attachment data should be queryable across the note's lifetime the same way other note-data providers are; mirror whichever disposal policy `local_note_datasource_provider.dart` itself uses).

**Known gotcha to build the test around (already hit in this project - see `dictation_service_provider_test.dart` and `test/features/notes/presentation/add_edit_note_page_test.dart`'s pump helpers):** an autoDispose provider read via `container.read(x)` before `pumpWidget` can get disposed and silently rebuild if nothing is listening to it yet. Add `container.listen(audioRecordingServiceProvider, (_, _) {});` right after any such read in tests.

- [ ] **Step 1: Write the failing test.** Create `test/features/notes/presentation/providers/audio_recording_service_provider_test.dart`:
  ```dart
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';

  import 'package:flutter_clean_notes/features/notes/presentation/providers/audio_recording_service_provider.dart';
  import 'package:flutter_clean_notes/features/notes/presentation/services/audio_recording_service.dart';

  void main() {
    test('provides an AudioRecordingService and disposes it when the container is disposed', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final service = container.read(audioRecordingServiceProvider);
      container.listen(audioRecordingServiceProvider, (_, _) {});

      expect(service, isA<AudioRecordingService>());
      expect(service.currentState, AudioRecordingState.idle);

      container.dispose();

      expect(
        () => service.stateStream.listen((_) {}),
        throwsStateError,
      );
    });
  }
  ```
- [ ] **Step 2: Run to verify it fails:**
  ```bash
  flutter test test/features/notes/presentation/providers/audio_recording_service_provider_test.dart
  ```
- [ ] **Step 3: Implement.** Create `lib/features/notes/presentation/providers/audio_recording_service_provider.dart`:
  ```dart
  import 'package:riverpod_annotation/riverpod_annotation.dart';

  import 'package:flutter_clean_notes/features/notes/presentation/services/audio_recording_service.dart';

  part 'audio_recording_service_provider.g.dart';

  @riverpod
  AudioRecordingService audioRecordingService(Ref ref) {
    final service = AudioRecordingService();
    ref.onDispose(service.dispose);
    return service;
  }
  ```
  Read `lib/features/notes/presentation/providers/local_note_datasource_provider.dart` first to copy its exact disposal-policy convention (autoDispose or not, `keepAlive`, etc.) before writing `audio_attachment_repository_provider.dart` - match it exactly, don't guess:
  ```dart
  import 'package:riverpod_annotation/riverpod_annotation.dart';

  import 'package:flutter_clean_notes/features/notes/data/repositories/audio_attachment_repository.dart';
  import 'package:flutter_clean_notes/features/notes/presentation/providers/local_note_datasource_provider.dart';

  part 'audio_attachment_repository_provider.g.dart';

  @riverpod
  AudioAttachmentRepository audioAttachmentRepository(Ref ref) {
    final dataSource = ref.watch(localNoteDataSourceProvider);
    return AudioAttachmentRepositoryImpl(dataSource: dataSource);
  }
  ```
  (Adjust `ref.watch(localNoteDataSourceProvider)`'s exact usage to match how that provider is actually consumed elsewhere - e.g. it may itself be a `FutureProvider`/async value requiring `.value` or `await`; check `note_providers.dart` for a real example of consuming it before assuming a plain synchronous read works.)
- [ ] **Step 4:** Run codegen and verify no drift:
  ```bash
  dart run build_runner build --delete-conflicting-outputs
  ```
- [ ] **Step 5: Run the test to verify it passes:**
  ```bash
  flutter test test/features/notes/presentation/providers/audio_recording_service_provider_test.dart
  ```
- [ ] **Step 6: Gate.**
  ```bash
  flutter analyze --fatal-infos --fatal-warnings
  dart format --output=none --set-exit-if-changed lib test
  bun .gitnexus/run.cjs analyze --index-only
  bun .gitnexus/run.cjs detect-changes --scope staged --repo .
  ```
- [ ] **Step 7: Commit.**
  ```bash
  git add lib/features/notes/presentation/providers/audio_recording_service_provider.dart \
          lib/features/notes/presentation/providers/audio_recording_service_provider.g.dart \
          lib/features/notes/presentation/providers/audio_attachment_repository_provider.dart \
          lib/features/notes/presentation/providers/audio_attachment_repository_provider.g.dart \
          test/features/notes/presentation/providers/audio_recording_service_provider_test.dart
  git commit -m "feat(audio-memo): add audioRecordingServiceProvider and audioAttachmentRepositoryProvider"
  ```

---

### Task 6: `AudioRecordButton` widget

**Files:**
- Create: `lib/features/notes/presentation/widgets/audio_record_button.dart`
- Test: `test/features/notes/presentation/widgets/audio_record_button_test.dart`

**Interfaces:**
- Consumes: `audioRecordingServiceProvider` (Task 5), `AudioRecordingState`/`AudioRecordingService`/`isAudioRecordingSupported()` (Task 3), `audioAttachmentRepositoryProvider` (Task 5), `buildAudioEmbed` (Task 4).
- Produces: `AudioRecordButton` widget, constructor `AudioRecordButton({required TextEditingController controller, required int noteId, bool enabled = true, bool autoStart = false, super.key})`. On a successful `stop()` result, calls `audioAttachmentRepository.addAttachment(...)`, then inserts `buildAudioEmbed(id)` into `controller` at the selection captured when recording started.

- [ ] **Step 1: Write the failing widget test.** Create `test/features/notes/presentation/widgets/audio_record_button_test.dart`:
  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';

  import 'package:flutter_clean_notes/features/notes/data/repositories/audio_attachment_repository.dart';
  import 'package:flutter_clean_notes/features/notes/presentation/providers/audio_attachment_repository_provider.dart';
  import 'package:flutter_clean_notes/features/notes/presentation/providers/audio_recording_service_provider.dart';
  import 'package:flutter_clean_notes/features/notes/presentation/services/audio_recording_service.dart';
  import 'package:flutter_clean_notes/features/notes/presentation/widgets/audio_record_button.dart';

  import '../../../../helpers/fake_permission_requester.dart';
  import '../../../../helpers/fake_recorder.dart';

  class _FakeAudioAttachmentRepository implements AudioAttachmentRepository {
    int addCalls = 0;
    String nextId = 'attachment-1';

    @override
    Future<String> addAttachment({
      required int noteId,
      required String filePath,
      required int durationMs,
      required List<double> waveform,
    }) async {
      addCalls += 1;
      return nextId;
    }

    @override
    Future<void> deleteAttachment(String id) async {}

    @override
    Future<void> deleteAttachmentsForNote(int noteId) async {}

    @override
    Future<List<AudioAttachment>> attachmentsForNote(int noteId) async => const [];
  }

  Future<({FakeRecorder recorder, _FakeAudioAttachmentRepository repo})> _pump(
    WidgetTester tester,
    TextEditingController controller, {
    bool enabled = true,
  }) async {
    final recorder = FakeRecorder();
    final repo = _FakeAudioAttachmentRepository();
    final container = ProviderContainer(
      overrides: [
        audioRecordingServiceProvider.overrideWith(
          (ref) => AudioRecordingService(
            recorder: recorder,
            permissions: FakePermissionRequester(),
          ),
        ),
        audioAttachmentRepositoryProvider.overrideWith((ref) => repo),
      ],
    );
    addTearDown(container.dispose);
    container.listen(audioRecordingServiceProvider, (_, _) {});

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: AudioRecordButton(controller: controller, noteId: 1, enabled: enabled),
          ),
        ),
      ),
    );
    return (recorder: recorder, repo: repo);
  }

  void main() {
    testWidgets('tapping the record icon starts recording', (tester) async {
      final controller = TextEditingController();
      final fakes = await _pump(tester, controller);

      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pump();

      expect(fakes.recorder.startCalls, 1);
    });

    testWidgets('stopping inserts the audio embed at the cursor recording started at', (tester) async {
      final controller = TextEditingController(text: 'Hello ')
        ..selection = const TextSelection.collapsed(offset: 6);
      final fakes = await _pump(tester, controller);
      fakes.recorder.nextStopResult = const AudioRecordingResult(
        filePath: '/tmp/rec.m4a',
        durationMs: 3000,
        waveform: [0.1, 0.2],
      );

      await tester.tap(find.byIcon(Icons.mic_none_rounded));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.stop_circle_rounded));
      await tester.pumpAndSettle();

      expect(fakes.repo.addCalls, 1);
      expect(controller.text, 'Hello ![audio](attachment://attachment-1)');
    });

    testWidgets('disabled when enabled is false', (tester) async {
      final controller = TextEditingController();
      await _pump(tester, controller, enabled: false);

      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.onPressed, isNull);
    });
  }
  ```
- [ ] **Step 2: Run to verify it fails:**
  ```bash
  flutter test test/features/notes/presentation/widgets/audio_record_button_test.dart
  ```
- [ ] **Step 3: Implement.** Create `lib/features/notes/presentation/widgets/audio_record_button.dart`:
  ```dart
  import 'dart:async';

  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';

  import 'package:flutter_clean_notes/features/notes/data/repositories/audio_attachment_repository.dart';
  import 'package:flutter_clean_notes/features/notes/presentation/providers/audio_attachment_repository_provider.dart';
  import 'package:flutter_clean_notes/features/notes/presentation/providers/audio_recording_service_provider.dart';
  import 'package:flutter_clean_notes/features/notes/presentation/services/audio_recording_service.dart';

  class AudioRecordButton extends ConsumerStatefulWidget {
    const AudioRecordButton({
      required this.controller,
      required this.noteId,
      this.enabled = true,
      this.autoStart = false,
      super.key,
    });

    final TextEditingController controller;
    final int noteId;
    final bool enabled;
    final bool autoStart;

    @override
    ConsumerState<AudioRecordButton> createState() => _AudioRecordButtonState();
  }

  class _AudioRecordButtonState extends ConsumerState<AudioRecordButton> {
    AudioRecordingState _state = AudioRecordingState.idle;
    AudioRecordingService? _service;
    StreamSubscription<AudioRecordingState>? _stateSub;
    int? _pendingInsertOffset;
    bool _autoStarted = false;

    @override
    Widget build(BuildContext context) {
      final service = ref.watch(audioRecordingServiceProvider);
      _subscribeIfNeeded(service);
      _maybeAutoStart(service);

      return IconButton(
        tooltip: _state == AudioRecordingState.unavailable
            ? 'editor.audioRecordUnavailable'.tr()
            : 'editor.audioRecord'.tr(),
        icon: Icon(
          _state == AudioRecordingState.recording
              ? Icons.stop_circle_rounded
              : Icons.mic_none_rounded,
        ),
        onPressed: (!widget.enabled || !isAudioRecordingSupported() || _state == AudioRecordingState.unavailable)
            ? null
            : () => _toggle(service),
      );
    }

    void _subscribeIfNeeded(AudioRecordingService service) {
      if (identical(_service, service)) return;
      _stateSub?.cancel();
      _service = service;
      _state = service.currentState;
      _stateSub = service.stateStream.listen(_handleState);
    }

    void _maybeAutoStart(AudioRecordingService service) {
      if (_autoStarted || !widget.autoStart) return;
      _autoStarted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _toggle(service));
    }

    void _handleState(AudioRecordingState state) {
      if (!mounted) return;
      setState(() => _state = state);
      if (state == AudioRecordingState.error) {
        _showSnackBar('editor.audioRecordError'.tr());
      } else if (state == AudioRecordingState.unavailable) {
        _showSnackBar('editor.audioRecordUnavailable'.tr());
      } else if (state == AudioRecordingState.permissionDenied) {
        _showSnackBar('editor.dictationPermissionDenied'.tr());
      } else if (state == AudioRecordingState.permissionPermanentlyDenied) {
        _showSnackBar('editor.dictationPermissionPermanentlyDenied'.tr());
      }
    }

    void _showSnackBar(String message) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    }

    Future<void> _toggle(AudioRecordingService service) async {
      if (_state == AudioRecordingState.recording) {
        final result = await service.stop();
        if (result == null || !mounted) return;
        final repo = ref.read(audioAttachmentRepositoryProvider);
        final id = await repo.addAttachment(
          noteId: widget.noteId,
          filePath: result.filePath,
          durationMs: result.durationMs,
          waveform: result.waveform,
        );
        _insertEmbed(id);
      } else {
        _pendingInsertOffset = widget.controller.selection.isValid
            ? widget.controller.selection.start
            : widget.controller.text.length;
        await service.start();
      }
    }

    void _insertEmbed(String attachmentId) {
      final controller = widget.controller;
      final offset = _pendingInsertOffset ?? controller.text.length;
      final embed = buildAudioEmbed(attachmentId);
      final newText = controller.text.replaceRange(offset, offset, embed);
      controller.value = controller.value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: offset + embed.length),
        composing: TextRange.empty,
      );
    }

    @override
    void dispose() {
      _stateSub?.cancel();
      super.dispose();
    }
  }
  ```
  Add `import 'package:easy_localization/easy_localization.dart';` for the `.tr()` extension used above (omitted from the block for brevity - it is required).
- [ ] **Step 4: Run to verify pass:**
  ```bash
  flutter test test/features/notes/presentation/widgets/audio_record_button_test.dart
  ```
- [ ] **Step 5:** Add the three new translation keys used above (`editor.audioRecord`, `editor.audioRecordUnavailable`, `editor.audioRecordError`) to both `assets/translations/en.json` and `assets/translations/vi.json` (the `editor.dictationPermissionDenied`/`editor.dictationPermissionPermanentlyDenied` keys are reused as-is from Phase 2A, not duplicated). Suggested copy: en `"audioRecord": "Record audio", "audioRecordUnavailable": "Audio recording unavailable", "audioRecordError": "Recording stopped due to an error"`; vi `"audioRecord": "Ghi âm", "audioRecordUnavailable": "Không thể ghi âm", "audioRecordError": "Ghi âm đã dừng do lỗi"`.
- [ ] **Step 6: Gate.**
  ```bash
  flutter analyze --fatal-infos --fatal-warnings
  dart format --output=none --set-exit-if-changed lib test
  bun .gitnexus/run.cjs analyze --index-only
  bun .gitnexus/run.cjs detect-changes --scope staged --repo .
  ```
- [ ] **Step 7: Commit.**
  ```bash
  git add lib/features/notes/presentation/widgets/audio_record_button.dart \
          test/features/notes/presentation/widgets/audio_record_button_test.dart \
          assets/translations/en.json assets/translations/vi.json
  git commit -m "feat(audio-memo): add AudioRecordButton widget"
  ```

---

### Task 7: `AudioPlayerBlock` widget + wire both into the note editor

**Files:**
- Create: `lib/features/notes/presentation/widgets/audio_player_block.dart`
- Modify: `lib/features/notes/presentation/widgets/editor_formatting_bar.dart`
- Modify: `lib/features/notes/presentation/pages/add_edit_note_page.dart`
- Modify: `test/features/notes/presentation/editor_formatting_bar_test.dart`
- Modify: `test/features/notes/presentation/add_edit_note_page_test.dart`
- Test: `test/features/notes/presentation/widgets/audio_player_block_test.dart`

**Interfaces:**
- Consumes: `AudioRecordButton` (Task 6), `AudioAttachment`/`audioAttachmentRepositoryProvider` (Task 4/5), `just_audio`.
- Produces: `AudioPlayerBlock` widget, constructor `AudioPlayerBlock({required String attachmentId, super.key})` - looks up the attachment by id (via `audioAttachmentRepositoryProvider`, matched against `noteId` is not needed here since ids are globally unique), renders waveform + play/pause + speed (1x/1.25x/1.5x/2x) + skip ±5s/±10s, or the reused "unavailable" placeholder if the attachment/file can't be found.

**Before editing:** run GitNexus impact analysis on `EditorFormattingBar` and `AddEditNotePage` first, per CLAUDE.md:
```bash
bun .gitnexus/run.cjs impact "EditorFormattingBar" --direction upstream --repo .
bun .gitnexus/run.cjs impact "AddEditNotePage" --direction upstream --repo .
```
Confirm risk before proceeding; `AddEditNotePage` is a large, central file - stop and flag if either comes back HIGH/CRITICAL or UNKNOWN rather than proceeding on judgment alone.

- [ ] **Step 1: Write the failing tests.**

  Create `test/features/notes/presentation/widgets/audio_player_block_test.dart`:
  ```dart
  import 'package:flutter/material.dart';
  import 'package:flutter_riverpod/flutter_riverpod.dart';
  import 'package:flutter_test/flutter_test.dart';

  import 'package:flutter_clean_notes/features/notes/data/repositories/audio_attachment_repository.dart';
  import 'package:flutter_clean_notes/features/notes/presentation/providers/audio_attachment_repository_provider.dart';
  import 'package:flutter_clean_notes/features/notes/presentation/widgets/audio_player_block.dart';

  class _FakeAudioAttachmentRepository implements AudioAttachmentRepository {
    final Map<String, AudioAttachment> byId = {};

    @override
    Future<String> addAttachment({
      required int noteId,
      required String filePath,
      required int durationMs,
      required List<double> waveform,
    }) async => throw UnimplementedError();

    @override
    Future<void> deleteAttachment(String id) async {}

    @override
    Future<void> deleteAttachmentsForNote(int noteId) async {}

    @override
    Future<List<AudioAttachment>> attachmentsForNote(int noteId) async =>
        byId.values.where((a) => a.noteId == noteId).toList();

    Future<AudioAttachment?> byAttachmentId(String id) async => byId[id];
  }

  void main() {
    testWidgets('renders waveform/player controls for a known attachment', (tester) async {
      final repo = _FakeAudioAttachmentRepository()
        ..byId['a1'] = AudioAttachment(
          id: 'a1',
          noteId: 1,
          filePath: '/tmp/does-not-exist.m4a',
          durationMs: 4000,
          waveform: const [0.1, 0.5, 0.2],
          createdAt: DateTime.now(),
        );
      final container = ProviderContainer(
        overrides: [audioAttachmentRepositoryProvider.overrideWith((ref) => repo)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: AudioPlayerBlock(attachmentId: 'a1'))),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    });

    testWidgets('shows the unavailable placeholder for an unknown attachment id', (tester) async {
      final repo = _FakeAudioAttachmentRepository();
      final container = ProviderContainer(
        overrides: [audioAttachmentRepositoryProvider.overrideWith((ref) => repo)],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: AudioPlayerBlock(attachmentId: 'missing'))),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    });
  }
  ```
  Add to `test/features/notes/presentation/editor_formatting_bar_test.dart` (append, following this file's existing `_pumpBar` conventions - already extended once in Phase 2A's Task 5 to include a `ProviderScope`; extend the same override list with `audioRecordingServiceProvider`/`audioAttachmentRepositoryProvider` overrides the same way):
  ```dart
  testWidgets('renders an audio record control alongside formatting controls', (tester) async {
    final controller = TextEditingController();
    await _pumpBar(tester, controller);

    expect(find.byIcon(Icons.mic_none_rounded), findsNWidgets(2), reason: 'dictation mic + audio record both use mic_none_rounded when idle - distinguish by tooltip if this fails ambiguously');
  });
  ```
  (If the dictation mic and audio record icons being visually identical when idle makes this test ambiguous once written, give `AudioRecordButton` a distinct idle icon, e.g. `Icons.fiber_manual_record_outlined`, instead of reusing `Icons.mic_none_rounded` - resolve this during Step 2 below, before Step 3, since it affects Task 6's already-written `audio_record_button_test.dart` too; if changed, update Task 6's tests to match and note the icon change in this task's commit message.)
- [ ] **Step 2: Run to verify they fail:**
  ```bash
  flutter test test/features/notes/presentation/widgets/audio_player_block_test.dart
  flutter test test/features/notes/presentation/editor_formatting_bar_test.dart
  ```
- [ ] **Step 3: Implement `AudioPlayerBlock`.** Create `lib/features/notes/presentation/widgets/audio_player_block.dart` using `just_audio`'s `AudioPlayer` (`setFilePath`, `play`/`pause`, `setSpeed(double)`, `seek(Duration)`, `positionStream`/`durationStream` - **verify these exact method/stream names against the resolved `just_audio` version before finalizing**, same convention as Task 3's `PlatformRecorder`). Render: a `CustomPaint`-based waveform from `attachment.waveform` (simple bar visualization, no external charting package), a play/pause `IconButton`, a duration label, a speed `DropdownButton`/cycling button (1x/1.25x/1.5x/2x), two skip `IconButton`s (±5s handled via one tap, ±10s via a second control or a long-press - implementer's choice of exact interaction, but both must exist per the spec), and a delete `IconButton` (`Icons.delete_outline_rounded`, `key: Key('audio-player-delete-$attachmentId')`) that calls `audioAttachmentRepositoryProvider`'s `deleteAttachment(attachmentId)` and, via a required `VoidCallback onDeleted` constructor param, tells the caller (Task 7 Step 5's wiring) to remove the embed line from the note's text - `AudioPlayerBlock` itself does not have access to the note's `TextEditingController`, so it must not try to edit the note text directly. If `attachment` is null (id not found) or the file at `attachment.filePath` does not exist on disk (`File(path).existsSync()`), render the same placeholder pattern as `add_edit_note_page.dart`'s existing `imageBuilder` unavailable state (`Icons.image_not_supported_outlined`, same `Semantics`/`DecoratedBox` structure) with `editor.audioUnavailable`.tr() as the label (new translation key, both locales, same style as `editor.imageUnavailable`) - no delete button in this state (nothing valid to delete by id if the row itself is already gone; if the row exists but the file is missing, still show delete so the user can clear the dead reference).
- [ ] **Step 4: Add a silent "ensure persisted" path to `AddEditNotePage`, for recording on a brand-new note.** Read this plan's Review Focus entry on this exact scenario first. `AddEditNotePage._saveNote()` (line ~722) is an explicit, user-triggered save-and-close action - there is no autosave to reuse. Add a new private method, sibling to `_saveNote()`:
  ```dart
  Future<int> _ensureNotePersisted() async {
    if (_persistedId != null) return _persistedId!;
    final note = Note(
      id: null,
      title: _titleController.text.trim(),
      content: _contentController.text.trim(),
      color: _selectedColor.toARGB32(),
      createdAt: _createdAt,
      isPinned: _isPinned,
      tags: List<String>.unmodifiable(_tags),
      status: _status,
      reminder: _reminder,
    );
    final notifier = ref.read(notesProvider.notifier);
    final persisted = await notifier.addNote(note, now: widget.now);
    // Match whatever addNote's real return shape is (an id, or a Note with
    // an id, or void with the id readable back from `notesProvider` state
    // afterward) - read `notesProvider`'s `addNote` implementation before
    // writing this line; this plan assumes it returns something the id can
    // be read from, verify rather than assume.
    _persistedId = /* extracted id */;
    return _persistedId!;
  }
  ```
  This deliberately skips `_saveNote()`'s blank-content validation (`title.isEmpty && content.isEmpty` guard) and its `_requestClose()`/`_saving` UI-state changes - starting a recording is not the same user action as tapping save, and must not navigate the user out of the editor or block on the same validation a real save enforces. A later explicit `_saveNote()` on the same page must see `_persistedId != null` and go through its existing update path, not create a second note - this is already `_saveNote()`'s existing behavior (line 774's `if (_persistedId == null)` branch), so no change needed there, only confirm it with the test in Step 6.
- [ ] **Step 5: Wire `AudioRecordButton` into `EditorFormattingBar`.** In `editor_formatting_bar.dart`, import `audio_record_button.dart`, replace `EditorFormattingBar`'s implicit `noteId` requirement with a `Future<int> Function() ensureNoteId` constructor parameter (not a plain `int? noteId` - the id may not exist yet, per Step 4) threaded straight through to `AudioRecordButton`'s own `required Future<int> Function() ensureNoteId` param (replacing Task 6's originally-planned plain `required int noteId` - update Task 6's `AudioRecordButton` constructor and its `_toggle`'s start branch to `final noteId = await widget.ensureNoteId();` before calling `service.start()`, and update `audio_record_button_test.dart`'s `_pump` helper to pass `ensureNoteId: () async => 1` in place of the plain `noteId: 1` it used in Task 6 - note this discrepancy explicitly in this task's commit message, since it changes an interface Task 6 already committed). In `add_edit_note_page.dart`, pass `ensureNoteId: _ensureNotePersisted` into `EditorFormattingBar(...)`, and add `AudioRecordButton`... already added via `EditorFormattingBar`'s own controls list (no separate call needed here beyond what Task 6 wired into `EditorFormattingBar.build()`'s `controls`).
- [ ] **Step 6: Wire the Markdown embed renderer and the delete-removes-embed-line behavior.** In `add_edit_note_page.dart`, extend the existing `MarkdownBody.imageBuilder` callback: parse the image `Uri` it receives (the callback's first positional parameter, currently unused/`_`) and check `uri.scheme == 'attachment'`; if so, `return AudioPlayerBlock(attachmentId: uri.host, onDeleted: () => _removeAudioEmbedFromBody(uri.host));` (host, since `attachment://<id>` puts the id in the URI's host position - confirm this parses as expected with a quick `Uri.parse('attachment://abc-123').host == 'abc-123'` sanity check while implementing, and adjust to `.path` instead if it does not); otherwise keep the existing unavailable-placeholder behavior unchanged for real image URLs. Add a new private method:
  ```dart
  void _removeAudioEmbedFromBody(String attachmentId) {
    setState(() {
      _contentController.text = removeAudioEmbed(_contentController.text, attachmentId);
    });
  }
  ```
  (imports `removeAudioEmbed` from Task 4's `audio_attachment_repository.dart`.)
  Add the `autoStartRecording` constructor param to `AddEditNotePage`: `this.autoStartRecording = false,` alongside `this.initialContent`, threaded down to `EditorFormattingBar`/`AudioRecordButton`'s own `autoStart`.
  In `lib/app/router.dart`'s `/note/new` route builder, add:
  ```dart
  final autoStartRecording = state.uri.queryParameters['action'] == 'record';
  ```
  and pass `autoStartRecording: autoStartRecording` into the `AddEditNotePage(...)` constructor call, alongside the existing `initialContent`.
- [ ] **Step 7: Write the failing test for the "ensure persisted" behavior.** Add to `test/features/notes/presentation/add_edit_note_page_test.dart` (follow this file's existing pump-helper and `notesProvider` fake/override conventions exactly - read the file first rather than guessing its setup):
  ```dart
  testWidgets('starting a recording on a brand-new note persists it exactly once', (tester) async {
    // Pump a brand-new (no `note:` param) AddEditNotePage per this file's
    // existing convention for that case, with a way to observe/count calls
    // into notesProvider's addNote (spy on the fake note repository this
    // file's harness already injects - check its shape before writing this
    // assertion, do not invent a new fake).
    // ...pump...

    await tester.tap(find.byIcon(Icons.mic_none_rounded)); // or the distinct
    // audio-record icon if Task 7 Step 1's icon-collision note applied
    await tester.pump();

    // Assert exactly one addNote call happened as a result of starting the
    // recording (not on pumpWidget, not twice).

    await tester.tap(find.byIcon(Icons.stop_circle_rounded));
    await tester.pumpAndSettle();

    // Assert still exactly one addNote call total after stopping too - the
    // second recording session (if the test starts one) or an explicit save
    // afterward must update the same persisted id, never insert a second
    // note. Adjust exact assertions to whatever spy/fake mechanism this
    // file's existing tests already use for notesProvider.
  });
  ```
- [ ] **Step 8: Run to verify it fails, then the full existing `add_edit_note_page_test.dart` suite plus the other two files touched this task, for regressions:**
  ```bash
  flutter test test/features/notes/presentation/widgets/audio_player_block_test.dart
  flutter test test/features/notes/presentation/editor_formatting_bar_test.dart
  flutter test test/features/notes/presentation/add_edit_note_page_test.dart
  ```
- [ ] **Step 9:** Add `editor.audioUnavailable` to both translation files (en: "Audio unavailable", vi: "Không có âm thanh").
- [ ] **Step 10: Gate.**
  ```bash
  flutter analyze --fatal-infos --fatal-warnings
  flutter test --concurrency=1
  dart format --output=none --set-exit-if-changed lib test
  bun .gitnexus/run.cjs analyze --index-only
  bun .gitnexus/run.cjs detect-changes --scope staged --repo .
  ```
- [ ] **Step 11: Commit.**
  ```bash
  git add lib/features/notes/presentation/widgets/audio_player_block.dart \
          lib/features/notes/presentation/widgets/editor_formatting_bar.dart \
          lib/features/notes/presentation/pages/add_edit_note_page.dart \
          lib/app/router.dart \
          test/features/notes/presentation/widgets/audio_player_block_test.dart \
          test/features/notes/presentation/editor_formatting_bar_test.dart \
          test/features/notes/presentation/add_edit_note_page_test.dart \
          assets/translations/en.json assets/translations/vi.json
  git commit -m "feat(audio-memo): wire AudioRecordButton + AudioPlayerBlock into the note editor"
  ```

---

### Task 8: Home Screen Widget quick-record shortcut

**Files:**
- Modify: `android/app/src/main/kotlin/com/example/flutter_clean_notes/QuickActionsWidget.kt`
- Modify iOS widget equivalent: `ios/CleanNotesWidgetExtension/QuickActionsWidget.swift`
- Modify: `lib/app/router.dart` (if the widget click doesn't already route through `WidgetLaunchCoordinator.resolveRoute` correctly for a `clean-notes://new?action=record` URI - verify first with the existing test suite for that file before assuming a change is needed here; §"Verify first" step below)

**Interfaces:**
- Consumes: `clean-notes://new?action=record` deep link, already correctly forwarded to `/note/new?action=record` by `WidgetLaunchCoordinator.resolveRoute`'s existing query-parameter passthrough (verified while writing this plan - no code change needed in `widget_launch_coordinator.dart` itself, only in what URI the native widget button sends).
- Produces: a new tappable shortcut on the existing Quick Capture Widget (Android `Glance`/`AppWidgetProvider` layout and iOS `WidgetKit` layout, both already shipped in Phase 1) that opens `clean-notes://new?action=record` instead of plain `clean-notes://new`.

- [ ] **Step 1: Verify the existing deep-link routing needs no change.** Run:
  ```bash
  flutter test test/app/  # or wherever widget_launch_coordinator_test.dart lives - locate it first
  ```
  Add one new test case to that existing test file confirming `WidgetLaunchCoordinator.resolveRoute(Uri.parse('clean-notes://new?action=record'))` returns `/note/new?action=record` - this should already pass against the current implementation (§3's investigation confirmed the existing query-parameter passthrough at `router.dart`/`widget_launch_coordinator.dart` handles this with zero code changes); if it does NOT pass, the passthrough behavior assumed by this plan was wrong and Task 7's router change needs revisiting before continuing this task.
- [ ] **Step 2: Add the Android shortcut.** Read `QuickActionsWidget.kt` in full first to find how the existing shortcuts (note nhanh, tìm kiếm) are defined (`PendingIntent`s built from `clean-notes://` URIs, per this project's session-handoff docs describing the Phase 1 widget work and its `FLAG_IMMUTABLE` hardening) and add a new button following the exact same pattern, with `Uri.parse("clean-notes://new?action=record")` as its target and the layout resource updated to include a new record-icon button (check `res/layout/` for the widget's existing layout XML and add the new button element there, matching the existing buttons' styling).
- [ ] **Step 3: Add the iOS shortcut.** Read `ios/CleanNotesWidgetExtension/QuickActionsWidget.swift` in full first (this file already implements the Phase 1 Quick Capture Widget's SwiftUI layout and `widgetURL`/`Link` targets) and add a new button following the exact same pattern, with `URL(string: "clean-notes://new?action=record")!` as its target.
- [ ] **Step 4: Manual verification** (this step cannot be TDD'd - native widget layout has no automated test in this project, matching Phase 1's own precedent): install the app via `flutter run` (not a manual build+install - this project's own documented lesson from Phase 1's widget QA is that `flutter run` is required for correct native registration), add the Quick Capture Widget to the home screen if not already there, tap the new record shortcut, confirm the app opens with a new note and starts recording automatically.
- [ ] **Step 5: Gate.**
  ```bash
  flutter analyze --fatal-infos --fatal-warnings
  flutter test --concurrency=1
  dart format --output=none --set-exit-if-changed lib test
  bun .gitnexus/run.cjs analyze --index-only
  bun .gitnexus/run.cjs detect-changes --scope staged --repo .
  ```
- [ ] **Step 6: Commit.**
  ```bash
  git add android/app/src/main/kotlin/com/example/flutter_clean_notes/QuickActionsWidget.kt \
          ios/CleanNotesWidgetExtension/QuickActionsWidget.swift \
          [any modified layout/test files from Steps 1-3]
  git commit -m "feat(audio-memo): add quick-record shortcut to the Home Screen Widget"
  ```

---

### Task 9: Manual/Visual QA & Merge Readiness

**Files:** none (verification only).

- [ ] **Step 1:** On a real device if available (per this plan's Review Focus and the spec's own testing section, prefer real hardware for this task specifically - Phase 2A's QA found a real iOS Simulator CoreAudio limitation, documented in `docs/agents/session-handoff-2026-09-26.md` Part 2 item #15, that can prevent real audio I/O from working in a simulator at all), confirm: tapping the record control prompts for mic permission on first use; recording starts and the elapsed-time indicator updates; stopping inserts a player block at the right position; the player actually plays back audible recorded audio with working play/pause, speed change, and skip controls; deleting a recording removes its player block, file, and DB row.
- [ ] **Step 2:** Repeat via the Home Screen Widget quick-record shortcut (Task 8): confirm it creates a new note and starts recording automatically.
- [ ] **Step 3:** Confirm the record control is disabled (not tappable) on a desktop build (`flutter run -d macos` or similar) - no crash, no error, simply inert.
- [ ] **Step 4:** Capture screenshots (idle / recording / playback states, at least one platform, light + dark) into `docs/screenshots/`, following this project's established pre-release visual QA rule (`docs/qa.md`) and naming convention (`audio_memo_<platform>_<state>_<theme>.png`, matching `ios_dictation_*` from Phase 2A).
- [ ] **Step 5: Full-suite gate.**
  ```bash
  dart format --output=none --set-exit-if-changed lib test
  flutter analyze --fatal-infos --fatal-warnings
  flutter test --concurrency=1
  bun .gitnexus/run.cjs detect-changes --scope all --repo .
  ```
  All green; working tree clean except the new screenshots.
- [ ] **Step 6: Commit the screenshots.**
  ```bash
  git add docs/screenshots/
  git commit -m "docs(qa): add Audio Memo Recording visual QA screenshots"
  ```
