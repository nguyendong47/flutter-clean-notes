import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_clean_notes/features/notes/data/repositories/audio_attachment_repository.dart';
import 'package:flutter_clean_notes/features/notes/data/repositories/note_repository_impl.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'repository forwards an import as one converted bulk operation',
    () async {
      final dataSource = _RecordingLocalNoteDataSource();
      final repository = NoteRepositoryImpl(
        dataSource,
        audioAttachmentRepository: _FakeAudioAttachmentRepository(),
      );
      final notes = [
        Note(
          title: 'First',
          content: 'First body',
          color: 1,
          createdAt: DateTime.utc(2026, 8, 23),
        ),
        Note(
          title: 'Second',
          content: 'Second body',
          color: 2,
          createdAt: DateTime.utc(2026, 8, 23, 0, 1),
        ),
      ];

      await repository.importNotes(notes);

      expect(dataSource.importCalls, 1);
      expect(dataSource.addCalls, 0);
      expect(dataSource.imported.map((note) => note.title), [
        'First',
        'Second',
      ]);
    },
  );

  test('repository forwards global tag removal as one operation', () async {
    final dataSource = _RecordingLocalNoteDataSource();
    final repository = NoteRepositoryImpl(
      dataSource,
      audioAttachmentRepository: _FakeAudioAttachmentRepository(),
    );

    final changed = await repository.removeTag('shared');

    expect(changed, 3);
    expect(dataSource.removedTags, ['shared']);
  });

  test('repository forwards an atomic pin toggle', () async {
    final dataSource = _RecordingLocalNoteDataSource();
    final repository = NoteRepositoryImpl(
      dataSource,
      audioAttachmentRepository: _FakeAudioAttachmentRepository(),
    );

    final changed = await repository.toggleNotePin(42);

    expect(changed, 1);
    expect(dataSource.toggledNoteIds, [42]);
  });

  test(
    'deleteNote cleans up audio attachments after the note row is deleted',
    () async {
      final dataSource = _RecordingLocalNoteDataSource()..nextDeleteResult = 1;
      final attachments = _FakeAudioAttachmentRepository();
      final repository = NoteRepositoryImpl(
        dataSource,
        audioAttachmentRepository: attachments,
      );

      final deleted = await repository.deleteNote(7);

      expect(deleted, 1);
      expect(attachments.deleteForNoteCalls, 1);
      expect(attachments.lastNoteId, 7);
    },
  );

  test(
    'deleteNote does not clean up attachments when the note row was not actually deleted',
    () async {
      final dataSource = _RecordingLocalNoteDataSource()..nextDeleteResult = 0;
      final attachments = _FakeAudioAttachmentRepository();
      final repository = NoteRepositoryImpl(
        dataSource,
        audioAttachmentRepository: attachments,
      );

      await repository.deleteNote(7);

      expect(attachments.deleteForNoteCalls, 0);
    },
  );

  test(
    'deleteNote still reports success even if attachment cleanup throws',
    () async {
      final dataSource = _RecordingLocalNoteDataSource()..nextDeleteResult = 1;
      final attachments = _FakeAudioAttachmentRepository()
        ..throwOnDelete = true;
      final repository = NoteRepositoryImpl(
        dataSource,
        audioAttachmentRepository: attachments,
      );

      final deleted = await repository.deleteNote(7);

      expect(
        deleted,
        1,
        reason:
            'a secondary cleanup failure must never fail the primary delete',
      );
    },
  );
}

class _FakeAudioAttachmentRepository implements AudioAttachmentRepository {
  int deleteForNoteCalls = 0;
  int? lastNoteId;
  bool throwOnDelete = false;

  @override
  Future<String> addAttachment({
    required int noteId,
    required String filePath,
    required int durationMs,
    required List<double> waveform,
  }) async => throw UnimplementedError();

  @override
  Future<void> deleteAttachment(String id) async {}

  @override
  Future<void> deleteAttachmentsForNote(int noteId) async {
    deleteForNoteCalls += 1;
    lastNoteId = noteId;
    if (throwOnDelete) throw StateError('cleanup failed');
  }

  @override
  Future<List<AudioAttachment>> attachmentsForNote(int noteId) async =>
      const [];
}

class _RecordingLocalNoteDataSource implements LocalNoteDataSource {
  int addCalls = 0;
  int importCalls = 0;
  int nextDeleteResult = 0;
  List<NoteModel> imported = const [];
  final List<String> removedTags = [];
  final List<int> toggledNoteIds = [];

  @override
  Future<int> addNote(NoteModel note) async {
    addCalls += 1;
    return 1;
  }

  @override
  Future<void> importNotes(List<NoteModel> notes) async {
    importCalls += 1;
    imported = [...notes];
  }

  @override
  Future<int> removeTag(String tag) async {
    removedTags.add(tag);
    return 3;
  }

  @override
  Future<int> cleanupTrash() async => 0;

  @override
  Future<int> deleteNote(int id) async => nextDeleteResult;

  @override
  Future<List<NoteModel>> getNotes() async => const [];

  @override
  Future<List<NoteModel>> getNotesByStatus(int status) async => const [];

  @override
  Future<int> setNoteStatus(int id, int status) async => 0;

  @override
  Future<int> toggleNotePin(int id) async {
    toggledNoteIds.add(id);
    return 1;
  }

  @override
  Future<int> updateNote(NoteModel note) async => 0;
}
