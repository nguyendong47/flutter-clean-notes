import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/privacy_page.dart';

void main() {
  testWidgets('explains storage reminders transfers and network behavior', (
    tester,
  ) async {
    // Mutation caught: removing a storage boundary, reminder disclosure, or
    // user-control statement makes the offline notice incomplete.
    await _pumpPrivacyPage(tester, size: const Size(375, 812));

    expect(find.byKey(const Key('privacy-page')), findsOneWidget);
    expect(find.text('Your notes stay under your control'), findsOneWidget);
    expect(find.text('Where your notes live'), findsOneWidget);
    expect(find.text('Reminders use platform services'), findsOneWidget);
    expect(find.text('Import, export, and backup'), findsOneWidget);
    expect(find.text('You control app-initiated transfers'), findsOneWidget);
    expect(find.text('Network behavior'), findsOneWidget);
    expect(find.text('Retention and deletion'), findsOneWidget);
    expect(find.textContaining('IndexedDB'), findsOneWidget);
    expect(
      find.textContaining(
        'Scheduling is unavailable on Web, Windows, and Linux',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Clean Notes starts an export only when you choose Export or Backup',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('destination you choose controls later storage'),
      findsOneWidget,
    );
    expect(find.textContaining('temporary or cache copies'), findsOneWidget);
    expect(find.textContaining('no app-owned remote API'), findsOneWidget);
    expect(find.textContaining('deployment origin'), findsOneWidget);
    expect(find.textContaining('third-party font CDN'), findsOneWidget);
    expect(find.textContaining('title, content, and tags'), findsOneWidget);
    expect(
      find.textContaining(
        'IDs, color, creation time, pin state, status, and reminder times',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'operating-system backup or device transfer may copy app data',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('available offline'), findsOneWidget);

    final heading = tester.getSemantics(
      find.byKey(const Key('privacy-primary-heading')),
    );
    expect(heading.flagsCollection.isHeader, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('remains scrollable without overflow on compact enlarged text', (
    tester,
  ) async {
    // Mutation caught: replacing the scrollable constrained layout with a
    // fixed-height column overflows on a small landscape window.
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = errors.add;
    addTearDown(() => FlutterError.onError = previous);

    await _pumpPrivacyPage(
      tester,
      size: const Size(568, 320),
      textScaler: const TextScaler.linear(2),
      theme: AuroraTheme.dark(),
    );

    final scrollable = tester.state<ScrollableState>(
      find.descendant(
        of: find.byKey(const Key('privacy-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    expect(
      find.byKey(const Key('privacy-back-button')).hitTestable(),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const Key('privacy-back-button'))).height,
      greaterThanOrEqualTo(48),
    );
    expect(errors, isEmpty);
  });

  testWidgets('centers a readable content measure on wide windows', (
    tester,
  ) async {
    // Mutation caught: dropping the max-width constraint stretches long-form
    // privacy copy across the full desktop viewport.
    await _pumpPrivacyPage(tester, size: const Size(1024, 768));

    final content = find.byKey(const Key('privacy-content'));
    final rect = tester.getRect(content);
    expect(rect.width, lessThanOrEqualTo(760));
    expect(rect.center.dx, closeTo(512, 0.5));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpPrivacyPage(
  WidgetTester tester, {
  required Size size,
  TextScaler textScaler = TextScaler.noScaling,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AuroraTheme.light(),
      home: MediaQuery(
        data: MediaQueryData(size: size, textScaler: textScaler),
        child: PrivacyPage(onClose: () {}),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
