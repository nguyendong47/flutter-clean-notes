import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test(
    'adding a reminder commits its note generation and schedule command together',
    () async {
      sqfliteFfiInit();
      final database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(database.close);
      await _createNotesTable(database);
      final dataSource = LocalNoteDataSourceImpl(database: database);
      final reminder = DateTime.utc(2030, 1, 15, 11, 15);

      final id = await dataSource.addNote(
        NoteModel(
          title: 'Durable reminder',
          content: '',
          color: 1,
          createdAt: DateTime.utc(2030, 1, 15),
          reminder: reminder,
        ),
      );

      final note = (await database.query(
        'notes',
        where: 'id = ?',
        whereArgs: [id],
      )).single;
      final command = (await database.query('reminder_outbox')).single;
      expect(note['reminderGeneration'], command['generation']);
      expect(command, containsPair('noteId', id));
      expect(command, containsPair('operation', 'schedule'));
      expect(command, containsPair('scheduledAt', reminder.toIso8601String()));
    },
  );

  test('adding a reminder rolls back when its command insert fails', () async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(database.close);
    await _createNotesTable(database);
    await database.execute('''
      CREATE TRIGGER reject_schedule
      BEFORE INSERT ON reminder_outbox
      WHEN NEW.operation = 'schedule'
      BEGIN
        SELECT RAISE(ABORT, 'forced schedule failure');
      END
    ''');
    final dataSource = LocalNoteDataSourceImpl(database: database);

    await expectLater(
      dataSource.addNote(_note(reminder: DateTime.utc(2030, 1, 15, 11))),
      throwsA(anything),
    );

    expect(await database.query('notes'), isEmpty);
    expect(await database.query('reminder_outbox'), isEmpty);
  });

  test(
    'changing a reminder supersedes the prior generation atomically',
    () async {
      sqfliteFfiInit();
      final database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      addTearDown(database.close);
      await _createNotesTable(database);
      final dataSource = LocalNoteDataSourceImpl(database: database);
      final first = DateTime.utc(2030, 1, 15, 11);
      final second = DateTime.utc(2030, 1, 15, 12);
      final id = await dataSource.addNote(_note(reminder: first));
      final firstGeneration = (await database.query(
        'notes',
        columns: const ['reminderGeneration'],
      )).single['reminderGeneration'];

      expect(await dataSource.updateNote(_note(id: id, reminder: second)), 1);

      final note = (await database.query('notes')).single;
      final commands = await database.query('reminder_outbox');
      expect(commands, hasLength(1));
      expect(commands.single['generation'], isNot(firstGeneration));
      expect(note['reminderGeneration'], commands.single['generation']);
      expect(commands.single['operation'], 'schedule');
      expect(commands.single['scheduledAt'], second.toIso8601String());
    },
  );

  test('an unchanged reminder does not churn its generation', () async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(database.close);
    await _createNotesTable(database);
    final dataSource = LocalNoteDataSourceImpl(database: database);
    final reminder = DateTime.utc(2030, 1, 15, 11);
    final id = await dataSource.addNote(_note(reminder: reminder));
    final before = (await database.query('reminder_outbox')).single;

    expect(
      await dataSource.updateNote(
        _note(id: id, title: 'Changed title', reminder: reminder),
      ),
      1,
    );

    expect((await database.query('reminder_outbox')).single, before);
  });

  test('clearing a reminder replaces schedule with cancel', () async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(database.close);
    await _createNotesTable(database);
    final dataSource = LocalNoteDataSourceImpl(database: database);
    final id = await dataSource.addNote(
      _note(reminder: DateTime.utc(2030, 1, 15, 11)),
    );

    expect(await dataSource.updateNote(_note(id: id)), 1);

    final note = (await database.query('notes')).single;
    final command = (await database.query('reminder_outbox')).single;
    expect(note['reminder'], isNull);
    expect(note['reminderGeneration'], command['generation']);
    expect(command['operation'], 'cancel');
    expect(command['scheduledAt'], isNull);
  });

  test('deleting a note leaves one durable cancel command', () async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(database.close);
    await _createNotesTable(database);
    final dataSource = LocalNoteDataSourceImpl(database: database);
    final id = await dataSource.addNote(_note());

    expect(await dataSource.deleteNote(id), 1);

    expect(await database.query('notes'), isEmpty);
    final command = (await database.query('reminder_outbox')).single;
    expect(command['noteId'], id);
    expect(command['operation'], 'cancel');
    expect(command['scheduledAt'], isNull);
  });

  test('delete rolls back when its cancel command cannot be written', () async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(database.close);
    await _createNotesTable(database);
    final dataSource = LocalNoteDataSourceImpl(database: database);
    final id = await dataSource.addNote(_note());
    await database.execute('''
      CREATE TRIGGER reject_cancel
      BEFORE INSERT ON reminder_outbox
      WHEN NEW.operation = 'cancel'
      BEGIN
        SELECT RAISE(ABORT, 'forced cancel failure');
      END
    ''');

    await expectLater(dataSource.deleteNote(id), throwsA(anything));

    expect(
      await database.query('notes', where: 'id = ?', whereArgs: [id]),
      hasLength(1),
    );
  });

  test('trash cleanup commits one cancel command per deleted note', () async {
    sqfliteFfiInit();
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(database.close);
    await _createNotesTable(database);
    final dataSource = LocalNoteDataSourceImpl(database: database);
    final first = await dataSource.addNote(
      _note(createdAt: DateTime.utc(2020), status: NoteStatus.trashed),
    );
    final second = await dataSource.addNote(
      _note(createdAt: DateTime.utc(2020, 1, 2), status: NoteStatus.trashed),
    );
    await dataSource.addNote(_note(createdAt: DateTime.utc(2020)));

    expect(await dataSource.cleanupTrash(), 2);

    final commands = await database.query(
      'reminder_outbox',
      orderBy: 'noteId ASC',
    );
    expect(commands.map((row) => row['noteId']), [first, second]);
    expect(commands.map((row) => row['operation']), everyElement('cancel'));
  });

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
    expect(raw.single['tags'], 'json:["finance,2026","work"]');
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

NoteModel _note({
  int? id,
  String title = 'Note',
  DateTime? createdAt,
  NoteStatus status = NoteStatus.active,
  DateTime? reminder,
}) {
  return NoteModel(
    id: id,
    title: title,
    content: '',
    color: 1,
    createdAt: createdAt ?? DateTime.utc(2030, 1, 15),
    status: status,
    reminder: reminder,
  );
}

Future<void> _createNotesTable(Database database) async {
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
        reminder TEXT,
        reminderGeneration INTEGER NOT NULL DEFAULT 0
      )
    ''');
  await database.execute('''
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
}
