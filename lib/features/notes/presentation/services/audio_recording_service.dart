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
