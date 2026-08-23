import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/domain/usecases/note_usecases.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/in_memory_note_repository.dart';

void main() {
  test(
    'ImportNotes appends with fresh active identity and no reminder',
    () async {
      final existing = Note(
        id: 7,
        title: 'Existing',
        content: '',
        color: 0,
        createdAt: DateTime.utc(2026, 8, 22),
      );
      final repository = InMemoryNoteRepository.seeded([existing]);
      final imported = Note(
        id: 7,
        title: 'Imported',
        content: 'Backup content',
        color: 1,
        createdAt: DateTime.utc(2026, 8, 23),
        tags: const ['finance,2026'],
        status: NoteStatus.archived,
        reminder: DateTime.utc(2026, 8, 24),
      );

      await ImportNotes(repository)([imported]);

      expect(repository.notes, hasLength(2));
      final appended = repository.notes.singleWhere(
        (note) => note.title == 'Imported',
      );
      expect(appended.id, isNot(existing.id));
      expect(appended.status, NoteStatus.active);
      expect(appended.reminder, isNull);
      expect(appended.tags, ['finance,2026']);
    },
  );

  test('RemoveTag delegates one atomic repository operation', () async {
    final repository = InMemoryNoteRepository.seeded([
      Note(
        id: 1,
        title: 'Active',
        content: '',
        color: 0,
        createdAt: DateTime.utc(2026, 8, 23),
        tags: const ['shared', 'active'],
      ),
      Note(
        id: 2,
        title: 'Archive',
        content: '',
        color: 0,
        createdAt: DateTime.utc(2026, 8, 22),
        tags: const ['shared', 'archive'],
        status: NoteStatus.archived,
      ),
    ]);

    final changed = await RemoveTag(repository)('shared');

    expect(changed, 2);
    expect(repository.removeTagCalls, 1);
    expect(
      repository.notes.expand((note) => note.tags),
      isNot(contains('shared')),
    );
  });
}
