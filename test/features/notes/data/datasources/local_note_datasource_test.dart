import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'bulk import rolls back every insert when a later insert fails',
    () async {
      sqfliteFfiInit();
      final database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(database.close);
      await database.execute('''
      CREATE TABLE notes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT NOT NULL,
        color INTEGER NOT NULL,
        createdAt TEXT NOT NULL,
        isPinned INTEGER NOT NULL DEFAULT 0,
        tags TEXT NOT NULL DEFAULT '',
        status INTEGER NOT NULL DEFAULT 0,
        reminder TEXT
      )
    ''');
      await database.execute('''
      CREATE TRIGGER reject_second_import
      BEFORE INSERT ON notes
      WHEN NEW.title = 'Second'
      BEGIN
        SELECT RAISE(ABORT, 'forced import failure');
      END
    ''');
      final dataSource = LocalNoteDataSourceImpl(database: database);
      final notes = [
        NoteModel(
          title: 'First',
          content: 'First body',
          color: 1,
          createdAt: DateTime.utc(2026, 8, 23),
        ),
        NoteModel(
          title: 'Second',
          content: 'Second body',
          color: 2,
          createdAt: DateTime.utc(2026, 8, 23, 0, 1),
        ),
      ];

      await expectLater(dataSource.importNotes(notes), throwsA(anything));

      final countRows = await database.rawQuery('SELECT COUNT(*) FROM notes');
      expect(countRows.single.values.single, 0);

      await database.execute('DROP TRIGGER reject_second_import');
      await dataSource.importNotes(notes);

      final rows = await database.query('notes', orderBy: 'id ASC');
      expect(rows.map((row) => row['title']), ['First', 'Second']);
    },
  );
}
