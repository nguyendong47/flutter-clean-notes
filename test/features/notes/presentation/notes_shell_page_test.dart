import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/notes_bottom_bar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final theme in <ThemeData>[AuroraTheme.light(), AuroraTheme.dark()]) {
    final brightness = theme.brightness.name;
    testWidgets(
      'bottom bar has one disjoint 48 pixel semantic target per action at 320 in $brightness mode',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        var selectedIndex = -1;
        var createCount = 0;
        var moreCount = 0;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: const ColoredBox(color: Colors.transparent),
              bottomNavigationBar: NotesBottomBar(
                currentIndex: 0,
                onDestinationSelected: (index) => selectedIndex = index,
                onCreate: () => createCount++,
                onMore: () => moreCount++,
              ),
            ),
          ),
        );

        const labels = <String>[
          'Notes tab',
          'Search tab',
          'Create new note',
          'Library tab',
          'More actions',
        ];
        const visibleLabels = <String>['Notes', 'Search', 'Library', 'More'];
        final rects = <Rect>[];
        for (final label in labels) {
          final finder = find.bySemanticsLabel(label);
          expect(finder, findsOneWidget);
          final rect = tester.getRect(finder);
          expect(rect.width, greaterThanOrEqualTo(48), reason: label);
          expect(rect.height, greaterThanOrEqualTo(48), reason: label);
          rects.add(rect);
        }
        for (var left = 0; left < rects.length; left++) {
          for (var right = left + 1; right < rects.length; right++) {
            expect(
              rects[left].overlaps(rects[right]),
              isFalse,
              reason: '${labels[left]} overlaps ${labels[right]}',
            );
          }
        }
        for (final label in visibleLabels) {
          final labelFinder = find.text(label);
          expect(labelFinder, findsOneWidget);
          final text = tester.widget<Text>(labelFinder);
          expect(text.maxLines, 1);
          expect(text.softWrap, isFalse);
          final labelRect = tester.getRect(labelFinder);
          final targetLabel = switch (label) {
            'Notes' => 'Notes tab',
            'Search' => 'Search tab',
            'Library' => 'Library tab',
            _ => 'More actions',
          };
          expect(
            rects[labels.indexOf(targetLabel)].contains(labelRect.center),
            isTrue,
            reason: '$label must remain inside its 48 pixel target',
          );
        }

        final notesNode = tester.getSemantics(
          find.bySemanticsLabel('Notes tab'),
        );
        final searchNode = tester.getSemantics(
          find.bySemanticsLabel('Search tab'),
        );
        final moreNode = tester.getSemantics(
          find.bySemanticsLabel('More actions'),
        );
        expect(notesNode.flagsCollection.isSelected, Tristate.isTrue);
        expect(searchNode.flagsCollection.isSelected, Tristate.isFalse);
        expect(moreNode.flagsCollection.isSelected, Tristate.none);

        final notesLabel = tester.widget<Text>(find.text('Notes'));
        final searchLabel = tester.widget<Text>(find.text('Search'));
        expect(notesLabel.style?.fontSize, 12);
        expect(notesLabel.style?.height, closeTo(16 / 12, 0.001));
        expect(notesLabel.style?.fontWeight, FontWeight.w600);
        expect(searchLabel.style?.fontWeight, FontWeight.w500);

        final barRect = tester.getRect(
          find.byKey(const Key('notes-bottom-bar-surface')),
        );
        expect(
          tester
              .widget<FloatingActionButton>(find.byType(FloatingActionButton))
              .tooltip,
          'Create new note',
        );
        final createRect = rects[2];
        expect(createRect.top, lessThan(barRect.top));
        await tester.tapAt(Offset(createRect.center.dx, createRect.top + 4));
        await tester.pump();
        expect(createCount, 1);

        await tester.tap(find.bySemanticsLabel('Search tab'));
        await tester.tap(find.bySemanticsLabel('Library tab'));
        await tester.tap(find.bySemanticsLabel('More actions'));
        await tester.pump();
        expect(selectedIndex, 2);
        expect(moreCount, 1);
        semantics.dispose();
      },
    );
  }

  testWidgets('tablet bar keeps at least 24 pixel side insets', (tester) async {
    tester.view.physicalSize = const Size(620, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AuroraTheme.light(),
        home: Scaffold(
          bottomNavigationBar: NotesBottomBar(
            currentIndex: 0,
            onDestinationSelected: (_) {},
            onCreate: () {},
            onMore: () {},
          ),
        ),
      ),
    );

    final surfaceRect = tester.getRect(
      find.byKey(const Key('notes-bottom-bar-surface')),
    );
    expect(surfaceRect.left, greaterThanOrEqualTo(24));
    expect(620 - surfaceRect.right, greaterThanOrEqualTo(24));
  });

  for (final textScale in [1.5, 2.0]) {
    testWidgets('compact labels fit without clipping at ${textScale}x', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          theme: AuroraTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: Scaffold(
            bottomNavigationBar: NotesBottomBar(
              currentIndex: 0,
              onDestinationSelected: (_) {},
              onCreate: () {},
              onMore: () {},
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      for (final label in const ['Notes', 'Search', 'Library', 'More']) {
        final labelFinder = find.text(label);
        final labelRect = tester.getRect(labelFinder);
        final paragraph = tester.renderObject<RenderParagraph>(labelFinder);
        expect(labelRect.width, lessThanOrEqualTo(48), reason: label);
        expect(labelRect.height, lessThanOrEqualTo(24), reason: label);
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      }
    });
  }
}
