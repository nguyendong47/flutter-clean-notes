import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:flutter_clean_notes/main.dart' as app;

const _pollInterval = Duration(milliseconds: 100);
const _defaultTimeout = Duration(seconds: 15);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('creates, finds, browses, and restores an Aurora note', (
    tester,
  ) async {
    final uniqueSuffix = DateTime.now().microsecondsSinceEpoch;
    final title = 'Aurora Android smoke $uniqueSuffix';
    final content = 'Integration smoke content $uniqueSuffix';

    app.main();

    await _waitFor(
      tester,
      find.byKey(const Key('notes-home-header')),
      description: 'the Home screen to finish booting',
      timeout: const Duration(seconds: 30),
    );
    expect(
      find.byKey(const Key('notes-bottom-bar-create-control')),
      findsOneWidget,
      reason: 'Home must expose the public create-note control.',
    );

    await _tapAndWaitFor(
      tester,
      find.byKey(const Key('notes-bottom-bar-create-control')),
      find.byKey(const Key('note-editor-page')),
      action: 'open the note editor',
    );
    await tester.enterText(find.byKey(const Key('editor-title-field')), title);
    await tester.enterText(find.byKey(const Key('editor-body-field')), content);
    await _tapAndWaitFor(
      tester,
      find.byKey(const Key('editor-done-button')),
      find.text(title),
      action: 'save the new note and return Home',
      timeout: const Duration(seconds: 20),
    );
    await _waitUntilAbsent(
      tester,
      find.byKey(const Key('note-editor-page')),
      description: 'the editor to close after saving',
    );
    expect(
      find.text(content),
      findsOneWidget,
      reason: 'Home must render the saved note content.',
    );

    await _tapAndWaitFor(
      tester,
      find.byKey(const Key('notes-bottom-bar-search-control')),
      find.byKey(const Key('notes-search-field')),
      action: 'open Search',
    );
    await tester.enterText(find.byKey(const Key('notes-search-field')), title);
    await _waitFor(
      tester,
      find.text('1 result'),
      description: 'Search to return the uniquely titled note',
    );
    expect(
      find.bySemanticsLabel('Open note $title'),
      findsOneWidget,
      reason: 'Search must expose the matching result as an openable note.',
    );

    await _tapAndWaitFor(
      tester,
      find.bySemanticsLabel('Open note $title'),
      find.byKey(const Key('note-editor-page')),
      action: 'open the search result',
    );
    expect(
      _textInField(tester, const Key('editor-title-field')),
      title,
      reason: 'Opening the search result must load its title.',
    );
    expect(
      _textInField(tester, const Key('editor-body-field')),
      content,
      reason: 'Opening the search result must load its content.',
    );

    await _tapAndWaitFor(
      tester,
      find.byKey(const Key('editor-back-button')),
      find.byKey(const Key('notes-search-field')),
      action: 'return from the note editor to Search',
    );
    expect(
      _searchQuery(tester),
      title,
      reason: 'Back navigation must preserve the Search query.',
    );
    expect(
      find.text('1 result'),
      findsOneWidget,
      reason: 'Back navigation must preserve the Search result state.',
    );
    expect(
      find.bySemanticsLabel('Open note $title'),
      findsOneWidget,
      reason: 'The matching note must remain openable after Back.',
    );

    await _tapAndWaitFor(
      tester,
      find.byKey(const Key('notes-bottom-bar-library-control')),
      find.byKey(const Key('notes-library-heading')),
      action: 'open Library',
    );
    await _waitFor(
      tester,
      find.text('No archived notes'),
      description: 'the default Archived library section',
    );
    await _tapAndWaitFor(
      tester,
      find.text('Trash'),
      find.text('Trash is empty'),
      action: 'switch Library to Trash',
    );
    await _tapAndWaitFor(
      tester,
      find.text('Archived'),
      find.text('No archived notes'),
      action: 'switch Library back to Archived',
    );

    await _tapAndWaitFor(
      tester,
      find.byKey(const Key('notes-bottom-bar-more-control')),
      find.byKey(const Key('more-actions-sheet')),
      action: 'open More',
    );
    for (final key in <Key>[
      const Key('more-row-theme'),
      const Key('more-row-manage-tags'),
      const Key('more-row-export-text'),
      const Key('more-row-backup-json'),
      const Key('more-row-export-markdown'),
      const Key('more-row-import-backup'),
    ]) {
      expect(
        find.byKey(key),
        findsOneWidget,
        reason: 'More must expose its core row keyed ${key.toString()}.',
      );
    }
    await _tapAndWaitFor(
      tester,
      find.byTooltip('Close More'),
      find.byKey(const Key('notes-library-heading')),
      action: 'close More back to Library',
    );
    await _waitUntilAbsent(
      tester,
      find.byKey(const Key('more-actions-sheet')),
      description: 'the More sheet to close',
    );

    await _tapAndWaitFor(
      tester,
      find.byKey(const Key('notes-bottom-bar-notes-control')),
      find.text(title),
      action: 'return Home',
    );

    await _tapAndWaitFor(
      tester,
      find.byTooltip('More actions for $title'),
      find.text('Archive'),
      action: 'open the saved note menu',
    );
    await _tapAndWaitFor(
      tester,
      find.text('Archive'),
      find.text('$title archived'),
      action: 'archive the saved note',
    );
    expect(
      find.text(title),
      findsNothing,
      reason: 'Archived notes must leave the active Home collection.',
    );
    await _tapAndWaitFor(
      tester,
      find.text('Undo'),
      find.text(title),
      action: 'undo the archive operation',
    );
    expect(
      find.byKey(const Key('notes-home-header')),
      findsOneWidget,
      reason: 'The smoke flow must finish on Home.',
    );
  });
}

String _textInField(WidgetTester tester, Key key) {
  return tester.widget<TextField>(find.byKey(key)).controller!.text;
}

String _searchQuery(WidgetTester tester) {
  return tester
      .widget<SearchBar>(find.byKey(const Key('notes-search-field')))
      .controller!
      .text;
}

Future<void> _tapAndWaitFor(
  WidgetTester tester,
  Finder control,
  Finder destination, {
  required String action,
  Duration timeout = _defaultTimeout,
}) async {
  await _waitFor(
    tester,
    control,
    description: 'the control needed to $action',
    timeout: timeout,
  );
  await tester.ensureVisible(control.first);
  await tester.pump();
  final hittableControl = control.hitTestable();
  expect(
    hittableControl,
    findsOneWidget,
    reason: 'The control to $action exists but is not hittable.',
  );
  await tester.tap(hittableControl);
  await tester.pump();
  await _waitFor(
    tester,
    destination,
    description: 'the UI expected after attempting to $action',
    timeout: timeout,
  );
}

Future<void> _waitFor(
  WidgetTester tester,
  Finder finder, {
  required String description,
  Duration timeout = _defaultTimeout,
}) async {
  final deadline = tester.binding.clock.now().add(timeout);
  while (finder.evaluate().isEmpty &&
      tester.binding.clock.now().isBefore(deadline)) {
    await tester.pump(_pollInterval);
  }
  expect(
    finder,
    findsOneWidget,
    reason: 'Timed out after ${timeout.inSeconds}s waiting for $description.',
  );
}

Future<void> _waitUntilAbsent(
  WidgetTester tester,
  Finder finder, {
  required String description,
  Duration timeout = _defaultTimeout,
}) async {
  final deadline = tester.binding.clock.now().add(timeout);
  while (finder.evaluate().isNotEmpty &&
      tester.binding.clock.now().isBefore(deadline)) {
    await tester.pump(_pollInterval);
  }
  expect(
    finder,
    findsNothing,
    reason: 'Timed out after ${timeout.inSeconds}s waiting for $description.',
  );
}
