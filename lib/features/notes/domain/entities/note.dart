enum NoteStatus { active, archived, trashed }

class Note {
  static const _unset = Object();

  final int? id;
  final String title;
  final String content;
  final int color;
  final DateTime createdAt;
  final bool isPinned;
  final List<String> tags;
  final NoteStatus status;
  final DateTime? reminder;

  const Note({
    this.id,
    required this.title,
    required this.content,
    required this.color,
    required this.createdAt,
    this.isPinned = false,
    this.tags = const [],
    this.status = NoteStatus.active,
    this.reminder,
  });

  Note copyWith({
    Object? id = _unset,
    String? title,
    String? content,
    int? color,
    DateTime? createdAt,
    bool? isPinned,
    List<String>? tags,
    NoteStatus? status,
    Object? reminder = _unset,
  }) {
    return Note(
      id: identical(id, _unset) ? this.id : id as int?,
      title: title ?? this.title,
      content: content ?? this.content,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
      isPinned: isPinned ?? this.isPinned,
      tags: tags ?? this.tags,
      status: status ?? this.status,
      reminder: identical(reminder, _unset)
          ? this.reminder
          : reminder as DateTime?,
    );
  }
}
