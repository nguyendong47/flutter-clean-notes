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
  Future<List<AudioAttachment>> attachmentsForNote(int noteId) async =>
      const [];

  @override
  Future<AudioAttachment?> getAttachment(String id) async => null;
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
          body: AudioRecordButton(
            controller: controller,
            ensureNoteId: () async => 1,
            enabled: enabled,
          ),
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

    await tester.tap(find.byIcon(Icons.fiber_manual_record_outlined));
    await tester.pump();

    expect(fakes.recorder.startCalls, 1);
  });

  testWidgets(
    'stopping inserts the audio embed at the cursor recording started at',
    (tester) async {
      final controller = TextEditingController(text: 'Hello ')
        ..selection = const TextSelection.collapsed(offset: 6);
      final fakes = await _pump(tester, controller);
      fakes.recorder.nextStopResult = const AudioRecordingResult(
        filePath: '/tmp/rec.m4a',
        durationMs: 3000,
        waveform: [0.1, 0.2],
      );

      await tester.tap(find.byIcon(Icons.fiber_manual_record_outlined));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.stop_circle_rounded));
      await tester.pumpAndSettle();

      expect(fakes.repo.addCalls, 1);
      expect(controller.text, 'Hello ![audio](attachment://attachment-1)');
    },
  );

  testWidgets('disabled when enabled is false', (tester) async {
    final controller = TextEditingController();
    await _pump(tester, controller, enabled: false);

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.onPressed, isNull);
  });
}
