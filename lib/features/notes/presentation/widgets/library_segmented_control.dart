import 'package:flutter/material.dart';

import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';

enum LibrarySection { archived, trash }

class LibrarySegmentedControl extends StatelessWidget {
  const LibrarySegmentedControl({
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final LibrarySection selected;
  final ValueChanged<LibrarySection> onSelected;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      padding: const EdgeInsets.all(16),
      blur: 18,
      opacity: 0.74,
      child: Semantics(
        container: true,
        label: 'Library sections',
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<LibrarySection>(
            segments: const [
              ButtonSegment(
                value: LibrarySection.archived,
                icon: Icon(Icons.archive_outlined),
                label: Text('Archived', textAlign: TextAlign.center),
              ),
              ButtonSegment(
                value: LibrarySection.trash,
                icon: Icon(Icons.delete_outline),
                label: Text('Trash', textAlign: TextAlign.center),
              ),
            ],
            selected: {selected},
            onSelectionChanged: (selection) => onSelected(selection.single),
            showSelectedIcon: true,
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(0, 48)),
              tapTargetSize: MaterialTapTargetSize.padded,
              visualDensity: VisualDensity.standard,
            ),
          ),
        ),
      ),
    );
  }
}
