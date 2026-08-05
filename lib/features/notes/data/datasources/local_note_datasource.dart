import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';

abstract class LocalNoteDataSource {
  Future<List<NoteModel>> getNotes();
  Future<int> addNote(NoteModel note);
  Future<int> updateNote(NoteModel note);
  Future<int> deleteNote(int id);
  Future<List<NoteModel>> getNotesByStatus(int status);
  Future<int> setNoteStatus(int id, int status);
  Future<int> cleanupTrash();
}

class LocalNoteDataSourceImpl implements LocalNoteDataSource {
  static Database? _database;
  static const String _tableName = 'notes';

  @override
  Future<int> cleanupTrash() async {
    final db = await database;
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    return await db.delete(
      _tableName,
      where: 'status = ? AND createdAt < ?',
      whereArgs: [NoteStatus.trashed.index, thirtyDaysAgo.toIso8601String()],
    );
  }

  Future<Database> get database async {
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
          version: 5,
          onCreate: _createDB,
          onUpgrade: _upgradeDB,
        ),
      );
    } else {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'notes_database.db');

      return await openDatabase(
        path,
        version: 5,
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
        reminder TEXT
      )
    ''');
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
  Future<int> addNote(NoteModel note) async {
    final db = await database;
    return await db.insert(_tableName, note.toJson());
  }

  @override
  Future<int> updateNote(NoteModel note) async {
    final db = await database;
    return await db.update(
      _tableName,
      note.toJson(),
      where: 'id = ?',
      whereArgs: [note.id],
    );
  }

  @override
  Future<int> deleteNote(int id) async {
    final db = await database;
    return await db.delete(_tableName, where: 'id = ?', whereArgs: [id]);
  }
}
