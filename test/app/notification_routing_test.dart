import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_clean_notes/app/app_providers.dart';
import 'package:flutter_clean_notes/app/notification_service.dart';
import 'package:flutter_clean_notes/app/router.dart';
import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/add_edit_note_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';

import '../helpers/in_memory_note_repository.dart';
import '../helpers/note_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('terminated-app notification launch opens exactly once', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final plugin = _LaunchDetailsPlugin();
    final service = NotificationService(plugin: plugin);
    plugin.launchDetails = NotificationAppLaunchDetails(
      true,
      notificationResponse: _openResponse(service),
    );

    try {
      await service.init();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
    final harness = await _pumpRouter(tester, service: service);

    expect(_path(harness.router), '/');
    expect(find.byType(AddEditNotePage), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(AddEditNotePage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_path(harness.router), '/');
    expect(find.byType(AddEditNotePage), findsNothing);
  });

  testWidgets('queued open retries when its navigator mounts later', (
    tester,
  ) async {
    final service = NotificationService(
      plugin: FlutterLocalNotificationsPlugin(),
    );
    final navigatorKey = GlobalKey<NavigatorState>();
    var openCount = 0;
    service.onNotificationTap = (note, context) {
      openCount++;
    };
    service
      ..attachContext(navigatorKey)
      ..handleNotificationResponse(_openResponse(service));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(openCount, 0);

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Ready')),
      ),
    );
    await tester.pump();
    expect(openCount, 1);

    await tester.pump();
    expect(openCount, 1);
  });

  testWidgets('notification received before first frame opens exactly once', (
    tester,
  ) async {
    final service = NotificationService(
      plugin: FlutterLocalNotificationsPlugin(),
    );
    service.handleNotificationResponse(_openResponse(service));

    final harness = await _pumpRouter(tester, service: service);
    expect(rootNavigatorKey.currentContext, isNotNull);
    expect(_path(harness.router), '/');
    expect(find.byType(AddEditNotePage), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(_path(harness.router), '/');
    expect(find.byType(AddEditNotePage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_path(harness.router), '/');
    expect(find.byType(AddEditNotePage), findsNothing);
  });

  testWidgets('notification received after mount preserves Search origin', (
    tester,
  ) async {
    final harness = await _pumpRouter(tester, initialLocation: '/search');

    harness.service.handleNotificationResponse(_openResponse(harness.service));
    await tester.pumpAndSettle();
    expect(_path(harness.router), '/search');
    expect(find.byType(AddEditNotePage), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(_path(harness.router), '/search');
    expect(find.byType(AddEditNotePage), findsNothing);
  });
}

typedef _Harness = ({
  ProviderContainer container,
  GoRouter router,
  NotificationService service,
});

Future<_Harness> _pumpRouter(
  WidgetTester tester, {
  String initialLocation = '/',
  NotificationService? service,
}) async {
  tester.view.physicalSize = const Size(375, 812);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final notificationService =
      service ?? NotificationService(plugin: FlutterLocalNotificationsPlugin());
  final container = ProviderContainer(
    overrides: [
      noteRepositoryProvider.overrideWithValue(
        InMemoryNoteRepository.seeded(sampleNotes),
      ),
      notificationServiceProvider.overrideWithValue(notificationService),
    ],
  );
  final router = container.read(routerProvider);
  if (initialLocation != '/') router.go(initialLocation);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        theme: AuroraTheme.light(),
        darkTheme: AuroraTheme.dark(),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  return (container: container, router: router, service: notificationService);
}

NotificationResponse _openResponse(NotificationService service) {
  return NotificationResponse(
    notificationResponseType:
        NotificationResponseType.selectedNotificationAction,
    actionId: NotificationService.actionOpen,
    payload: service.buildPayload(sampleNote),
  );
}

String _path(GoRouter router) => router.routeInformationProvider.value.uri.path;

class _LaunchDetailsPlugin extends Fake
    implements FlutterLocalNotificationsPlugin {
  NotificationAppLaunchDetails? launchDetails;

  @override
  Future<bool?> initialize(
    InitializationSettings initializationSettings, {
    DidReceiveNotificationResponseCallback? onDidReceiveNotificationResponse,
    DidReceiveBackgroundNotificationResponseCallback?
    onDidReceiveBackgroundNotificationResponse,
  }) async => true;

  @override
  Future<NotificationAppLaunchDetails?>
  getNotificationAppLaunchDetails() async => launchDetails;
}
