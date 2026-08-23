import 'dart:convert';

import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';

abstract final class NoteExportFormatter {
  static const emptyExportMessage = 'No notes to export.';

  static String toText(Iterable<Note> notes) {
    final buffer = StringBuffer();
    for (final note in notes) {
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

  static String toMarkdown(Iterable<Note> notes) {
    final materialized = notes.toList(growable: false);
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

  static String toJson(Iterable<Note> notes) {
    final maps = notes
        .map((note) => NoteModel.fromEntity(note).toJson())
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

    return [
      for (var index = 0; index < decoded.length; index++)
        _parseNote(decoded[index], index + 1),
    ];
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

    final normalized = <String, dynamic>{
      if (map.containsKey('id')) 'id': _nullableInt(map['id'], number, 'id'),
      'title': _string(map['title'], number, 'title'),
      'content': _string(map['content'], number, 'content'),
      'color': _integer(map['color'], number, 'color'),
      'createdAt': _date(map['createdAt'], number, 'createdAt'),
      'isPinned': _pinned(map['isPinned'], number),
      'tags': _tags(map['tags'], number),
      'status': _status(map['status'], number),
      'reminder': _nullableDate(map['reminder'], number, 'reminder'),
    };

    try {
      return NoteModel.fromJson(normalized);
    } catch (_) {
      throw FormatException('Note $number contains invalid data.');
    }
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

  static String _tags(Object? value, int number) {
    if (value is String) return value;
    if (value is List) {
      if (value.any((tag) => tag is! String)) {
        throw _invalidField(number, 'tags');
      }
      return value.cast<String>().join(',');
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
