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

  testWidgets('recognized text is inserted into the controller at the cursor', (
    tester,
  ) async {
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

  testWidgets('unavailable (no recognizer for locale) disables the button', (
    tester,
  ) async {
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

  testWidgets(
    'permission denied shows a snackbar but leaves the button tappable',
    (tester) async {
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
      expect(
        button.onPressed,
        isNotNull,
        reason:
            'permission denial must stay retriable, not permanently disabled',
      );
      expect(find.byType(SnackBar), findsOneWidget);
    },
  );

  testWidgets('a mid-session recognizer error shows a snackbar', (
    tester,
  ) async {
    final controller = TextEditingController();
    final recognizer = await _pump(tester, controller);

    await tester.tap(find.byIcon(Icons.mic_none_rounded));
    await tester.pump();
    recognizer.simulateError('boom');
    await tester.pump();

    expect(find.byType(SnackBar), findsOneWidget);
  });
}
