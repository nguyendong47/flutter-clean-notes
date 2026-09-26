import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_widget/home_widget.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_clean_notes/features/notes/data/services/home_widget_sync_gateway.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/domain/services/widget_sync_service.dart';

const String testNoteTitle = 'AppGroupSyncTest Title 98765';
const String testNoteContent = '''# Sync Verification
- [ ] Buy groceries for sync test
- [x] Completed item 42
- [ ] Third checklist item''';
const int testNoteColor = 0xFF4A90E2;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'syncs pinned note and checklist directly to shared App Group storage',
    (tester) async {
      final dataSource = LocalNoteDataSourceImpl();
      const gateway = HomeWidgetSyncGateway();
      const syncService = WidgetSyncService(gateway: gateway);

      // Create a distinctive pinned note with checklist markdown
      final newNote = NoteModel(
        title: testNoteTitle,
        content: testNoteContent,
        color: testNoteColor,
        createdAt: DateTime.now(),
        isPinned: true,
        status: NoteStatus.active,
      );

      final noteId = await dataSource.addNote(newNote);
      expect(noteId, greaterThan(0), reason: 'Note ID must be generated');

      // Fetch all notes from SQLite
      final notes = await dataSource.getNotes();
      final createdNote = notes.firstWhere(
        (n) => n.id == noteId,
        orElse: () => throw StateError('Created note $noteId not found in SQLite'),
      );
      expect(createdNote.isPinned, isTrue);

      // Execute widget sync using the app's real sync pipeline
      await syncService.syncNotes(notes);

      // In-process verification via HomeWidget plugin
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await HomeWidget.setAppGroupId(gateway.groupId);
      }

      final readHasPinned = await HomeWidget.getWidgetData<bool>('widget_has_pinned');
      final readTitle = await HomeWidget.getWidgetData<String>('widget_pinned_title');
      final readId = await HomeWidget.getWidgetData<String>('widget_pinned_id');
      final readChecklist = await HomeWidget.getWidgetData<String>('widget_pinned_checklist');

      expect(readHasPinned, isTrue, reason: 'widget_has_pinned must be true');
      expect(readTitle, equals(testNoteTitle), reason: 'widget_pinned_title must match');
      expect(readId, equals(noteId.toString()), reason: 'widget_pinned_id must match');
      expect(
        readChecklist,
        contains('Buy groceries for sync test'),
        reason: 'widget_pinned_checklist must include first checklist item',
      );
      expect(
        readChecklist,
        contains('Completed item 42'),
        reason: 'widget_pinned_checklist must include completed checklist item',
      );
    },
  );
}
