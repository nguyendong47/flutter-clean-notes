import 'package:flutter/material.dart';
import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/app/widgets/aurora_background.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('normal background paints one linear and two radial fields', (
    tester,
  ) async {
    await _pumpBackground(tester);

    final decorations = _decorations(tester);
    expect(
      decorations.where((decoration) => decoration.gradient is LinearGradient),
      hasLength(1),
    );
    expect(
      decorations.where((decoration) => decoration.gradient is RadialGradient),
      hasLength(2),
    );
    expect(find.byType(SafeArea), findsOneWidget);
    expect(find.text('Notes content'), findsOneWidget);
  });

  for (final setting in <({String name, bool highContrast, bool disabled})>[
    (name: 'high contrast', highContrast: true, disabled: false),
    (name: 'disabled animations', highContrast: false, disabled: true),
  ]) {
    for (final appearance in <({String name, ThemeData theme})>[
      (name: 'light', theme: AuroraTheme.light()),
      (name: 'dark', theme: AuroraTheme.dark()),
    ]) {
      testWidgets(
        '${setting.name} paints one opaque ${appearance.name} theme surface',
        (tester) async {
          await _pumpBackground(
            tester,
            theme: appearance.theme,
            highContrast: setting.highContrast,
            disableAnimations: setting.disabled,
          );

          final decorations = _decorations(tester);
          expect(decorations, hasLength(1));
          expect(decorations.single.gradient, isNull);
          expect(
            decorations.single.color,
            appearance.theme.colorScheme.surface,
          );
          expect(decorations.single.color!.a, 1);
          expect(find.byType(SafeArea), findsOneWidget);
          expect(find.text('Notes content'), findsOneWidget);
        },
      );
    }
  }
}

Future<void> _pumpBackground(
  WidgetTester tester, {
  ThemeData? theme,
  bool highContrast = false,
  bool disableAnimations = false,
}) async {
  final resolvedTheme = theme ?? AuroraTheme.light();
  await tester.pumpWidget(
    MaterialApp(
      theme: resolvedTheme,
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            highContrast: highContrast,
            disableAnimations: disableAnimations,
          ),
          child: const AuroraBackground(child: Text('Notes content')),
        ),
      ),
    ),
  );
  await tester.pump();
}

List<BoxDecoration> _decorations(WidgetTester tester) {
  return tester
      .widgetList<DecoratedBox>(
        find.descendant(
          of: find.byType(AuroraBackground),
          matching: find.byType(DecoratedBox),
        ),
      )
      .map((box) => box.decoration)
      .whereType<BoxDecoration>()
      .toList();
}
