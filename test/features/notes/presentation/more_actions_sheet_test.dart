import 'dart:async';
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
    expect(find.byType(GlassSurface), findsOneWidget);
    expect(find.byType(SafeArea), findsWidgets);
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
    expect(tester.getSize(exportRow), sizeBefore);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(MoreActionsSheet), findsOneWidget);

    await tester.tap(find.byKey(const Key('more-row-backup-json')));
    await tester.pump();
    expect(gateway.shareFileCalls, 0);

    gateway.shareGate!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(MoreActionsSheet), findsOneWidget);

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

  testWidgets('tag removal confirms exact global count and blocks busy back', (
    tester,
  ) async {
    final repository = _ControlledRepository.seeded(_tagNotes)
      ..updateGate = Completer<void>();
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

    expect(repository.updateCalls, 1);
    expect(find.text('Removing…'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(repository.updateCalls, 1);

    repository.updateGate!.complete();
    await tester.pumpAndSettle();

    expect(repository.updateCalls, 3);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('shared'), findsNothing);
    expect(harness.container.read(selectedTagProvider), isNull);
    expect(
      repository.notes.expand((note) => note.tags),
      isNot(contains('shared')),
    );
  });

  testWidgets('failed tag removal stays inline and can retry', (tester) async {
    final repository = _ControlledRepository.seeded(_tagNotes)
      ..updateError = StateError('write failed');
    await _pumpMore(tester, repository: repository);
    await _openTags(tester);
    await tester.tap(find.byTooltip('Remove shared tag'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Could not remove “shared”. Try again.'), findsOneWidget);
    expect(find.byType(TagManagerSheet), findsOneWidget);

    repository.updateError = null;
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
  await container.read(notesProvider.future);
  await tester.pumpAndSettle();
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
  int writeCalls = 0;

  @override
  Future<ThemeMode> readMode() async => mode;

  @override
  Future<void> writeMode(ThemeMode mode) async {
    writeCalls += 1;
    if (writeError case final error?) throw error;
    this.mode = mode;
  }
}

class _FakeNotesTransferGateway extends NotesTransferGateway {
  String? pickedJson;
  Object? pickError;
  Object? shareError;
  Completer<void>? shareGate;

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
  Future<void> shareText({
    required String text,
    required String subject,
    Rect? sharePositionOrigin,
  }) async {
    shareTextCalls += 1;
    if (shareError case final error?) throw error;
    await shareGate?.future;
  }

  @override
  Future<void> shareFile({
    required String text,
    required String fileName,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    shareFileCalls += 1;
    if (shareError case final error?) throw error;
    await shareGate?.future;
  }
}

class _ControlledRepository extends InMemoryNoteRepository {
  _ControlledRepository.seeded(super.notes) : super.seeded();

  Completer<void>? updateGate;
  int updateCalls = 0;

  @override
  Future<int> updateNote(Note note) async {
    updateCalls += 1;
    await updateGate?.future;
    return super.updateNote(note);
  }
}
