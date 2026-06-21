import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';

abstract class LocalNoteDataSource {
  Future<List<NoteModel>> getNotes();
  Future<int> addNote(NoteModel note);
  Future<int> updateNote(NoteModel note);
  Future<int> deleteNote(int id);
}

class LocalNoteDataSourceImpl implements LocalNoteDataSource {
  static Database? _database;
  static const String _tableName = 'notes';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final docDir = await getApplicationSupportDirectory();
      final path = join(docDir.path, 'notes_database.db');
      
      // Ensure FFI libraries are loaded before opening the database
      sqfliteFfiInit();
      
      // Explicitly use the FFI factory to bypass the global sqflite channels that are failing 
      return await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: _createDB,
        ),
      );
    } else {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'notes_database.db');
      
      return await openDatabase(
        path,
        version: 1,
        onCreate: _createDB,
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
        createdAt TEXT NOT NULL
      )
    ''');
  }

  @override
  Future<List<NoteModel>> getNotes() async {
    final db = await database;
    final result = await db.query(_tableName, orderBy: 'createdAt DESC');
    return result.map((json) => NoteModel.fromJson(json)).toList();
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
    return await db.delete(
      _tableName,
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
