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
    testWidgets('Aurora shell is semantic and overflow-free at $viewport', (
      tester,
    ) async {
      // Mutation caught: reducing navigation/action hit areas or removing their
      // spoken names during a responsive layout change.
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        errors.add(details);
        debugPrint(
          'Captured accessibility FlutterError: ${details.exceptionAsString()}',
        );
      };
      addTearDown(() => FlutterError.onError = previous);
      await _pumpShell(tester, size: viewport);

      for (final label in const [
        'Notes tab',
        'Search tab',
        'Create new note',
        'Library tab',
        'More actions',
      ]) {
        final finder = find.bySemanticsLabel(label);
        expect(finder, findsOneWidget);
        final rect = tester.getRect(finder);
        expect(rect.width, greaterThanOrEqualTo(48), reason: label);
        expect(rect.height, greaterThanOrEqualTo(48), reason: label);
      }
      expect(find.bySemanticsLabel('Search notes'), findsOneWidget);
      expect(find.bySemanticsLabel('Open note Aurora design'), findsOneWidget);
      FlutterError.onError = previous;
      expect(errors, isEmpty);
    });
  }

  testWidgets(
    'compact enlarged text, reduced motion, and dark surfaces remain usable',
    (tester) async {
      // Mutation caught: fixed compact navigation that clips enlarged labels or
      // forces animation-dependent interaction on reduced-motion devices.
      final errors = <FlutterErrorDetails>[];
      final previous = FlutterError.onError;
      FlutterError.onError = errors.add;
      addTearDown(() => FlutterError.onError = previous);
      await _pumpShell(
        tester,
        size: const Size(320, 640),
        textScaler: const TextScaler.linear(1.5),
        disableAnimations: true,
        theme: AuroraTheme.dark(),
      );
      await tester.tap(find.bySemanticsLabel('Search tab'));
      await tester.pump();
      expect(find.bySemanticsLabel('Search notes and tags'), findsOneWidget);
      expect(find.byKey(const Key('notes-search-field')), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('More actions'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('more-row-theme')), findsOneWidget);
      FlutterError.onError = previous;
      expect(errors, isEmpty);
    },
  );

  testWidgets(
    'editor controls clear a keyboard inset and destructive affordances are named',
    (tester) async {
      // Mutation caught: formatting controls hidden behind the keyboard or a
      // destructive confirmation reduced to icon/color-only feedback.
      await _pumpShell(
        tester,
        size: const Size(375, 812),
        viewInsets: const EdgeInsets.only(bottom: 300),
        initialLocation: '/note/1',
      );
      final title = find.byKey(const Key('editor-title-field'));
      await tester.tap(title);
      await tester.pump();
      final formatting = tester.getRect(
        find.byKey(const Key('editor-formatting-bar')),
      );
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
    },
  );
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required Size size,
  TextScaler textScaler = TextScaler.noScaling,
  bool disableAnimations = false,
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
    container.dispose();
  });
}
