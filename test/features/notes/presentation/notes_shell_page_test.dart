import 'dart:math' as math;
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/notes_bottom_bar.dart';

import '../../../support/localization_test_wrapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // easy_localization's RootBundleAssetLoader reads translation JSON via
  // rootBundle.loadString, which flutter's CachingAssetBundle caches by key.
  // A stale cache entry from an earlier test's (now-disposed) EasyLocalization
  // instance causes every subsequent wrapWithTestLocalization(...) build in
  // this file to hang forever awaiting that load (see
  // aissat/easy_localization#268/#362). Clearing the cache after each test
  // keeps every load a fresh read.
  tearDown(() => rootBundle.clear());

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
          wrapWithTestLocalization(
            Builder(
              builder: (localizationContext) => MaterialApp(
                theme: theme,
                localizationsDelegates:
                    localizationContext.localizationDelegates,
                supportedLocales: localizationContext.supportedLocales,
                locale: localizationContext.locale,
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
            ),
          ),
        );
        await tester.pumpAndSettle();

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
      wrapWithTestLocalization(
        Builder(
          builder: (localizationContext) => MaterialApp(
            theme: AuroraTheme.light(),
            localizationsDelegates: localizationContext.localizationDelegates,
            supportedLocales: localizationContext.supportedLocales,
            locale: localizationContext.locale,
            home: Scaffold(
              bottomNavigationBar: NotesBottomBar(
                currentIndex: 0,
                onDestinationSelected: (_) {},
                onCreate: () {},
                onMore: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surfaceRect = tester.getRect(
      find.byKey(const Key('notes-bottom-bar-surface')),
    );
    expect(surfaceRect.left, greaterThanOrEqualTo(24));
    expect(620 - surfaceRect.right, greaterThanOrEqualTo(24));
  });

  for (final theme in <ThemeData>[AuroraTheme.light(), AuroraTheme.dark()]) {
    testWidgets(
      'Create FAB uses restrained Aurora elevation and a contrasting keyboard focus indicator in ${theme.brightness.name} mode',
      (tester) async {
        // Mutation caught: inheriting the stock black FAB shadow/focus elevation
        // recreates the heavy ring, while removing the replacement outline
        // leaves keyboard users without a visible focus state.
        final previousStrategy = FocusManager.instance.highlightStrategy;
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        addTearDown(
          () => FocusManager.instance.highlightStrategy = previousStrategy,
        );
        final semantics = tester.ensureSemantics();

        await tester.pumpWidget(
          wrapWithTestLocalization(
            Builder(
              builder: (localizationContext) => MaterialApp(
                theme: theme,
                localizationsDelegates:
                    localizationContext.localizationDelegates,
                supportedLocales: localizationContext.supportedLocales,
                locale: localizationContext.locale,
                home: Scaffold(
                  bottomNavigationBar: NotesBottomBar(
                    currentIndex: 0,
                    onDestinationSelected: (_) {},
                    onCreate: () {},
                    onMore: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final control = find.byKey(
          const Key('notes-bottom-bar-create-control'),
        );
        final button = tester.widget<FloatingActionButton>(control);
        final colorScheme = Theme.of(
          tester.element(find.byType(NotesBottomBar)),
        ).colorScheme;
        expect(button.backgroundColor, colorScheme.primary);
        expect(button.foregroundColor, colorScheme.onPrimary);
        expect(
          _contrastRatio(button.backgroundColor!, button.foregroundColor!),
          greaterThanOrEqualTo(4.5),
        );
        final buttonMaterial = tester.widget<Material>(
          find.descendant(
            of: control,
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Material && widget.type == MaterialType.button,
            ),
          ),
        );
        expect(buttonMaterial.shadowColor, isNot(anyOf(isNull, Colors.black)));
        expect(button.elevation, lessThanOrEqualTo(2));
        expect(button.focusElevation, lessThanOrEqualTo(2));
        expect(button.hoverElevation, lessThanOrEqualTo(3));
        expect(button.highlightElevation, lessThanOrEqualTo(2));
        expect(button.disabledElevation, 0);
        expect(button.focusColor, isNot(anyOf(isNull, Colors.transparent)));
        expect(button.hoverColor, isNot(anyOf(isNull, Colors.transparent)));
        expect(button.shape, isA<CircleBorder>());

        final indicator = find.byKey(
          const Key('notes-bottom-bar-create-focus-indicator'),
        );
        final idleDecoration =
            tester.widget<AnimatedContainer>(indicator).decoration!
                as ShapeDecoration;
        expect((idleDecoration.shape as CircleBorder).side.color.a, 0);

        tester.widget<FloatingActionButton>(control).focusNode!.requestFocus();
        await tester.pumpAndSettle();

        final focusedDecoration =
            tester.widget<AnimatedContainer>(indicator).decoration!
                as ShapeDecoration;
        final focusedSide = (focusedDecoration.shape as CircleBorder).side;
        expect(focusedSide.width, greaterThanOrEqualTo(2));
        expect(focusedSide.color.a, 1);
        expect(
          _contrastRatio(focusedSide.color, button.backgroundColor!),
          greaterThanOrEqualTo(3),
        );
        expect(
          tester.widget<FloatingActionButton>(control).focusNode!.hasFocus,
          isTrue,
        );
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('Create new note'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
        semantics.dispose();
      },
    );
  }

  for (final textScale in [1.5, 2.0]) {
    testWidgets('labels visibly scale at ${textScale}x without clipping', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      Future<void> pumpBar(double scale) async {
        await tester.pumpWidget(
          wrapWithTestLocalization(
            Builder(
              builder: (localizationContext) => MaterialApp(
                theme: AuroraTheme.light(),
                localizationsDelegates:
                    localizationContext.localizationDelegates,
                supportedLocales: localizationContext.supportedLocales,
                locale: localizationContext.locale,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(textScaler: TextScaler.linear(scale)),
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
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      const labels = ['Notes', 'Search', 'Library', 'More'];
      await pumpBar(1);
      final baselineHeights = {
        for (final label in labels)
          label: tester.getRect(find.text(label)).height,
      };

      await pumpBar(textScale);

      expect(tester.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(NotesBottomBar),
          matching: find.byType(FittedBox),
        ),
        findsNothing,
      );
      for (final label in labels) {
        final labelFinder = find.text(label);
        final labelRect = tester.getRect(labelFinder);
        final paragraph = tester.renderObject<RenderParagraph>(labelFinder);
        final targetLabel = label == 'More' ? 'More actions' : '$label tab';
        final targetRect = tester.getRect(find.bySemanticsLabel(targetLabel));
        expect(
          labelRect.height,
          greaterThan(baselineHeights[label]! * (textScale - 0.1)),
          reason: '$label must retain the user requested text enlargement',
        );
        expect(targetRect.width, greaterThanOrEqualTo(48), reason: label);
        expect(targetRect.height, greaterThanOrEqualTo(48), reason: label);
        expect(
          targetRect.left <= labelRect.left &&
              targetRect.top <= labelRect.top &&
              targetRect.right >= labelRect.right &&
              targetRect.bottom >= labelRect.bottom,
          isTrue,
          reason: '$label paint bounds must remain inside its target',
        );
        final text = tester.widget<Text>(labelFinder);
        expect(
          text.overflow,
          isNot(anyOf(TextOverflow.fade, TextOverflow.ellipsis)),
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      }

      const targetKeys = [
        Key('notes-bottom-bar-notes-control'),
        Key('notes-bottom-bar-search-control'),
        Key('notes-bottom-bar-create-control'),
        Key('notes-bottom-bar-library-control'),
        Key('notes-bottom-bar-more-control'),
      ];
      final targetRects = [
        for (final key in targetKeys) tester.getRect(find.byKey(key)),
      ];
      for (var first = 0; first < targetRects.length; first++) {
        for (var second = first + 1; second < targetRects.length; second++) {
          expect(
            _distanceBetween(targetRects[first], targetRects[second]),
            greaterThanOrEqualTo(8),
            reason:
                '${targetKeys[first]} and ${targetKeys[second]} need 8 pixels between targets',
          );
        }
      }
    });
  }

  testWidgets(
    'jumbo 3x text derives bar height and keeps labels in disjoint targets',
    (tester) async {
      final semantics = tester.ensureSemantics();
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      var selectedIndex = -1;
      await tester.pumpWidget(
        wrapWithTestLocalization(
          Builder(
            builder: (localizationContext) => MaterialApp(
              theme: AuroraTheme.light(),
              localizationsDelegates: localizationContext.localizationDelegates,
              supportedLocales: localizationContext.supportedLocales,
              locale: localizationContext.locale,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(3)),
                child: child!,
              ),
              home: Scaffold(
                bottomNavigationBar: NotesBottomBar(
                  currentIndex: 1,
                  onDestinationSelected: (index) => selectedIndex = index,
                  onCreate: () {},
                  onMore: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final regionRect = tester.getRect(
        find.byKey(const Key('notes-bottom-bar-region')),
      );
      final surfaceRect = tester.getRect(
        find.byKey(const Key('notes-bottom-bar-surface')),
      );
      expect(
        regionRect.height,
        greaterThan(NotesBottomBar.expandedRegionHeight),
      );
      expect(
        surfaceRect.height,
        greaterThan(NotesBottomBar.expandedSurfaceHeight),
      );

      const labels = <String, String>{
        'Notes tab': 'Notes',
        'Search tab': 'Search',
        'Library tab': 'Library',
        'More actions': 'More',
      };
      final targetRects = <Rect>[];
      for (final entry in labels.entries) {
        final target = find.bySemanticsLabel(entry.key);
        final visibleLabel = find.text(entry.value);
        final targetRect = tester.getRect(target);
        final labelRect = tester.getRect(visibleLabel);
        final paragraph = tester.renderObject<RenderParagraph>(visibleLabel);
        expect(targetRect.width, greaterThanOrEqualTo(48), reason: entry.key);
        expect(targetRect.height, greaterThanOrEqualTo(48), reason: entry.key);
        expect(
          targetRect.contains(labelRect.topLeft),
          isTrue,
          reason: entry.key,
        );
        expect(
          targetRect.contains(labelRect.bottomRight),
          isTrue,
          reason: entry.key,
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: entry.key);
        targetRects.add(targetRect);
      }
      targetRects.add(tester.getRect(find.bySemanticsLabel('Create new note')));
      for (var first = 0; first < targetRects.length; first++) {
        for (var second = first + 1; second < targetRects.length; second++) {
          expect(
            _distanceBetween(targetRects[first], targetRects[second]),
            greaterThanOrEqualTo(8),
          );
        }
      }

      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Notes tab'))
            .flagsCollection
            .isSelected,
        Tristate.isFalse,
      );
      expect(
        tester
            .getSemantics(find.bySemanticsLabel('Search tab'))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      await tester.tap(find.bySemanticsLabel('Library tab'));
      await tester.pump();
      expect(selectedIndex, 2);
      semantics.dispose();
    },
  );

  for (final textScale in [1.5, 2.0]) {
    testWidgets(
      'expanded ${textScale}x layout raises Create 20 pixels above glass',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          wrapWithTestLocalization(
            Builder(
              builder: (localizationContext) => MaterialApp(
                theme: AuroraTheme.light(),
                localizationsDelegates:
                    localizationContext.localizationDelegates,
                supportedLocales: localizationContext.supportedLocales,
                locale: localizationContext.locale,
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
            ),
          ),
        );
        await tester.pumpAndSettle();

        final regionRect = tester.getRect(
          find.byKey(const Key('notes-bottom-bar-region')),
        );
        final surfaceRect = tester.getRect(
          find.byKey(const Key('notes-bottom-bar-surface')),
        );
        final createRect = tester.getRect(
          find.byKey(const Key('notes-bottom-bar-create-control')),
        );

        expect(regionRect.height, 132);
        expect(surfaceRect.height, 112);
        expect(surfaceRect.top - createRect.top, 20);
      },
    );
  }

  testWidgets('reduced motion disables bottom bar selection animations', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithTestLocalization(
        Builder(
          builder: (localizationContext) => MaterialApp(
            theme: AuroraTheme.light(),
            localizationsDelegates: localizationContext.localizationDelegates,
            supportedLocales: localizationContext.supportedLocales,
            locale: localizationContext.locale,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
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
        ),
      ),
    );
    await tester.pumpAndSettle();

    final animations = tester.widgetList<AnimatedContainer>(
      find.descendant(
        of: find.byType(NotesBottomBar),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(animations, isNotEmpty);
    expect(
      animations.every((animation) => animation.duration == Duration.zero),
      isTrue,
    );
  });

  testWidgets('Tab order is visual and Enter preserves keyboard focus', (
    tester,
  ) async {
    final previousStrategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy = previousStrategy,
    );
    var selectedIndex = -1;

    await tester.pumpWidget(
      wrapWithTestLocalization(
        Builder(
          builder: (localizationContext) => MaterialApp(
            theme: AuroraTheme.light(),
            localizationsDelegates: localizationContext.localizationDelegates,
            supportedLocales: localizationContext.supportedLocales,
            locale: localizationContext.locale,
            home: Scaffold(
              bottomNavigationBar: NotesBottomBar(
                currentIndex: 0,
                onDestinationSelected: (index) => selectedIndex = index,
                onCreate: () {},
                onMore: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const controlKeys = [
      Key('notes-bottom-bar-notes-control'),
      Key('notes-bottom-bar-search-control'),
      Key('notes-bottom-bar-create-control'),
      Key('notes-bottom-bar-library-control'),
      Key('notes-bottom-bar-more-control'),
    ];
    for (final key in controlKeys) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final focusNode = switch (tester.widget(find.byKey(key))) {
        final InkWell inkWell => inkWell.focusNode,
        final FloatingActionButton button => button.focusNode,
        _ => null,
      };
      expect(focusNode?.hasFocus, isTrue, reason: key.toString());
    }

    FocusScope.of(tester.element(find.byType(NotesBottomBar))).requestFocus(
      tester
          .widget<InkWell>(
            find.byKey(const Key('notes-bottom-bar-search-control')),
          )
          .focusNode,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selectedIndex, 1);
    expect(
      tester
          .widget<InkWell>(
            find.byKey(const Key('notes-bottom-bar-search-control')),
          )
          .focusNode
          ?.hasFocus,
      isTrue,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      tester
          .widget<FloatingActionButton>(
            find.byKey(const Key('notes-bottom-bar-create-control')),
          )
          .focusNode
          ?.hasFocus,
      isTrue,
      reason: 'a queued restore must not override a later Tab',
    );

    tester
        .widget<InkWell>(
          find.byKey(const Key('notes-bottom-bar-notes-control')),
        )
        .focusNode!
        .requestFocus();
    await tester.pump();
    final selectedSurface = tester.widget<AnimatedContainer>(
      find.byKey(const Key('notes-bottom-bar-notes-surface')),
    );
    final decoration = selectedSurface.decoration! as BoxDecoration;
    expect(decoration.color, isNot(Colors.transparent));
    expect(decoration.border?.top.width, 2);
    expect(
      decoration.border?.top.color,
      Theme.of(tester.element(find.byType(NotesBottomBar))).colorScheme.primary,
    );
  });

  testWidgets('touch activation dismisses an active text input', (
    tester,
  ) async {
    final fieldFocus = FocusNode();
    addTearDown(fieldFocus.dispose);
    var selectedIndex = -1;
    await tester.pumpWidget(
      wrapWithTestLocalization(
        Builder(
          builder: (localizationContext) => MaterialApp(
            theme: AuroraTheme.light(),
            localizationsDelegates: localizationContext.localizationDelegates,
            supportedLocales: localizationContext.supportedLocales,
            locale: localizationContext.locale,
            home: Scaffold(
              body: TextField(focusNode: fieldFocus),
              bottomNavigationBar: NotesBottomBar(
                currentIndex: 0,
                onDestinationSelected: (index) => selectedIndex = index,
                onCreate: () {},
                onMore: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(fieldFocus.hasFocus, isTrue);
    await tester.tap(find.bySemanticsLabel('Search tab'));
    await tester.pump();
    expect(selectedIndex, 1);
    expect(fieldFocus.hasFocus, isFalse);
  });

  testWidgets('external focus cancels a pending destination restore', (
    tester,
  ) async {
    final previousStrategy = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy = previousStrategy,
    );
    final externalFocus = FocusNode();
    addTearDown(externalFocus.dispose);
    await tester.pumpWidget(
      wrapWithTestLocalization(
        Builder(
          builder: (localizationContext) => MaterialApp(
            theme: AuroraTheme.light(),
            localizationsDelegates: localizationContext.localizationDelegates,
            supportedLocales: localizationContext.supportedLocales,
            locale: localizationContext.locale,
            home: Scaffold(
              body: TextButton(
                focusNode: externalFocus,
                onPressed: () {},
                child: const Text('Outside action'),
              ),
              bottomNavigationBar: NotesBottomBar(
                currentIndex: 0,
                onDestinationSelected: (_) {},
                onCreate: () {},
                onMore: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final notesNode = tester
        .widget<InkWell>(
          find.byKey(const Key('notes-bottom-bar-notes-control')),
        )
        .focusNode!;
    notesNode.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    externalFocus.requestFocus();
    await tester.pump();

    expect(externalFocus.hasFocus, isTrue);
    expect(notesNode.hasFocus, isFalse);
  });

  testWidgets('high text remains usable in phone landscape', (tester) async {
    tester.view.physicalSize = const Size(640, 320);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      wrapWithTestLocalization(
        Builder(
          builder: (localizationContext) => MaterialApp(
            theme: AuroraTheme.dark(),
            localizationsDelegates: localizationContext.localizationDelegates,
            supportedLocales: localizationContext.supportedLocales,
            locale: localizationContext.locale,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Scaffold(
              bottomNavigationBar: NotesBottomBar(
                currentIndex: 1,
                onDestinationSelected: (_) {},
                onCreate: () {},
                onMore: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final surfaceRect = tester.getRect(
      find.byKey(const Key('notes-bottom-bar-surface')),
    );
    expect(surfaceRect.left, greaterThanOrEqualTo(24));
    expect(640 - surfaceRect.right, greaterThanOrEqualTo(24));
    for (final label in const [
      'Notes tab',
      'Search tab',
      'Create new note',
      'Library tab',
      'More actions',
    ]) {
      final targetRect = tester.getRect(find.bySemanticsLabel(label));
      expect(targetRect.width, greaterThanOrEqualTo(48), reason: label);
      expect(targetRect.height, greaterThanOrEqualTo(48), reason: label);
    }
  });
}

double _distanceBetween(Rect first, Rect second) {
  final horizontal = math.max(
    0,
    math.max(first.left - second.right, second.left - first.right),
  );
  final vertical = math.max(
    0,
    math.max(first.top - second.bottom, second.top - first.bottom),
  );
  return math.sqrt(horizontal * horizontal + vertical * vertical);
}

double _contrastRatio(Color first, Color second) {
  final lighter = math.max(first.computeLuminance(), second.computeLuminance());
  final darker = math.min(first.computeLuminance(), second.computeLuminance());
  return (lighter + 0.05) / (darker + 0.05);
}
