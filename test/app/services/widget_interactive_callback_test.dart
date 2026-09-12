import 'package:flutter_clean_notes/app/services/widget_interactive_callback.dart';
import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/reminder_command.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/widget_sync_payload.dart';
import 'package:flutter_clean_notes/features/notes/domain/services/widget_sync_gateway.dart';
import 'package:flutter_clean_notes/features/notes/domain/services/widget_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDataSource implements NotesPersistenceDataSource {
  final List<NoteModel> storedNotes = [];
  NoteModel? lastUpdatedNote;

  @override
  Future<List<NoteModel>> getNotes() async => List.of(storedNotes);

  @override
  Future<int> updateNote(NoteModel note) async {
    lastUpdatedNote = note;
    final index = storedNotes.indexWhere((n) => n.id == note.id);
    if (index != -1) {
      storedNotes[index] = note;
    }
    return 1;
  }

  @override
  Future<int> addNote(NoteModel note) async {
    storedNotes.add(note);
    return note.id ?? storedNotes.length;
  }

  @override
  Future<void> importNotes(List<NoteModel> notes) async {}

  @override
  Future<int> deleteNote(int id) async => 1;

  @override
  Future<List<NoteModel>> getNotesByStatus(int status) async => [];

  @override
  Future<int> setNoteStatus(int id, int status) async => 1;

  @override
  Future<int> toggleNotePin(int id) async => 1;

  @override
  Future<int> cleanupTrash() async => 0;

  @override
  Future<int> removeTag(String tag) async => 0;

  @override
  Future<bool> acknowledgeReminderCommand(int generation) async => true;

  @override
  Future<bool> isReminderCommandCurrent(int generation) async => true;

  @override
  Future<List<ReminderCommand>> pendingReminderCommands({int? noteId}) async => [];

  @override
  Future<void> reconcileReminderNotifications({
    required List<PendingReminderNotification> pending,
    required DateTime now,
  }) async {}

  @override
  Future<ReminderCommand?> snoozeReminder({
    required int noteId,
    required int? expectedGeneration,
    required DateTime scheduledAt,
  }) async => null;
}

class _FakeGateway implements WidgetSyncGateway {
  WidgetSyncPayload? lastPayload;
  int syncCalls = 0;

  @override
  Future<void> syncPayload(WidgetSyncPayload payload) async {
    lastPayload = payload;
    syncCalls++;
  }
}

void main() {
  group('handleChecklistToggle', () {
    late _FakeDataSource dataSource;
    late _FakeGateway gateway;
    late WidgetSyncService syncService;

    setUp(() {
      dataSource = _FakeDataSource();
      gateway = _FakeGateway();
      syncService = WidgetSyncService(gateway: gateway);

      dataSource.storedNotes.add(
        NoteModel(
          id: 42,
          title: 'Checklist note',
          content: '- [ ] Task 1\n- [x] Task 2\n- [ ] Task 3',
          color: 0xFF000000,
          createdAt: DateTime(2026, 9, 10),
          isPinned: true,
        ),
      );
    });

    test('toggles checklist item from unchecked to checked and syncs', () async {
      await handleChecklistToggle(
        noteId: 42,
        itemIndex: 0,
        dataSource: dataSource,
        syncService: syncService,
      );

      expect(dataSource.lastUpdatedNote, isNotNull);
      expect(dataSource.lastUpdatedNote!.content, contains('- [x] Task 1'));
      expect(dataSource.lastUpdatedNote!.content, contains('- [x] Task 2'));
      expect(gateway.syncCalls, 1);
      expect(gateway.lastPayload?.hasPinned, isTrue);
      expect(gateway.lastPayload?.checklist.first.isDone, isTrue);
    });

    test('toggles checklist item from checked to unchecked and syncs', () async {
      await handleChecklistToggle(
        noteId: 42,
        itemIndex: 1,
        dataSource: dataSource,
        syncService: syncService,
      );

      expect(dataSource.lastUpdatedNote, isNotNull);
      expect(dataSource.lastUpdatedNote!.content, contains('- [ ] Task 1'));
      expect(dataSource.lastUpdatedNote!.content, contains('- [ ] Task 2'));
      expect(gateway.syncCalls, 1);
      expect(gateway.lastPayload?.checklist[1].isDone, isFalse);
    });

    test('does nothing when noteId does not exist', () async {
      await handleChecklistToggle(
        noteId: 999,
        itemIndex: 0,
        dataSource: dataSource,
        syncService: syncService,
      );

      expect(dataSource.lastUpdatedNote, isNull);
      expect(gateway.syncCalls, 0);
    });

    test('does nothing when itemIndex is out of bounds', () async {
      await handleChecklistToggle(
        noteId: 42,
        itemIndex: 99,
        dataSource: dataSource,
        syncService: syncService,
      );

      expect(dataSource.lastUpdatedNote, isNull);
      expect(gateway.syncCalls, 0);
    });
  });

  group('widgetInteractiveCallback URI routing', () {
    test('ignores non-matching URIs safely', () async {
      await expectLater(
        widgetInteractiveCallback(Uri.parse('https://example.com')),
        completes,
      );
      await expectLater(
        widgetInteractiveCallback(Uri.parse('clean-notes://note?id=42')),
        completes,
      );
      await expectLater(
        widgetInteractiveCallback(null),
        completes,
      );
    });
  });
}
