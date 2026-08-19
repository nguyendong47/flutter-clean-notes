import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';

enum NoteSort { newest, oldest, titleAZ, titleZA }

List<Note> filterNotes({
  required List<Note> notes,
  required NoteStatus status,
  String query = '',
  String? tag,
  required NoteSort sort,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final result = notes.where((note) {
    if (note.status != status) return false;
    if (tag != null && !note.tags.contains(tag)) return false;
    if (normalizedQuery.isEmpty) return true;

    return note.title.toLowerCase().contains(normalizedQuery) ||
        note.content.toLowerCase().contains(normalizedQuery) ||
        note.tags.any(
          (noteTag) => noteTag.toLowerCase().contains(normalizedQuery),
        );
  }).toList();

  result.sort((a, b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    return switch (sort) {
      NoteSort.newest => b.createdAt.compareTo(a.createdAt),
      NoteSort.oldest => a.createdAt.compareTo(b.createdAt),
      NoteSort.titleAZ => a.title.compareTo(b.title),
      NoteSort.titleZA => b.title.compareTo(a.title),
    };
  });

  return result;
}
