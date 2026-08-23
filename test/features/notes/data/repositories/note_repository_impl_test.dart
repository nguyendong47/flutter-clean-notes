import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_clean_notes/features/notes/data/repositories/note_repository_impl.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'repository forwards an import as one converted bulk operation',
    () async {
      final dataSource = _RecordingLocalNoteDataSource();
      final repository = NoteRepositoryImpl(dataSource);
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
    final repository = NoteRepositoryImpl(dataSource);

    final changed = await repository.removeTag('shared');

    expect(changed, 3);
    expect(dataSource.removedTags, ['shared']);
  });
}

class _RecordingLocalNoteDataSource implements LocalNoteDataSource {
  int addCalls = 0;
  int importCalls = 0;
  List<NoteModel> imported = const [];
  final List<String> removedTags = [];

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
  Future<int> deleteNote(int id) async => 0;

  @override
  Future<List<NoteModel>> getNotes() async => const [];

  @override
  Future<List<NoteModel>> getNotesByStatus(int status) async => const [];

  @override
  Future<int> setNoteStatus(int id, int status) async => 0;

  @override
  Future<int> updateNote(NoteModel note) async => 0;
}
