import 'dart:ui' show SemanticsAction;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_clean_notes/app/app_providers.dart';
import 'package:flutter_clean_notes/app/notification_service.dart';
import 'package:flutter_clean_notes/app/router.dart';
import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/privacy_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_reminder_gateway_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import '../helpers/fake_note_reminder_gateway.dart';
import '../helpers/in_memory_note_repository.dart';
import '../helpers/note_fixtures.dart';
import '../support/localization_test_wrapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  // easy_localization's RootBundleAssetLoader reads translation JSON via
  // rootBundle.loadString, which flutter's CachingAssetBundle caches by key.
  // A stale cache entry from an earlier test's (now-disposed) EasyLocalization
  // instance causes every subsequent wrapWithTestLocalization(...) build in
  // this file to hang forever awaiting that load (see
  // aissat/easy_localization#268/#362). Clearing the cache after each test
  // keeps every load a fresh read.
  tearDown(() => rootBundle.clear());

  testWidgets('More exposes a focusable Privacy entry that opens a root route', (
    tester,
  ) async {
    // Mutation caught: a non-focusable row, modal-local push, or missing route
    // prevents keyboard and deep-link users from reaching Privacy.
    final harness = await _pumpRouter(tester);
    await harness.container.read(appThemeProvider.future);
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('More actions'));
    await tester.pumpAndSettle();

    final privacyEntry = find.byKey(const Key('more-privacy-button'));
    expect(privacyEntry, findsOneWidget);
    expect(tester.getSize(privacyEntry).height, greaterThanOrEqualTo(48));
    final semantics = tester.getSemantics(privacyEntry).getSemanticsData();
    expect(semantics.label, 'Privacy');
    expect(semantics.hint, 'How Clean Notes handles data');
    expect(semantics.flagsCollection.isButton, isTrue);
    expect(semantics.hasAction(SemanticsAction.tap), isTrue);

    final focused = await _focus(tester, privacyEntry);
    expect(focused.hasFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('more-actions-sheet')), findsNothing);
    expect(find.byType(PrivacyPage), findsOneWidget);
    expect(_path(harness.router), '/');
    expect(
      Navigator.of(tester.element(find.byType(PrivacyPage))),
      same(rootNavigatorKey.currentState),
    );

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyPage), findsNothing);
    expect(_path(harness.router), '/');
  });

  testWidgets('direct Privacy route has a predictable Back fallback', (
    tester,
  ) async {
    // Mutation caught: direct navigation without a previous route trapping the
    // user because Back only tries to pop an empty root stack.
    final harness = await _pumpRouter(tester, initialLocation: '/privacy');

    expect(find.byType(PrivacyPage), findsOneWidget);
    expect(_path(harness.router), '/privacy');
    final back = find.byKey(const Key('privacy-back-button'));
    expect(back.hitTestable(), findsOneWidget);
    expect(tester.getSize(back).width, greaterThanOrEqualTo(48));
    expect(tester.getSize(back).height, greaterThanOrEqualTo(48));

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(PrivacyPage), findsNothing);
    expect(_path(harness.router), '/');
  });

  testWidgets('direct Privacy route AppBar Back uses the same fallback', (
    tester,
  ) async {
    // Mutation caught: making the explicit onClose callback a no-op leaves the
    // AppBar button unable to exit a directly opened Privacy route.
    final harness = await _pumpRouter(tester, initialLocation: '/privacy');

    final back = find.byKey(const Key('privacy-back-button'));
    expect(back.hitTestable(), findsOneWidget);
    await tester.tap(back);
    await tester.pumpAndSettle();

    expect(find.byType(PrivacyPage), findsNothing);
    expect(_path(harness.router), '/');
  });
}

typedef _RouterHarness = ({ProviderContainer container, GoRouter router});

Future<_RouterHarness> _pumpRouter(
  WidgetTester tester, {
  String initialLocation = '/',
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final container = ProviderContainer(
    overrides: [
      noteRepositoryProvider.overrideWithValue(
        InMemoryNoteRepository.seeded(sampleNotes),
      ),
      notificationServiceProvider.overrideWithValue(
        NotificationService(plugin: FlutterLocalNotificationsPlugin()),
      ),
      noteReminderGatewayProvider.overrideWithValue(FakeNoteReminderGateway()),
    ],
  );
  addTearDown(container.dispose);
  final router = container.read(routerProvider);
  if (initialLocation != '/') router.go(initialLocation);

  await tester.pumpWidget(
    wrapWithTestLocalization(
      UncontrolledProviderScope(
        container: container,
        child: Builder(
          builder: (localizationContext) => MaterialApp.router(
            theme: AuroraTheme.light(),
            darkTheme: AuroraTheme.dark(),
            routerConfig: router,
            localizationsDelegates:
                localizationContext.localizationDelegates,
            supportedLocales: localizationContext.supportedLocales,
            locale: localizationContext.locale,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
  return (container: container, router: router);
}

String _path(GoRouter router) => router.routeInformationProvider.value.uri.path;

Future<FocusNode> _focus(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 30; attempt++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focus = FocusManager.instance.primaryFocus;
    if (focus != null && _isDescendantOf(focus.context, target)) return focus;
  }
  throw TestFailure('Could not focus the Privacy row');
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
