import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/glass_note_card.dart';

class NotesCollection extends StatelessWidget {
  const NotesCollection({
    required this.notes,
    required this.onOpen,
    required this.onTogglePin,
    required this.onArchive,
    required this.onTrash,
    required this.onRestore,
    required this.onDelete,
    super.key,
  });

  final List<Note> notes;
  final void Function(Note note) onOpen;
  final Future<void> Function(Note note) onTogglePin;
  final Future<void> Function(Note note) onArchive;
  final Future<void> Function(Note note) onTrash;
  final Future<void> Function(Note note) onRestore;
  final Future<void> Function(Note note) onDelete;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.crossAxisExtent;
        final horizontalInset = _horizontalInset(viewportWidth);
        final columnCount = viewportWidth < 360
            ? 1
            : viewportWidth < 700
            ? 2
            : 3;

        return SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: horizontalInset),
          sliver: SliverMasonryGrid.count(
            crossAxisCount: columnCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childCount: notes.length,
            itemBuilder: (context, index) {
              final note = notes[index];
              return GlassNoteCard(
                key: ValueKey('note-card-${note.id ?? note.title}'),
                note: note,
                onOpen: () => onOpen(note),
                onTogglePin: () => onTogglePin(note),
                onArchive: () => onArchive(note),
                onTrash: () => onTrash(note),
                onRestore: () => onRestore(note),
                onDelete: () => onDelete(note),
              );
            },
          ),
        );
      },
    );
  }
}

double _horizontalInset(double viewportWidth) {
  final gutter = viewportWidth >= 600 ? 24.0 : 16.0;
  return ((viewportWidth - 840) / 2).clamp(gutter, double.infinity).toDouble();
}
