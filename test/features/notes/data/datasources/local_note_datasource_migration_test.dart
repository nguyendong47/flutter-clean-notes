import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Directory supportDirectory;
  final openedDatabases = <Database>[];

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'clean_notes_migration_',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          if (call.method == 'getApplicationSupportDirectory') {
            return supportDirectory.path;
          }
          return null;
        });
  });

  tearDown(() async {
    for (final database in openedDatabases.reversed) {
      if (database.isOpen) await database.close();
    }
    openedDatabases.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (supportDirectory.existsSync()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test('upgrades a v1 file to v5 and preserves the legacy row', () async {
    await _writeFixture(
      supportDirectory,
      version: 1,
      rows: const [
        {
          'id': 41,
          'title': 'V1 field note',
          'content': 'Oldest durable body',
          'color': 3,
          'createdAt': '2024-01-02T03:04:05.000Z',
        },
      ],
    );

    final notes = await _upgradeAndRestart(openedDatabases);

    expect(notes, hasLength(1));
    expect(_noteSnapshot(notes.single), {
      'id': 41,
      'title': 'V1 field note',
      'content': 'Oldest durable body',
      'color': 3,
      'createdAt': DateTime.utc(2024, 1, 2, 3, 4, 5),
      'isPinned': false,
      'tags': const <String>[],
      'status': NoteStatus.active,
      'reminder': null,
    });
  });

  test('upgrades a v2 file without losing its pinned value', () async {
    await _writeFixture(
      supportDirectory,
      version: 2,
      rows: const [
        {
          'id': 42,
          'title': 'Pinned since v2',
          'content': 'Keep the pin',
          'color': 5,
          'createdAt': '2024-02-03T04:05:06.000Z',
          'isPinned': 1,
        },
      ],
    );

    final notes = await _upgradeAndRestart(openedDatabases);

    expect(notes, hasLength(1));
    expect(_noteSnapshot(notes.single), {
      'id': 42,
      'title': 'Pinned since v2',
      'content': 'Keep the pin',
      'color': 5,
      'createdAt': DateTime.utc(2024, 2, 3, 4, 5, 6),
      'isPinned': true,
      'tags': const <String>[],
      'status': NoteStatus.active,
      'reminder': null,
    });
  });

  test('upgrades a v3 file and keeps legacy tags readable', () async {
    await _writeFixture(
      supportDirectory,
      version: 3,
      rows: const [
        {
          'id': 43,
          'title': 'Tagged in v3',
          'content': 'Legacy comma-delimited tags',
          'color': 7,
          'createdAt': '2024-03-04T05:06:07.000Z',
          'isPinned': 0,
          'tags': 'finance,legacy',
        },
      ],
    );

    final notes = await _upgradeAndRestart(openedDatabases);

    expect(notes, hasLength(1));
    expect(_noteSnapshot(notes.single), {
      'id': 43,
      'title': 'Tagged in v3',
      'content': 'Legacy comma-delimited tags',
      'color': 7,
      'createdAt': DateTime.utc(2024, 3, 4, 5, 6, 7),
      'isPinned': false,
      'tags': const ['finance', 'legacy'],
      'status': NoteStatus.active,
      'reminder': null,
    });
    expect(
      (await openedDatabases.last.query('notes')).single['tags'],
      'finance,legacy',
    );
  });

  test('upgrades a v4 file and preserves every note status', () async {
    await _writeFixture(
      supportDirectory,
      version: 4,
      rows: const [
        {
          'id': 44,
          'title': 'Active v4',
          'content': 'Active body',
          'color': 9,
          'createdAt': '2024-04-05T06:07:08.000Z',
          'isPinned': 1,
          'tags': 'active',
          'status': 0,
        },
        {
          'id': 45,
          'title': 'Archived v4',
          'content': 'Archive body',
          'color': 10,
          'createdAt': '2024-04-04T06:07:08.000Z',
          'isPinned': 0,
          'tags': 'archive',
          'status': 1,
        },
        {
          'id': 46,
          'title': 'Trashed v4',
          'content': 'Trash body',
          'color': 11,
          'createdAt': '2024-04-03T06:07:08.000Z',
          'isPinned': 0,
          'tags': 'trash',
          'status': 2,
        },
      ],
    );

    final notes = await _upgradeAndRestart(openedDatabases);

    expect(notes.map(_noteSnapshot), [
      {
        'id': 44,
        'title': 'Active v4',
        'content': 'Active body',
        'color': 9,
        'createdAt': DateTime.utc(2024, 4, 5, 6, 7, 8),
        'isPinned': true,
        'tags': const ['active'],
        'status': NoteStatus.active,
        'reminder': null,
      },
      {
        'id': 45,
        'title': 'Archived v4',
        'content': 'Archive body',
        'color': 10,
        'createdAt': DateTime.utc(2024, 4, 4, 6, 7, 8),
        'isPinned': false,
        'tags': const ['archive'],
        'status': NoteStatus.archived,
        'reminder': null,
      },
      {
        'id': 46,
        'title': 'Trashed v4',
        'content': 'Trash body',
        'color': 11,
        'createdAt': DateTime.utc(2024, 4, 3, 6, 7, 8),
        'isPinned': false,
        'tags': const ['trash'],
        'status': NoteStatus.trashed,
        'reminder': null,
      },
    ]);
  });

  test('reopens a v5 file without changing its rich row', () async {
    await _writeFixture(
      supportDirectory,
      version: 5,
      rows: const [
        {
          'id': 47,
          'title': 'Current v5',
          'content': 'No migration needed',
          'color': 13,
          'createdAt': '2024-05-06T07:08:09.000Z',
          'isPinned': 1,
          'tags': '["current","reminder"]',
          'status': 1,
          'reminder': '2027-06-07T08:09:10.000Z',
        },
      ],
    );

    final notes = await _upgradeAndRestart(openedDatabases);

    expect(notes, hasLength(1));
    expect(_noteSnapshot(notes.single), {
      'id': 47,
      'title': 'Current v5',
      'content': 'No migration needed',
      'color': 13,
      'createdAt': DateTime.utc(2024, 5, 6, 7, 8, 9),
      'isPinned': true,
      'tags': const ['current', 'reminder'],
      'status': NoteStatus.archived,
      'reminder': DateTime.utc(2027, 6, 7, 8, 9, 10),
    });
  });

  test('creates a fresh empty v5 file with the exact current schema', () async {
    final dataSource = LocalNoteDataSourceImpl();
    final database = await dataSource.database;
    openedDatabases.add(database);

    await _expectCurrentSchema(database);

    expect(await _readAllStatuses(dataSource), isEmpty);
    expect(File(database.path).existsSync(), isTrue);
  });

  test('live datasource instances share one database file', () async {
    final firstDataSource = LocalNoteDataSourceImpl();
    final firstDatabase = await firstDataSource.database;
    openedDatabases.add(firstDatabase);
    final id = await firstDataSource.addNote(
      NoteModel(
        title: 'Shared live file',
        content: 'Written by the first datasource',
        color: 15,
        createdAt: DateTime.utc(2026, 8, 24, 9, 10, 11),
        isPinned: true,
        tags: const ['shared', 'live'],
        reminder: DateTime.utc(2027, 8, 24, 9, 10, 11),
      ),
    );

    final secondDataSource = LocalNoteDataSourceImpl();
    final secondDatabase = await secondDataSource.database;
    openedDatabases.add(secondDatabase);
    final notes = await secondDataSource.getNotes();

    expect(secondDatabase.path, firstDatabase.path);
    expect(File(secondDatabase.path).existsSync(), isTrue);
    expect(notes, hasLength(1));
    expect(_noteSnapshot(notes.single), {
      'id': id,
      'title': 'Shared live file',
      'content': 'Written by the first datasource',
      'color': 15,
      'createdAt': DateTime.utc(2026, 8, 24, 9, 10, 11),
      'isPinned': true,
      'tags': const ['shared', 'live'],
      'status': NoteStatus.active,
      'reminder': DateTime.utc(2027, 8, 24, 9, 10, 11),
    });
  });
}

Map<String, Object?> _noteSnapshot(NoteModel note) {
  return {
    'id': note.id,
    'title': note.title,
    'content': note.content,
    'color': note.color,
    'createdAt': note.createdAt,
    'isPinned': note.isPinned,
    'tags': note.tags,
    'status': note.status,
    'reminder': note.reminder,
  };
}

Future<List<NoteModel>> _upgradeAndRestart(
  List<Database> openedDatabases,
) async {
  final firstDataSource = LocalNoteDataSourceImpl();
  final firstDatabase = await firstDataSource.database;
  openedDatabases.add(firstDatabase);
  await _expectCurrentSchema(firstDatabase);
  final beforeRestart = await _readAllStatuses(firstDataSource);

  await firstDatabase.close();

  final restartedDataSource = LocalNoteDataSourceImpl();
  final restartedDatabase = await restartedDataSource.database;
  openedDatabases.add(restartedDatabase);
  await _expectCurrentSchema(restartedDatabase);
  final afterRestart = await _readAllStatuses(restartedDataSource);

  expect(
    afterRestart.map((note) => note.toJson()).toList(),
    beforeRestart.map((note) => note.toJson()).toList(),
  );
  return afterRestart;
}

Future<List<NoteModel>> _readAllStatuses(LocalNoteDataSource dataSource) async {
  final notes = <NoteModel>[];
  for (final status in NoteStatus.values) {
    notes.addAll(await dataSource.getNotesByStatus(status.index));
  }
  notes.sort((left, right) => left.id!.compareTo(right.id!));
  return notes;
}

Future<void> _expectCurrentSchema(Database database) async {
  expect(await database.getVersion(), 5);
  final objects = await database.rawQuery('''
    SELECT type, name, tbl_name, sql
    FROM sqlite_master
    WHERE name NOT GLOB 'sqlite_*'
    ORDER BY type, name
  ''');
  expect(
    objects
        .map(
          (object) => {
            'type': object['type'],
            'name': object['name'],
            'tbl_name': object['tbl_name'],
          },
        )
        .toList(),
    [
      {'type': 'table', 'name': 'notes', 'tbl_name': 'notes'},
    ],
  );
  final normalizedCreateSql = (objects.single['sql'] as String)
      .toLowerCase()
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  expect(normalizedCreateSql, startsWith('create table notes ('));
  expect(normalizedCreateSql, contains('id integer primary key autoincrement'));
  final forbiddenSchemaPatterns = <String, RegExp>{
    'CHECK': RegExp(r'\bcheck\s*\('),
    'COLLATE': RegExp(r'\bcollate\b'),
    'CONSTRAINT': RegExp(r'\bconstraint\b'),
    'DEFERRABLE': RegExp(r'\bdeferrable\b'),
    'GENERATED': RegExp(r'\bgenerated\b'),
    'ON CONFLICT': RegExp(r'\bon\s+conflict\b'),
    'REFERENCES': RegExp(r'\breferences\b'),
    'STRICT': RegExp(r'\bstrict\b'),
    'UNIQUE': RegExp(r'\bunique\b'),
    'WITHOUT ROWID': RegExp(r'\bwithout\s+rowid\b'),
  };
  for (final forbiddenClause in forbiddenSchemaPatterns.entries) {
    expect(
      forbiddenClause.value.hasMatch(normalizedCreateSql),
      isFalse,
      reason: 'Unexpected schema clause: ${forbiddenClause.key}',
    );
  }
  final tableList = await database.rawQuery("PRAGMA table_list('notes')");
  expect(tableList, hasLength(1));
  expect(tableList.single['type'], 'table');
  expect(tableList.single['ncol'], 9);
  expect(tableList.single['wr'], 0);
  expect(tableList.single['strict'], 0);
  expect(await database.rawQuery('PRAGMA foreign_key_list(notes)'), isEmpty);
  final columns = await database.rawQuery('PRAGMA table_xinfo(notes)');
  expect(columns, [
    {
      'cid': 0,
      'name': 'id',
      'type': 'INTEGER',
      'notnull': 0,
      'dflt_value': null,
      'pk': 1,
      'hidden': 0,
    },
    {
      'cid': 1,
      'name': 'title',
      'type': 'TEXT',
      'notnull': 1,
      'dflt_value': null,
      'pk': 0,
      'hidden': 0,
    },
    {
      'cid': 2,
      'name': 'content',
      'type': 'TEXT',
      'notnull': 1,
      'dflt_value': null,
      'pk': 0,
      'hidden': 0,
    },
    {
      'cid': 3,
      'name': 'color',
      'type': 'INTEGER',
      'notnull': 1,
      'dflt_value': null,
      'pk': 0,
      'hidden': 0,
    },
    {
      'cid': 4,
      'name': 'createdAt',
      'type': 'TEXT',
      'notnull': 1,
      'dflt_value': null,
      'pk': 0,
      'hidden': 0,
    },
    {
      'cid': 5,
      'name': 'isPinned',
      'type': 'INTEGER',
      'notnull': 1,
      'dflt_value': '0',
      'pk': 0,
      'hidden': 0,
    },
    {
      'cid': 6,
      'name': 'tags',
      'type': 'TEXT',
      'notnull': 1,
      'dflt_value': "''",
      'pk': 0,
      'hidden': 0,
    },
    {
      'cid': 7,
      'name': 'status',
      'type': 'INTEGER',
      'notnull': 1,
      'dflt_value': '0',
      'pk': 0,
      'hidden': 0,
    },
    {
      'cid': 8,
      'name': 'reminder',
      'type': 'TEXT',
      'notnull': 0,
      'dflt_value': null,
      'pk': 0,
      'hidden': 0,
    },
  ]);
  expect(
    await database.rawQuery('PRAGMA index_list(notes)'),
    isEmpty,
    reason:
        'The v5 table uses its INTEGER PRIMARY KEY rowid, not a side index.',
  );
}

Future<void> _writeFixture(
  Directory supportDirectory, {
  required int version,
  required List<Map<String, Object?>> rows,
}) async {
  final databasePath = path.join(supportDirectory.path, 'notes_database.db');
  final database = await databaseFactoryFfi.openDatabase(
    databasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  try {
    await database.execute(_schemaByVersion[version]!);
    for (final row in rows) {
      await database.insert('notes', row);
    }
    await database.execute('PRAGMA user_version = $version');
  } finally {
    await database.close();
  }
}

const _schemaByVersion = <int, String>{
  1: '''
    CREATE TABLE notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      color INTEGER NOT NULL,
      createdAt TEXT NOT NULL
    )
  ''',
  2: '''
    CREATE TABLE notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      color INTEGER NOT NULL,
      createdAt TEXT NOT NULL,
      isPinned INTEGER NOT NULL DEFAULT 0
    )
  ''',
  3: '''
    CREATE TABLE notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      color INTEGER NOT NULL,
      createdAt TEXT NOT NULL,
      isPinned INTEGER NOT NULL DEFAULT 0,
      tags TEXT NOT NULL DEFAULT ''
    )
  ''',
  4: '''
    CREATE TABLE notes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      title TEXT NOT NULL,
      content TEXT NOT NULL,
      color INTEGER NOT NULL,
      createdAt TEXT NOT NULL,
      isPinned INTEGER NOT NULL DEFAULT 0,
      tags TEXT NOT NULL DEFAULT '',
      status INTEGER NOT NULL DEFAULT 0
    )
  ''',
  5: '''
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
  ''',
};
