import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_clean_notes/features/notes/data/repositories/audio_attachment_repository.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/audio_attachment_repository_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/audio_player_block.dart';

class _FakeAudioAttachmentRepository implements AudioAttachmentRepository {
  final Map<String, AudioAttachment> byId = {};

  @override
  Future<String> addAttachment({
    required int noteId,
    required String filePath,
    required int durationMs,
    required List<double> waveform,
  }) async => throw UnimplementedError();

  @override
  Future<void> deleteAttachment(String id) async {
    byId.remove(id);
  }

  @override
  Future<void> deleteAttachmentsForNote(int noteId) async {}

  @override
  Future<List<AudioAttachment>> attachmentsForNote(int noteId) async =>
      byId.values.where((a) => a.noteId == noteId).toList();

  @override
  Future<AudioAttachment?> getAttachment(String id) async => byId[id];
}

void main() {
  late Directory tempDir;
  late String realFilePath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('audio_player_block_test_');
    final file = File('${tempDir.path}/rec.m4a')..writeAsBytesSync(const []);
    realFilePath = file.path;
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  testWidgets('renders waveform/player controls for a known attachment', (
    tester,
  ) async {
    final repo = _FakeAudioAttachmentRepository()
      ..byId['a1'] = AudioAttachment(
        id: 'a1',
        noteId: 1,
        filePath: realFilePath,
        durationMs: 4000,
        waveform: const [0.1, 0.5, 0.2],
        createdAt: DateTime.now(),
      );
    final container = ProviderContainer(
      overrides: [
        audioAttachmentRepositoryProvider.overrideWith((ref) => repo),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: AudioPlayerBlock(attachmentId: 'a1')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets(
    'shows the unavailable placeholder for an unknown attachment id',
    (tester) async {
      final repo = _FakeAudioAttachmentRepository();
      final container = ProviderContainer(
        overrides: [
          audioAttachmentRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: AudioPlayerBlock(attachmentId: 'missing')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
      expect(
        find.byIcon(Icons.delete_outline_rounded),
        findsNothing,
        reason: 'nothing valid to delete by id when the row itself is missing',
      );
    },
  );

  testWidgets(
    'shows the unavailable placeholder but keeps delete when the row exists '
    'but its file is missing',
    (tester) async {
      final repo = _FakeAudioAttachmentRepository()
        ..byId['a1'] = AudioAttachment(
          id: 'a1',
          noteId: 1,
          filePath: '/tmp/definitely-does-not-exist-audio-memo.m4a',
          durationMs: 4000,
          waveform: const [0.1, 0.5, 0.2],
          createdAt: DateTime.now(),
        );
      final container = ProviderContainer(
        overrides: [
          audioAttachmentRepositoryProvider.overrideWith((ref) => repo),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: AudioPlayerBlock(attachmentId: 'a1')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
      expect(
        find.byIcon(Icons.play_arrow_rounded),
        findsNothing,
        reason: 'a missing file must not render as playable',
      );
      expect(
        find.byKey(const Key('audio-player-delete-a1')),
        findsOneWidget,
        reason: 'the dead reference must still be clearable',
      );
    },
  );

  testWidgets('tapping delete calls deleteAttachment and onDeleted callback', (
    tester,
  ) async {
    var deleted = false;
    final repo = _FakeAudioAttachmentRepository()
      ..byId['a1'] = AudioAttachment(
        id: 'a1',
        noteId: 1,
        filePath: '/tmp/does-not-exist.m4a',
        durationMs: 4000,
        waveform: const [0.1, 0.5, 0.2],
        createdAt: DateTime.now(),
      );
    final container = ProviderContainer(
      overrides: [
        audioAttachmentRepositoryProvider.overrideWith((ref) => repo),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: AudioPlayerBlock(
              attachmentId: 'a1',
              onDeleted: () => deleted = true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('audio-player-delete-a1')));
    await tester.pumpAndSettle();

    expect(deleted, isTrue);
    expect(repo.byId.containsKey('a1'), isFalse);
  });
}
