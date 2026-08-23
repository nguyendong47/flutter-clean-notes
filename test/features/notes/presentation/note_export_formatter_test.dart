import 'dart:convert';

import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/note_export_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NoteExportFormatter JSON', () {
    test('round-trips every persisted note field in the current format', () {
      final note = Note(
        id: 42,
        title: 'Aurora backup',
        content: 'Every field survives.',
        color: 0xFF6757D9,
        createdAt: DateTime.utc(2026, 8, 23, 9, 15),
        isPinned: true,
        tags: const ['work', 'finance,2026'],
        status: NoteStatus.archived,
        reminder: DateTime.utc(2026, 8, 24, 7, 30),
      );

      final payload = NoteExportFormatter.toJson([note]);
      final restored = NoteExportFormatter.fromJson(payload).single;

      expect(restored.id, note.id);
      expect(restored.title, note.title);
      expect(restored.content, note.content);
      expect(restored.color, note.color);
      expect(restored.createdAt, note.createdAt);
      expect(restored.isPinned, note.isPinned);
      expect(restored.tags, note.tags);
      expect(restored.status, note.status);
      expect(restored.reminder, note.reminder);

      final encoded = (jsonDecode(payload) as List<Object?>).single;
      expect(encoded, <String, Object?>{
        'id': 42,
        'title': 'Aurora backup',
        'content': 'Every field survives.',
        'color': 0xFF6757D9,
        'createdAt': '2026-08-23T09:15:00.000Z',
        'isPinned': 1,
        'tags': ['work', 'finance,2026'],
        'status': 1,
        'reminder': '2026-08-24T07:30:00.000Z',
      });
      expect(NoteExportFormatter.toJson([note]), payload);
    });

    test('accepts legacy comma-delimited backup tags', () {
      final payload = jsonEncode([
        {
          'title': 'Legacy tags',
          'content': '',
          'color': 17,
          'createdAt': '2026-08-17T10:00:00.000Z',
          'isPinned': 0,
          'tags': 'legacy, work',
          'status': 0,
          'reminder': null,
        },
      ]);

      final note = NoteExportFormatter.fromJson(payload).single;

      expect(note.tags, ['legacy', 'work']);
    });

    test('accepts the legacy boolean list and named-status shape', () {
      final payload = jsonEncode([
        {
          'title': 'Legacy note',
          'content': 'Created by the original UI exporter',
          'color': 17,
          'createdAt': '2026-08-17T10:00:00.000Z',
          'isPinned': true,
          'tags': ['legacy', 'work'],
          'status': 'trashed',
        },
      ]);

      final note = NoteExportFormatter.fromJson(payload).single;

      expect(note.id, isNull);
      expect(note.title, 'Legacy note');
      expect(note.isPinned, isTrue);
      expect(note.tags, ['legacy', 'work']);
      expect(note.status, NoteStatus.trashed);
      expect(note.reminder, isNull);
    });

    test('rejects malformed top-level JSON with a readable format error', () {
      for (final payload in ['not json', '{}', 'null']) {
        expect(
          () => NoteExportFormatter.fromJson(payload),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('backup'),
            ),
          ),
          reason: payload,
        );
      }
    });

    test('rejects non-map note entries without leaking a cast error', () {
      expect(
        () => NoteExportFormatter.fromJson('[1]'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Note 1'),
          ),
        ),
      );
    });

    test('rejects wrong scalar and collection types by field', () {
      final valid = <String, Object?>{
        'id': 8,
        'title': 'Valid title',
        'content': 'Valid content',
        'color': 7,
        'createdAt': '2026-08-23T09:00:00.000Z',
        'isPinned': 1,
        'tags': 'work,design',
        'status': 0,
        'reminder': null,
      };
      final invalidValues = <String, Object?>{
        'id': '8',
        'title': 7,
        'content': false,
        'color': 'violet',
        'createdAt': 12,
        'isPinned': 'yes',
        'tags': [1],
        'status': true,
        'reminder': 12,
      };

      for (final entry in invalidValues.entries) {
        final malformed = {...valid, entry.key: entry.value};
        expect(
          () => NoteExportFormatter.fromJson(jsonEncode([malformed])),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              contains('"${entry.key}"'),
            ),
          ),
          reason: entry.key,
        );
      }
    });

    test('rejects invalid dates and status values as format errors', () {
      final base = <String, Object?>{
        'title': 'Invalid field',
        'content': '',
        'color': 0,
        'createdAt': '2026-08-23T09:00:00.000Z',
        'isPinned': 0,
        'tags': '',
        'status': 0,
        'reminder': null,
      };

      for (final malformed in [
        {...base, 'createdAt': 'not-a-date'},
        {...base, 'reminder': 'not-a-date'},
        {...base, 'status': 99},
        {...base, 'status': 'deleted'},
      ]) {
        expect(
          () => NoteExportFormatter.fromJson(jsonEncode([malformed])),
          throwsA(isA<FormatException>()),
        );
      }
    });
  });

  group('NoteExportFormatter readable exports', () {
    test('uses an explicit message when text export has no notes', () {
      expect(NoteExportFormatter.toText(const []), 'No notes to export.');
    });

    test('preserves authored Markdown and escapes generated metadata only', () {
      final markdown = NoteExportFormatter.toMarkdown([
        Note(
          title: 'Plan\r\n## injected #1',
          content: '''## Existing heading
**bold** and [link](https://example.com)
- [ ] checklist
| A | B |
| - | - |
`code *literal*`''',
          color: 0,
          createdAt: DateTime.utc(2026, 8, 23),
          tags: const ['work|urgent', 'multi\nline'],
        ),
      ]);

      expect(markdown, '''# Plan \\#\\# injected \\#1

## Existing heading
**bold** and [link](https://example.com)
- [ ] checklist
| A | B |
| - | - |
`code *literal*`

Tags: #work\\|urgent, #multi line''');
    });
  });
}
