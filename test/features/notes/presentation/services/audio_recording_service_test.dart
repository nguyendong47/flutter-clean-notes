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
    service = AudioRecordingService(
      recorder: recorder,
      permissions: permissions,
    );
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

  test(
    'permission denied moves to permissionDenied without calling start',
    () async {
      permissions.result = DictationPermissionResult.denied;

      await service.start();

      expect(recorder.startCalls, 0);
      expect(service.currentState, AudioRecordingState.permissionDenied);
    },
  );

  test(
    'permission permanentlyDenied moves to permissionPermanentlyDenied',
    () async {
      permissions.result = DictationPermissionResult.permanentlyDenied;

      await service.start();

      expect(recorder.startCalls, 0);
      expect(
        service.currentState,
        AudioRecordingState.permissionPermanentlyDenied,
      );
    },
  );

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

  test(
    'stop() returning null (sub-1s recording) is treated as a discard, still returns to idle',
    () async {
      recorder.nextStopResult = null;
      await service.start();

      final result = await service.stop();

      expect(result, isNull);
      expect(service.currentState, AudioRecordingState.idle);
    },
  );

  test('stop() while idle is a safe no-op returning null', () async {
    final result = await service.stop();

    expect(result, isNull);
    expect(recorder.stopCalls, 0);
  });

  test(
    'calling start() twice while already recording is a no-op the second time',
    () async {
      await service.start();
      await service.start();

      expect(
        recorder.startCalls,
        1,
        reason: 'must not start a second overlapping recording',
      );
    },
  );

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

  test(
    'recorder.start() throwing is caught and surfaces as error, not an uncaught exception',
    () async {
      final throwingRecorder = _ThrowingStartRecorder();
      final throwingService = AudioRecordingService(
        recorder: throwingRecorder,
        permissions: permissions,
      );
      addTearDown(throwingService.dispose);

      await throwingService.start();

      expect(throwingService.currentState, AudioRecordingState.error);
    },
  );
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
