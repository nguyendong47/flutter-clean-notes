import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_clean_notes/app/app_providers.dart';
import 'package:flutter_clean_notes/app/notification_service.dart';
import 'package:flutter_clean_notes/app/router.dart';
import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_reminder_gateway_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import '../../../helpers/fake_note_reminder_gateway.dart';
import '../../../helpers/in_memory_note_repository.dart';
import '../../../helpers/note_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final viewport in const [
    Size(320, 640),
    Size(360, 640),
    Size(375, 812),
    Size(390, 844),
    Size(768, 1024),
  ]) {
    testWidgets('route controls are tappable and overflow-free at $viewport', (
      tester,
    ) async {
      // Mutation caught: a compact route target becoming untappable or a branch
      // overflowing only after navigation away from Home.
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);
      await _pumpShell(tester, size: viewport);

      for (final label in const [
        'Notes tab',
        'Search tab',
        'Create new note',
        'Library tab',
        'More actions',
      ]) {
        final finder = find.bySemanticsLabel(label).hitTestable();
        expect(finder, findsOneWidget);
        final rect = tester.getRect(finder);
        expect(rect.width, greaterThanOrEqualTo(48), reason: label);
        expect(rect.height, greaterThanOrEqualTo(48), reason: label);
      }
      expect(_isSelected(tester, 'Notes tab'), Tristate.isTrue);
      expect(_isSelected(tester, 'Search tab'), Tristate.isFalse);
      expect(find.bySemanticsLabel('Open note Aurora design'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Search tab').hitTestable());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('notes-search-field')).hitTestable(),
        findsOneWidget,
      );
      expect(_isSelected(tester, 'Search tab'), Tristate.isTrue);

      await tester.tap(find.bySemanticsLabel('Library tab').hitTestable());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('notes-library-heading')), findsOneWidget);
      expect(_isSelected(tester, 'Library tab'), Tristate.isTrue);

      await tester.tap(find.bySemanticsLabel('Notes tab').hitTestable());
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Open note Aurora design'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Create new note').hitTestable());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('note-editor-page')), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('editor-back-button')).hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Notes tab'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('More actions').hitTestable());
      await tester.pumpAndSettle();
      final moreSheet = find.byKey(const Key('more-actions-sheet'));
      expect(moreSheet, findsOneWidget);
      Navigator.of(tester.element(moreSheet)).pop();
      await tester.pumpAndSettle();

      expect(errors, isEmpty);
    });
  }

  testWidgets(
    '320x640 enlarged text navigates with composed reduced-motion high contrast',
    (tester) async {
      // Mutation caught: reduced motion bypassing the high-contrast opaque glass
      // fallback, or enlarged compact controls losing their interaction target.
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);
      await _pumpShell(
        tester,
        size: const Size(320, 640),
        textScaler: const TextScaler.linear(1.5),
        disableAnimations: true,
        highContrast: true,
        theme: AuroraTheme.dark(),
      );
      expect(find.byType(BackdropFilter), findsNothing);
      expect(_isSelected(tester, 'Notes tab'), Tristate.isTrue);

      await tester.tap(find.bySemanticsLabel('Search tab').hitTestable());
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Search notes and tags'), findsOneWidget);
      expect(
        find.byKey(const Key('notes-search-field')).hitTestable(),
        findsOneWidget,
      );
      expect(_isSelected(tester, 'Search tab'), Tristate.isTrue);
      expect(find.byType(BackdropFilter), findsNothing);

      await tester.tap(find.bySemanticsLabel('More actions').hitTestable());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('more-row-theme')), findsOneWidget);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(errors, isEmpty);
    },
  );

  testWidgets(
    'focused editor title and formatting controls clear the keyboard',
    (tester) async {
      // Mutation caught: focus reveal moving only the formatting bar while the
      // focused title remains obscured behind keyboard-adjacent chrome.
      await _pumpShell(
        tester,
        size: const Size(375, 812),
        viewInsets: const EdgeInsets.only(bottom: 300),
        initialLocation: '/note/1',
      );
      final title = find.byKey(const Key('editor-title-field'));
      await tester.tap(title);
      await tester.pump();
      await tester.pump();
      final formatting = tester.getRect(
        find.byKey(const Key('editor-formatting-bar')),
      );
      final titleRect = tester.getRect(title);
      expect(tester.widget<TextField>(title).focusNode?.hasFocus, isTrue);
      expect(titleRect.top, greaterThanOrEqualTo(0));
      expect(titleRect.bottom, lessThanOrEqualTo(formatting.top));
      expect(formatting.bottom, lessThanOrEqualTo(512.1));
      for (final key in const [
        Key('editor-back-button'),
        Key('editor-preview-toggle'),
        Key('editor-metadata-button'),
        Key('editor-done-button'),
      ]) {
        final size = tester.getSize(find.byKey(key));
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Search clear and filter controls expose size and selected state',
    (tester) async {
      // Mutation caught: icon-only Search controls losing names/hit area, or tag
      // selection becoming color-only.
      await _pumpShell(tester, size: const Size(390, 844));
      await tester.tap(find.bySemanticsLabel('Search tab').hitTestable());
      await tester.pumpAndSettle();
      final field = find.byKey(const Key('notes-search-field'));
      await tester.enterText(field, 'Aurora');
      await tester.pumpAndSettle();

      final clear = find.byKey(const Key('notes-search-clear-icon'));
      final filter = find.byKey(const Key('notes-search-filter'));
      for (final control in [clear, filter]) {
        expect(control.hitTestable(), findsOneWidget);
        final size = tester.getSize(control);
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
      }
      final clearSemantics = tester.getSemantics(clear).getSemanticsData();
      expect(clearSemantics.tooltip, 'Clear search');
      expect(clearSemantics.hasAction(SemanticsAction.tap), isTrue);
      final filterSemantics = tester
          .getSemantics(find.bySemanticsLabel('Search filters, 0 active'))
          .getSemanticsData();
      expect(filterSemantics.hasAction(SemanticsAction.tap), isTrue);
      expect(filterSemantics.flagsCollection.isExpanded, Tristate.isFalse);

      await tester.tap(filter.hitTestable());
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(filter).flagsCollection.isExpanded,
        Tristate.isTrue,
      );
      final allTag = find.byKey(const Key('filter-tag-all'));
      final workTag = find.byKey(const Key('filter-tag-work'));
      expect(tester.getSize(allTag).height, greaterThanOrEqualTo(44));
      expect(tester.getSize(workTag).height, greaterThanOrEqualTo(44));
      expect(
        tester.getSemantics(allTag).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        tester.getSemantics(workTag).flagsCollection.isSelected,
        Tristate.isFalse,
      );

      await tester.tap(workTag);
      await tester.pump();
      expect(
        tester.getSemantics(workTag).flagsCollection.isSelected,
        Tristate.isTrue,
      );
      expect(
        tester.getSemantics(allTag).flagsCollection.isSelected,
        Tristate.isFalse,
      );
      expect(
        tester
            .getSemantics(find.byKey(const Key('sort-option-newest')))
            .flagsCollection
            .isSelected,
        Tristate.isTrue,
      );
      final done = find.widgetWithText(FilledButton, 'Done');
      expect(tester.getSize(done).height, greaterThanOrEqualTo(44));
      await tester.tap(done);
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(filter).flagsCollection.isExpanded,
        Tristate.isFalse,
      );

      await tester.tap(clear.hitTestable());
      await tester.pump();
      await tester.pump();
      expect(tester.widget<SearchBar>(field).controller?.text, isEmpty);
      expect(tester.widget<SearchBar>(field).focusNode?.hasFocus, isTrue);
    },
  );

  testWidgets(
    'Trash selection and delete confirmation are semantic 44px actions',
    (tester) async {
      // Mutation caught: destructive confirmation controls shrinking below the
      // minimum target or Trash selection becoming color-only.
      await _pumpShell(tester, size: const Size(375, 812));
      await tester.tap(find.bySemanticsLabel('Library tab').hitTestable());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Trash'));
      await tester.pumpAndSettle();
      expect(
        tester.getSemantics(find.text('Trash')).flagsCollection.isSelected,
        Tristate.isTrue,
      );

      await tester.tap(find.byTooltip('More actions for Discarded draft'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete forever').last);
      await tester.pumpAndSettle();

      const title = 'Delete “Discarded draft” forever?';
      expect(tester.getSemantics(find.text(title)).label, title);
      expect(
        tester.getSemantics(find.text('This action cannot be undone.')).label,
        'This action cannot be undone.',
      );
      final cancel = find.widgetWithText(TextButton, 'Cancel');
      final delete = find.widgetWithText(FilledButton, 'Delete forever');
      for (final action in [cancel, delete]) {
        expect(action.hitTestable(), findsOneWidget);
        final size = tester.getSize(action);
        expect(size.width, greaterThanOrEqualTo(44));
        expect(size.height, greaterThanOrEqualTo(44));
        expect(
          tester
              .getSemantics(action)
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
      }
    },
  );

  testWidgets('Home, Search, and Library reserve 112px bottom clearance', (
    tester,
  ) async {
    // Mutation caught: a branch dropping its explicit scroll inset so the
    // floating navigation obscures its final content.
    await _pumpShell(tester, size: const Size(375, 812));
    expect(
      _lastSliverBottom(tester, 'notes-home-bottom-padding'),
      greaterThanOrEqualTo(112),
    );

    await tester.tap(find.bySemanticsLabel('Search tab').hitTestable());
    await tester.pumpAndSettle();
    final searchList = tester.widget<ListView>(find.byType(ListView).first);
    expect(
      searchList.padding!.resolve(TextDirection.ltr).bottom,
      greaterThanOrEqualTo(112),
    );

    await tester.tap(find.bySemanticsLabel('Library tab').hitTestable());
    await tester.pumpAndSettle();
    expect(
      _lastSliverBottom(tester, 'notes-library-bottom-padding'),
      greaterThanOrEqualTo(112),
    );
  });
}

Tristate _isSelected(WidgetTester tester, String label) {
  return tester
      .getSemantics(find.bySemanticsLabel(label))
      .flagsCollection
      .isSelected;
}

double _lastSliverBottom(WidgetTester tester, String key) {
  final scrollView = tester.widget<CustomScrollView>(
    find.byType(CustomScrollView).first,
  );
  final padding = scrollView.slivers.last as SliverPadding;
  expect(padding.key, Key(key));
  return padding.padding.resolve(TextDirection.ltr).bottom;
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required Size size,
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
  bool highContrast = false,
  ThemeData? theme,
  EdgeInsets viewInsets = EdgeInsets.zero,
  String initialLocation = '/',
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final container = ProviderContainer(
    overrides: [
      noteRepositoryProvider.overrideWithValue(
        InMemoryNoteRepository.seeded(sampleNotes),
      ),
      noteReminderGatewayProvider.overrideWithValue(FakeNoteReminderGateway()),
      notificationServiceProvider.overrideWithValue(
        NotificationService(plugin: FlutterLocalNotificationsPlugin()),
      ),
    ],
  );
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  if (initialLocation != '/') router.go(initialLocation);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: theme ?? AuroraTheme.light(),
        darkTheme: AuroraTheme.dark(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: textScaler,
            disableAnimations: disableAnimations,
            highContrast: highContrast,
            viewInsets: viewInsets,
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
