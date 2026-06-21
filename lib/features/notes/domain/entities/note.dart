class Note {
  final int? id;
  final String title;
  final String content;
  final int color;
  final DateTime createdAt;

  const Note({
    this.id,
    required this.title,
    required this.content,
    required this.color,
    required this.createdAt,
  });

  Note copyWith({
    int? id,
    String? title,
    String? content,
    int? color,
    DateTime? createdAt,
  }) {
    return Note(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      color: color ?? this.color,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
