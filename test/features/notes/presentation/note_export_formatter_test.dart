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

      final backup = AllStatusNotesBackup.fromAllStatuses([note]);
      final payload = NoteExportFormatter.toJson(backup);
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
      expect(NoteExportFormatter.toJson(backup), payload);
    });

    test('exports only backups that satisfy every import resource limit', () {
      final longestTitle = 'x' * NoteBackupImportLimits.maxTitleCodeUnits;
      final longestTag = 't' * NoteBackupImportLimits.maxTagCodeUnits;
      final boundary = _backupNote(title: longestTitle, tags: [longestTag]);

      final payload = NoteExportFormatter.toJson(
        AllStatusNotesBackup.fromAllStatuses([boundary]),
      );

      final restored = NoteExportFormatter.fromJson(payload).single;
      expect(restored.title, longestTitle);
      expect(restored.tags, [longestTag]);

      final tooManyTags = _backupNote(
        tags: List<String>.filled(
          NoteBackupImportLimits.maxTagsPerNote + 1,
          'tag',
        ),
      );
      final tooLongTag = _backupNote(
        tags: ['t' * (NoteBackupImportLimits.maxTagCodeUnits + 1)],
      );
      final tooManyTotalTags = List<Note>.filled(
        (NoteBackupImportLimits.maxTotalTags ~/
                NoteBackupImportLimits.maxTagsPerNote) +
            1,
        _backupNote(
          tags: List<String>.filled(
            NoteBackupImportLimits.maxTagsPerNote,
            'tag',
          ),
        ),
      );
      final tooManyNotes = List<Note>.filled(
        NoteBackupImportLimits.maxNotes + 1,
        _backupNote(),
      );

      final invalidBackups = <AllStatusNotesBackup>[
        AllStatusNotesBackup.fromAllStatuses([
          _backupNote(
            title:
                'private-title-${'x' * NoteBackupImportLimits.maxTitleCodeUnits}',
          ),
        ]),
        AllStatusNotesBackup.fromAllStatuses([
          _backupNote(
            content:
                'private-content-${'x' * NoteBackupImportLimits.maxContentCodeUnits}',
          ),
        ]),
        AllStatusNotesBackup.fromAllStatuses([tooManyTags]),
        AllStatusNotesBackup.fromAllStatuses([tooLongTag]),
        AllStatusNotesBackup.fromAllStatuses(tooManyTotalTags),
        AllStatusNotesBackup.fromAllStatuses(tooManyNotes),
      ];

      for (final invalid in invalidBackups) {
        try {
          NoteExportFormatter.toJson(invalid);
          fail('Expected an unrestorable backup to be rejected.');
        } on FormatException catch (error) {
          expect(error.message, isNot(contains('private-title')));
          expect(error.message, isNot(contains('private-content')));
        }
      }
    });

    test('rejects an export whose UTF-8 JSON exceeds 10 MiB', () {
      final multibyteContent =
          '界' * (NoteBackupImportLimits.maxUtf8Bytes ~/ 3 + 1);
      expect(
        multibyteContent.length,
        lessThan(NoteBackupImportLimits.maxContentCodeUnits),
      );
      final backup = AllStatusNotesBackup.fromAllStatuses([
        _backupNote(content: multibyteContent),
      ]);

      try {
        NoteExportFormatter.toJson(backup);
        fail('Expected a backup larger than 10 MiB to be rejected.');
      } on FormatException catch (error) {
        expect(error.message, allOf(contains('backup'), contains('too large')));
      }
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

    test('rejects deeply nested JSON before decoding it', () {
      const nesting = 1000;
      final map = jsonEncode(_validBackupNote());
      final nested = '${'[' * nesting}0${']' * nesting}';
      final payload = '[${map.substring(0, map.length - 1)},"extra":$nested}]';

      expect(
        () => NoteExportFormatter.fromJson(payload),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('backup'), contains('deeply nested')),
          ),
        ),
      );
    });

    test('rejects excessive JSON structure before decoding it', () {
      const emptyCollections = 250000;
      final map = jsonEncode(_validBackupNote());
      final wide = List<String>.filled(emptyCollections, '[]').join(',');
      final payload = '[${map.substring(0, map.length - 1)},"extra":[$wide]}]';

      expect(
        () => NoteExportFormatter.fromJson(payload),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('backup'), contains('too complex')),
          ),
        ),
      );
    });

    test('does not count structural delimiters inside JSON strings', () {
      final content = List<String>.filled(150000, r'[]{}:,"\\').join();
      final payload = jsonEncode([
        {..._validBackupNote(), 'content': content},
      ]);

      expect(NoteExportFormatter.fromJson(payload).single.content, content);
    });

    test('rejects nested unknown fields but accepts scalar metadata', () {
      expect(
        NoteExportFormatter.fromJson(
          jsonEncode([
            {..._validBackupNote(), 'formatVersion': 'future-v2'},
          ]),
        ),
        hasLength(1),
      );

      expect(
        () => NoteExportFormatter.fromJson(
          jsonEncode([
            {
              ..._validBackupNote(),
              'private-extension': [
                {'nested': 'private-value'},
              ],
            },
          ]),
        ),
        throwsA(
          isA<FormatException>()
              .having(
                (error) => error.message,
                'message',
                allOf(contains('Note 1'), contains('nested data')),
              )
              .having(
                (error) => error.message,
                'sanitized message',
                isNot(contains('private')),
              ),
        ),
      );
    });

    test('accepts exactly 10 MiB of JSON and rejects one UTF-8 byte more', () {
      const maxBytes = NoteBackupImportLimits.maxUtf8Bytes;
      final exact = '[${' ' * (maxBytes - 2)}]';

      expect(utf8.encode(exact), hasLength(maxBytes));
      expect(NoteExportFormatter.fromJson(exact), isEmpty);
      expect(
        () => NoteExportFormatter.fromJson('$exact '),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('backup'), contains('too large')),
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

    test('accepts the note-count boundary and rejects one more note', () {
      final note = _validBackupNote();
      final atLimit = jsonEncode(
        List<Object?>.filled(NoteBackupImportLimits.maxNotes, note),
      );

      expect(
        NoteExportFormatter.fromJson(atLimit),
        hasLength(NoteBackupImportLimits.maxNotes),
      );

      final overLimit = jsonEncode(
        List<Object?>.filled(NoteBackupImportLimits.maxNotes + 1, note),
      );
      expect(
        () => NoteExportFormatter.fromJson(overLimit),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('too many notes'),
          ),
        ),
      );
    });

    test('bounds note field count and field-name length', () {
      final atFieldLimit = _validBackupNote();
      for (
        var index = atFieldLimit.length;
        index < NoteBackupImportLimits.maxFieldsPerNote;
        index++
      ) {
        atFieldLimit['extra$index'] = null;
      }
      expect(
        NoteExportFormatter.fromJson(jsonEncode([atFieldLimit])),
        hasLength(1),
      );

      final tooManyFields = {...atFieldLimit, 'overflow': null};
      expect(
        () => NoteExportFormatter.fromJson(jsonEncode([tooManyFields])),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            allOf(contains('Note 1'), contains('too many fields')),
          ),
        ),
      );

      final acceptedFieldName =
          'x' * NoteBackupImportLimits.maxFieldNameCodeUnits;
      expect(
        NoteExportFormatter.fromJson(
          jsonEncode([
            {..._validBackupNote(), acceptedFieldName: null},
          ]),
        ),
        hasLength(1),
      );

      const privateMarker = 'private-field-marker';
      final rejectedFieldName =
          privateMarker +
          ('x' *
              (NoteBackupImportLimits.maxFieldNameCodeUnits +
                  1 -
                  privateMarker.length));
      expect(
        () => NoteExportFormatter.fromJson(
          jsonEncode([
            {..._validBackupNote(), rejectedFieldName: null},
          ]),
        ),
        throwsA(
          isA<FormatException>()
              .having(
                (error) => error.message,
                'message',
                allOf(contains('field name'), contains('too long')),
              )
              .having(
                (error) => error.message,
                'sanitized message',
                isNot(contains(privateMarker)),
              ),
        ),
      );
    });

    test('accepts title and content boundaries then rejects longer fields', () {
      final cases = <(String, int)>[
        ('title', NoteBackupImportLimits.maxTitleCodeUnits),
        ('content', NoteBackupImportLimits.maxContentCodeUnits),
      ];

      for (final (field, maxLength) in cases) {
        final atLimit = {..._validBackupNote(), field: 'x' * maxLength};
        expect(
          NoteExportFormatter.fromJson(jsonEncode([atLimit])),
          hasLength(1),
          reason: '$field boundary',
        );

        final overLimit = {
          ..._validBackupNote(),
          field: 'private-value-${'x' * (maxLength - 12)}',
        };
        expect(
          () => NoteExportFormatter.fromJson(jsonEncode([overLimit])),
          throwsA(
            isA<FormatException>()
                .having(
                  (error) => error.message,
                  'message',
                  allOf(contains('"$field"'), contains('too long')),
                )
                .having(
                  (error) => error.message,
                  'sanitized message',
                  isNot(contains('private-value')),
                ),
          ),
          reason: '$field over boundary',
        );
      }
    });

    test('bounds list and legacy tags before materializing imported notes', () {
      final atLimitTags = List<String>.filled(
        NoteBackupImportLimits.maxTagsPerNote,
        'tag',
      );
      expect(
        NoteExportFormatter.fromJson(
          jsonEncode([
            {..._validBackupNote(), 'tags': atLimitTags},
          ]),
        ).single.tags,
        hasLength(NoteBackupImportLimits.maxTagsPerNote),
      );

      final tooManyTags = [...atLimitTags, 'private-tag-marker'];
      expect(
        () => NoteExportFormatter.fromJson(
          jsonEncode([
            {..._validBackupNote(), 'tags': tooManyTags},
          ]),
        ),
        throwsA(
          isA<FormatException>()
              .having(
                (error) => error.message,
                'message',
                contains('too many tags'),
              )
              .having(
                (error) => error.message,
                'sanitized message',
                isNot(contains('private-tag-marker')),
              ),
        ),
      );

      final longestTag = 'x' * NoteBackupImportLimits.maxTagCodeUnits;
      expect(
        NoteExportFormatter.fromJson(
          jsonEncode([
            {
              ..._validBackupNote(),
              'tags': [longestTag],
            },
          ]),
        ).single.tags,
        [longestTag],
      );
      expect(
        () => NoteExportFormatter.fromJson(
          jsonEncode([
            {
              ..._validBackupNote(),
              'tags': ['private-tag-${'x' * longestTag.length}'],
            },
          ]),
        ),
        throwsA(isA<FormatException>()),
      );

      final legacyBoundary = atLimitTags.join(',');
      expect(
        NoteExportFormatter.fromJson(
          jsonEncode([
            {..._validBackupNote(), 'tags': legacyBoundary},
          ]),
        ).single.tags,
        hasLength(NoteBackupImportLimits.maxTagsPerNote),
      );
      expect(
        () => NoteExportFormatter.fromJson(
          jsonEncode([
            {..._validBackupNote(), 'tags': '$legacyBoundary,overflow'},
          ]),
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('accepts the total-tag boundary and rejects one more tag', () {
      final notes = <Map<String, Object?>>[];
      var remaining = NoteBackupImportLimits.maxTotalTags;
      while (remaining > 0) {
        final count = remaining > NoteBackupImportLimits.maxTagsPerNote
            ? NoteBackupImportLimits.maxTagsPerNote
            : remaining;
        notes.add({
          ..._validBackupNote(),
          'tags': List<String>.filled(count, 'tag'),
        });
        remaining -= count;
      }

      expect(
        NoteExportFormatter.fromJson(jsonEncode(notes)),
        hasLength(notes.length),
      );

      final overLimit = [
        ...notes,
        {
          ..._validBackupNote(),
          'tags': ['private-overflow-tag'],
        },
      ];
      expect(
        () => NoteExportFormatter.fromJson(jsonEncode(overLimit)),
        throwsA(
          isA<FormatException>()
              .having(
                (error) => error.message,
                'message',
                contains('too many tags in total'),
              )
              .having(
                (error) => error.message,
                'sanitized message',
                isNot(contains('private-overflow-tag')),
              ),
        ),
      );
    });
  });

  group('NoteExportFormatter readable exports', () {
    test('uses an explicit message when text export has no notes', () {
      expect(
        NoteExportFormatter.toText(
          ReadableNotesExport.fromAllStatuses(const []),
        ),
        'No notes to export.',
      );
    });

    test('preserves authored Markdown and escapes generated metadata only', () {
      final markdown = NoteExportFormatter.toMarkdown(
        ReadableNotesExport.fromAllStatuses([
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
        ]),
      );

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

Map<String, Object?> _validBackupNote() {
  return <String, Object?>{
    'id': 8,
    'title': 'Valid title',
    'content': 'Valid content',
    'color': 7,
    'createdAt': '2026-08-23T09:00:00.000Z',
    'isPinned': 1,
    'tags': const <String>[],
    'status': 0,
    'reminder': null,
  };
}

Note _backupNote({
  String title = 'Valid title',
  String content = 'Valid content',
  List<String> tags = const <String>[],
}) {
  return Note(
    id: 8,
    title: title,
    content: content,
    color: 7,
    createdAt: DateTime.utc(2026, 8, 23, 9),
    isPinned: true,
    tags: tags,
    status: NoteStatus.active,
  );
}
