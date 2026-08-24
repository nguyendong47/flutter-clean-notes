import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/reminder_command.dart';

abstract class LocalNoteDataSource {
  Future<List<NoteModel>> getNotes();
  Future<int> addNote(NoteModel note);
  Future<void> importNotes(List<NoteModel> notes);
  Future<int> updateNote(NoteModel note);
  Future<int> deleteNote(int id);
  Future<List<NoteModel>> getNotesByStatus(int status);
  Future<int> setNoteStatus(int id, int status);
  Future<int> toggleNotePin(int id);
  Future<int> cleanupTrash();
  Future<int> removeTag(String tag);
}

abstract interface class ReminderOutboxDataSource {
  Future<List<ReminderCommand>> pendingReminderCommands({int? noteId});
  Future<bool> isReminderCommandCurrent(int generation);
  Future<bool> acknowledgeReminderCommand(int generation);
  Future<ReminderCommand?> snoozeReminder({
    required int noteId,
    required int? expectedGeneration,
    required DateTime scheduledAt,
  });
  Future<void> reconcileReminderNotifications({
    required List<PendingReminderNotification> pending,
    required DateTime now,
  });
}

abstract interface class NotesPersistenceDataSource
    implements LocalNoteDataSource, ReminderOutboxDataSource {}

class LocalNoteDataSourceImpl implements NotesPersistenceDataSource {
  LocalNoteDataSourceImpl({Database? database}) : _databaseOverride = database;

  Database? _database;
  static const int _schemaVersion = 7;
  static const String _tableName = 'notes';
  static const String _reminderOutboxTable = 'reminder_outbox';
  final Database? _databaseOverride;

  @override
  Future<int> cleanupTrash() async {
    final db = await database;
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    return db.transaction((transaction) async {
      final where = 'status = ? AND createdAt < ?';
      final whereArgs = [
        NoteStatus.trashed.index,
        thirtyDaysAgo.toIso8601String(),
      ];
      final rows = await transaction.query(
        _tableName,
        columns: const ['id'],
        where: where,
        whereArgs: whereArgs,
      );
      final deleted = await transaction.delete(
        _tableName,
        where: where,
        whereArgs: whereArgs,
      );
      for (final row in rows) {
        await _replaceReminderCommand(
          transaction,
          noteId: row['id']! as int,
          operation: 'cancel',
          updateNoteGeneration: false,
        );
      }
      return deleted;
    });
  }

  Future<Database> get database async {
    if (_databaseOverride case final database?) return database;
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    if (!kIsWeb &&
        (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final docDir = await getApplicationSupportDirectory();
      final path = join(docDir.path, 'notes_database.db');

      // Ensure FFI libraries are loaded before opening the database
      sqfliteFfiInit();

      // Explicitly use the FFI factory to bypass the global sqflite channels that are failing
      return await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: _schemaVersion,
          onCreate: _createDB,
          onUpgrade: _upgradeDB,
        ),
      );
    } else {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'notes_database.db');

      return await openDatabase(
        path,
        version: _schemaVersion,
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
      );
    }
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $_tableName (
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
    await _createReminderOutbox(db);
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
        'ALTER TABLE $_tableName ADD COLUMN isPinned INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE $_tableName ADD COLUMN tags TEXT NOT NULL DEFAULT ''",
      );
    }
    if (oldVersion < 4) {
      await db.execute(
        'ALTER TABLE $_tableName ADD COLUMN status INTEGER NOT NULL DEFAULT 0',
      );
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE $_tableName ADD COLUMN reminder TEXT');
    }
    if (oldVersion < 6) {
      final rows = await db.query(_tableName, columns: const ['id', 'tags']);
      final batch = db.batch();
      for (final row in rows) {
        batch.update(
          _tableName,
          {
            'tags': NoteModel.encodeLegacyTagsForMigration(
              row['tags'] as String,
            ),
          },
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      await batch.commit(noResult: true);
    }
    if (oldVersion < 7) {
      await db.execute(
        'ALTER TABLE $_tableName ADD COLUMN reminderGeneration INTEGER NOT NULL DEFAULT 0',
      );
      await _createReminderOutbox(db);
    }
  }

  Future<void> _createReminderOutbox(Database db) async {
    await db.execute('''
      CREATE TABLE $_reminderOutboxTable (
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
      CREATE INDEX reminder_outbox_note_generation
      ON $_reminderOutboxTable(noteId, generation)
    ''');
  }

  @override
  Future<List<NoteModel>> getNotes() async {
    final db = await database;
    final result = await db.query(
      _tableName,
      where: 'status = ?',
      whereArgs: [NoteStatus.active.index],
      orderBy: 'isPinned DESC, createdAt DESC',
    );
    return result.map((json) => NoteModel.fromJson(json)).toList();
  }

  @override
  Future<List<NoteModel>> getNotesByStatus(int status) async {
    final db = await database;
    final result = await db.query(
      _tableName,
      where: 'status = ?',
      whereArgs: [status],
      orderBy: 'isPinned DESC, createdAt DESC',
    );
    return result.map((json) => NoteModel.fromJson(json)).toList();
  }

  @override
  Future<int> setNoteStatus(int id, int status) async {
    final db = await database;
    return await db.update(
      _tableName,
      {'status': status},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  @override
  Future<int> toggleNotePin(int id) async {
    final db = await database;
    return db.rawUpdate(
      '''
      UPDATE $_tableName
      SET isPinned = CASE isPinned WHEN 0 THEN 1 ELSE 0 END
      WHERE id = ?
      ''',
      [id],
    );
  }

  @override
  Future<int> addNote(NoteModel note) async {
    final db = await database;
    return db.transaction((transaction) async {
      final id = await transaction.insert(_tableName, note.toJson());
      final reminder = note.reminder;
      if (reminder != null) {
        await _replaceReminderCommand(
          transaction,
          noteId: id,
          operation: 'schedule',
          scheduledAt: reminder,
          updateNoteGeneration: true,
        );
      }
      return id;
    });
  }

  Future<int> _replaceReminderCommand(
    DatabaseExecutor database, {
    required int noteId,
    required String operation,
    DateTime? scheduledAt,
    required bool updateNoteGeneration,
  }) async {
    final generation = await database.insert(_reminderOutboxTable, {
      'noteId': noteId,
      'operation': operation,
      'scheduledAt': scheduledAt?.toIso8601String(),
    });
    await database.delete(
      _reminderOutboxTable,
      where: 'noteId = ? AND generation < ?',
      whereArgs: [noteId, generation],
    );
    if (updateNoteGeneration) {
      await database.update(
        _tableName,
        {'reminderGeneration': generation},
        where: 'id = ?',
        whereArgs: [noteId],
      );
    }
    return generation;
  }

  @override
  Future<List<ReminderCommand>> pendingReminderCommands({int? noteId}) async {
    final db = await database;
    final rows = await db.query(
      _reminderOutboxTable,
      where: noteId == null ? null : 'noteId = ?',
      whereArgs: noteId == null ? null : [noteId],
      orderBy: 'generation ASC',
    );
    return rows.map(_reminderCommandFromRow).toList(growable: false);
  }

  @override
  Future<bool> isReminderCommandCurrent(int generation) async {
    final db = await database;
    final rows = await db.query(
      _reminderOutboxTable,
      columns: const ['generation'],
      where: 'generation = ?',
      whereArgs: [generation],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<bool> acknowledgeReminderCommand(int generation) async {
    final db = await database;
    return await db.delete(
          _reminderOutboxTable,
          where: 'generation = ?',
          whereArgs: [generation],
        ) ==
        1;
  }

  @override
  Future<ReminderCommand?> snoozeReminder({
    required int noteId,
    required int? expectedGeneration,
    required DateTime scheduledAt,
  }) async {
    final db = await database;
    return db.transaction((transaction) async {
      final rows = await transaction.query(
        _tableName,
        columns: const ['reminderGeneration'],
        where: 'id = ?',
        whereArgs: [noteId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final currentGeneration = rows.single['reminderGeneration']! as int;
      final expectedMatches = expectedGeneration == null
          ? currentGeneration == 0
          : currentGeneration == expectedGeneration;
      if (!expectedMatches) return null;

      final generation = await _replaceReminderCommand(
        transaction,
        noteId: noteId,
        operation: 'schedule',
        scheduledAt: scheduledAt,
        updateNoteGeneration: true,
      );
      await transaction.update(
        _tableName,
        {'reminder': scheduledAt.toIso8601String()},
        where: 'id = ?',
        whereArgs: [noteId],
      );
      return ReminderCommand(
        generation: generation,
        noteId: noteId,
        operation: ReminderCommandOperation.schedule,
        scheduledAt: scheduledAt,
      );
    });
  }

  @override
  Future<void> reconcileReminderNotifications({
    required List<PendingReminderNotification> pending,
    required DateTime now,
  }) async {
    final db = await database;
    await db.transaction((transaction) async {
      final noteRows = await transaction.query(
        _tableName,
        columns: const ['id', 'reminder', 'reminderGeneration'],
      );
      final notesById = <int, Map<String, Object?>>{
        for (final row in noteRows) row['id']! as int: row,
      };
      final coveredNoteIds = <int>{};

      for (final notification in pending) {
        final note = notesById[notification.notificationId];
        final reminderText = note?['reminder'] as String?;
        if (note == null || reminderText == null) {
          await _ensureReminderCommand(
            transaction,
            noteId: notification.notificationId,
            operation: 'cancel',
            updateNoteGeneration: note != null,
          );
          continue;
        }

        final reminder = DateTime.parse(reminderText);
        final noteGeneration = note['reminderGeneration']! as int;
        if (notification.isLegacy && noteGeneration == 0) {
          coveredNoteIds.add(notification.notificationId);
          continue;
        }
        if (notification.generation == noteGeneration &&
            reminder.isAfter(now)) {
          coveredNoteIds.add(notification.notificationId);
          continue;
        }
        if (reminder.isAfter(now)) {
          await _ensureReminderCommand(
            transaction,
            noteId: notification.notificationId,
            operation: 'schedule',
            scheduledAt: reminder,
            updateNoteGeneration: true,
          );
        } else {
          await _ensureReminderCommand(
            transaction,
            noteId: notification.notificationId,
            operation: 'cancel',
            updateNoteGeneration: true,
          );
        }
      }

      for (final entry in notesById.entries) {
        final reminderText = entry.value['reminder'] as String?;
        if (reminderText == null || coveredNoteIds.contains(entry.key)) {
          continue;
        }
        final reminder = DateTime.parse(reminderText);
        if (!reminder.isAfter(now)) continue;
        await _ensureReminderCommand(
          transaction,
          noteId: entry.key,
          operation: 'schedule',
          scheduledAt: reminder,
          updateNoteGeneration: true,
        );
      }
    });
  }

  Future<int> _ensureReminderCommand(
    DatabaseExecutor database, {
    required int noteId,
    required String operation,
    DateTime? scheduledAt,
    required bool updateNoteGeneration,
  }) async {
    final existing = await database.query(
      _reminderOutboxTable,
      columns: const ['generation'],
      where: 'noteId = ?',
      whereArgs: [noteId],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      return existing.single['generation']! as int;
    }
    return _replaceReminderCommand(
      database,
      noteId: noteId,
      operation: operation,
      scheduledAt: scheduledAt,
      updateNoteGeneration: updateNoteGeneration,
    );
  }

  ReminderCommand _reminderCommandFromRow(Map<String, Object?> row) {
    final scheduledAt = row['scheduledAt'] as String?;
    return ReminderCommand(
      generation: row['generation']! as int,
      noteId: row['noteId']! as int,
      operation: switch (row['operation']) {
        'schedule' => ReminderCommandOperation.schedule,
        'cancel' => ReminderCommandOperation.cancel,
        final value => throw StateError('Unknown reminder operation: $value'),
      },
      scheduledAt: scheduledAt == null ? null : DateTime.parse(scheduledAt),
    );
  }

  @override
  Future<void> importNotes(List<NoteModel> notes) async {
    final db = await database;
    await db.transaction((transaction) async {
      for (final note in notes) {
        await transaction.insert(_tableName, note.toJson());
      }
    });
  }

  @override
  Future<int> updateNote(NoteModel note) async {
    final db = await database;
    return db.transaction((transaction) async {
      final rows = await transaction.query(
        _tableName,
        columns: const ['reminder'],
        where: 'id = ?',
        whereArgs: [note.id],
        limit: 1,
      );
      if (rows.isEmpty) return 0;
      final previousReminder = rows.single['reminder'] as String?;
      final nextReminder = note.reminder?.toIso8601String();
      final updated = await transaction.update(
        _tableName,
        note.toJson(),
        where: 'id = ?',
        whereArgs: [note.id],
      );
      if (updated == 1 && previousReminder != nextReminder) {
        await _replaceReminderCommand(
          transaction,
          noteId: note.id!,
          operation: nextReminder == null ? 'cancel' : 'schedule',
          scheduledAt: note.reminder,
          updateNoteGeneration: true,
        );
      }
      return updated;
    });
  }

  @override
  Future<int> deleteNote(int id) async {
    final db = await database;
    return db.transaction((transaction) async {
      final deleted = await transaction.delete(
        _tableName,
        where: 'id = ?',
        whereArgs: [id],
      );
      if (deleted == 1) {
        await _replaceReminderCommand(
          transaction,
          noteId: id,
          operation: 'cancel',
          updateNoteGeneration: false,
        );
      }
      return deleted;
    });
  }

  @override
  Future<int> removeTag(String tag) async {
    final db = await database;
    return db.transaction((transaction) async {
      final rows = await transaction.query(_tableName, orderBy: 'id ASC');
      var changed = 0;
      for (final row in rows) {
        final note = NoteModel.fromJson(row);
        if (!note.tags.contains(tag)) continue;
        final updated = NoteModel.fromEntity(
          note.copyWith(
            tags: note.tags.where((candidate) => candidate != tag).toList(),
          ),
        );
        changed += await transaction.update(
          _tableName,
          {'tags': updated.toJson()['tags']},
          where: 'id = ?',
          whereArgs: [note.id],
        );
      }
      return changed;
    });
  }
}
