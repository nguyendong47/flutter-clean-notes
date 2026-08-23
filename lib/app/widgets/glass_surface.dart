import 'dart:ui';

import 'package:flutter/material.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    super.key,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.padding = const EdgeInsets.all(16),
    this.blur = 18,
    this.opacity = 0.7,
  }) : assert(blur >= 0),
       assert(opacity >= 0 && opacity <= 1);

  final Widget child;
  final BorderRadiusGeometry borderRadius;
  final EdgeInsetsGeometry padding;
  final double blur;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final media = MediaQuery.maybeOf(context);
    final disableBlur =
        blur == 0 ||
        media?.disableAnimations == true ||
        media?.highContrast == true;
    final surface = DecoratedBox(
      decoration: BoxDecoration(
        color: disableBlur
            ? colorScheme.surface
            : colorScheme.surface.withValues(alpha: opacity),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(
            alpha: disableBlur ? 1 : 0.45,
          ),
        ),
        borderRadius: borderRadius,
      ),
      child: Padding(padding: padding, child: child),
    );

    return Semantics(
      container: true,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: disableBlur
            ? surface
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: surface,
              ),
      ),
    );
  }
}
