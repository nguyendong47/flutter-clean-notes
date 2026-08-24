import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('persists and reloads a comma-bearing tag without ambiguity', () async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(database.close);
    await _createNotesTable(database);
    final dataSource = LocalNoteDataSourceImpl(database: database);

    await dataSource.addNote(
      NoteModel(
        title: 'Budget',
        content: 'Forecast',
        color: 1,
        createdAt: DateTime.utc(2026, 8, 23),
        tags: const ['finance,2026', 'work'],
      ),
    );

    final raw = await database.query('notes');
    final restored = await dataSource.getNotes();
    expect(raw.single['tags'], '["finance,2026","work"]');
    expect(restored.single.tags, ['finance,2026', 'work']);
  });

  test('pin toggle changes only isPinned for the selected row', () async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(database.close);
    await _createNotesTable(database);
    final dataSource = LocalNoteDataSourceImpl(database: database);
    final id = await dataSource.addNote(
      NoteModel(
        title: 'Archived source',
        content: 'Keep every non-pin field',
        color: 7,
        createdAt: DateTime.utc(2026, 8, 24),
        tags: const ['safe'],
        status: NoteStatus.archived,
        reminder: DateTime.utc(2026, 8, 25),
      ),
    );

    expect(await dataSource.toggleNotePin(id), 1);

    final row = await database.query('notes', where: 'id = ?', whereArgs: [id]);
    final restored = NoteModel.fromJson(row.single);
    expect(restored.isPinned, isTrue);
    expect(restored.status, NoteStatus.archived);
    expect(restored.title, 'Archived source');
    expect(restored.content, 'Keep every non-pin field');
    expect(restored.tags, ['safe']);
    expect(restored.reminder, DateTime.utc(2026, 8, 25));
  });

  test(
    'bulk import rolls back every insert when a later insert fails',
    () async {
      sqfliteFfiInit();
      final database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(database.close);
      await _createNotesTable(database);
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

  test(
    'global tag removal rolls back every status on a later failure',
    () async {
      sqfliteFfiInit();
      final database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(database.close);
      await _createNotesTable(database);
      final dataSource = LocalNoteDataSourceImpl(database: database);
      for (final note in [
        NoteModel(
          title: 'Active',
          content: '',
          color: 1,
          createdAt: DateTime.utc(2026, 8, 23),
          tags: const ['shared', 'finance,2026'],
        ),
        NoteModel(
          title: 'Archive',
          content: '',
          color: 2,
          createdAt: DateTime.utc(2026, 8, 22),
          tags: const ['shared', 'archive'],
          status: NoteStatus.archived,
        ),
        NoteModel(
          title: 'Trash',
          content: '',
          color: 3,
          createdAt: DateTime.utc(2026, 8, 21),
          tags: const ['shared', 'trash'],
          status: NoteStatus.trashed,
        ),
      ]) {
        await dataSource.addNote(note);
      }
      await database.execute('''
      CREATE TRIGGER reject_archive_tag_update
      BEFORE UPDATE OF tags ON notes
      WHEN OLD.title = 'Archive'
      BEGIN
        SELECT RAISE(ABORT, 'forced tag update failure');
      END
    ''');

      await expectLater(dataSource.removeTag('shared'), throwsA(anything));

      var rows = await database.query('notes', orderBy: 'id ASC');
      expect(
        rows.map((row) => NoteModel.fromJson(row).tags),
        everyElement(contains('shared')),
      );

      await database.execute('DROP TRIGGER reject_archive_tag_update');
      expect(await dataSource.removeTag('shared'), 3);

      rows = await database.query('notes', orderBy: 'id ASC');
      expect(
        rows.map((row) => NoteModel.fromJson(row).tags),
        everyElement(isNot(contains('shared'))),
      );
      expect(NoteModel.fromJson(rows.first).tags, ['finance,2026']);
    },
  );
}

Future<void> _createNotesTable(Database database) {
  return database.execute('''
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
}
