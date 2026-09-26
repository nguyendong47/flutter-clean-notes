import 'dart:async';

import 'package:flutter/services.dart' show MissingPluginException;
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

  test(
    'permission permanentlyDenied moves to permissionPermanentlyDenied',
    () async {
      permissions.result = DictationPermissionResult.permanentlyDenied;

      await service.start(localeId: 'en_US');

      expect(recognizer.listenCalls, 0);
      expect(service.currentState, DictationState.permissionPermanentlyDenied);
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
    'recognizer error with error_language_not_supported or error_language_unavailable moves to unavailable',
    () async {
      await service.start(localeId: 'en_US');

      recognizer.simulateError('error_language_not_supported');
      await Future<void>.delayed(Duration.zero);

      expect(service.currentState, DictationState.unavailable);
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

  test(
    'second service sharing underlying recognizer reclaims status listeners after first init',
    () async {
      final sharedSpeech = FakeSpeechToText();
      final service1 = DictationService(
        recognizer: PlatformSpeechRecognizer(sharedSpeech),
        permissions: permissions,
      );
      await service1.start(localeId: 'en_US');
      expect(sharedSpeech.initializeCallCount, 1);
      service1.dispose();

      final service2 = DictationService(
        recognizer: PlatformSpeechRecognizer(sharedSpeech),
        permissions: permissions,
      );
      await service2.start(localeId: 'en_US');
      expect(sharedSpeech.initializeCallCount, 2);
      expect(service2.currentState, DictationState.listening);

      // Simulate OS ending session on the shared speech engine
      sharedSpeech.simulateOsEndedSession();
      await Future<void>.delayed(Duration.zero);

      expect(service2.currentState, DictationState.idle);
    },
  );

  test(
    'rapid concurrent start() calls run only one sequence and allow future start()',
    () async {
      final future1 = service.start(localeId: 'en_US');
      final future2 = service.start(localeId: 'en_US');

      await Future.wait([future1, future2]);

      expect(permissions.requestCalls, 1);
      expect(recognizer.listenCalls, 1);
      expect(service.currentState, DictationState.listening);

      await service.stop();
      expect(service.currentState, DictationState.idle);

      await service.start(localeId: 'en_US');
      expect(permissions.requestCalls, 2);
      expect(recognizer.listenCalls, 2);
      expect(service.currentState, DictationState.listening);
    },
  );

  test(
    'disposing service while start() is awaiting listen cancels recognizer and prevents listening state',
    () async {
      final controllableRecognizer = _ControllableListenRecognizer();
      final inFlightService = DictationService(
        recognizer: controllableRecognizer,
        permissions: permissions,
      );

      final startFuture = inFlightService.start(localeId: 'en_US');

      inFlightService.dispose();
      expect(controllableRecognizer.cancelCalls, greaterThanOrEqualTo(1));

      controllableRecognizer.listenCompleter.complete();
      await startFuture;

      expect(inFlightService.currentState, isNot(DictationState.listening));
      expect(controllableRecognizer.cancelCalls, greaterThanOrEqualTo(1));
    },
  );

  test(
    'start() catching UnsupportedError maps to unavailable rather than generic error',
    () async {
      final unsupportedService = DictationService(
        recognizer: _UnsupportedErrorRecognizer(),
        permissions: permissions,
      );
      addTearDown(unsupportedService.dispose);

      await unsupportedService.start(localeId: 'en_US');

      expect(unsupportedService.currentState, DictationState.unavailable);
    },
  );

  test(
    'start() catching MissingPluginException maps to unavailable rather than generic error',
    () async {
      final missingPluginService = DictationService(
        recognizer: recognizer,
        permissions: _MissingPluginPermissionRequester(),
      );
      addTearDown(missingPluginService.dispose);

      await missingPluginService.start(localeId: 'en_US');

      expect(missingPluginService.currentState, DictationState.unavailable);
    },
  );

  test(
    'FakePermissionRequester.requestMicrophone returns the configured result',
    () async {
      final permissions = FakePermissionRequester(
        result: DictationPermissionResult.permanentlyDenied,
      );

      final result = await permissions.requestMicrophone();

      expect(result, DictationPermissionResult.permanentlyDenied);
    },
  );
}

class _ControllableListenRecognizer extends FakeSpeechRecognizer {
  final listenCompleter = Completer<void>();

  @override
  Future<void> listen({
    required void Function(String text, bool isFinal) onResult,
    required String localeId,
  }) async {
    listenCalls += 1;
    await listenCompleter.future;
    await super.listen(onResult: onResult, localeId: localeId);
  }
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

class _UnsupportedErrorRecognizer extends FakeSpeechRecognizer {
  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String message) onError,
  }) async {
    throw UnsupportedError('Platform._operatingSystem not supported on web');
  }
}

class _MissingPluginPermissionRequester implements PermissionRequester {
  @override
  Future<DictationPermissionResult> requestMicrophoneAndSpeech() async {
    throw MissingPluginException();
  }

  @override
  Future<DictationPermissionResult> requestMicrophone() async {
    throw MissingPluginException();
  }
}
