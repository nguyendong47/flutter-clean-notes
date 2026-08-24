import 'dart:io';

import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_clean_notes/features/notes/data/repositories/reminder_outbox_repository_impl.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/reminder_command.dart';
import 'package:flutter_clean_notes/features/notes/domain/repositories/reminder_outbox_repository.dart';
import 'package:flutter_clean_notes/features/notes/domain/services/reminder_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  final now = DateTime.utc(2030, 1, 15, 10);

  test(
    'committed create survives process death before native schedule',
    () async {
      final fixture = await _PhysicalFixture.create();
      addTearDown(fixture.dispose);
      final firstDatabase = await fixture.open();
      final firstDataSource = LocalNoteDataSourceImpl(database: firstDatabase);
      final reminder = now.add(const Duration(hours: 1));
      final id = await firstDataSource.addNote(_note(reminder));
      final generation =
          (await firstDataSource.pendingReminderCommands()).single.generation;
      await firstDatabase.close();

      final restartedDatabase = await fixture.open();
      final restartedDataSource = LocalNoteDataSourceImpl(
        database: restartedDatabase,
      );
      final gateway = _NativeStoreGateway();
      final coordinator = ReminderCoordinator(
        repository: ReminderOutboxRepositoryImpl(restartedDataSource),
        gateway: gateway,
        now: () => now,
      );
      await coordinator.drain(
        permissionPolicy: ReminderPermissionPolicy.existingOnly,
      );

      expect(gateway.scheduled.single.generation, generation);
      expect(gateway.scheduled.single.noteId, id);
      expect(gateway.scheduled.single.scheduledAt, reminder);
      expect(await restartedDataSource.pendingReminderCommands(), isEmpty);
      await restartedDatabase.close();
    },
  );

  test(
    'native success before ack replays the same generation after restart',
    () async {
      final fixture = await _PhysicalFixture.create();
      addTearDown(fixture.dispose);
      final firstDatabase = await fixture.open();
      final firstDataSource = LocalNoteDataSourceImpl(database: firstDatabase);
      await firstDataSource.addNote(_note(now.add(const Duration(hours: 1))));
      final command = (await firstDataSource.pendingReminderCommands()).single;
      final firstGateway = _NativeStoreGateway()..throwAfterScheduling = true;
      final firstCoordinator = ReminderCoordinator(
        repository: ReminderOutboxRepositoryImpl(firstDataSource),
        gateway: firstGateway,
        now: () => now,
      );

      await expectLater(firstCoordinator.drain(), throwsStateError);
      expect(firstGateway.byId[command.noteId], command);
      expect(await firstDataSource.pendingReminderCommands(), [command]);
      await firstDatabase.close();

      final restartedDatabase = await fixture.open();
      final restartedDataSource = LocalNoteDataSourceImpl(
        database: restartedDatabase,
      );
      final restartedGateway = _NativeStoreGateway();
      final restartedCoordinator = ReminderCoordinator(
        repository: ReminderOutboxRepositoryImpl(restartedDataSource),
        gateway: restartedGateway,
        now: () => now,
      );
      await restartedCoordinator.drain();

      expect(restartedGateway.byId[command.noteId], command);
      expect(await restartedDataSource.pendingReminderCommands(), isEmpty);
      await restartedDatabase.close();
    },
  );

  test('durable snooze survives permission denial and restart', () async {
    final fixture = await _PhysicalFixture.create();
    addTearDown(fixture.dispose);
    final firstDatabase = await fixture.open();
    final firstDataSource = LocalNoteDataSourceImpl(database: firstDatabase);
    final id = await firstDataSource.addNote(
      _note(now.add(const Duration(hours: 1))),
    );
    final original = (await firstDataSource.pendingReminderCommands()).single;
    final nativeStore = <int, ReminderCommand>{};
    final deniedGateway = _NativeStoreGateway(nativeStore: nativeStore);
    final firstCoordinator = ReminderCoordinator(
      repository: ReminderOutboxRepositoryImpl(firstDataSource),
      gateway: deniedGateway,
      now: () => now,
    );
    await firstCoordinator.drain();
    expect(nativeStore[id], original);
    deniedGateway.denyScheduling = true;

    await expectLater(
      firstCoordinator.snooze(
        noteId: id,
        expectedGeneration: original.generation,
        delayMinutes: 15,
      ),
      throwsA(isA<_PermissionDenied>()),
    );
    final snoozed = (await firstDataSource.pendingReminderCommands()).single;
    expect(snoozed.scheduledAt, now.add(const Duration(minutes: 15)));
    expect(nativeStore, isEmpty);
    await firstDatabase.close();

    final restartedDatabase = await fixture.open();
    final restartedDataSource = LocalNoteDataSourceImpl(
      database: restartedDatabase,
    );
    final restartedGateway = _NativeStoreGateway(nativeStore: nativeStore);
    final restartedCoordinator = ReminderCoordinator(
      repository: ReminderOutboxRepositoryImpl(restartedDataSource),
      gateway: restartedGateway,
      now: () => now,
    );
    await restartedCoordinator.reconcileAtStartup();

    expect(restartedGateway.scheduled.single, snoozed);
    expect(
      (await restartedDatabase.query('notes')).single['reminder'],
      snoozed.scheduledAt!.toIso8601String(),
    );
    await restartedDatabase.close();
  });
}

NoteModel _note(DateTime reminder) => NoteModel(
  title: 'Process death',
  content: '',
  color: 1,
  createdAt: DateTime.utc(2030, 1, 15),
  reminder: reminder,
);

final class _PermissionDenied implements Exception {}

final class _NativeStoreGateway implements ReminderNotificationGateway {
  _NativeStoreGateway({Map<int, ReminderCommand>? nativeStore})
    : byId = nativeStore ?? <int, ReminderCommand>{};

  @override
  bool get supportsScheduling => true;

  final Map<int, ReminderCommand> byId;
  final List<ReminderCommand> scheduled = [];
  bool throwAfterScheduling = false;
  bool denyScheduling = false;

  @override
  Future<void> cancel(int noteId) async {
    byId.remove(noteId);
  }

  @override
  Future<List<PendingReminderNotification>> pendingNotifications() async {
    return [
      for (final command in byId.values)
        PendingReminderNotification.v2(
          notificationId: command.noteId,
          generation: command.generation,
        ),
    ];
  }

  @override
  Future<void> schedule(
    ReminderCommand command, {
    required ReminderPermissionPolicy permissionPolicy,
  }) async {
    if (denyScheduling) throw _PermissionDenied();
    byId[command.noteId] = command;
    scheduled.add(command);
    if (throwAfterScheduling) throw StateError('crashed before ack');
  }
}

final class _PhysicalFixture {
  const _PhysicalFixture(this.directory, this.databasePath);

  final Directory directory;
  final String databasePath;

  static Future<_PhysicalFixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'clean_notes_outbox_',
    );
    return _PhysicalFixture(
      directory,
      path.join(directory.path, 'notes_database.db'),
    );
  }

  Future<Database> open() {
    return databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: 7,
        onCreate: (database, _) async {
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
          await database.execute('''
            CREATE INDEX reminder_outbox_note_generation
            ON reminder_outbox(noteId, generation)
          ''');
        },
      ),
    );
  }

  Future<void> dispose() async {
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}
