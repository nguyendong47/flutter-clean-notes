import 'dart:convert';

class WidgetChecklistItem {
  const WidgetChecklistItem({required this.text, required this.isDone});

  final String text;
  final bool isDone;

  Map<String, dynamic> toJson() => {'text': text, 'done': isDone};

  factory WidgetChecklistItem.fromJson(Map<String, dynamic> json) =>
      WidgetChecklistItem(
        text: json['text'] as String? ?? '',
        isDone: json['done'] as bool? ?? false,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WidgetChecklistItem &&
          runtimeType == other.runtimeType &&
          text == other.text &&
          isDone == other.isDone;

  @override
  int get hashCode => Object.hash(text, isDone);
}

class WidgetNoteItem {
  const WidgetNoteItem({
    required this.id,
    required this.title,
    required this.contentPreview,
    this.checklist = const [],
    this.colorValue = 0xFFFFFFFF,
  });

  final int id;
  final String title;
  final String contentPreview;
  final List<WidgetChecklistItem> checklist;
  final int colorValue;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WidgetNoteItem &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          contentPreview == other.contentPreview &&
          colorValue == other.colorValue;

  @override
  int get hashCode => Object.hash(id, title, contentPreview, colorValue);
}

class WidgetSyncPayload {
  const WidgetSyncPayload({
    required this.hasPinned,
    this.noteId,
    this.title = '',
    this.contentPreview = '',
    this.checklist = const [],
    this.colorValue = 0xFFFFFFFF,
    this.updatedAt,
    this.boundNotes = const [],
  });

  final bool hasPinned;
  final int? noteId;
  final String title;
  final String contentPreview;
  final List<WidgetChecklistItem> checklist;
  final int colorValue;
  final DateTime? updatedAt;
  final List<WidgetNoteItem> boundNotes;

  static const empty = WidgetSyncPayload(hasPinned: false);

  Map<String, dynamic> toMap() => {
    'hasPinned': hasPinned,
    'noteId': noteId?.toString() ?? '',
    'title': title,
    'contentPreview': contentPreview,
    'checklistJson': jsonEncode(checklist.map((e) => e.toJson()).toList()),
    'colorValue': colorValue,
    'updatedAt': updatedAt?.toIso8601String() ?? '',
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WidgetSyncPayload &&
          runtimeType == other.runtimeType &&
          hasPinned == other.hasPinned &&
          noteId == other.noteId &&
          title == other.title &&
          contentPreview == other.contentPreview &&
          colorValue == other.colorValue;

  @override
  int get hashCode =>
      Object.hash(hasPinned, noteId, title, contentPreview, colorValue);
}
