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

  test(
    'start() requests permission, initializes, and begins listening',
    () async {
      final states = <DictationState>[];
      service.stateStream.listen(states.add);

      await service.start(localeId: 'vi_VN');

      expect(permissions.requestCalls, 1);
      expect(recognizer.listenCalls, 1);
      expect(recognizer.lastLocaleId, 'vi_VN');
      expect(service.currentState, DictationState.listening);
      expect(states, contains(DictationState.listening));
    },
  );

  test(
    'permission denied moves to permissionDenied without calling listen',
    () async {
      permissions.granted = false;

      await service.start(localeId: 'en_US');

      expect(recognizer.listenCalls, 0);
      expect(service.currentState, DictationState.permissionDenied);
    },
  );

  test('permission denied leaves start() retriable (not stuck)', () async {
    permissions.granted = false;
    await service.start(localeId: 'en_US');
    expect(service.currentState, DictationState.permissionDenied);

    permissions.granted = true;
    await service.start(localeId: 'en_US');

    expect(recognizer.listenCalls, 1);
    expect(service.currentState, DictationState.listening);
  });

  test(
    'recognizer.initialize() returning false moves to unavailable',
    () async {
      recognizer.initializeResult = false;

      await service.start(localeId: 'en_US');

      expect(recognizer.listenCalls, 0);
      expect(service.currentState, DictationState.unavailable);
    },
  );

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

  test(
    'calling start() twice while already listening is a no-op the second time',
    () async {
      await service.start(localeId: 'en_US');
      await service.start(localeId: 'en_US');

      expect(
        recognizer.listenCalls,
        1,
        reason: 'must not start a second overlapping session',
      );
    },
  );

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

  test(
    'a mid-session recognizer error moves to error state without throwing',
    () async {
      await service.start(localeId: 'en_US');

      recognizer.simulateError('recognizer failed');
      await Future<void>.delayed(Duration.zero);

      expect(service.currentState, DictationState.error);
    },
  );

  test(
    'recognizer.listen() throwing is caught and surfaces as error, not an uncaught exception',
    () async {
      recognizer.initializeResult = true;
      final throwingRecognizer = _ThrowingListenRecognizer();
      final throwingService = DictationService(
        recognizer: throwingRecognizer,
        permissions: permissions,
      );
      addTearDown(throwingService.dispose);

      await throwingService.start(localeId: 'en_US');

      expect(throwingService.currentState, DictationState.error);
    },
  );
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
