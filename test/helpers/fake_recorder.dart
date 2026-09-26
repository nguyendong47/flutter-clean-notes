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
    final error = _throwError;
    if (error != null) {
      _throwError = null;
      throw error;
    }
    _isRecording = startResult;
    return startResult;
  }

  @override
  Future<AudioRecordingResult?> stop() async {
    stopCalls += 1;
    final error = _throwError;
    if (error != null) {
      _throwError = null;
      throw error;
    }
    _isRecording = false;
    return nextStopResult;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
    final error = _throwError;
    if (error != null) {
      _throwError = null;
      throw error;
    }
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
