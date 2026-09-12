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

  /// Toggle a checklist item at the given [targetIndex] (0-based) in markdown text.
  /// Converts `- [ ]` / `* [ ]` to `- [x]` and `- [x]` / `* [x]` to `- [ ]`.
  /// Returns the modified markdown content, or original markdown if [targetIndex] is out of bounds.
  static String toggleChecklistItem(String markdown, int targetIndex) {
    if (targetIndex < 0) return markdown;

    final lines = markdown.split('\n');
    final checkPattern = RegExp(r'^(\s*[-*]\s*\[)([ xX])(\]\s*.*)$');
    var currentIndex = 0;
    var modified = false;
    final updatedLines = <String>[];

    for (final line in lines) {
      final match = checkPattern.firstMatch(line);
      if (match != null) {
        if (currentIndex == targetIndex) {
          final prefix = match.group(1)!;
          final mark = match.group(2)!;
          final suffix = match.group(3)!;
          final newMark = (mark == 'x' || mark == 'X') ? ' ' : 'x';
          updatedLines.add('$prefix$newMark$suffix');
          modified = true;
        } else {
          updatedLines.add(line);
        }
        currentIndex++;
      } else {
        updatedLines.add(line);
      }
    }

    return modified ? updatedLines.join('\n') : markdown;
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

    final boundItems = activeNotes.take(10).map((n) {
      return WidgetNoteItem(
        id: n.id ?? 0,
        title: n.title.trim().isNotEmpty ? n.title.trim() : 'Ghi chú',
        contentPreview: extractPreview(n.content),
        checklist: extractChecklist(n.content),
        colorValue: n.color,
      );
    }).toList();

    if (pinnedNotes.isEmpty) {
      return WidgetSyncPayload(hasPinned: false, boundNotes: boundItems);
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
      boundNotes: boundItems,
    );
  }

  /// Synchronize the given list of notes to the home screen widget storage.
  Future<void> syncNotes(List<Note> notes) async {
    final payload = buildPayload(notes);
    await gateway.syncPayload(payload);
  }
}
