import 'dart:async';
import 'dart:io' show Platform;

import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String message) onError,
  });

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

  final _stateController = StreamController<DictationState>.broadcast(
    sync: true,
  );
  final _textController = StreamController<String>.broadcast(sync: true);

  DictationState _state = DictationState.idle;
  DictationState get currentState => _state;
  bool _initialized = false;
  bool _disposed = false;

  Stream<DictationState> get stateStream {
    if (_disposed) {
      throw StateError('Cannot listen to stateStream after dispose');
    }
    return _GuardedStream(_stateController.stream, () => _disposed);
  }

  Stream<String> get recognizedTextStream {
    if (_disposed) {
      throw StateError('Cannot listen to recognizedTextStream after dispose');
    }
    return _GuardedStream(_textController.stream, () => _disposed);
  }

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
    _disposed = true;
    if (_recognizer.isListening) {
      unawaited(_recognizer.cancel());
    }
    _stateController.close();
    _textController.close();
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
      listenOptions: stt.SpeechListenOptions(localeId: localeId),
      onResult: (result) =>
          onResult(result.recognizedWords, result.finalResult),
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
