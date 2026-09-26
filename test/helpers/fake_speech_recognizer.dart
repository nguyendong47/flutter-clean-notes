import 'dart:async';

import 'package:flutter_clean_notes/features/notes/presentation/services/dictation_service.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class FakeSpeechRecognizer implements SpeechRecognizer {
  bool initializeResult = true;
  bool _isListening = false;
  String? lastLocaleId;
  int listenCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  void Function(String text, bool isFinal)? _onResult;
  void Function(String status)? statusListener;
  void Function(String message)? errorListener;

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String message) onError,
  }) async {
    statusListener = onStatus;
    errorListener = onError;
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
    statusListener?.call('notListening');
  }

  /// Test helper: simulate a recognizer error mid-session.
  void simulateError(String message) {
    _isListening = false;
    errorListener?.call(message);
  }
}

class FakeSpeechToText implements stt.SpeechToText {
  bool initializeResult = true;
  int initializeCallCount = 0;
  bool _isListening = false;
  int listenCalls = 0;
  int stopCalls = 0;
  int cancelCalls = 0;
  String? lastLocaleId;

  @override
  stt.SpeechStatusListener? statusListener;

  @override
  stt.SpeechErrorListener? errorListener;

  @override
  Future<bool> initialize({
    stt.SpeechErrorListener? onError,
    stt.SpeechStatusListener? onStatus,
    debugLogging = false,
    Duration finalTimeout = stt.SpeechToText.defaultFinalTimeout,
    List<stt.SpeechConfigOption>? options,
  }) async {
    initializeCallCount += 1;
    if (initializeCallCount == 1) {
      statusListener = onStatus;
      errorListener = onError;
    }
    return initializeResult;
  }

  @override
  Future<bool> listen({
    stt.SpeechResultListener? onResult,
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
    stt.SpeechSoundLevelChange? onSoundLevelChange,
    cancelOnError = false,
    partialResults = true,
    onDevice = false,
    stt.ListenMode listenMode = stt.ListenMode.confirmation,
    sampleRate = 0,
    stt.SpeechListenOptions? listenOptions,
  }) async {
    listenCalls += 1;
    lastLocaleId = localeId ?? listenOptions?.localeId;
    _isListening = true;
    return true;
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

  void simulateOsEndedSession() {
    _isListening = false;
    statusListener?.call('notListening');
  }

  void simulateError(String errorMsg) {
    _isListening = false;
    errorListener?.call(SpeechRecognitionError(errorMsg, false));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
