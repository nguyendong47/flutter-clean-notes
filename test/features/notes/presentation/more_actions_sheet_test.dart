import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_clean_notes/app/app_providers.dart';
import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/notes_transfer_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/notes_transfer_gateway.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/more_actions_sheet.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/tag_manager_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/in_memory_note_repository.dart';

void main() {
  testWidgets('shows grouped labeled actions with semantic 56 pixel rows', (
    tester,
  ) async {
    await _pumpMore(tester);

    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Organization'), findsOneWidget);
    expect(find.text('Transfer'), findsOneWidget);
    for (final label in [
      'Theme',
      'Manage tags',
      'Export text',
      'Backup JSON',
      'Export Markdown',
      'Import backup',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    for (final mode in ['System', 'Light', 'Dark']) {
      expect(find.text(mode), findsOneWidget);
    }

    for (final key in _moreRowKeys) {
      final row = find.byKey(Key(key));
      expect(row, findsOneWidget, reason: key);
      expect(tester.getSize(row).height, greaterThanOrEqualTo(56), reason: key);
      expect(
        tester.getSemantics(row).flagsCollection.isButton,
        isTrue,
        reason: key,
      );
    }
    expect(
      tester
          .getSemantics(find.byKey(const Key('theme-mode-system')))
          .flagsCollection
          .isSelected,
      Tristate.isTrue,
    );
    for (final key in [
      'more-row-theme',
      'more-row-manage-tags',
      'more-row-export-text',
      'more-row-backup-json',
      'more-row-export-markdown',
      'more-row-import-backup',
    ]) {
      expect(
        tester.getSemantics(find.byKey(Key(key))).flagsCollection.isSelected,
        Tristate.none,
        reason: key,
      );
    }
    for (final key in ['theme-mode-light', 'theme-mode-dark']) {
      expect(
        tester.getSemantics(find.byKey(Key(key))).flagsCollection.isSelected,
        Tristate.isFalse,
        reason: key,
      );
    }
    for (final entry in _moreRowSemantics.entries) {
      final row = find.byKey(Key(entry.key));
      final data = tester.getSemantics(row).getSemanticsData();
      expect(data.label, entry.value.label, reason: entry.key);
      expect(data.value, entry.value.value, reason: entry.key);
      expect(data.hasAction(SemanticsAction.tap), isTrue, reason: entry.key);
      expect(
        find.bySemanticsLabel(RegExp('^${RegExp.escape(entry.value.label)}\$')),
        findsOneWidget,
        reason: '${entry.key} must have one spoken label',
      );
    }
    expect(
      tester
          .getSemantics(find.byKey(const Key('more-row-theme')))
          .flagsCollection
          .isExpanded,
      Tristate.isTrue,
    );
    await tester.tap(find.byKey(const Key('more-row-theme')));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSemantics(find.byKey(const Key('more-row-theme')))
          .flagsCollection
          .isExpanded,
      Tristate.isFalse,
    );
    expect(find.byKey(const Key('theme-mode-system')), findsNothing);
    expect(find.byType(GlassSurface), findsOneWidget);
    expect(find.byType(SafeArea), findsWidgets);
  });

  testWidgets('idle More and Tag routes dismiss from the scrim in order', (
    tester,
  ) async {
    await _pumpMore(tester, notes: _tagNotes);
    final dismissBarrier = find.bySemanticsLabel('Scrim');
    expect(dismissBarrier, findsOneWidget);
    expect(
      tester
          .getSemantics(dismissBarrier)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await _openTags(tester);

    expect(dismissBarrier, findsOneWidget);
    expect(
      tester
          .getSemantics(dismissBarrier)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();

    expect(find.byType(TagManagerSheet), findsNothing);
    expect(find.byType(MoreActionsSheet), findsOneWidget);

    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(find.byType(MoreActionsSheet), findsNothing);

    await tester.tap(find.text('Open more'));
    await tester.pumpAndSettle();
    tester.semantics.dismiss(find.semantics.byLabel('Scrim'));
    await tester.pumpAndSettle();
    expect(find.byType(MoreActionsSheet), findsNothing);
  });

  testWidgets('awaits theme persistence and reports rollback inline', (
    tester,
  ) async {
    final store = _FakeThemeModeStore()..writeError = StateError('disk full');
    final harness = await _pumpMore(tester, themeStore: store);

    await tester.tap(find.byKey(const Key('theme-mode-dark')));
    await tester.pumpAndSettle();

    expect(store.writeCalls, 1);
    expect(store.mode, ThemeMode.system);
    expect(harness.container.read(appThemeProvider).value, ThemeMode.system);
    expect(find.byType(MoreActionsSheet), findsOneWidget);
    expect(
      find.text('Could not save theme preference. Try again.'),
      findsOneWidget,
    );
    expect(
      tester
          .getSemantics(
            find.text('Could not save theme preference. Try again.'),
          )
          .flagsCollection
          .isLiveRegion,
      isTrue,
    );

    store.writeError = null;
    await tester.tap(find.byKey(const Key('theme-mode-dark')));
    await tester.pumpAndSettle();

    expect(store.mode, ThemeMode.dark);
    expect(harness.container.read(appThemeProvider).value, ThemeMode.dark);
    expect(
      find.text('Could not save theme preference. Try again.'),
      findsNothing,
    );
  });

  testWidgets(
    'theme persistence stays emphasized, announced, and route-guarded',
    (tester) async {
      final gate = Completer<void>();
      final store = _FakeThemeModeStore()..writeGate = gate;
      await _pumpMore(tester, themeStore: store);
      final darkRow = find.byKey(const Key('theme-mode-dark'));

      await tester.tap(darkRow);
      await tester.pump();

      expect(store.writeCalls, 1);
      expect(
        find.descendant(
          of: darkRow,
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );
      final loadingSemantics = tester.getSemantics(darkRow).getSemanticsData();
      expect(loadingSemantics.value, 'Saving theme preference…');
      expect(loadingSemantics.flagsCollection.isLiveRegion, isTrue);
      expect(loadingSemantics.hasAction(SemanticsAction.tap), isFalse);
      expect(
        find.descendant(
          of: darkRow,
          matching: find.byWidgetPredicate(
            (widget) => widget is Opacity && widget.opacity == 1,
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('more-row-manage-tags')),
          matching: find.byWidgetPredicate(
            (widget) => widget is Opacity && widget.opacity < 0.6,
          ),
        ),
        findsOneWidget,
      );

      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      expect(find.byType(MoreActionsSheet), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(MoreActionsSheet), findsOneWidget);

      await tester.tap(darkRow, warnIfMissed: false);
      await tester.pump();
      expect(store.writeCalls, 1);
      expect(find.bySemanticsLabel('Scrim'), findsNothing);

      gate.complete();
      await tester.pumpAndSettle();
      expect(store.mode, ThemeMode.dark);
      expect(find.byType(MoreActionsSheet), findsOneWidget);
      expect(find.bySemanticsLabel('Scrim'), findsOneWidget);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.byType(MoreActionsSheet), findsNothing);
    },
  );

  testWidgets('keeps transfer row stable, blocks overlap and survives errors', (
    tester,
  ) async {
    final gateway = _FakeNotesTransferGateway()..shareGate = Completer<void>();
    await _pumpMore(tester, gateway: gateway);
    final exportRow = find.byKey(const Key('more-row-export-text'));
    final sizeBefore = tester.getSize(exportRow);

    await tester.tap(exportRow);
    await tester.pump();

    expect(find.byType(MoreActionsSheet), findsOneWidget);
    expect(gateway.shareTextCalls, 1);
    expect(
      find.descendant(
        of: exportRow,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsOneWidget,
    );
    expect(find.text('Exporting text…'), findsOneWidget);
    final loadingSemantics = tester
        .getSemantics(find.byKey(const Key('more-transfer-status-exportText')))
        .getSemanticsData();
    expect(loadingSemantics.label, 'Export text');
    expect(loadingSemantics.value, 'Exporting text…');
    expect(loadingSemantics.flagsCollection.isLiveRegion, isTrue);
    expect(loadingSemantics.hasAction(SemanticsAction.tap), isFalse);
    expect(find.bySemanticsLabel(RegExp(r'^Export text$')), findsOneWidget);
    expect(tester.getSize(exportRow), sizeBefore);

    final inactiveRow = find.byKey(const Key('more-row-backup-json'));
    final activeOpacity = find.descendant(
      of: exportRow,
      matching: find.byWidgetPredicate(
        (widget) => widget is Opacity && widget.opacity == 1,
      ),
    );
    final inactiveOpacity = find.descendant(
      of: inactiveRow,
      matching: find.byWidgetPredicate(
        (widget) => widget is Opacity && widget.opacity < 0.6,
      ),
    );
    expect(activeOpacity, findsOneWidget);
    expect(inactiveOpacity, findsOneWidget);
    expect(tester.widget<Opacity>(activeOpacity).opacity, 1);
    expect(tester.widget<Opacity>(inactiveOpacity).opacity, lessThan(0.6));
    final activeSurface = tester.widget<Material>(
      find.descendant(of: exportRow, matching: find.byType(Material)).first,
    );
    final inactiveSurface = tester.widget<Material>(
      find.descendant(of: inactiveRow, matching: find.byType(Material)).first,
    );
    expect(inactiveSurface.color!.a, lessThan(activeSurface.color!.a));

    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(find.byType(MoreActionsSheet), findsOneWidget);
    expect(find.bySemanticsLabel('Scrim'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(MoreActionsSheet), findsOneWidget);

    await tester.tap(find.byKey(const Key('more-row-backup-json')));
    await tester.pump();
    expect(gateway.shareFileCalls, 0);

    gateway.shareGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(MoreActionsSheet), findsOneWidget);
    expect(find.bySemanticsLabel('Scrim'), findsOneWidget);
    expect(find.text('Text export complete.'), findsOneWidget);
    final successSemantics = tester
        .getSemantics(find.byKey(const Key('more-transfer-status-exportText')))
        .getSemanticsData();
    expect(successSemantics.label, 'Export text');
    expect(successSemantics.value, 'Text export complete.');
    expect(successSemantics.flagsCollection.isLiveRegion, isTrue);
    expect(successSemantics.hasAction(SemanticsAction.tap), isTrue);

    gateway
      ..shareGate = null
      ..shareError = StateError('share unavailable');
    await tester.tap(find.byKey(const Key('more-row-backup-json')));
    await tester.pumpAndSettle();

    expect(find.byType(MoreActionsSheet), findsOneWidget);
    expect(find.text('Could not share backup. Try again.'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('more-row-backup-json')),
        matching: find.text('Could not share backup. Try again.'),
      ),
      findsOneWidget,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open more'));
    await tester.pump();

    expect(find.text('Could not share backup. Try again.'), findsNothing);
    expect(find.text('Text export complete.'), findsNothing);

    await tester.pumpAndSettle();

    expect(find.text('Could not share backup. Try again.'), findsNothing);
    expect(find.text('Text export complete.'), findsNothing);
  });

  testWidgets('announces row-local import success with imported count', (
    tester,
  ) async {
    final gateway = _FakeNotesTransferGateway()
      ..pickedJson = jsonEncode([
        {
          'title': 'First import',
          'content': 'First body',
          'color': 1,
          'createdAt': '2026-08-23T00:00:00.000Z',
          'isPinned': 0,
          'tags': '',
          'status': 0,
          'reminder': null,
        },
        {
          'title': 'Second import',
          'content': 'Second body',
          'color': 2,
          'createdAt': '2026-08-23T00:01:00.000Z',
          'isPinned': 0,
          'tags': '',
          'status': 0,
          'reminder': null,
        },
      ]);
    await _pumpMore(tester, gateway: gateway);
    final importRow = find.byKey(const Key('more-row-import-backup'));
    await tester.ensureVisible(importRow);

    await tester.tap(importRow);
    await tester.pumpAndSettle();

    final status = find.byKey(const Key('more-transfer-status-importBackup'));
    expect(find.descendant(of: importRow, matching: status), findsOneWidget);
    expect(find.text('Imported 2 notes.'), findsOneWidget);
    expect(tester.getSemantics(status).flagsCollection.isLiveRegion, isTrue);
  });

  testWidgets('share outcomes stay truthful and clear across sessions', (
    tester,
  ) async {
    final gateway = _FakeNotesTransferGateway()
      ..shareResult = NotesShareResult.unavailable;
    final harness = await _pumpMore(tester, gateway: gateway);
    final backupRow = find.byKey(const Key('more-row-backup-json'));
    await tester.ensureVisible(backupRow);

    await tester.tap(backupRow);
    await tester.pumpAndSettle();

    expect(find.text('Share sheet opened.'), findsOneWidget);
    expect(find.text('Backup sharing complete.'), findsNothing);
    expect(
      harness.container.read(notesTransferProvider).requireValue?.status,
      NotesTransferOutcomeStatus.shareSheetOpened,
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open more'));
    await tester.pump();

    expect(find.text('Share sheet opened.'), findsNothing);
    expect(find.text('Backup sharing complete.'), findsNothing);
    await tester.pumpAndSettle();

    gateway.shareResult = NotesShareResult.dismissed;
    final exportRow = find.byKey(const Key('more-row-export-text'));
    await tester.ensureVisible(exportRow);
    await tester.pumpAndSettle();
    await tester.tap(exportRow);
    await tester.pumpAndSettle();

    expect(find.text('Text export complete.'), findsNothing);
    expect(find.text('Share sheet opened.'), findsNothing);
    expect(harness.container.read(notesTransferProvider).requireValue, isNull);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open more'));
    await tester.pump();

    expect(find.text('Text export complete.'), findsNothing);
    expect(find.text('Share sheet opened.'), findsNothing);
  });

  testWidgets('silent import cancellation restores import focus', (
    tester,
  ) async {
    final gateway = _FakeNotesTransferGateway()..pickedJson = null;
    await _pumpMore(tester, gateway: gateway);
    final importRow = find.byKey(const Key('more-row-import-backup'));
    final origin = await _focus(tester, importRow);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(gateway.pickCalls, 1);
    expect(find.byType(MoreActionsSheet), findsOneWidget);
    expect(
      find.byKey(const Key('more-transfer-error-importBackup')),
      findsNothing,
    );
    expect(FocusManager.instance.primaryFocus, same(origin));
  });

  testWidgets('nested tag sheet obeys back order and restores Manage focus', (
    tester,
  ) async {
    await _pumpMore(tester, notes: _tagNotes);
    final manageRow = find.byKey(const Key('more-row-manage-tags'));
    final origin = await _focus(tester, manageRow);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byType(TagManagerSheet), findsOneWidget);
    expect(find.byType(MoreActionsSheet), findsOneWidget);
    expect(find.text('shared'), findsOneWidget);
    expect(find.text('3 notes'), findsOneWidget);
    expect(find.byType(GlassSurface), findsNWidgets(2));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byType(TagManagerSheet), findsNothing);
    expect(find.byType(MoreActionsSheet), findsOneWidget);
    expect(FocusManager.instance.primaryFocus, same(origin));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(MoreActionsSheet), findsNothing);
  });

  testWidgets('tag row exposes one label plus a separate delete action', (
    tester,
  ) async {
    await _pumpMore(tester, notes: _tagNotes);
    await _openTags(tester);

    final row = find.byKey(const Key('tag-row-shared'));
    final tagSemantics = find.bySemanticsLabel(RegExp(r'^shared$'));
    expect(tagSemantics, findsOneWidget);
    final rowData = tester.getSemantics(row).getSemanticsData();
    expect(rowData.label, 'shared');
    expect(rowData.value, '3 notes');
    expect(rowData.hasAction(SemanticsAction.tap), isFalse);

    final delete = find.bySemanticsLabel(RegExp(r'^Remove shared tag$'));
    expect(delete, findsOneWidget);
    final deleteData = tester.getSemantics(delete).getSemanticsData();
    expect(deleteData.label, 'Remove shared tag');
    expect(deleteData.flagsCollection.isButton, isTrue);
    expect(deleteData.hasAction(SemanticsAction.tap), isTrue);
  });

  testWidgets('tag manager distinguishes loading from a true empty state', (
    tester,
  ) async {
    final repository = _ControlledRepository.seeded(_tagNotes)
      ..readGate = Completer<void>();
    await _pumpMore(tester, repository: repository, awaitNotes: false);
    final manageTags = find.byKey(const Key('more-row-manage-tags'));
    await tester.ensureVisible(manageTags);

    await tester.tap(manageTags);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(TagManagerSheet), findsOneWidget);
    expect(find.text('Loading tags…'), findsOneWidget);
    expect(find.text('No tags yet'), findsNothing);

    repository.readGate!.complete();
    await tester.pumpAndSettle();

    expect(find.text('Loading tags…'), findsNothing);
    expect(find.text('shared'), findsOneWidget);
  });

  testWidgets('tag manager shows initial error and a 48 pixel retry', (
    tester,
  ) async {
    final repository = _ControlledRepository.seeded(_tagNotes)
      ..getError = StateError('database path leaked');
    await _pumpMore(tester, repository: repository, awaitNotes: false);
    await _openTags(tester);

    expect(find.text('Could not load tags. Try again.'), findsOneWidget);
    expect(find.text('No tags yet'), findsNothing);
    final retry = find.byKey(const Key('tag-retry'));
    expect(retry, findsOneWidget);
    expect(tester.getSize(retry).height, greaterThanOrEqualTo(48));

    repository.getError = null;
    await tester.tap(retry);
    await tester.pumpAndSettle();

    expect(find.text('Could not load tags. Try again.'), findsNothing);
    expect(find.text('shared'), findsOneWidget);
  });

  testWidgets('tag manager retains counts when a pin update fails', (
    tester,
  ) async {
    final repository = _ControlledRepository.seeded(_tagNotes);
    final harness = await _pumpMore(tester, repository: repository);
    await _openTags(tester);
    final before = harness.container.read(notesProvider).requireValue;
    repository.updateError = StateError('write failed');

    await expectLater(
      harness.container.read(notesProvider.notifier).togglePin(before.first),
      throwsStateError,
    );
    await tester.pump();

    final state = harness.container.read(notesProvider);
    expect(state, isA<AsyncData<List<Note>>>());
    expect(state.value, same(before));
    expect(state.hasError, isFalse);
    expect(
      find.text('Could not refresh tag counts. Showing saved counts.'),
      findsNothing,
    );
    expect(find.text('shared'), findsOneWidget);
    expect(find.text('3 notes'), findsOneWidget);
    expect(find.text('No tags yet'), findsNothing);
    expect(find.byKey(const Key('tag-retry')), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('tag manager shows empty only after an empty load completes', (
    tester,
  ) async {
    await _pumpMore(tester, notes: const []);
    await _openTags(tester);

    expect(find.text('No tags yet'), findsOneWidget);
    expect(find.text('Loading tags…'), findsNothing);
    expect(find.byKey(const Key('tag-retry')), findsNothing);
  });

  testWidgets(
    'tag refresh retry disables removal and every route dismissal until complete',
    (tester) async {
      final repository = _ControlledRepository.seeded(_tagNotes);
      final harness = await _pumpMore(tester, repository: repository);
      await _openTags(tester);

      repository.getError = StateError('refresh failed');
      harness.container.invalidate(notesProvider);
      await expectLater(
        harness.container.read(notesProvider.future),
        throwsStateError,
      );
      await tester.pump();
      expect(
        find.text('Could not refresh tag counts. Showing saved counts.'),
        findsOneWidget,
      );

      repository
        ..getError = null
        ..readGate = Completer<void>();
      await tester.tap(find.byKey(const Key('tag-retry')));
      await tester.pump();

      final remove = find.bySemanticsLabel('Remove shared tag');
      expect(remove, findsOneWidget);
      final removeSemantics = tester.getSemantics(remove).getSemanticsData();
      expect(removeSemantics.flagsCollection.isEnabled, Tristate.isFalse);
      expect(removeSemantics.hasAction(SemanticsAction.tap), isFalse);
      expect(find.bySemanticsLabel('Scrim'), findsNothing);

      await tester.tap(
        find.byTooltip('Remove shared tag'),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tapAt(const Offset(4, 4));
      await tester.pump();
      expect(find.byType(TagManagerSheet), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(TagManagerSheet), findsOneWidget);

      repository.readGate!.complete();
      await tester.pumpAndSettle();

      final enabledSemantics = tester.getSemantics(remove).getSemanticsData();
      expect(enabledSemantics.flagsCollection.isEnabled, Tristate.isTrue);
      expect(enabledSemantics.hasAction(SemanticsAction.tap), isTrue);
      expect(find.bySemanticsLabel('Scrim'), findsOneWidget);

      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    },
  );

  testWidgets('tag removal confirms exact global count and blocks busy back', (
    tester,
  ) async {
    final repository = _ControlledRepository.seeded(_tagNotes)
      ..removeTagGate = Completer<void>();
    final harness = await _pumpMore(tester, repository: repository);
    harness.container.read(selectedTagProvider.notifier).select('shared');
    await _openTags(tester);

    final remove = find.byTooltip('Remove shared tag');
    expect(tester.getSize(remove).height, greaterThanOrEqualTo(48));
    await tester.tap(remove);
    await tester.pumpAndSettle();

    expect(find.text('Remove “shared” from 3 notes?'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Remove'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pump();

    expect(repository.removeTagInvocations, 1);
    expect(find.text('Removing…'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.bySemanticsLabel('Scrim'), findsNothing);
    await tester.tapAt(const Offset(4, 4));
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repository.removeTagInvocations, 1);

    repository.removeTagGate!.complete();
    await tester.pumpAndSettle();

    expect(repository.removeTagInvocations, 1);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('shared'), findsNothing);
    expect(find.bySemanticsLabel('Scrim'), findsOneWidget);
    expect(harness.container.read(selectedTagProvider), isNull);
    expect(
      repository.notes.expand((note) => note.tags),
      isNot(contains('shared')),
    );
  });

  testWidgets('failed tag removal stays inline and can retry', (tester) async {
    final repository = _ControlledRepository.seeded(_tagNotes)
      ..removeTagError = StateError('write failed');
    await _pumpMore(tester, repository: repository);
    await _openTags(tester);
    await tester.tap(find.byTooltip('Remove shared tag'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Could not remove “shared”. Try again.'), findsOneWidget);
    expect(find.byType(TagManagerSheet), findsOneWidget);

    repository.removeTagError = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('shared'), findsNothing);
  });

  testWidgets('both sheets fit 320 pixels at 1.5 text scale in both themes', (
    tester,
  ) async {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      await _pumpMore(
        tester,
        notes: [
          _note(21, NoteStatus.active, const [
            'a very long global tag that must wrap without clipping',
          ]),
        ],
        size: const Size(320, 760),
        textScaler: const TextScaler.linear(1.5),
        themeMode: mode,
        viewInsetsBottom: 180,
      );

      expect(find.byType(SingleChildScrollView), findsOneWidget);
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Dark'), findsOneWidget);
      final moreInsets = tester.widget<Padding>(
        find.byKey(const Key('more-sheet-insets')),
      );
      expect(
        moreInsets.padding.resolve(TextDirection.ltr).bottom,
        greaterThanOrEqualTo(180),
      );
      expect(tester.takeException(), isNull, reason: '$mode more');

      await _openTags(tester);

      expect(find.byType(TagManagerSheet), findsOneWidget);
      expect(
        find.text('a very long global tag that must wrap without clipping'),
        findsOneWidget,
      );
      final tagInsets = tester.widget<Padding>(
        find.byKey(const Key('tag-sheet-insets')),
      );
      expect(
        tagInsets.padding.resolve(TextDirection.ltr).bottom,
        greaterThanOrEqualTo(180),
      );
      expect(
        tester.getSize(find.byType(TagManagerSheet)).width,
        lessThanOrEqualTo(320),
      );
      expect(tester.takeException(), isNull, reason: '$mode tags');

      final remove = find.byTooltip(
        'Remove a very long global tag that must wrap without clipping tag',
      );
      await tester.tap(remove);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '$mode dialog');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
  });
}

const _moreRowKeys = [
  'more-row-theme',
  'theme-mode-system',
  'theme-mode-light',
  'theme-mode-dark',
  'more-row-manage-tags',
  'more-row-export-text',
  'more-row-backup-json',
  'more-row-export-markdown',
  'more-row-import-backup',
];

const _moreRowSemantics = {
  'more-row-theme': (label: 'Theme', value: 'Follow device setting'),
  'theme-mode-system': (label: 'System', value: 'Match this device'),
  'theme-mode-light': (label: 'Light', value: 'Always use light appearance'),
  'theme-mode-dark': (label: 'Dark', value: 'Always use dark appearance'),
  'more-row-manage-tags': (
    label: 'Manage tags',
    value: 'Review usage and remove tags everywhere',
  ),
  'more-row-export-text': (
    label: 'Export text',
    value: 'Share a readable text copy',
  ),
  'more-row-backup-json': (
    label: 'Backup JSON',
    value: 'Share a restorable backup file',
  ),
  'more-row-export-markdown': (
    label: 'Export Markdown',
    value: 'Share notes with Markdown formatting',
  ),
  'more-row-import-backup': (
    label: 'Import backup',
    value: 'Append notes from a JSON backup',
  ),
};

final _tagNotes = [
  _note(1, NoteStatus.active, const ['shared', 'shared', 'active']),
  _note(2, NoteStatus.archived, const ['shared', 'archive']),
  _note(3, NoteStatus.trashed, const ['shared', 'trash']),
];

Future<({ProviderContainer container, _FakeNotesTransferGateway gateway})>
_pumpMore(
  WidgetTester tester, {
  _FakeNotesTransferGateway? gateway,
  _FakeThemeModeStore? themeStore,
  InMemoryNoteRepository? repository,
  List<Note>? notes,
  Size size = const Size(375, 900),
  TextScaler textScaler = TextScaler.noScaling,
  ThemeMode themeMode = ThemeMode.light,
  double viewInsetsBottom = 0,
  bool awaitNotes = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final resolvedGateway = gateway ?? _FakeNotesTransferGateway();
  final resolvedStore = themeStore ?? _FakeThemeModeStore();
  final resolvedRepository =
      repository ?? InMemoryNoteRepository.seeded(notes ?? _tagNotes);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        notesTransferGatewayProvider.overrideWithValue(resolvedGateway),
        themeModeStoreProvider.overrideWithValue(resolvedStore),
        noteRepositoryProvider.overrideWithValue(resolvedRepository),
      ],
      child: MaterialApp(
        theme: AuroraTheme.light(),
        darkTheme: AuroraTheme.dark(),
        themeMode: themeMode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: textScaler,
            viewInsets: EdgeInsets.only(bottom: viewInsetsBottom),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => unawaited(MoreActionsSheet.show(context)),
                child: const Text('Open more'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Open more'));
  await tester.pumpAndSettle();

  final container = ProviderScope.containerOf(
    tester.element(find.byType(MoreActionsSheet)),
  );
  if (awaitNotes) {
    await container.read(notesProvider.future);
    await tester.pumpAndSettle();
  }
  return (container: container, gateway: resolvedGateway);
}

Future<void> _openTags(WidgetTester tester) async {
  final manageTags = find.byKey(const Key('more-row-manage-tags'));
  await tester.ensureVisible(manageTags);
  await tester.tap(manageTags);
  await tester.pumpAndSettle();
  expect(find.byType(TagManagerSheet), findsOneWidget);
}

Future<FocusNode> _focus(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && _isDescendantOf(focus.context, target)) return focus;
  }
  throw TestFailure('Could not focus the requested widget');
}

bool _isDescendantOf(BuildContext? context, Finder ancestor) {
  if (context is! Element) return false;
  final target = ancestor.evaluate().single;
  Element? current = context;
  while (current != null) {
    if (identical(current, target)) return true;
    Element? parent;
    current.visitAncestorElements((element) {
      parent = element;
      return false;
    });
    current = parent;
  }
  return false;
}

Note _note(int id, NoteStatus status, List<String> tags) {
  return Note(
    id: id,
    title: 'Note $id',
    content: 'Content $id',
    color: id,
    createdAt: DateTime.utc(2026, 8, 23).add(Duration(minutes: id)),
    tags: tags,
    status: status,
  );
}

class _FakeThemeModeStore implements ThemeModeStore {
  ThemeMode mode = ThemeMode.system;
  Object? writeError;
  Completer<void>? writeGate;
  int writeCalls = 0;

  @override
  Future<ThemeMode> readMode() async => mode;

  @override
  Future<void> writeMode(ThemeMode mode) async {
    writeCalls += 1;
    await writeGate?.future;
    if (writeError case final error?) throw error;
    this.mode = mode;
  }
}

class _FakeNotesTransferGateway extends NotesTransferGateway {
  String? pickedJson;
  Object? pickError;
  Object? shareError;
  Completer<void>? shareGate;
  NotesShareResult shareResult = NotesShareResult.completed;

  int pickCalls = 0;
  int shareTextCalls = 0;
  int shareFileCalls = 0;

  @override
  Future<String?> pickJsonText() async {
    pickCalls += 1;
    if (pickError case final error?) throw error;
    return pickedJson;
  }

  @override
  Future<NotesShareResult> shareText({
    required String text,
    required String subject,
    Rect? sharePositionOrigin,
  }) async {
    shareTextCalls += 1;
    if (shareError case final error?) throw error;
    await shareGate?.future;
    return shareResult;
  }

  @override
  Future<NotesShareResult> shareFile({
    required String text,
    required String fileName,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    shareFileCalls += 1;
    if (shareError case final error?) throw error;
    await shareGate?.future;
    return shareResult;
  }
}

class _ControlledRepository extends InMemoryNoteRepository {
  _ControlledRepository.seeded(super.notes) : super.seeded();

  Completer<void>? removeTagGate;
  Completer<void>? readGate;
  int removeTagInvocations = 0;

  @override
  Future<int> removeTag(String tag) async {
    removeTagInvocations += 1;
    await removeTagGate?.future;
    return super.removeTag(tag);
  }

  @override
  Future<List<Note>> getNotesByStatus(NoteStatus status) async {
    await readGate?.future;
    return super.getNotesByStatus(status);
  }
}
