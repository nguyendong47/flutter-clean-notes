import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';

class NoteModel extends Note {
  const NoteModel({
    super.id,
    required super.title,
    required super.content,
    required super.color,
    required super.createdAt,
    super.isPinned,
    super.tags,
    super.status,
    super.reminder,
  });

  factory NoteModel.fromJson(Map<String, dynamic> json) {
    return NoteModel(
      id: json['id'] as int?,
      title: json['title'] as String,
      content: json['content'] as String,
      color: json['color'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isPinned: json['isPinned'] == 1,
      tags: _tagsFromJson(json['tags']),
      status: NoteStatus.values[json['status'] as int? ?? 0],
      reminder: json['reminder'] != null
          ? DateTime.tryParse(json['reminder'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'content': content,
      'color': color,
      'createdAt': createdAt.toIso8601String(),
      'isPinned': isPinned ? 1 : 0,
      'tags': tags.join(','),
      'status': status.index,
      if (reminder != null) 'reminder': reminder!.toIso8601String(),
    };
  }

  factory NoteModel.fromEntity(Note note) {
    return NoteModel(
      id: note.id,
      title: note.title,
      content: note.content,
      color: note.color,
      createdAt: note.createdAt,
      isPinned: note.isPinned,
      tags: note.tags,
      status: note.status,
      reminder: note.reminder,
    );
  }

  static List<String> _tagsFromJson(dynamic value) {
    if (value == null) return const [];
    final str = value as String;
    if (str.isEmpty) return const [];
    return str
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
  }
}
