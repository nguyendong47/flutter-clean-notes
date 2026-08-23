import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';

class NoteFilterSheet extends ConsumerWidget {
  const NoteFilterSheet({super.key});

  static const _radius = BorderRadius.all(Radius.circular(28));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mediaQuery = MediaQuery.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final tags = ref.watch(homeTagsProvider);
    final selectedTag = ref.watch(selectedTagProvider);
    final sort = ref.watch(sortOrderProvider);
    final duration = mediaQuery.disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 200);

    return AnimatedPadding(
      duration: duration,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: GlassSurface(
          key: const Key('note-filter-sheet'),
          borderRadius: _radius,
          padding: EdgeInsets.zero,
          blur: 18,
          opacity: 0.9,
          child: Material(
            color: Colors.transparent,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Filter and sort',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      SizedBox.square(
                        dimension: 48,
                        child: IconButton(
                          tooltip: 'Close filters',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Tags',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _TagChoice(
                        key: const Key('filter-tag-all'),
                        label: 'All',
                        selected: selectedTag == null,
                        onSelected: () =>
                            ref.read(selectedTagProvider.notifier).select(null),
                      ),
                      for (final tag in tags)
                        _TagChoice(
                          key: ValueKey('filter-tag-$tag'),
                          label: tag,
                          selected: selectedTag == tag,
                          onSelected: () => ref
                              .read(selectedTagProvider.notifier)
                              .select(tag),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Sort by',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final order in NoteSort.values)
                    _SortChoice(
                      key: ValueKey('sort-option-${order.name}'),
                      label: _sortLabel(order),
                      selected: sort == order,
                      onSelected: () =>
                          ref.read(sortOrderProvider.notifier).set(order),
                    ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final labelStyle =
                          Theme.of(context).textTheme.labelLarge ??
                          const TextStyle();
                      double minimumButtonWidth(String label) {
                        final painter = TextPainter(
                          text: TextSpan(text: label, style: labelStyle),
                          textDirection: Directionality.of(context),
                          textScaler: mediaQuery.textScaler,
                          maxLines: 1,
                        )..layout();
                        final measuredWidth = painter.width;
                        painter.dispose();
                        return (measuredWidth + 48)
                            .clamp(120.0, double.infinity)
                            .toDouble();
                      }

                      final stackActions =
                          constraints.maxWidth <
                          minimumButtonWidth('Clear filters') +
                              minimumButtonWidth('Done') +
                              12;
                      final clearButton = ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: OutlinedButton(
                          onPressed: () {
                            ref.read(selectedTagProvider.notifier).select(null);
                            ref
                                .read(sortOrderProvider.notifier)
                                .set(NoteSort.newest);
                          },
                          child: const Text('Clear filters'),
                        ),
                      );
                      final doneButton = ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Done'),
                        ),
                      );

                      if (stackActions) {
                        return Column(
                          key: const Key('note-filter-actions-stacked'),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            clearButton,
                            const SizedBox(height: 12),
                            doneButton,
                          ],
                        );
                      }

                      return Row(
                        key: const Key('note-filter-actions-inline'),
                        children: [
                          Expanded(child: clearButton),
                          const SizedBox(width: 12),
                          Expanded(child: doneButton),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TagChoice extends StatelessWidget {
  const _TagChoice({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Filter by tag $label',
      button: true,
      selected: selected,
      onTap: onSelected,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: FilterChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onSelected(),
          materialTapTargetSize: MaterialTapTargetSize.padded,
        ),
      ),
    );
  }
}

class _SortChoice extends StatelessWidget {
  const _SortChoice({
    required this.label,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Sort by $label',
      button: true,
      selected: selected,
      onTap: onSelected,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(child: Text(label)),
                const SizedBox(width: 12),
                Icon(
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _sortLabel(NoteSort sort) {
  return switch (sort) {
    NoteSort.newest => 'Newest',
    NoteSort.oldest => 'Oldest',
    NoteSort.titleAZ => 'Title A–Z',
    NoteSort.titleZA => 'Title Z–A',
  };
}
