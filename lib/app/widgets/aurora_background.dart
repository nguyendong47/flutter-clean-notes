import 'package:flutter/material.dart';

import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';

class AuroraBackground extends StatelessWidget {
  const AuroraBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final simplifyEffects =
        MediaQuery.highContrastOf(context) ||
        MediaQuery.disableAnimationsOf(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (simplifyEffects)
          DecoratedBox(decoration: BoxDecoration(color: colorScheme.surface))
        else ...[
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  theme.scaffoldBackgroundColor,
                  colorScheme.surfaceContainerLowest,
                ],
              ),
            ),
          ),
          Positioned(
            top: -140,
            right: -110,
            width: 360,
            height: 360,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      colorScheme.primary.withValues(alpha: 0.3),
                      colorScheme.primary.withValues(alpha: 0),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -130,
            left: -100,
            width: 340,
            height: 340,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      AuroraTheme.mint.withValues(alpha: 0.24),
                      AuroraTheme.mint.withValues(alpha: 0),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
        SafeArea(child: child),
      ],
    );
  }
}
