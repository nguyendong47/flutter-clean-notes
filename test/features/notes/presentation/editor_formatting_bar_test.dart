import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/dictation_service_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/dictation_service.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/editor_formatting_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/fake_permission_requester.dart';
import '../../../helpers/fake_speech_recognizer.dart';
import '../../../support/localization_test_wrapper.dart';

void main() {
  // easy_localization's RootBundleAssetLoader reads translation JSON via
  // rootBundle.loadString, which flutter's CachingAssetBundle caches by key.
  // A stale cache entry from an earlier test's (now-disposed) EasyLocalization
  // instance causes every subsequent wrapWithTestLocalization(...) build in
  // this file to hang forever awaiting that load (see
  // aissat/easy_localization#268/#362). Clearing the cache after each test
  // keeps every load a fresh read.
  tearDown(() => rootBundle.clear());

  const wrapperCases =
      <({String key, String tooltip, String before, String after})>[
        (key: 'bold', tooltip: 'Bold', before: '**', after: '**'),
        (key: 'italic', tooltip: 'Italic', before: '*', after: '*'),
        (key: 'strike', tooltip: 'Strikethrough', before: '~~', after: '~~'),
        (key: 'code', tooltip: 'Inline code', before: '`', after: '`'),
      ];

  for (final formatCase in wrapperCases) {
    testWidgets('${formatCase.tooltip} wraps selection and preserves it', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'selected')
        ..selection = const TextSelection(baseOffset: 0, extentOffset: 8);
      addTearDown(controller.dispose);
      await _pumpBar(tester, controller);

      await tester.tap(find.byKey(Key('editor-format-${formatCase.key}')));
      await tester.pump();

      expect(
        controller.text,
        '${formatCase.before}selected${formatCase.after}',
      );
      expect(
        controller.selection,
        TextSelection(
          baseOffset: formatCase.before.length,
          extentOffset: formatCase.before.length + 8,
        ),
      );
    });

    testWidgets('${formatCase.tooltip} inserts markers at the caret', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'ab')
        ..selection = const TextSelection.collapsed(offset: 1);
      addTearDown(controller.dispose);
      await _pumpBar(tester, controller);

      await tester.tap(find.byKey(Key('editor-format-${formatCase.key}')));
      await tester.pump();

      expect(controller.text, 'a${formatCase.before}${formatCase.after}b');
      expect(
        controller.selection,
        TextSelection.collapsed(offset: 1 + formatCase.before.length),
      );
    });
  }

  const prefixCases = <({String key, String tooltip, String prefix})>[
    (key: 'quote', tooltip: 'Quote', prefix: '> '),
    (key: 'h1', tooltip: 'Heading 1', prefix: '# '),
    (key: 'h2', tooltip: 'Heading 2', prefix: '## '),
    (key: 'bullet', tooltip: 'Bulleted list', prefix: '- '),
    (key: 'checklist', tooltip: 'Checklist', prefix: '- [ ] '),
  ];

  for (final formatCase in prefixCases) {
    testWidgets('${formatCase.tooltip} toggles only the caret line', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'first\nsecond')
        ..selection = const TextSelection.collapsed(offset: 8);
      addTearDown(controller.dispose);
      await _pumpBar(tester, controller);
      final control = find.byKey(
        Key('editor-format-${formatCase.key}'),
        skipOffstage: false,
      );
      final scrollable = find.descendant(
        of: find.byKey(const Key('editor-formatting-scroll')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(control, 160, scrollable: scrollable);

      await tester.tap(control);
      await tester.pump();

      expect(controller.text, 'first\n${formatCase.prefix}second');
      expect(
        controller.selection,
        TextSelection.collapsed(
          offset: 6 + formatCase.prefix.length + 'second'.length,
        ),
      );

      await tester.tap(control);
      await tester.pump();
      expect(controller.text, 'first\nsecond');
      expect(controller.selection, const TextSelection.collapsed(offset: 12));
    });

    testWidgets('${formatCase.tooltip} preserves legacy selection output', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'first\nsecond')
        ..selection = const TextSelection(baseOffset: 7, extentOffset: 10);
      addTearDown(controller.dispose);
      await _pumpBar(tester, controller);
      final control = find.byKey(
        Key('editor-format-${formatCase.key}'),
        skipOffstage: false,
      );
      final scrollable = find.descendant(
        of: find.byKey(const Key('editor-formatting-scroll')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(control, 160, scrollable: scrollable);

      await tester.tap(control);
      await tester.pump();

      expect(controller.text, 'first\n${formatCase.prefix}second');
      expect(
        controller.selection,
        TextSelection.collapsed(
          offset: 6 + formatCase.prefix.length + 'second'.length,
        ),
      );
    });
  }

  testWidgets('all nine labeled controls are at least 48 square', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pumpBar(tester, controller, width: 320);

    const controls = <({String key, String tooltip})>[
      (key: 'bold', tooltip: 'Bold'),
      (key: 'italic', tooltip: 'Italic'),
      (key: 'strike', tooltip: 'Strikethrough'),
      (key: 'code', tooltip: 'Inline code'),
      (key: 'quote', tooltip: 'Quote'),
      (key: 'h1', tooltip: 'Heading 1'),
      (key: 'h2', tooltip: 'Heading 2'),
      (key: 'bullet', tooltip: 'Bulleted list'),
      (key: 'checklist', tooltip: 'Checklist'),
    ];
    final scrollable = find.descendant(
      of: find.byKey(const Key('editor-formatting-scroll')),
      matching: find.byType(Scrollable),
    );
    for (final control in controls) {
      final finder = find.byKey(
        Key('editor-format-${control.key}'),
        skipOffstage: false,
      );
      await tester.scrollUntilVisible(finder, 120, scrollable: scrollable);
      expect(finder, findsOneWidget);
      expect(find.byTooltip(control.tooltip), findsOneWidget);
      final size = tester.getSize(finder);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('320 formatting bar stays overflow-free at 3x text', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pumpBar(
      tester,
      controller,
      width: 320,
      textScaler: const TextScaler.linear(3),
    );

    final scrollable = find.descendant(
      of: find.byKey(const Key('editor-formatting-scroll')),
      matching: find.byType(Scrollable),
    );
    for (final key in const ['bold', 'h1', 'h2', 'checklist']) {
      await tester.scrollUntilVisible(
        find.byKey(Key('editor-format-$key'), skipOffstage: false),
        120,
        scrollable: scrollable,
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('3x heading controls use labeled icons inside 48dp targets', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pumpBar(
      tester,
      controller,
      width: 320,
      textScaler: const TextScaler.linear(3),
    );

    final scrollable = find.descendant(
      of: find.byKey(const Key('editor-formatting-scroll')),
      matching: find.byType(Scrollable),
    );
    for (final heading in const [
      (key: 'h1', label: 'Heading 1', icon: Icons.looks_one_rounded),
      (key: 'h2', label: 'Heading 2', icon: Icons.looks_two_rounded),
    ]) {
      final control = find.byKey(
        Key('editor-format-${heading.key}'),
        skipOffstage: false,
      );
      await tester.scrollUntilVisible(control, 120, scrollable: scrollable);
      expect(tester.getSize(control), const Size.square(48));
      expect(
        find.descendant(of: control, matching: find.byIcon(heading.icon)),
        findsOneWidget,
      );
      final semanticControl = find.bySemanticsLabel(heading.label);
      expect(semanticControl, findsOneWidget);
      final controlSemantics = tester.getSemantics(semanticControl);
      expect(controlSemantics.label, heading.label);
      expect(controlSemantics.flagsCollection.isButton, isTrue);
    }
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('renders a dictation mic control alongside formatting controls', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pumpBar(tester, controller);

    expect(find.byIcon(Icons.mic_none_rounded), findsOneWidget);
  });

  testWidgets('dictation mic control is disabled when the bar is disabled', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await _pumpBar(tester, controller, enabled: false);

    final micButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.mic_none_rounded),
        matching: find.byType(IconButton),
      ),
    );
    expect(micButton.onPressed, isNull);
  });
}

Future<void> _pumpBar(
  WidgetTester tester,
  TextEditingController controller, {
  bool enabled = true,
  double width = 375,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dictationServiceProvider.overrideWith(
          (ref) => DictationService(
            recognizer: FakeSpeechRecognizer(),
            permissions: FakePermissionRequester(),
          ),
        ),
      ],
      child: wrapWithTestLocalization(
        Builder(
          builder: (localizationContext) => MaterialApp(
            localizationsDelegates: localizationContext.localizationDelegates,
            supportedLocales: localizationContext.supportedLocales,
            locale: localizationContext.locale,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: textScaler),
              child: child!,
            ),
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: EditorFormattingBar(
                    controller: controller,
                    enabled: enabled,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
