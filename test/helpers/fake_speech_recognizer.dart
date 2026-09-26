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
