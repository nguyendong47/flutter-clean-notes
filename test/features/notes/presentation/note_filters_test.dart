import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_filters.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/note_fixtures.dart';

void main() {
  test('combines status normalized query exact tag and sort', () {
    final result = filterNotes(
      notes: sampleNotes,
      status: NoteStatus.active,
      query: '  DESIGN  ',
      tag: 'work',
      sort: NoteSort.titleAZ,
    );

    expect(result.map((note) => note.title), [
      'Aurora design',
      'Design follow-up',
    ]);
  });

  test('matches a normalized query against title content and tags', () {
    final titleMatch = filterNotes(
      notes: sampleNotes,
      status: NoteStatus.active,
      query: 'AURORA',
      sort: NoteSort.newest,
    );
    final contentMatch = filterNotes(
      notes: sampleNotes,
      status: NoteStatus.active,
      query: 'stationery',
      sort: NoteSort.newest,
    );
    final tagMatch = filterNotes(
      notes: sampleNotes,
      status: NoteStatus.active,
      query: 'PERSONAL',
      sort: NoteSort.newest,
    );

    expect(titleMatch.map((note) => note.id), [1]);
    expect(contentMatch.map((note) => note.id), [3]);
    expect(tagMatch.map((note) => note.id), [3]);
  });

  test('requires an exact selected tag', () {
    final result = filterNotes(
      notes: sampleNotes,
      status: NoteStatus.active,
      tag: 'Work',
      sort: NoteSort.newest,
    );

    expect(result, isEmpty);
  });

  test('keeps pinned notes first then applies every requested sort', () {
    final notes = [
      Note(
        id: 10,
        title: 'Zulu pinned',
        content: '',
        color: 0,
        createdAt: DateTime.utc(2026, 8, 10),
        isPinned: true,
      ),
      Note(
        id: 11,
        title: 'Alpha pinned',
        content: '',
        color: 0,
        createdAt: DateTime.utc(2026, 8, 11),
        isPinned: true,
      ),
      Note(
        id: 12,
        title: 'Bravo',
        content: '',
        color: 0,
        createdAt: DateTime.utc(2026, 8, 12),
      ),
      Note(
        id: 13,
        title: 'Charlie',
        content: '',
        color: 0,
        createdAt: DateTime.utc(2026, 8, 9),
      ),
    ];

    expect(
      filterNotes(
        notes: notes,
        status: NoteStatus.active,
        sort: NoteSort.newest,
      ).map((note) => note.id),
      [11, 10, 12, 13],
    );
    expect(
      filterNotes(
        notes: notes,
        status: NoteStatus.active,
        sort: NoteSort.oldest,
      ).map((note) => note.id),
      [10, 11, 13, 12],
    );
    expect(
      filterNotes(
        notes: notes,
        status: NoteStatus.active,
        sort: NoteSort.titleAZ,
      ).map((note) => note.id),
      [11, 10, 12, 13],
    );
    expect(
      filterNotes(
        notes: notes,
        status: NoteStatus.active,
        sort: NoteSort.titleZA,
      ).map((note) => note.id),
      [10, 11, 13, 12],
    );
  });

  test('sorts a copy without mutating the input list', () {
    final input = List<Note>.of(sampleNotes);
    final originalIds = input.map((note) => note.id).toList();

    final result = filterNotes(
      notes: input,
      status: NoteStatus.active,
      sort: NoteSort.titleZA,
    );

    expect(input.map((note) => note.id), originalIds);
    expect(result, isNot(same(input)));
  });
}
