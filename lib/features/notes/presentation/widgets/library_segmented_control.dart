import 'package:easy_localization/easy_localization.dart';
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
        label: 'library.sections'.tr(),
        child: SizedBox(
          width: double.infinity,
          child: SegmentedButton<LibrarySection>(
            segments: [
              ButtonSegment(
                value: LibrarySection.archived,
                icon: const Icon(Icons.archive_outlined),
                label: Text('library.archived'.tr(), textAlign: TextAlign.center),
              ),
              ButtonSegment(
                value: LibrarySection.trash,
                icon: const Icon(Icons.delete_outline),
                label: Text('library.trash'.tr(), textAlign: TextAlign.center),
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
