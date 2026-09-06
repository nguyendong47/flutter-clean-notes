import 'dart:async';

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/glass_note_card.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets('exposes exact open semantics and useful action tooltips', (
    tester,
  ) async {
    var opened = false;
    await _pumpCard(tester, note: _note(), onOpen: () => opened = true);

    expect(find.bySemanticsLabel('Open note Aurora design'), findsOneWidget);
    expect(find.byTooltip('Open note Aurora design'), findsOneWidget);
    final moreActions = find.byTooltip('More actions for Aurora design');
    expect(moreActions, findsOneWidget);
    final actionSize = tester.getSize(moreActions);
    expect(actionSize.width, greaterThanOrEqualTo(44));
    expect(actionSize.height, greaterThanOrEqualTo(44));

    await tester.tap(moreActions);
    await tester.pumpAndSettle();

    expect(opened, isFalse);
    expect(find.text('Pin note'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Move to trash'), findsOneWidget);
  });

  testWidgets('uses an untitled fallback for content-only notes', (
    tester,
  ) async {
    await _pumpCard(tester, note: _note(title: '   '));

    expect(find.text('Untitled note'), findsOneWidget);
    expect(find.bySemanticsLabel('Open note Untitled note'), findsOneWidget);
    expect(find.byTooltip('Open note Untitled note'), findsOneWidget);
    expect(find.byTooltip('More actions for Untitled note'), findsOneWidget);
  });

  testWidgets('same-title cards expose ordered metadata in semantic values', (
    tester,
  ) async {
    final notes = [
      _note(
        title: 'Shared plan',
        content: 'First preview',
        tags: const ['work', 'design', 'hidden'],
        isPinned: true,
      ),
      Note(
        id: 43,
        title: 'Shared plan',
        content: 'Second preview',
        color: 0xFF2DB9A8,
        createdAt: DateTime.utc(2026, 8, 19, 11),
        tags: const ['personal'],
      ),
    ];
    await _pumpCards(tester, notes);

    final openCards = find.bySemanticsLabel('Open note Shared plan');
    expect(openCards, findsNWidgets(2));
    expect(
      tester.getSemantics(openCards.at(0)).value,
      'First preview. Tags work, design, 1 more. Pinned. '
      'Created Aug 17, 2026. Reminder Aug 18, 9:00 AM',
    );
    expect(
      tester.getSemantics(openCards.at(1)).value,
      'Second preview. Tags personal. Created Aug 19, 2026',
    );
    expect(find.byTooltip('More actions for Shared plan'), findsNWidgets(2));
  });

  testWidgets('preview truncation preserves an emoji ZWJ grapheme', (
    tester,
  ) async {
    final prefix = List.filled(178, 'a').join();
    const family = '👨‍👩‍👧‍👦';
    final expectedPreview = '$prefix$family…';
    await _pumpCard(tester, note: _note(content: '$prefix$family-continues'));

    expect(find.text(expectedPreview), findsOneWidget);
    expect(
      tester
          .getSemantics(find.bySemanticsLabel('Open note Aurora design'))
          .value,
      contains(expectedPreview),
    );
  });

  testWidgets('keeps card geometry stable while every mutation future runs', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final scenarios = <({String action, NoteStatus status, bool pinned})>[
      (action: 'Pin note', status: NoteStatus.active, pinned: false),
      (action: 'Archive', status: NoteStatus.active, pinned: false),
      (action: 'Move to trash', status: NoteStatus.active, pinned: false),
      (action: 'Restore', status: NoteStatus.archived, pinned: false),
      (action: 'Delete forever', status: NoteStatus.trashed, pinned: false),
    ];

    for (final scenario in scenarios) {
      final completer = Completer<void>();
      var started = false;
      var opened = false;
      Future<void> selectedMutation() {
        started = true;
        return completer.future;
      }

      final note = _note(status: scenario.status, isPinned: scenario.pinned);
      await _pumpCard(
        tester,
        note: note,
        onOpen: () => opened = true,
        onTogglePin: scenario.action == 'Pin note'
            ? selectedMutation
            : _complete,
        onArchive: scenario.action == 'Archive' ? selectedMutation : _complete,
        onTrash: scenario.action == 'Move to trash'
            ? selectedMutation
            : _complete,
        onRestore: scenario.action == 'Restore' ? selectedMutation : _complete,
        onDelete: scenario.action == 'Delete forever'
            ? selectedMutation
            : _complete,
      );
      final card = find.byKey(const Key('tested-glass-note-card'));
      final idleSize = tester.getSize(card);

      await tester.tap(find.byTooltip('More actions for Aurora design'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(scenario.action).last);
      await tester.pump();

      expect(started, isTrue, reason: scenario.action);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(tester.getSize(card), idleSize);
      final updating = find.bySemanticsLabel('Updating note Aurora design');
      expect(updating, findsOneWidget, reason: scenario.action);
      final updatingNode = tester.getSemantics(updating);
      expect(
        updatingNode.getSemanticsData().flagsCollection.isLiveRegion,
        isTrue,
        reason: scenario.action,
      );
      expect(
        updatingNode.childrenCountInTraversalOrder,
        0,
        reason: scenario.action,
      );

      await tester.tap(find.bySemanticsLabel('Open note Aurora design'));
      await tester.pump();
      expect(opened, isFalse, reason: scenario.action);

      completer.complete();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(tester.getSize(card), idleSize);

      await tester.tap(find.bySemanticsLabel('Open note Aurora design'));
      await tester.pump();
      expect(opened, isTrue, reason: scenario.action);
    }
    semantics.dispose();
  });

  testWidgets('limits informational tags and remains usable in dark mode', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      theme: AuroraTheme.dark(),
      textScaler: const TextScaler.linear(1.5),
      note: _note(
        tags: const [
          'a very long planning tag',
          'design system',
          'accessibility',
          'mobile',
        ],
        content:
            'A long note preview that should wrap naturally without turning '
            'the card into a fixed-height surface or overflowing at larger '
            'system text sizes.',
      ),
    );

    expect(find.text('a very long planning tag'), findsOneWidget);
    expect(find.text('design system'), findsOneWidget);
    expect(find.text('+2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required Note note,
  ThemeData? theme,
  TextScaler textScaler = TextScaler.noScaling,
  VoidCallback? onOpen,
  Future<void> Function()? onTogglePin,
  Future<void> Function()? onArchive,
  Future<void> Function()? onTrash,
  Future<void> Function()? onRestore,
  Future<void> Function()? onDelete,
  bool supportsReminderScheduling = true,
}) async {
  tester.view.physicalSize = const Size(360, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    wrapWithTestLocalization(
      Builder(
        builder: (localizationContext) => MaterialApp(
          theme: theme ?? AuroraTheme.light(),
          localizationsDelegates: localizationContext.localizationDelegates,
          supportedLocales: localizationContext.supportedLocales,
          locale: localizationContext.locale,
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 900),
              textScaler: textScaler,
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: GlassNoteCard(
                  key: const Key('tested-glass-note-card'),
                  note: note,
                  supportsReminderScheduling: supportsReminderScheduling,
                  onOpen: onOpen ?? () {},
                  onTogglePin: onTogglePin ?? _complete,
                  onArchive: onArchive ?? _complete,
                  onTrash: onTrash ?? _complete,
                  onRestore: onRestore ?? _complete,
                  onDelete: onDelete ?? _complete,
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

Future<void> _complete() async {}

Future<void> _pumpCards(WidgetTester tester, List<Note> notes) async {
  tester.view.physicalSize = const Size(360, 900);
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
          home: MediaQuery(
            data: const MediaQueryData(size: Size(360, 900)),
            child: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    for (final note in notes)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: GlassNoteCard(
                          key: ValueKey('semantic-note-${note.id}'),
                          note: note,
                          supportsReminderScheduling: true,
                          onOpen: () {},
                          onTogglePin: _complete,
                          onArchive: _complete,
                          onTrash: _complete,
                          onRestore: _complete,
                          onDelete: _complete,
                        ),
                      ),
                  ],
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

Note _note({
  String title = 'Aurora design',
  NoteStatus status = NoteStatus.active,
  bool isPinned = false,
  List<String> tags = const ['work', 'design'],
  String content = 'Plan the glass experience',
}) {
  return Note(
    id: 42,
    title: title,
    content: content,
    color: 0xFF6757D9,
    createdAt: DateTime.utc(2026, 8, 17, 10),
    isPinned: isPinned,
    tags: tags,
    status: status,
    reminder: DateTime.utc(2026, 8, 18, 9),
  );
}
