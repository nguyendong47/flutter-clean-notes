import 'dart:convert';

import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';

/// A privacy-scoped snapshot for human-readable exports.
///
/// Construction always removes Trash so callers cannot accidentally pass an
/// all-status collection to the text or Markdown formatters.
final class ReadableNotesExport {
  ReadableNotesExport.fromAllStatuses(Iterable<Note> notes)
    : _notes = List<Note>.unmodifiable(notes.where(_isReadableNote));

  final List<Note> _notes;
}

/// A complete snapshot for JSON backup, including every note status.
final class AllStatusNotesBackup {
  AllStatusNotesBackup.fromAllStatuses(Iterable<Note> notes)
    : _notes = List<Note>.unmodifiable(notes);

  final List<Note> _notes;
}

/// Semantic limits applied to JSON backups before an import transaction.
///
/// The picker separately caps files at 10 MiB. These limits prevent a compact
/// payload from expanding into an excessive number of notes, fields, or tags
/// while remaining generous for personal note collections.
abstract final class NoteBackupImportLimits {
  /// Maximum notes accepted from one backup.
  static const int maxNotes = 10_000;

  /// Maximum JSON fields accepted in one note object.
  static const int maxFieldsPerNote = 32;

  /// Maximum UTF-16 code units accepted in a JSON field name.
  static const int maxFieldNameCodeUnits = 128;

  /// Maximum UTF-16 code units accepted in a note title.
  static const int maxTitleCodeUnits = 32 * 1024;

  /// Maximum UTF-16 code units accepted in a note body.
  static const int maxContentCodeUnits = 5 * 1024 * 1024;

  /// Maximum tags accepted in one note.
  static const int maxTagsPerNote = 256;

  /// Maximum tags accepted across one backup.
  static const int maxTotalTags = 50_000;

  /// Maximum UTF-16 code units accepted in one tag.
  static const int maxTagCodeUnits = 1024;

  /// Maximum raw size of legacy comma-delimited tags before splitting.
  static const int maxLegacyTagsCodeUnits =
      maxTagsPerNote * maxTagCodeUnits + maxTagsPerNote - 1;
}

abstract final class NoteExportFormatter {
  static const emptyExportMessage = 'No notes to export.';

  static String toText(ReadableNotesExport export) {
    final buffer = StringBuffer();
    for (final note in export._notes) {
      if (note.title.trim().isNotEmpty) buffer.writeln('# ${note.title}');
      if (note.content.isNotEmpty) buffer.writeln(note.content);
      if (note.tags.isNotEmpty) {
        buffer.writeln('Tags: ${note.tags.join(', ')}');
      }
      buffer.writeln();
    }
    final text = buffer.toString().trim();
    return text.isEmpty ? emptyExportMessage : text;
  }

  static String toMarkdown(ReadableNotesExport export) {
    final materialized = export._notes;
    if (materialized.isEmpty) return emptyExportMessage;

    final buffer = StringBuffer();
    for (var index = 0; index < materialized.length; index++) {
      final note = materialized[index];
      final title = note.title.trim().isEmpty ? 'Untitled note' : note.title;
      buffer
        ..writeln('# ${_escapeMarkdown(_singleLine(title))}')
        ..writeln();
      if (note.content.isNotEmpty) {
        buffer
          ..writeln(note.content)
          ..writeln();
      }
      if (note.tags.isNotEmpty) {
        final tags = note.tags
            .map((tag) => '#${_escapeMarkdown(_singleLine(tag))}')
            .join(', ');
        buffer
          ..writeln('Tags: $tags')
          ..writeln();
      }
      if (index != materialized.length - 1) {
        buffer
          ..writeln('---')
          ..writeln();
      }
    }
    return buffer.toString().trimRight();
  }

  static String toJson(AllStatusNotesBackup backup) {
    final maps = backup._notes
        .map(
          (note) => <String, Object?>{
            if (note.id != null) 'id': note.id,
            'title': note.title,
            'content': note.content,
            'color': note.color,
            'createdAt': note.createdAt.toIso8601String(),
            'isPinned': note.isPinned ? 1 : 0,
            'tags': List<String>.of(note.tags, growable: false),
            'status': note.status.index,
            'reminder': note.reminder?.toIso8601String(),
          },
        )
        .toList(growable: false);
    return const JsonEncoder.withIndent('  ').convert(maps);
  }

  static List<Note> fromJson(String payload) {
    final source = payload.startsWith('\uFEFF')
        ? payload.substring(1)
        : payload;
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const FormatException('The backup is not valid JSON.');
    }
    if (decoded is! List<Object?>) {
      throw const FormatException('The backup must contain a list of notes.');
    }

    if (decoded.length > NoteBackupImportLimits.maxNotes) {
      throw FormatException(
        'The backup contains too many notes '
        '(maximum ${NoteBackupImportLimits.maxNotes}).',
      );
    }

    var totalTags = 0;
    for (var index = 0; index < decoded.length; index++) {
      totalTags += _validateResourceLimits(decoded[index], index + 1);
      if (totalTags > NoteBackupImportLimits.maxTotalTags) {
        throw FormatException(
          'The backup contains too many tags in total '
          '(maximum ${NoteBackupImportLimits.maxTotalTags}).',
        );
      }
    }

    return [
      for (var index = 0; index < decoded.length; index++)
        _parseNote(decoded[index], index + 1),
    ];
  }

  static int _validateResourceLimits(Object? value, int number) {
    if (value is! Map) return 0;
    if (value.length > NoteBackupImportLimits.maxFieldsPerNote) {
      throw FormatException(
        'Note $number contains too many fields '
        '(maximum ${NoteBackupImportLimits.maxFieldsPerNote}).',
      );
    }

    for (final key in value.keys) {
      if (key is String &&
          key.length > NoteBackupImportLimits.maxFieldNameCodeUnits) {
        throw FormatException(
          'Note $number contains a field name that is too long.',
        );
      }
    }

    _validateStringLength(
      value['title'],
      number,
      'title',
      NoteBackupImportLimits.maxTitleCodeUnits,
    );
    _validateStringLength(
      value['content'],
      number,
      'content',
      NoteBackupImportLimits.maxContentCodeUnits,
    );
    return _validateTags(value['tags'], number);
  }

  static void _validateStringLength(
    Object? value,
    int number,
    String field,
    int maxCodeUnits,
  ) {
    if (value is String && value.length > maxCodeUnits) {
      throw FormatException(
        'Note $number has a "$field" field that is too long.',
      );
    }
  }

  static int _validateTags(Object? value, int number) {
    if (value is String) {
      if (value.length > NoteBackupImportLimits.maxLegacyTagsCodeUnits) {
        throw FormatException('Note $number contains tags that are too long.');
      }
      final rawTags = value.split(',');
      if (rawTags.length > NoteBackupImportLimits.maxTagsPerNote) {
        throw FormatException(
          'Note $number contains too many tags '
          '(maximum ${NoteBackupImportLimits.maxTagsPerNote}).',
        );
      }
      var count = 0;
      for (final rawTag in rawTags) {
        final tag = rawTag.trim();
        if (tag.isEmpty) continue;
        _validateTagLength(tag, number);
        count += 1;
      }
      return count;
    }

    if (value is List) {
      if (value.length > NoteBackupImportLimits.maxTagsPerNote) {
        throw FormatException(
          'Note $number contains too many tags '
          '(maximum ${NoteBackupImportLimits.maxTagsPerNote}).',
        );
      }
      for (final tag in value) {
        if (tag is String) _validateTagLength(tag, number);
      }
      return value.length;
    }

    return 0;
  }

  static void _validateTagLength(String tag, int number) {
    if (tag.length > NoteBackupImportLimits.maxTagCodeUnits) {
      throw FormatException('Note $number contains a tag that is too long.');
    }
  }

  static Note _parseNote(Object? value, int number) {
    if (value is! Map) {
      throw FormatException('Note $number must be a JSON object.');
    }
    final map = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw FormatException('Note $number contains an invalid field name.');
      }
      map[entry.key as String] = entry.value;
    }

    final createdAt = _date(map['createdAt'], number, 'createdAt');
    final reminder = _nullableDate(map['reminder'], number, 'reminder');
    return Note(
      id: map.containsKey('id') ? _nullableInt(map['id'], number, 'id') : null,
      title: _string(map['title'], number, 'title'),
      content: _string(map['content'], number, 'content'),
      color: _integer(map['color'], number, 'color'),
      createdAt: DateTime.parse(createdAt),
      isPinned: _pinned(map['isPinned'], number) == 1,
      tags: _tags(map['tags'], number),
      status: NoteStatus.values[_status(map['status'], number)],
      reminder: reminder == null ? null : DateTime.parse(reminder),
    );
  }

  static int? _nullableInt(Object? value, int number, String field) {
    if (value == null || value is int) return value as int?;
    throw _invalidField(number, field);
  }

  static int _integer(Object? value, int number, String field) {
    if (value is int) return value;
    throw _invalidField(number, field);
  }

  static String _string(Object? value, int number, String field) {
    if (value is String) return value;
    throw _invalidField(number, field);
  }

  static String _date(Object? value, int number, String field) {
    final date = _string(value, number, field);
    if (DateTime.tryParse(date) == null) throw _invalidField(number, field);
    return date;
  }

  static String? _nullableDate(Object? value, int number, String field) {
    if (value == null) return null;
    return _date(value, number, field);
  }

  static int _pinned(Object? value, int number) {
    return switch (value) {
      true => 1,
      false => 0,
      0 => 0,
      1 => 1,
      _ => throw _invalidField(number, 'isPinned'),
    };
  }

  static List<String> _tags(Object? value, int number) {
    if (value is String) {
      return value
          .split(',')
          .map((tag) => tag.trim())
          .where((tag) => tag.isNotEmpty)
          .toList();
    }
    if (value is List) {
      if (value.any((tag) => tag is! String)) {
        throw _invalidField(number, 'tags');
      }
      return value.cast<String>().toList(growable: false);
    }
    throw _invalidField(number, 'tags');
  }

  static int _status(Object? value, int number) {
    if (value is int && value >= 0 && value < NoteStatus.values.length) {
      return value;
    }
    if (value is String) {
      for (final status in NoteStatus.values) {
        if (status.name == value) return status.index;
      }
    }
    throw _invalidField(number, 'status');
  }

  static FormatException _invalidField(int number, String field) {
    return FormatException('Note $number has an invalid "$field" field.');
  }

  static String _singleLine(String value) {
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String _escapeMarkdown(String value) {
    var escaped = value.replaceAll(r'\', r'\\');
    for (final character in const [
      '`',
      '*',
      '_',
      '[',
      ']',
      '<',
      '>',
      '#',
      '|',
    ]) {
      escaped = escaped.replaceAll(character, '\\$character');
    }
    return escaped;
  }
}

bool _isReadableNote(Note note) {
  return switch (note.status) {
    NoteStatus.active || NoteStatus.archived => true,
    NoteStatus.trashed => false,
  };
}
