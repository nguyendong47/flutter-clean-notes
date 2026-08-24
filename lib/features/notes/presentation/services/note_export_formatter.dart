import 'dart:convert';
import 'dart:typed_data';

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

/// Resource limits shared by JSON backup creation and restoration.
///
/// These limits prevent a compact payload from expanding into an excessive
/// number of notes, fields, or tags while remaining generous for personal note
/// collections. String limits use UTF-16 code units, matching Dart's
/// [String.length]. Whole-backup size uses UTF-8 bytes, matching transferred
/// files.
abstract final class NoteBackupImportLimits {
  /// Maximum UTF-8 bytes accepted or emitted for one backup.
  static const int maxUtf8Bytes = 10 * 1024 * 1024;

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

  /// Maximum JSON collection nesting accepted before decoding.
  static const int maxJsonNestingDepth = 64;

  /// Maximum structural JSON tokens accepted before decoding.
  ///
  /// This covers the theoretical import boundary of [maxNotes] objects with
  /// [maxFieldsPerNote] scalar fields plus [maxTotalTags] list entries.
  static const int maxJsonStructuralTokens =
      maxNotes * (2 * maxFieldsPerNote + 4) + maxTotalTags + 2;
}

abstract final class NoteExportFormatter {
  static const emptyExportMessage = 'No notes to export.';
  static const _knownNoteFields = <String>{
    'id',
    'title',
    'content',
    'color',
    'createdAt',
    'isPinned',
    'tags',
    'status',
    'reminder',
  };

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
    final notes = backup._notes;
    _checkNoteCount(notes.length);

    final maps = <Map<String, Object?>>[];
    var totalTags = 0;
    for (var index = 0; index < notes.length; index++) {
      final map = _noteToMap(notes[index]);
      final parsed = _parseNote(map, index + 1);
      totalTags = _checkTotalTags(totalTags, parsed.tags.length);
      maps.add(map);
    }

    final payload = _encodeBackupJson(maps);
    _checkJsonEnvelope(payload);
    return payload;
  }

  static List<Note> fromJson(String payload) {
    _checkJsonEnvelope(payload);
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

    _checkNoteCount(decoded.length);

    final notes = <Note>[];
    var totalTags = 0;
    for (var index = 0; index < decoded.length; index++) {
      final note = _parseNote(decoded[index], index + 1);
      totalTags = _checkTotalTags(totalTags, note.tags.length);
      notes.add(note);
    }
    return notes;
  }

  static Map<String, Object?> _noteToMap(Note note) {
    return <String, Object?>{
      if (note.id != null) 'id': note.id,
      'title': note.title,
      'content': note.content,
      'color': note.color,
      'createdAt': note.createdAt.toIso8601String(),
      'isPinned': note.isPinned ? 1 : 0,
      'tags': List<String>.of(note.tags, growable: false),
      'status': note.status.index,
      'reminder': note.reminder?.toIso8601String(),
    };
  }

  static String _encodeBackupJson(List<Map<String, Object?>> maps) {
    final output = _CappedJsonByteSink(
      maxBytes: NoteBackupImportLimits.maxUtf8Bytes,
    );
    final input = JsonUtf8Encoder(
      '  ',
      null,
      64 * 1024,
    ).startChunkedConversion(output);
    input
      ..add(maps)
      ..close();
    return utf8.decode(output.takeBytes());
  }

  static void _checkNoteCount(int count) {
    if (count > NoteBackupImportLimits.maxNotes) {
      throw FormatException(
        'The backup contains too many notes '
        '(maximum ${NoteBackupImportLimits.maxNotes}).',
      );
    }
  }

  static int _checkTotalTags(int current, int additional) {
    final total = current + additional;
    if (total > NoteBackupImportLimits.maxTotalTags) {
      throw FormatException(
        'The backup contains too many tags in total '
        '(maximum ${NoteBackupImportLimits.maxTotalTags}).',
      );
    }
    return total;
  }

  static void _checkJsonEnvelope(String payload) {
    var byteLength = 0;
    var depth = 0;
    var structuralTokens = 0;
    var topLevelSeparators = 0;
    var inString = false;
    var escaped = false;
    var rootArray = false;
    var sawRootToken = false;

    for (var index = 0; index < payload.length; index++) {
      final codeUnit = payload.codeUnitAt(index);
      if (codeUnit <= 0x7F) {
        byteLength += 1;
      } else if (codeUnit <= 0x7FF) {
        byteLength += 2;
      } else if (codeUnit >= 0xD800 &&
          codeUnit <= 0xDBFF &&
          index + 1 < payload.length) {
        final next = payload.codeUnitAt(index + 1);
        if (next >= 0xDC00 && next <= 0xDFFF) {
          byteLength += 4;
          index += 1;
          if (byteLength > NoteBackupImportLimits.maxUtf8Bytes) {
            throw const FormatException(
              'The backup is too large. Choose a backup up to 10 MB.',
            );
          }
          continue;
        }
        byteLength += 3;
      } else {
        byteLength += 3;
      }

      if (byteLength > NoteBackupImportLimits.maxUtf8Bytes) {
        throw const FormatException(
          'The backup is too large. Choose a backup up to 10 MB.',
        );
      }

      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (codeUnit == 0x5C) {
          escaped = true;
        } else if (codeUnit == 0x22) {
          inString = false;
        }
        continue;
      }
      if (codeUnit == 0x22) {
        inString = true;
        continue;
      }

      if (!sawRootToken && !_isJsonWhitespace(codeUnit)) {
        sawRootToken = true;
        rootArray = codeUnit == 0x5B;
      }

      switch (codeUnit) {
        case 0x5B || 0x7B:
          structuralTokens += 1;
          depth += 1;
          if (depth > NoteBackupImportLimits.maxJsonNestingDepth) {
            throw const FormatException('The backup is too deeply nested.');
          }
        case 0x5D || 0x7D:
          structuralTokens += 1;
          depth -= 1;
        case 0x2C:
          structuralTokens += 1;
          if (rootArray && depth == 1) {
            topLevelSeparators += 1;
            if (topLevelSeparators >= NoteBackupImportLimits.maxNotes) {
              _checkNoteCount(topLevelSeparators + 1);
            }
          }
        case 0x3A:
          structuralTokens += 1;
      }

      if (structuralTokens > NoteBackupImportLimits.maxJsonStructuralTokens) {
        throw const FormatException('The backup structure is too complex.');
      }
    }
  }

  static bool _isJsonWhitespace(int codeUnit) {
    return codeUnit == 0x20 ||
        codeUnit == 0x09 ||
        codeUnit == 0x0A ||
        codeUnit == 0x0D ||
        codeUnit == 0xFEFF;
  }

  static Note _parseNote(Object? value, int number) {
    if (value is! Map) {
      throw FormatException('Note $number must be a JSON object.');
    }
    final map = <String, Object?>{};
    if (value.length > NoteBackupImportLimits.maxFieldsPerNote) {
      throw FormatException(
        'Note $number contains too many fields '
        '(maximum ${NoteBackupImportLimits.maxFieldsPerNote}).',
      );
    }

    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw FormatException('Note $number contains an invalid field name.');
      }
      final key = entry.key as String;
      if (key.length > NoteBackupImportLimits.maxFieldNameCodeUnits) {
        throw FormatException(
          'Note $number contains a field name that is too long.',
        );
      }
      if (!_knownNoteFields.contains(key) &&
          (entry.value is List || entry.value is Map)) {
        throw FormatException('Note $number contains unsupported nested data.');
      }
      map[key] = entry.value;
    }

    final createdAt = _date(map['createdAt'], number, 'createdAt');
    final reminder = _nullableDate(map['reminder'], number, 'reminder');
    final title = _boundedString(
      map['title'],
      number,
      'title',
      NoteBackupImportLimits.maxTitleCodeUnits,
    );
    final content = _boundedString(
      map['content'],
      number,
      'content',
      NoteBackupImportLimits.maxContentCodeUnits,
    );
    final tags = _parseTags(map['tags'], number);
    return Note(
      id: map.containsKey('id') ? _nullableInt(map['id'], number, 'id') : null,
      title: title,
      content: content,
      color: _integer(map['color'], number, 'color'),
      createdAt: DateTime.parse(createdAt),
      isPinned: _pinned(map['isPinned'], number) == 1,
      tags: tags,
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

  static String _boundedString(
    Object? value,
    int number,
    String field,
    int maxCodeUnits,
  ) {
    final text = _string(value, number, field);
    if (text.length > maxCodeUnits) {
      throw FormatException(
        'Note $number has a "$field" field that is too long.',
      );
    }
    return text;
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

  static List<String> _parseTags(Object? value, int number) {
    if (value is String) {
      if (value.length > NoteBackupImportLimits.maxLegacyTagsCodeUnits) {
        throw FormatException('Note $number contains tags that are too long.');
      }
      final rawTags = value.split(',');
      _checkTagCount(rawTags.length, number);
      final tags = <String>[];
      for (final rawTag in rawTags) {
        final tag = rawTag.trim();
        if (tag.isEmpty) continue;
        _checkTagLength(tag, number);
        tags.add(tag);
      }
      return tags;
    }
    if (value is List) {
      _checkTagCount(value.length, number);
      final tags = <String>[];
      for (final rawTag in value) {
        if (rawTag is! String) throw _invalidField(number, 'tags');
        _checkTagLength(rawTag, number);
        tags.add(rawTag);
      }
      return List<String>.unmodifiable(tags);
    }
    throw _invalidField(number, 'tags');
  }

  static void _checkTagCount(int count, int number) {
    if (count > NoteBackupImportLimits.maxTagsPerNote) {
      throw FormatException(
        'Note $number contains too many tags '
        '(maximum ${NoteBackupImportLimits.maxTagsPerNote}).',
      );
    }
  }

  static void _checkTagLength(String tag, int number) {
    if (tag.length > NoteBackupImportLimits.maxTagCodeUnits) {
      throw FormatException('Note $number contains a tag that is too long.');
    }
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

final class _CappedJsonByteSink implements Sink<List<int>> {
  _CappedJsonByteSink({required this.maxBytes});

  final int maxBytes;
  final BytesBuilder _bytes = BytesBuilder();

  @override
  void add(List<int> data) {
    if (_bytes.length + data.length > maxBytes) {
      throw const FormatException(
        'The backup is too large. Choose a backup up to 10 MB.',
      );
    }
    _bytes.add(data);
  }

  @override
  void close() {}

  Uint8List takeBytes() => _bytes.takeBytes();
}
