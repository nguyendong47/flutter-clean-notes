import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_clean_notes/features/notes/data/repositories/audio_attachment_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Database database;
  late LocalNoteDataSourceImpl dataSource;
  late AudioAttachmentRepositoryImpl repository;
  late int noteId;

  setUp(() async {
    database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: 8,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE notes (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              title TEXT NOT NULL,
              content TEXT NOT NULL,
              color INTEGER NOT NULL,
              createdAt TEXT NOT NULL,
              isPinned INTEGER NOT NULL DEFAULT 0,
              tags TEXT NOT NULL DEFAULT '',
              status INTEGER NOT NULL DEFAULT 0,
              reminder TEXT,
              reminderGeneration INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE reminder_outbox (
              generation INTEGER PRIMARY KEY AUTOINCREMENT,
              noteId INTEGER,
              operation TEXT NOT NULL
                CHECK (operation IN ('schedule', 'cancel')),
              scheduledAt TEXT,
              CHECK (
                (operation = 'schedule' AND noteId IS NOT NULL AND scheduledAt IS NOT NULL)
                OR
                (operation = 'cancel' AND noteId IS NOT NULL AND scheduledAt IS NULL)
              )
            )
          ''');
          await db.execute('''
            CREATE TABLE note_audio_attachments (
              id TEXT PRIMARY KEY,
              noteId INTEGER NOT NULL,
              filePath TEXT NOT NULL,
              durationMs INTEGER NOT NULL,
              waveformData TEXT NOT NULL,
              createdAt TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE INDEX audio_attachments_note_id
            ON note_audio_attachments(noteId)
          ''');
        },
      ),
    );
    dataSource = LocalNoteDataSourceImpl(database: database);
    repository = AudioAttachmentRepositoryImpl(dataSource: dataSource);
    noteId = await dataSource.addNote(
      NoteModel(
        title: 'Test',
        content: '',
        color: 0,
        createdAt: DateTime.now(),
      ),
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'addAttachment persists a row retrievable by attachmentsForNote',
    () async {
      final id = await repository.addAttachment(
        noteId: noteId,
        filePath: '/tmp/rec.m4a',
        durationMs: 3000,
        waveform: [0.1, 0.2, 0.3],
      );

      final attachments = await repository.attachmentsForNote(noteId);

      expect(attachments, hasLength(1));
      expect(attachments.single.id, id);
      expect(attachments.single.filePath, '/tmp/rec.m4a');
      expect(attachments.single.durationMs, 3000);
      expect(attachments.single.waveform, [0.1, 0.2, 0.3]);
    },
  );

  test('deleteAttachment removes only the targeted attachment', () async {
    final firstId = await repository.addAttachment(
      noteId: noteId,
      filePath: '/tmp/a.m4a',
      durationMs: 1000,
      waveform: const [],
    );
    final secondId = await repository.addAttachment(
      noteId: noteId,
      filePath: '/tmp/b.m4a',
      durationMs: 1000,
      waveform: const [],
    );

    await repository.deleteAttachment(firstId);
    final remaining = await repository.attachmentsForNote(noteId);

    expect(remaining.map((a) => a.id), [secondId]);
  });

  test(
    'deleteAttachmentsForNote removes every attachment for that note only',
    () async {
      final otherNoteId = await dataSource.addNote(
        NoteModel(
          title: 'Other',
          content: '',
          color: 0,
          createdAt: DateTime.now(),
        ),
      );
      await repository.addAttachment(
        noteId: noteId,
        filePath: '/tmp/a.m4a',
        durationMs: 1000,
        waveform: const [],
      );
      await repository.addAttachment(
        noteId: otherNoteId,
        filePath: '/tmp/b.m4a',
        durationMs: 1000,
        waveform: const [],
      );

      await repository.deleteAttachmentsForNote(noteId);

      expect(await repository.attachmentsForNote(noteId), isEmpty);
      expect(await repository.attachmentsForNote(otherNoteId), hasLength(1));
    },
  );

  test('buildAudioEmbed and removeAudioEmbed round-trip', () {
    const id = 'abc-123';
    final embedded = 'Before\n${buildAudioEmbed(id)}\nAfter';

    final removed = removeAudioEmbed(embedded, id);

    expect(removed, 'Before\nAfter');
    expect(removed, isNot(contains('attachment://$id')));
  });
}
