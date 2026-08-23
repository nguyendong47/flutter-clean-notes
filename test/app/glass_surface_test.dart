import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/app/widgets/aurora_background.dart';
import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';

void main() {
  testWidgets('GlassSurface clips and blurs its child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: GlassSurface(child: Text('Glass content'))),
    );

    expect(find.text('Glass content'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(ClipRRect), findsWidgets);
  });

  testWidgets('GlassSurface uses an opaque fallback for reduced motion', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: GlassSurface(child: Text('Reduced motion content')),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    final semantics = tester.widget<Semantics>(
      find.descendant(
        of: find.byType(GlassSurface),
        matching: find.byType(Semantics),
      ),
    );
    expect(semantics.container, isTrue);
  });

  testWidgets('GlassSurface uses an opaque fallback for high contrast', (
    tester,
  ) async {
    // Mutation caught: disabling blur while leaving the surface or border
    // translucent, which lets background detail reduce high-contrast clarity.
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(highContrast: true),
          child: GlassSurface(child: Text('High contrast content')),
        ),
      ),
    );

    expect(find.byType(BackdropFilter), findsNothing);
    final decorated = tester.widget<DecoratedBox>(
      find.descendant(
        of: find.byType(GlassSurface),
        matching: find.byType(DecoratedBox),
      ),
    );
    final decoration = decorated.decoration as BoxDecoration;
    final activeSurface = Theme.of(
      tester.element(find.byType(GlassSurface)),
    ).colorScheme.surface;
    expect(decoration.color, activeSurface);
    expect(decoration.color!.toARGB32() >>> 24, 255);

    final border = decoration.border;
    expect(border, isA<Border>());
    final borderColor = (border! as Border).top.color;
    expect(borderColor.toARGB32() >>> 24, 255);
  });

  testWidgets(
    'high contrast opaque glass keeps inherited normal text at 4.5 to 1',
    (tester) async {
      for (final theme in [AuroraTheme.light(), AuroraTheme.dark()]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: MediaQuery(
                data: MediaQueryData(highContrast: true),
                child: GlassSurface(child: Text('High contrast text')),
              ),
            ),
          ),
        );

        final glass = find.byType(GlassSurface);
        final decorated = tester.widget<DecoratedBox>(
          find.descendant(of: glass, matching: find.byType(DecoratedBox)),
        );
        final background = (decorated.decoration as BoxDecoration).color!;
        final textContext = tester.element(find.text('High contrast text'));
        final foreground = DefaultTextStyle.of(textContext).style.color!;

        expect(background.a, 1);
        expect(
          _contrastRatio(foreground, background),
          greaterThanOrEqualTo(4.5),
          reason: theme.brightness.name,
        );
      }
    },
  );

  testWidgets('GlassSurface uses an opaque fallback when blur is zero', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: GlassSurface(blur: 0, child: Text('Unblurred content')),
      ),
    );

    expect(find.text('Unblurred content'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
  });

  testWidgets('AuroraBackground keeps content inside a safe area', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(padding: EdgeInsets.only(top: 24)),
          child: AuroraBackground(child: Text('Aurora content')),
        ),
      ),
    );

    expect(find.text('Aurora content'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AuroraBackground),
        matching: find.byType(SafeArea),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AuroraBackground),
        matching: find.byType(DecoratedBox),
      ),
      findsNWidgets(3),
    );
  });
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
