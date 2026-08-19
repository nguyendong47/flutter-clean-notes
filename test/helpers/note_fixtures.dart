import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';

final sampleNote = Note(
  id: 1,
  title: 'Aurora design',
  content: 'Plan the glass experience',
  color: 0xFF6757D9,
  createdAt: DateTime.utc(2026, 8, 17, 10),
  isPinned: true,
  tags: const ['work', 'design'],
  reminder: DateTime.utc(2026, 8, 18, 9),
);

final sampleNotes = List<Note>.unmodifiable([
  sampleNote,
  Note(
    id: 2,
    title: 'Design follow-up',
    content: 'Review the mobile mockups',
    color: 0xFF2DB9A8,
    createdAt: DateTime.utc(2026, 8, 19, 8),
    tags: const ['work'],
  ),
  Note(
    id: 3,
    title: 'Personal errands',
    content: 'Buy tea and stationery',
    color: 0xFFFFB86B,
    createdAt: DateTime.utc(2026, 8, 16, 12),
    tags: const ['personal'],
  ),
  Note(
    id: 4,
    title: 'Archived launch notes',
    content: 'The previous release checklist',
    color: 0xFF6757D9,
    createdAt: DateTime.utc(2026, 8, 15, 9),
    tags: const ['work', 'archive'],
    status: NoteStatus.archived,
  ),
  Note(
    id: 5,
    title: 'Discarded draft',
    content: 'An obsolete design direction',
    color: 0xFF8D91A8,
    createdAt: DateTime.utc(2026, 8, 14, 14),
    tags: const ['draft'],
    status: NoteStatus.trashed,
  ),
]);
