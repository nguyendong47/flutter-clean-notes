import 'package:flutter/material.dart';

import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';

/// Compact glass navigation for the three persistent notes destinations.
class NotesBottomBar extends StatelessWidget {
  const NotesBottomBar({
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.onCreate,
    required this.onMore,
    super.key,
  });

  static const double regionHeight = 92;

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onCreate;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final horizontalInset = MediaQuery.sizeOf(context).width >= 600
        ? 24.0
        : 16.0;
    return SafeArea(
      top: false,
      minimum: EdgeInsets.fromLTRB(horizontalInset, 0, horizontalInset, 12),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SizedBox(
            key: const Key('notes-bottom-bar-region'),
            width: double.infinity,
            height: regionHeight,
            child: Stack(
              children: [
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 72,
                  child: GlassSurface(
                    key: Key('notes-bottom-bar-surface'),
                    borderRadius: BorderRadius.all(Radius.circular(28)),
                    blur: 18,
                    opacity: 0.82,
                    padding: EdgeInsets.zero,
                    child: SizedBox.expand(),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: _DestinationButton(
                          label: 'Notes tab',
                          visibleLabel: 'Notes',
                          icon: Icons.notes_rounded,
                          selected: currentIndex == 0,
                          onTap: () => onDestinationSelected(0),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: _DestinationButton(
                          label: 'Search tab',
                          visibleLabel: 'Search',
                          icon: Icons.search_rounded,
                          selected: currentIndex == 1,
                          onTap: () => onDestinationSelected(1),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Semantics(
                        container: true,
                        button: true,
                        label: 'Create new note',
                        onTap: onCreate,
                        child: ExcludeSemantics(
                          child: FloatingActionButton(
                            heroTag: 'notes-shell-create',
                            tooltip: 'Create new note',
                            onPressed: onCreate,
                            child: const Icon(Icons.add_rounded, size: 28),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: _DestinationButton(
                          label: 'Library tab',
                          visibleLabel: 'Library',
                          icon: Icons.inventory_2_outlined,
                          selected: currentIndex == 2,
                          onTap: () => onDestinationSelected(2),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: _DestinationButton(
                          label: 'More actions',
                          visibleLabel: 'More',
                          icon: Icons.more_horiz_rounded,
                          selected: null,
                          onTap: onMore,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DestinationButton extends StatelessWidget {
  const _DestinationButton({
    required this.label,
    required this.visibleLabel,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String visibleLabel;
  final IconData icon;
  final bool? selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = selected ?? false;
    final foreground = isSelected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: label,
      onTap: onTap,
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(18),
            focusColor: colorScheme.primary.withValues(alpha: 0.16),
            hoverColor: colorScheme.primary.withValues(alpha: 0.10),
            splashColor: colorScheme.primary.withValues(alpha: 0.18),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.secondaryContainer.withValues(alpha: 0.88)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: foreground, size: 19),
                  const SizedBox(height: 1),
                  SizedBox(
                    width: 46,
                    height: 20,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        visibleLabel,
                        maxLines: 1,
                        softWrap: false,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: foreground,
                          fontSize: 12,
                          height: 16 / 12,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 1),
                  SizedBox(
                    height: 2,
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        width: isSelected ? 16 : 0,
                        height: 2,
                        decoration: BoxDecoration(
                          color: foreground,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
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
