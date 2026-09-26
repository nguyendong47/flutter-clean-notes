import 'package:flutter/foundation.dart';
import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_clean_notes/features/notes/data/services/home_widget_sync_gateway.dart';
import 'package:flutter_clean_notes/features/notes/domain/services/widget_sync_service.dart';

/// Top-level callback invoked by `home_widget` when an interactive action occurs
/// on a home screen widget in background isolate.
@pragma('vm:entry-point')
Future<void> widgetInteractiveCallback(Uri? uri) async {
  if (uri == null) return;

  if (uri.scheme == 'clean-notes' && uri.host == 'toggle-check') {
    final noteIdStr = uri.queryParameters['id'];
    final indexStr = uri.queryParameters['index'];
    if (noteIdStr == null || indexStr == null) return;

    final noteId = int.tryParse(noteIdStr);
    final index = int.tryParse(indexStr);
    if (noteId == null || index == null) return;

    await handleChecklistToggle(noteId: noteId, itemIndex: index);
  }
}

/// Toggles a checklist item in SQLite database and syncs updated state to home screen widgets.
Future<void> handleChecklistToggle({
  required int noteId,
  required int itemIndex,
  NotesPersistenceDataSource? dataSource,
  WidgetSyncService? syncService,
}) async {
  try {
    final ds = dataSource ?? LocalNoteDataSourceImpl();
    final notes = await ds.getNotes();
    final noteIndex = notes.indexWhere((n) => n.id == noteId);
    if (noteIndex == -1) return;

    final targetNote = notes[noteIndex];
    final updatedContent = WidgetSyncService.toggleChecklistItem(
      targetNote.content,
      itemIndex,
    );

    if (updatedContent == targetNote.content) return;

    final updatedModel = NoteModel.fromEntity(
      targetNote.copyWith(content: updatedContent, createdAt: DateTime.now()),
    );
    await ds.updateNote(updatedModel);

    final refreshedNotes = await ds.getNotes();
    final service =
        syncService ??
        const WidgetSyncService(gateway: HomeWidgetSyncGateway());
    await service.syncNotes(refreshedNotes);
  } catch (e, st) {
    debugPrint('Error toggling checklist item in background: $e\n$st');
  }
}
