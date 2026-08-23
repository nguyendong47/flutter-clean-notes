import 'package:flutter/material.dart';

import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';

/// Compact glass navigation for the three persistent notes destinations.
class NotesBottomBar extends StatefulWidget {
  const NotesBottomBar({
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.onCreate,
    required this.onMore,
    super.key,
  });

  static const double regionHeight = 92;
  static const double expandedRegionHeight = 108;

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onCreate;
  final VoidCallback onMore;

  @override
  State<NotesBottomBar> createState() => _NotesBottomBarState();
}

class _NotesBottomBarState extends State<NotesBottomBar> {
  int _activationEpoch = 0;
  late final List<FocusNode> _focusNodes = List.generate(
    5,
    (index) => FocusNode(debugLabel: 'Notes bottom bar action $index'),
  );

  @override
  void dispose() {
    for (final focusNode in _focusNodes) {
      focusNode.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final horizontalInset = mediaQuery.size.width >= 600 ? 24.0 : 16.0;
    final useExpandedLayout = mediaQuery.textScaler.scale(12) > 15.6;
    final motionDuration = mediaQuery.disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final regionHeight = useExpandedLayout
        ? NotesBottomBar.expandedRegionHeight
        : NotesBottomBar.regionHeight;

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
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: useExpandedLayout ? regionHeight : 72,
                  child: const GlassSurface(
                    key: Key('notes-bottom-bar-surface'),
                    borderRadius: BorderRadius.all(Radius.circular(28)),
                    blur: 18,
                    opacity: 0.82,
                    padding: EdgeInsets.zero,
                    child: SizedBox.expand(),
                  ),
                ),
                Positioned.fill(
                  child: FocusTraversalGroup(
                    policy: OrderedTraversalPolicy(),
                    child: useExpandedLayout
                        ? _buildExpandedLayout(motionDuration)
                        : _buildCompactLayout(motionDuration),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactLayout(Duration motionDuration) {
    return Align(
      alignment: Alignment.topCenter,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: _destination(0, motionDuration: motionDuration),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: _destination(1, motionDuration: motionDuration),
          ),
          const SizedBox(width: 12),
          _createButton(),
          const SizedBox(width: 12),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: _destination(2, motionDuration: motionDuration),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: _moreButton(motionDuration: motionDuration),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedLayout(Duration motionDuration) {
    return Center(
      child: SizedBox(
        width: 288,
        height: NotesBottomBar.expandedRegionHeight,
        child: Row(
          children: [
            SizedBox(
              width: 104,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _destination(
                    0,
                    expanded: true,
                    motionDuration: motionDuration,
                  ),
                  const SizedBox(height: 4),
                  _destination(
                    1,
                    expanded: true,
                    motionDuration: motionDuration,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            _createButton(),
            const SizedBox(width: 12),
            SizedBox(
              width: 104,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _destination(
                    2,
                    expanded: true,
                    motionDuration: motionDuration,
                  ),
                  const SizedBox(height: 4),
                  _moreButton(expanded: true, motionDuration: motionDuration),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _destination(
    int index, {
    required Duration motionDuration,
    bool expanded = false,
  }) {
    const labels = ['Notes tab', 'Search tab', 'Library tab'];
    const visibleLabels = ['Notes', 'Search', 'Library'];
    const icons = [
      Icons.notes_rounded,
      Icons.search_rounded,
      Icons.inventory_2_outlined,
    ];
    final focusIndex = index < 2 ? index : 3;
    return _DestinationButton(
      label: labels[index],
      visibleLabel: visibleLabels[index],
      icon: icons[index],
      selected: widget.currentIndex == index,
      expanded: expanded,
      motionDuration: motionDuration,
      focusNode: _focusNodes[focusIndex],
      traversalOrder: focusIndex.toDouble(),
      onTap: () => _activate(
        _focusNodes[focusIndex],
        () => widget.onDestinationSelected(index),
        restoreAfterNavigation: true,
      ),
    );
  }

  Widget _moreButton({
    required Duration motionDuration,
    bool expanded = false,
  }) {
    return _DestinationButton(
      label: 'More actions',
      visibleLabel: 'More',
      icon: Icons.more_horiz_rounded,
      selected: null,
      expanded: expanded,
      motionDuration: motionDuration,
      focusNode: _focusNodes[4],
      traversalOrder: 4,
      onTap: () => _activate(_focusNodes[4], widget.onMore),
    );
  }

  Widget _createButton() {
    return FocusTraversalOrder(
      order: const NumericFocusOrder(2),
      child: Semantics(
        container: true,
        button: true,
        label: 'Create new note',
        onTap: () => _activate(_focusNodes[2], widget.onCreate),
        child: ExcludeSemantics(
          child: FloatingActionButton(
            key: const Key('notes-bottom-bar-create-control'),
            heroTag: 'notes-shell-create',
            tooltip: 'Create new note',
            focusNode: _focusNodes[2],
            onPressed: () => _activate(_focusNodes[2], widget.onCreate),
            child: const Icon(Icons.add_rounded, size: 28),
          ),
        ),
      ),
    );
  }

  void _activate(
    FocusNode focusNode,
    VoidCallback callback, {
    bool restoreAfterNavigation = false,
  }) {
    final activationEpoch = ++_activationEpoch;
    final preserveKeyboardFocus =
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    if (preserveKeyboardFocus) {
      focusNode.requestFocus();
    } else {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    callback();
    if (preserveKeyboardFocus && restoreAfterNavigation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted ||
            activationEpoch != _activationEpoch ||
            FocusManager.instance.highlightMode !=
                FocusHighlightMode.traditional ||
            !focusNode.canRequestFocus) {
          return;
        }
        final currentFocus = FocusManager.instance.primaryFocus;
        if (currentFocus != null &&
            currentFocus != focusNode &&
            currentFocus is! FocusScopeNode) {
          return;
        }
        final anotherBarActionHasFocus = _focusNodes.any(
          (node) => node != focusNode && node.hasFocus,
        );
        if (!anotherBarActionHasFocus) focusNode.requestFocus();
      });
    }
  }
}

class _DestinationButton extends StatelessWidget {
  const _DestinationButton({
    required this.label,
    required this.visibleLabel,
    required this.icon,
    required this.selected,
    required this.expanded,
    required this.motionDuration,
    required this.focusNode,
    required this.traversalOrder,
    required this.onTap,
  });

  final String label;
  final String visibleLabel;
  final IconData icon;
  final bool? selected;
  final bool expanded;
  final Duration motionDuration;
  final FocusNode focusNode;
  final double traversalOrder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isSelected = selected ?? false;
    final foreground = isSelected
        ? colorScheme.onSecondaryContainer
        : colorScheme.onSurfaceVariant;
    final controlKey = Key(
      'notes-bottom-bar-${visibleLabel.toLowerCase()}-control',
    );

    return FocusTraversalOrder(
      order: NumericFocusOrder(traversalOrder),
      child: Semantics(
        container: true,
        button: true,
        selected: selected,
        label: label,
        onTap: onTap,
        child: ExcludeSemantics(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: controlKey,
              focusNode: focusNode,
              onTap: onTap,
              borderRadius: BorderRadius.circular(18),
              focusColor: Colors.transparent,
              hoverColor: colorScheme.primary.withValues(alpha: 0.10),
              splashColor: colorScheme.primary.withValues(alpha: 0.18),
              child: ListenableBuilder(
                listenable: focusNode,
                builder: (context, child) => AnimatedContainer(
                  key: Key(
                    'notes-bottom-bar-${visibleLabel.toLowerCase()}-surface',
                  ),
                  duration: motionDuration,
                  curve: Curves.easeOutCubic,
                  width: expanded ? 104 : 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.secondaryContainer.withValues(alpha: 0.88)
                        : Colors.transparent,
                    border: Border.all(
                      color: focusNode.hasFocus
                          ? colorScheme.primary
                          : Colors.transparent,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: child,
                ),
                child: expanded
                    ? _ExpandedDestinationContent(
                        icon: icon,
                        visibleLabel: visibleLabel,
                        foreground: foreground,
                        selected: isSelected,
                        motionDuration: motionDuration,
                      )
                    : _CompactDestinationContent(
                        icon: icon,
                        visibleLabel: visibleLabel,
                        foreground: foreground,
                        selected: isSelected,
                        motionDuration: motionDuration,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CompactDestinationContent extends StatelessWidget {
  const _CompactDestinationContent({
    required this.icon,
    required this.visibleLabel,
    required this.foreground,
    required this.selected,
    required this.motionDuration,
  });

  final IconData icon;
  final String visibleLabel;
  final Color foreground;
  final bool selected;
  final Duration motionDuration;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: foreground, size: 19),
        const SizedBox(height: 1),
        SizedBox(
          width: 46,
          child: Text(
            visibleLabel,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: _labelStyle(context, foreground, selected),
          ),
        ),
        const SizedBox(height: 1),
        SizedBox(
          height: 2,
          child: Center(
            child: AnimatedContainer(
              duration: motionDuration,
              curve: Curves.easeOutCubic,
              width: selected ? 16 : 0,
              height: 2,
              decoration: BoxDecoration(
                color: foreground,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExpandedDestinationContent extends StatelessWidget {
  const _ExpandedDestinationContent({
    required this.icon,
    required this.visibleLabel,
    required this.foreground,
    required this.selected,
    required this.motionDuration,
  });

  final IconData icon;
  final String visibleLabel;
  final Color foreground;
  final bool selected;
  final Duration motionDuration;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          SizedBox(
            width: 2,
            child: AnimatedContainer(
              duration: motionDuration,
              curve: Curves.easeOutCubic,
              width: 2,
              height: selected ? 16 : 0,
              decoration: BoxDecoration(
                color: foreground,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(icon, color: foreground, size: 18),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              visibleLabel,
              maxLines: 1,
              softWrap: false,
              style: _labelStyle(context, foreground, selected),
            ),
          ),
        ],
      ),
    );
  }
}

TextStyle? _labelStyle(BuildContext context, Color foreground, bool selected) {
  return Theme.of(context).textTheme.labelSmall?.copyWith(
    color: foreground,
    fontSize: 12,
    height: 16 / 12,
    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
    letterSpacing: -0.2,
  );
}
