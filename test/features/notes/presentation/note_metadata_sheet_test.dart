import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/note_metadata_sheet.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('metadata value defensively owns an unmodifiable tag snapshot', () {
    final source = <String>['work'];
    final value = NoteMetadataValue(
      color: Colors.white,
      tags: source,
      reminder: null,
    );

    source.add('outside');

    expect(value.tags, ['work']);
    expect(() => value.tags.add('inside'), throwsUnsupportedError);
  });

  testWidgets('Cancel discards every local tint and tag draft change', (
    tester,
  ) async {
    final initial = NoteMetadataValue(
      color: Colors.white,
      tags: const ['work'],
      reminder: DateTime(2026, 8, 30, 9),
    );
    final result = ValueNotifier<NoteMetadataValue?>(initial);
    addTearDown(result.dispose);
    await _openSheet(tester, initial: initial, result: result);

    await tester.tap(
      find.byKey(ValueKey('metadata-tint-${Colors.blue.shade100.toARGB32()}')),
    );
    await tester.enterText(
      find.byKey(const Key('metadata-tag-field')),
      'personal',
    );
    await tester.tap(find.byKey(const Key('metadata-add-tag')));
    await tester.tap(find.byKey(const ValueKey('metadata-remove-tag-work')));
    await tester.tap(find.byKey(const Key('metadata-cancel')));
    await tester.pumpAndSettle();

    expect(result.value, same(initial));
    expect(initial.color, Colors.white);
    expect(initial.tags, ['work']);
    expect(initial.reminder, DateTime(2026, 8, 30, 9));
  });

  testWidgets('Apply returns the complete local tint and tag draft', (
    tester,
  ) async {
    final initial = NoteMetadataValue(
      color: Colors.white,
      tags: const ['work'],
      reminder: null,
    );
    final result = ValueNotifier<NoteMetadataValue?>(null);
    addTearDown(result.dispose);
    await _openSheet(tester, initial: initial, result: result);

    final blue = Colors.blue.shade100;
    await tester.tap(find.byKey(ValueKey('metadata-tint-${blue.toARGB32()}')));
    await tester.enterText(
      find.byKey(const Key('metadata-tag-field')),
      'personal',
    );
    await tester.tap(find.byKey(const Key('metadata-add-tag')));
    await tester.tap(find.byKey(const Key('metadata-apply')));
    await tester.pumpAndSettle();

    expect(result.value?.color, blue);
    expect(result.value?.tags, ['work', 'personal']);
    expect(result.value?.reminder, isNull);
  });

  testWidgets('blank and duplicate tags are rejected and tags can be removed', (
    tester,
  ) async {
    final initial = NoteMetadataValue(
      color: Colors.white,
      tags: const ['work'],
      reminder: null,
    );
    final result = ValueNotifier<NoteMetadataValue?>(null);
    addTearDown(result.dispose);
    await _openSheet(tester, initial: initial, result: result);

    await tester.enterText(
      find.byKey(const Key('metadata-tag-field')),
      ' work ',
    );
    await tester.tap(find.byKey(const Key('metadata-add-tag')));
    await tester.pump();
    expect(find.text('Tag already added'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('metadata-tag-field')), '   ');
    await tester.tap(find.byKey(const Key('metadata-add-tag')));
    await tester.pump();
    expect(find.text('Enter a tag'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('metadata-remove-tag-work')));
    await tester.tap(find.byKey(const Key('metadata-apply')));
    await tester.pumpAndSettle();
    expect(result.value?.tags, isEmpty);
  });

  testWidgets('Clear reminder applies a real null value', (tester) async {
    final initial = NoteMetadataValue(
      color: Colors.white,
      tags: const [],
      reminder: DateTime(2026, 8, 30, 9),
    );
    final result = ValueNotifier<NoteMetadataValue?>(null);
    addTearDown(result.dispose);
    await _openSheet(tester, initial: initial, result: result);

    await tester.tap(find.byKey(const Key('metadata-clear-reminder')));
    await tester.tap(find.byKey(const Key('metadata-apply')));
    await tester.pumpAndSettle();

    expect(result.value?.reminder, isNull);
  });

  testWidgets('date and time pickers update the reminder draft before Apply', (
    tester,
  ) async {
    final initialReminder = DateTime(2026, 8, 30, 9, 15);
    final initial = NoteMetadataValue(
      color: Colors.white,
      tags: const [],
      reminder: initialReminder,
    );
    final result = ValueNotifier<NoteMetadataValue?>(null);
    addTearDown(result.dispose);
    await _openSheet(tester, initial: initial, result: result);

    await tester.tap(find.byKey(const Key('metadata-reminder-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('31'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Switch to text input mode'));
    await tester.pumpAndSettle();
    final timeFields = find.descendant(
      of: find.byType(TimePickerDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(timeFields.at(0), '10');
    await tester.enterText(timeFields.at(1), '45');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Aug 31, 2026 10:45 AM'), findsOneWidget);
    final apply = find.byKey(const Key('metadata-apply'));
    await tester.ensureVisible(apply);
    await tester.pump();
    await tester.tap(apply);
    await tester.pumpAndSettle();

    expect(result.value?.reminder, DateTime(2026, 8, 31, 10, 45));
  });

  testWidgets('short keyboard sheet stays inside top and keyboard safety', (
    tester,
  ) async {
    final result = ValueNotifier<NoteMetadataValue?>(null);
    addTearDown(result.dispose);
    await _openSheet(
      tester,
      initial: NoteMetadataValue(
        color: Colors.white,
        tags: const ['landscape'],
        reminder: DateTime(2026, 8, 30, 9),
      ),
      result: result,
      size: const Size(640, 360),
      textScaler: const TextScaler.linear(1.5),
      viewPadding: const EdgeInsets.only(top: 24, bottom: 20),
      viewInsets: const EdgeInsets.only(bottom: 120),
      disableAnimations: true,
    );

    final sheet = tester.getRect(find.byKey(const Key('metadata-sheet')));
    expect(
      find.ancestor(
        of: find.byKey(const Key('metadata-sheet')),
        matching: find.byType(SafeArea),
      ),
      findsOneWidget,
      reason: 'The modal route must be the single safe-area owner',
    );
    expect(sheet.top, greaterThanOrEqualTo(24));
    expect(sheet.bottom, lessThanOrEqualTo(240));
    await tester.ensureVisible(find.byKey(const Key('metadata-apply')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('closed keyboard reserves the bottom gesture inset once', (
    tester,
  ) async {
    final result = ValueNotifier<NoteMetadataValue?>(null);
    addTearDown(result.dispose);
    await _openSheet(
      tester,
      initial: NoteMetadataValue(
        color: Colors.white,
        tags: const [],
        reminder: null,
      ),
      result: result,
      size: const Size(320, 640),
      viewPadding: const EdgeInsets.only(bottom: 34),
      disableAnimations: true,
    );

    final sheetFinder = find.byKey(const Key('metadata-sheet'));
    expect(
      find.ancestor(of: sheetFinder, matching: find.byType(SafeArea)),
      findsOneWidget,
    );
    expect(
      640 - tester.getRect(sheetFinder).bottom,
      moreOrLessEquals(46),
      reason: 'The 34px gesture inset plus 12px design margin apply once',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('modal keyboard traversal begins with close then tint choices', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final result = ValueNotifier<NoteMetadataValue?>(null);
    addTearDown(result.dispose);
    await _openSheet(
      tester,
      initial: NoteMetadataValue(
        color: Colors.white,
        tags: const [],
        reminder: null,
      ),
      result: result,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      tester
          .getSemantics(find.byKey(const Key('metadata-close')))
          .flagsCollection
          .isFocused,
      Tristate.isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      tester
          .getSemantics(
            find.byKey(ValueKey('metadata-tint-${Colors.white.toARGB32()}')),
          )
          .flagsCollection
          .isFocused,
      Tristate.isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final red = find.byKey(
      ValueKey('metadata-tint-${Colors.red.shade100.toARGB32()}'),
    );
    expect(tester.getSemantics(red).flagsCollection.isFocused, Tristate.isTrue);
    final focusedMaterial = tester.widget<Material>(
      find.descendant(of: red, matching: find.byType(Material)),
    );
    final focusedBorder = focusedMaterial.shape! as CircleBorder;
    expect(focusedBorder.side.width, greaterThanOrEqualTo(3));
    expect(
      _contrastRatio(focusedBorder.side.color, Colors.red.shade100),
      greaterThanOrEqualTo(3),
    );
    semantics.dispose();
  });

  for (final theme in <ThemeData>[AuroraTheme.light(), AuroraTheme.dark()]) {
    testWidgets(
      'compact ${theme.brightness.name} sheet is semantic, single-glass, and collision free',
      (tester) async {
        final semantics = tester.ensureSemantics();
        final initial = NoteMetadataValue(
          color: Colors.white,
          tags: const ['a long responsive tag', 'second'],
          reminder: DateTime(2026, 8, 30, 9),
        );
        final result = ValueNotifier<NoteMetadataValue?>(null);
        addTearDown(result.dispose);
        await _openSheet(
          tester,
          initial: initial,
          result: result,
          size: const Size(320, 640),
          theme: theme,
          textScaler: const TextScaler.linear(2),
          viewPadding: const EdgeInsets.only(bottom: 34),
        );

        final tints = <({String name, Color color})>[
          (name: 'white', color: Colors.white),
          (name: 'red', color: Colors.red.shade100),
          (name: 'blue', color: Colors.blue.shade100),
          (name: 'green', color: Colors.green.shade100),
          (name: 'yellow', color: Colors.yellow.shade100),
          (name: 'purple', color: Colors.purple.shade100),
          (name: 'orange', color: Colors.orange.shade100),
        ];
        for (final tint in tints) {
          final finder = find.byKey(
            ValueKey('metadata-tint-${tint.color.toARGB32()}'),
          );
          expect(
            tester.getSemantics(finder).label,
            contains('${tint.name} note tint'),
          );
          final initialMaterial = tester.widget<Material>(
            find.descendant(of: finder, matching: find.byType(Material)),
          );
          final initialBorder = initialMaterial.shape! as CircleBorder;
          expect(
            _contrastRatio(initialBorder.side.color, tint.color),
            greaterThanOrEqualTo(3),
            reason: '${tint.name} needs a visible unselected boundary',
          );
          await tester.ensureVisible(finder);
          await tester.tap(finder);
          await tester.pump();
          expect(
            tester.getSemantics(finder).label,
            'Selected ${tint.name} note tint',
          );
          expect(
            tester.getSemantics(finder).flagsCollection.isSelected,
            Tristate.isTrue,
          );
          final check = tester.widget<Icon>(
            find.descendant(of: finder, matching: find.byType(Icon)),
          );
          final material = tester.widget<Material>(
            find.descendant(of: finder, matching: find.byType(Material)),
          );
          final border = material.shape! as CircleBorder;
          expect(
            _contrastRatio(check.color!, tint.color),
            greaterThanOrEqualTo(3),
          );
          expect(
            _contrastRatio(border.side.color, tint.color),
            greaterThanOrEqualTo(3),
          );
        }
        expect(
          find.descendant(
            of: find.byKey(const Key('metadata-sheet')),
            matching: find.byType(GlassSurface),
          ),
          findsOneWidget,
        );
        for (final key in const [
          'metadata-reminder-button',
          'metadata-clear-reminder',
          'metadata-cancel',
          'metadata-apply',
        ]) {
          final finder = find.byKey(Key(key), skipOffstage: false);
          await tester.ensureVisible(finder);
          await tester.pump();
          expect(tester.getSize(finder).height, greaterThanOrEqualTo(44));
        }
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
}

double _contrastRatio(Color first, Color second) {
  final lighter = first.computeLuminance() >= second.computeLuminance()
      ? first.computeLuminance()
      : second.computeLuminance();
  final darker = first.computeLuminance() < second.computeLuminance()
      ? first.computeLuminance()
      : second.computeLuminance();
  return (lighter + 0.05) / (darker + 0.05);
}

Future<void> _openSheet(
  WidgetTester tester, {
  required NoteMetadataValue initial,
  required ValueNotifier<NoteMetadataValue?> result,
  Size size = const Size(375, 812),
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
  EdgeInsets viewPadding = EdgeInsets.zero,
  EdgeInsets viewInsets = EdgeInsets.zero,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AuroraTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: textScaler,
          padding: EdgeInsets.only(
            top: viewPadding.top,
            bottom: (viewPadding.bottom - viewInsets.bottom)
                .clamp(0.0, double.infinity)
                .toDouble(),
          ),
          viewPadding: viewPadding,
          viewInsets: viewInsets,
          disableAnimations: disableAnimations,
        ),
        child: child!,
      ),
      home: Builder(
        builder: (sheetContext) => Scaffold(
          body: Center(
            child: FilledButton(
              key: const Key('open-metadata'),
              onPressed: () async {
                final value = await showModalBottomSheet<NoteMetadataValue>(
                  context: sheetContext,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) =>
                      NoteMetadataSheet(initialValue: initial),
                );
                if (value != null) result.value = value;
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('open-metadata')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('metadata-sheet')), findsOneWidget);
}
