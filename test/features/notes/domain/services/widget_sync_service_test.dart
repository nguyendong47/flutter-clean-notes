import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/widget_sync_payload.dart';
import 'package:flutter_clean_notes/features/notes/domain/services/widget_sync_gateway.dart';
import 'package:flutter_clean_notes/features/notes/domain/services/widget_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWidgetSyncGateway implements WidgetSyncGateway {
  WidgetSyncPayload? lastPayload;
  int syncCount = 0;

  @override
  Future<void> syncPayload(WidgetSyncPayload payload) async {
    lastPayload = payload;
    syncCount++;
  }
}

void main() {
  group('WidgetSyncService.extractChecklist', () {
    test('parses checklist markdown patterns into checklist items', () {
      const markdown = '''
# Heading
- [ ] Buy groceries
- [x] Pay electricity bill
* [X] Call doctor
* [ ] Schedule meeting
- Normal bullet item
Not a bullet
- [ ]   
''';

      final items = WidgetSyncService.extractChecklist(markdown);
      expect(items.length, 4);
      expect(
        items[0],
        const WidgetChecklistItem(text: 'Buy groceries', isDone: false),
      );
      expect(
        items[1],
        const WidgetChecklistItem(text: 'Pay electricity bill', isDone: true),
      );
      expect(
        items[2],
        const WidgetChecklistItem(text: 'Call doctor', isDone: true),
      );
      expect(
        items[3],
        const WidgetChecklistItem(text: 'Schedule meeting', isDone: false),
      );
    });

    test('returns empty list when no checklist items are found', () {
      const markdown = 'Just plain paragraph text\nWith multiple lines.';
      expect(WidgetSyncService.extractChecklist(markdown), isEmpty);
    });
  });

  group('WidgetSyncService.toggleChecklistItem', () {
    const sampleMarkdown = '''
# Todo List
- [ ] First task
- [x] Second task
Some middle note
* [ ] Third task
* [X] Fourth task
''';

    test('toggles unchecked item to checked', () {
      final result = WidgetSyncService.toggleChecklistItem(sampleMarkdown, 0);
      expect(result, contains('- [x] First task'));
      expect(result, contains('- [x] Second task'));
      expect(result, contains('* [ ] Third task'));
    });

    test('toggles checked item to unchecked', () {
      final result = WidgetSyncService.toggleChecklistItem(sampleMarkdown, 1);
      expect(result, contains('- [ ] First task'));
      expect(result, contains('- [ ] Second task'));
    });

    test('toggles asterisk bullet and uppercase checkmark', () {
      final result = WidgetSyncService.toggleChecklistItem(sampleMarkdown, 3);
      expect(result, contains('* [ ] Fourth task'));
    });

    test('returns unmodified markdown when index is negative', () {
      final result = WidgetSyncService.toggleChecklistItem(sampleMarkdown, -1);
      expect(result, sampleMarkdown);
    });

    test('returns unmodified markdown when index is out of bounds', () {
      final result = WidgetSyncService.toggleChecklistItem(sampleMarkdown, 99);
      expect(result, sampleMarkdown);
    });
  });

  group('WidgetSyncService.buildPayload', () {
    final gateway = _FakeWidgetSyncGateway();
    final service = WidgetSyncService(gateway: gateway);

    test('returns empty payload when notes list is empty', () {
      final payload = service.buildPayload([]);
      expect(payload.hasPinned, isFalse);
      expect(payload.title, isEmpty);
    });

    test('returns empty payload when no note is pinned', () {
      final notes = [
        Note(
          id: 1,
          title: 'Unpinned note',
          content: 'Hello world',
          color: 0xFF123456,
          createdAt: DateTime(2026, 9, 1),
          isPinned: false,
        ),
      ];

      final payload = service.buildPayload(notes);
      expect(payload.hasPinned, isFalse);
    });

    test('ignores archived and trashed notes even if marked as pinned', () {
      final notes = [
        Note(
          id: 1,
          title: 'Archived note',
          content: 'Content',
          color: 0xFF111111,
          createdAt: DateTime(2026, 9, 1),
          isPinned: true,
          status: NoteStatus.archived,
        ),
        Note(
          id: 2,
          title: 'Trashed note',
          content: 'Content',
          color: 0xFF222222,
          createdAt: DateTime(2026, 9, 2),
          isPinned: true,
          status: NoteStatus.trashed,
        ),
      ];

      final payload = service.buildPayload(notes);
      expect(payload.hasPinned, isFalse);
    });

    test(
      'selects the most recently created pinned note when multiple are pinned',
      () {
        final olderPinned = Note(
          id: 1,
          title: 'Older pinned',
          content: '- [ ] Item 1',
          color: 0xFF111111,
          createdAt: DateTime(2026, 9, 1),
          isPinned: true,
        );
        final newerPinned = Note(
          id: 2,
          title: 'Newer pinned',
          content: '- [x] Completed task\n- [ ] Pending task',
          color: 0xFF222222,
          createdAt: DateTime(2026, 9, 5),
          isPinned: true,
        );

        final payload = service.buildPayload([olderPinned, newerPinned]);
        expect(payload.hasPinned, isTrue);
        expect(payload.noteId, 2);
        expect(payload.title, 'Newer pinned');
        expect(payload.colorValue, 0xFF222222);
        expect(payload.checklist.length, 2);
        expect(payload.checklist[0].isDone, isTrue);
        expect(payload.checklist[1].isDone, isFalse);
      },
    );

    test('syncNotes invokes gateway with built payload', () async {
      final gateway = _FakeWidgetSyncGateway();
      final service = WidgetSyncService(gateway: gateway);

      final note = Note(
        id: 10,
        title: 'Important Note',
        content: 'Preview body text',
        color: 0xFF333333,
        createdAt: DateTime(2026, 9, 10),
        isPinned: true,
      );

      await service.syncNotes([note]);
      expect(gateway.syncCount, 1);
      expect(gateway.lastPayload?.hasPinned, isTrue);
      expect(gateway.lastPayload?.noteId, 10);
      expect(gateway.lastPayload?.title, 'Important Note');
      expect(gateway.lastPayload?.contentPreview, 'Preview body text');
    });
  });
}
