import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/reminder_command.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('exact-generation acknowledgement cannot remove a successor', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final firstAt = DateTime.utc(2030, 1, 15, 11);
    final secondAt = DateTime.utc(2030, 1, 15, 12);
    final id = await fixture.dataSource.addNote(_note(reminder: firstAt));
    final first = (await fixture.dataSource.pendingReminderCommands()).single;

    await fixture.dataSource.updateNote(_note(id: id, reminder: secondAt));
    final second = (await fixture.dataSource.pendingReminderCommands()).single;

    expect(second.generation, isNot(first.generation));
    expect(
      await fixture.dataSource.isReminderCommandCurrent(first.generation),
      isFalse,
    );
    expect(
      await fixture.dataSource.acknowledgeReminderCommand(first.generation),
      isFalse,
    );
    expect(
      await fixture.dataSource.isReminderCommandCurrent(second.generation),
      isTrue,
    );
    expect(
      await fixture.dataSource.acknowledgeReminderCommand(second.generation),
      isTrue,
    );
    expect(await fixture.dataSource.pendingReminderCommands(), isEmpty);
  });

  test('snooze persists a new generation before native work', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final id = await fixture.dataSource.addNote(
      _note(reminder: DateTime.utc(2030, 1, 15, 11)),
    );
    final current = (await fixture.dataSource.pendingReminderCommands()).single;
    final snoozedAt = DateTime.utc(2030, 1, 15, 11, 15);

    final snoozed = await fixture.dataSource.snoozeReminder(
      noteId: id,
      expectedGeneration: current.generation,
      scheduledAt: snoozedAt,
    );

    expect(snoozed, isNotNull);
    expect(snoozed!.generation, isNot(current.generation));
    expect(snoozed.scheduledAt, snoozedAt);
    final row = (await fixture.database.query('notes')).single;
    expect(row['reminder'], snoozedAt.toIso8601String());
    expect(row['reminderGeneration'], snoozed.generation);
    expect(await fixture.dataSource.pendingReminderCommands(), [snoozed]);
  });

  test('stale snooze performs no database work', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final reminder = DateTime.utc(2030, 1, 15, 11);
    final id = await fixture.dataSource.addNote(_note(reminder: reminder));
    final current = (await fixture.dataSource.pendingReminderCommands()).single;

    final result = await fixture.dataSource.snoozeReminder(
      noteId: id,
      expectedGeneration: current.generation + 1,
      scheduledAt: DateTime.utc(2030, 1, 15, 11, 15),
    );

    expect(result, isNull);
    expect(
      (await fixture.database.query('notes')).single['reminder'],
      reminder.toIso8601String(),
    );
    expect(await fixture.dataSource.pendingReminderCommands(), [current]);
  });

  test('legacy snooze is accepted only while generation is zero', () async {
    final fixture = await _Fixture.open();
    addTearDown(fixture.close);
    final id = await fixture.database.insert(
      'notes',
      _note(reminder: DateTime.utc(2030, 1, 15, 11)).toJson(),
    );

    final accepted = await fixture.dataSource.snoozeReminder(
      noteId: id,
      expectedGeneration: null,
      scheduledAt: DateTime.utc(2030, 1, 15, 11, 15),
    );
    final rejected = await fixture.dataSource.snoozeReminder(
      noteId: id,
      expectedGeneration: null,
      scheduledAt: DateTime.utc(2030, 1, 15, 11, 30),
    );

    expect(accepted, isNotNull);
    expect(rejected, isNull);
    expect(await fixture.dataSource.pendingReminderCommands(), [accepted]);
  });

  test(
    'audit preserves ambiguous legacy snooze with generation zero',
    () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.close);
      final id = await fixture.database.insert(
        'notes',
        _note(reminder: DateTime.utc(2029, 1, 15, 11)).toJson(),
      );

      await fixture.dataSource.reconcileReminderNotifications(
        pending: [PendingReminderNotification.legacy(notificationId: id)],
        now: DateTime.utc(2030, 1, 15),
      );

      expect(await fixture.dataSource.pendingReminderCommands(), isEmpty);
      expect(
        (await fixture.database.query('notes')).single['reminderGeneration'],
        0,
      );
    },
  );

  test(
    'audit creates v2 schedule only when future reminder has no coverage',
    () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.close);
      final id = await fixture.database.insert(
        'notes',
        _note(reminder: DateTime.utc(2030, 1, 15, 11)).toJson(),
      );

      await fixture.dataSource.reconcileReminderNotifications(
        pending: const [],
        now: DateTime.utc(2030, 1, 15, 10),
      );

      final command =
          (await fixture.dataSource.pendingReminderCommands()).single;
      expect(command.noteId, id);
      expect(command.operation, ReminderCommandOperation.schedule);
      expect(command.scheduledAt, DateTime.utc(2030, 1, 15, 11));
      expect(
        (await fixture.database.query('notes')).single['reminderGeneration'],
        command.generation,
      );
    },
  );

  test(
    'audit preserves matching v2 and cancels safe orphan ownership',
    () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.close);
      final id = await fixture.database.insert('notes', {
        ..._note(reminder: DateTime.utc(2030, 1, 15, 11)).toJson(),
        'reminderGeneration': 9,
      });

      await fixture.dataSource.reconcileReminderNotifications(
        pending: [
          PendingReminderNotification.v2(notificationId: id, generation: 9),
          const PendingReminderNotification.legacy(notificationId: 999),
        ],
        now: DateTime.utc(2030, 1, 15, 10),
      );

      final command =
          (await fixture.dataSource.pendingReminderCommands()).single;
      expect(command.noteId, 999);
      expect(command.operation, ReminderCommandOperation.cancel);
    },
  );

  test(
    'audit cancels an expired v2 notification but preserves legacy gen0',
    () async {
      final fixture = await _Fixture.open();
      addTearDown(fixture.close);
      final expiredV2 = await fixture.database.insert('notes', {
        ..._note(reminder: DateTime.utc(2029, 1, 15)).toJson(),
        'reminderGeneration': 9,
      });
      final legacy = await fixture.database.insert(
        'notes',
        _note(reminder: DateTime.utc(2029, 1, 16)).toJson(),
      );

      await fixture.dataSource.reconcileReminderNotifications(
        pending: [
          PendingReminderNotification.v2(
            notificationId: expiredV2,
            generation: 9,
          ),
          PendingReminderNotification.legacy(notificationId: legacy),
        ],
        now: DateTime.utc(2030, 1, 15),
      );

      final command =
          (await fixture.dataSource.pendingReminderCommands()).single;
      expect(command.noteId, expiredV2);
      expect(command.operation, ReminderCommandOperation.cancel);
      expect(
        (await fixture.database.query(
          'notes',
          columns: const ['reminderGeneration'],
          where: 'id = ?',
          whereArgs: [legacy],
        )).single['reminderGeneration'],
        0,
      );
    },
  );
}

NoteModel _note({int? id, DateTime? reminder}) => NoteModel(
  id: id,
  title: 'Note',
  content: '',
  color: 1,
  createdAt: DateTime.utc(2030, 1, 15),
  reminder: reminder,
);

final class _Fixture {
  const _Fixture(this.database, this.dataSource);

  final Database database;
  final LocalNoteDataSourceImpl dataSource;

  static Future<_Fixture> open() async {
    final database = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
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
    return _Fixture(database, LocalNoteDataSourceImpl(database: database));
  }

  Future<void> close() => database.close();
}
