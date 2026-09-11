import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/widget_sync_payload.dart';
import 'package:flutter_clean_notes/features/notes/domain/services/widget_sync_gateway.dart';

class WidgetSyncService {
  const WidgetSyncService({required this.gateway});

  final WidgetSyncGateway gateway;

  /// Parse markdown text into a list of checklist items if checklist lines are present.
  static List<WidgetChecklistItem> extractChecklist(String markdown) {
    final items = <WidgetChecklistItem>[];
    final lines = markdown.split('\n');
    final checkPattern = RegExp(r'^\s*[-*]\s*\[([ xX])\]\s*(.*)$');

    for (final line in lines) {
      final match = checkPattern.firstMatch(line);
      if (match != null) {
        final mark = match.group(1);
        final text = match.group(2)?.trim() ?? '';
        final isDone = mark == 'x' || mark == 'X';
        if (text.isNotEmpty) {
          items.add(WidgetChecklistItem(text: text, isDone: isDone));
        }
      }
    }
    return items;
  }

  /// Create a preview text by taking up to [maxLines] non-empty lines.
  static String extractPreview(String content, {int maxLines = 4}) {
    final lines = content
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .take(maxLines)
        .toList();
    return lines.join('\n');
  }

  /// Build a sync payload from a collection of notes.
  /// Priority:
  /// 1. Pinned active note with the latest createdAt.
  /// 2. If no pinned notes exist, fall back to empty payload so widget displays empty state.
  WidgetSyncPayload buildPayload(List<Note> notes) {
    final activeNotes = notes
        .where((n) => n.status == NoteStatus.active)
        .toList();
    final pinnedNotes = activeNotes.where((n) => n.isPinned).toList();

    if (pinnedNotes.isEmpty) {
      return WidgetSyncPayload.empty;
    }

    pinnedNotes.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final target = pinnedNotes.first;

    final checklist = extractChecklist(target.content);
    final preview = extractPreview(target.content);

    return WidgetSyncPayload(
      hasPinned: true,
      noteId: target.id,
      title: target.title.trim().isNotEmpty
          ? target.title.trim()
          : 'Ghi chú đã ghim',
      contentPreview: preview,
      checklist: checklist,
      colorValue: target.color,
      updatedAt: target.createdAt,
    );
  }

  /// Synchronize the given list of notes to the home screen widget storage.
  Future<void> syncNotes(List<Note> notes) async {
    final payload = buildPayload(notes);
    await gateway.syncPayload(payload);
  }
}
