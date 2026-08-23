import 'dart:async';

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
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/add_edit_note_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_reminder_gateway_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/persisted_note_mutation_exception.dart';

import '../helpers/fake_note_reminder_gateway.dart';
import '../helpers/in_memory_note_repository.dart';
import '../helpers/note_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
  ]) {
    testWidgets(
      'terminated-app notification launch opens exactly once on ${platform.name}',
      (tester) async {
        debugDefaultTargetPlatformOverride = platform;
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
      },
    );
  }

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

  testWidgets('legacy six-part payload opens the persisted note by ID', (
    tester,
  ) async {
    final harness = await _pumpRouter(tester);

    harness.service.handleNotificationResponse(
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: NotificationService.actionOpen,
        payload:
            '${sampleNote.id}|Stale private title|Stale private body|4280391411|2020-01-01T00:00:00.000Z|2020-01-02T00:00:00.000Z',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(AddEditNotePage), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('editor-title-field')))
          .controller!
          .text,
      sampleNote.title,
    );
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('editor-body-field')))
          .controller!
          .text,
      sampleNote.content,
    );
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

  testWidgets(
    'background save closes its owning editor after notification editor closes',
    (tester) async {
      // Mutation caught: letting editor A pop the current root route when its
      // save completes after a notification has pushed editor B.
      final repository = _DeferredAddRepository(sampleNotes);
      final harness = await _pumpRouter(
        tester,
        initialLocation: '/search',
        repository: repository,
      );
      harness.router.push('/note/new');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('editor-title-field')),
        'Saved editor A',
      );
      await tester.tap(find.byKey(const Key('editor-done-button')));
      await repository.entered.future;
      await tester.pump();

      harness.service.handleNotificationResponse(
        _openResponse(harness.service),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('existing-note-loading')), findsOneWidget);

      repository.release();
      await tester.pumpAndSettle();
      expect(
        find.byType(AddEditNotePage, skipOffstage: false),
        findsNWidgets(2),
      );

      const draft = 'Unsaved notification editor B draft';
      await tester.enterText(
        find.byKey(const Key('editor-title-field')),
        draft,
      );
      await tester.pump();

      expect(_path(harness.router), '/search');
      expect(
        find.byType(AddEditNotePage, skipOffstage: false),
        findsNWidgets(2),
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('editor-title-field')))
            .controller!
            .text,
        draft,
      );

      await tester.tap(find.byKey(const Key('editor-back-button')));
      await tester.pumpAndSettle();

      expect(_path(harness.router), '/search');
      expect(find.byType(AddEditNotePage, skipOffstage: false), findsNothing);
      expect(rootNavigatorKey.currentState!.canPop(), isFalse);
      expect(repository.addCalls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'partial-save close rechecks ownership after a notification push',
    (tester) async {
      // Mutation caught: capturing and invoking A's close callback on the next
      // frame without checking whether notification editor B became current.
      final repository = InMemoryNoteRepository.seeded(sampleNotes);
      final gateway = FakeNoteReminderGateway()
        ..cancelError = StateError('notification cancel failed');
      final harness = await _pumpRouter(
        tester,
        initialLocation: '/search',
        repository: repository,
        gateway: gateway,
      );
      harness.router.push('/note/1');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('editor-title-field')),
        'Partially saved editor A',
      );
      await tester.tap(find.byKey(const Key('editor-done-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('editor-save-error')), findsOneWidget);

      await tester.tap(find.byKey(const Key('editor-back-button')));
      harness.service.handleNotificationResponse(
        _openResponse(harness.service),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(AddEditNotePage, skipOffstage: false),
        findsNWidgets(2),
      );
      expect(rootNavigatorKey.currentState!.canPop(), isTrue);

      await tester.tap(find.byKey(const Key('editor-back-button')));
      await tester.pumpAndSettle();

      expect(_path(harness.router), '/search');
      expect(find.byType(AddEditNotePage, skipOffstage: false), findsNothing);
      expect(rootNavigatorKey.currentState!.canPop(), isFalse);
      expect(repository.notes.first.title, 'Partially saved editor A');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'notification editor waits for a committed partial save and cannot revert it',
    (tester) async {
      // Mutation caught: resolving editor B from notesProvider's previous value
      // while editor A's committed update is awaiting a reminder side effect.
      final repository = InMemoryNoteRepository.seeded(sampleNotes);
      final cancelGate = Completer<void>();
      final gateway = FakeNoteReminderGateway()
        ..cancelGate = cancelGate
        ..cancelError = StateError('notification cancel failed');
      final harness = await _pumpRouter(
        tester,
        initialLocation: '/search',
        repository: repository,
        gateway: gateway,
      );
      harness.router.push('/note/1');
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('editor-title-field')),
        'Persisted editor A title',
      );
      await tester.enterText(
        find.byKey(const Key('editor-body-field')),
        'Persisted editor A body',
      );
      await tester.tap(find.byKey(const Key('editor-done-button')));
      await tester.pump();

      expect(repository.notes.first.title, 'Persisted editor A title');
      expect(repository.notes.first.content, 'Persisted editor A body');
      expect(gateway.cancelled, [sampleNote.id]);

      harness.service.handleNotificationResponse(
        _openResponse(harness.service),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final openedAsLoading = find
          .byKey(const Key('existing-note-loading'))
          .evaluate()
          .length;
      cancelGate.complete();
      await tester.pumpAndSettle();

      expect(openedAsLoading, 1);
      expect(
        find.byType(AddEditNotePage, skipOffstage: false),
        findsNWidgets(2),
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('editor-title-field')))
            .controller!
            .text,
        'Persisted editor A title',
      );
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('editor-body-field')))
            .controller!
            .text,
        'Persisted editor A body',
      );

      gateway.cancelError = null;
      await tester.tap(find.byKey(const Key('editor-done-button')));
      await tester.pumpAndSettle();

      expect(repository.notes.first.title, 'Persisted editor A title');
      expect(repository.notes.first.content, 'Persisted editor A body');
      expect(find.byKey(const Key('editor-save-error')), findsOneWidget);

      await tester.tap(find.byKey(const Key('editor-back-button')));
      await tester.pumpAndSettle();

      expect(_path(harness.router), '/search');
      expect(find.byType(AddEditNotePage, skipOffstage: false), findsNothing);
      expect(rootNavigatorKey.currentState!.canPop(), isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'notification editor rejects cached notes carried by a refresh error',
    (tester) async {
      // Mutation caught: resolving an editor from AsyncError's previous value
      // instead of waiting for a successful retry.
      final repository = InMemoryNoteRepository.seeded(sampleNotes);
      final harness = await _pumpRouter(
        tester,
        initialLocation: '/search',
        repository: repository,
      );
      final note = harness.container.read(notesProvider).requireValue.first;
      repository.getErrorAtCall = repository.getCalls + 1;

      await expectLater(
        harness.container.read(notesProvider.notifier).togglePin(note),
        throwsA(isA<PersistedNoteMutationException>()),
      );
      expect(harness.container.read(notesProvider).hasError, isTrue);
      expect(harness.container.read(notesProvider).hasValue, isTrue);

      harness.service.handleNotificationResponse(
        _openResponse(harness.service),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('existing-note-error')), findsOneWidget);
      expect(find.byType(AddEditNotePage), findsNothing);

      await tester.tap(find.byKey(const Key('existing-note-retry')));
      await tester.pumpAndSettle();

      expect(find.byType(AddEditNotePage), findsOneWidget);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('editor-title-field')))
            .controller!
            .text,
        sampleNote.title,
      );
      expect(tester.takeException(), isNull);
    },
  );
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
  InMemoryNoteRepository? repository,
  FakeNoteReminderGateway? gateway,
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
        repository ?? InMemoryNoteRepository.seeded(sampleNotes),
      ),
      notificationServiceProvider.overrideWithValue(notificationService),
      if (gateway != null)
        noteReminderGatewayProvider.overrideWithValue(gateway),
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

class _DeferredAddRepository extends InMemoryNoteRepository {
  _DeferredAddRepository(super.notes) : super.seeded();

  final entered = Completer<void>();
  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<int> addNote(Note note) async {
    if (!entered.isCompleted) entered.complete();
    await _gate.future;
    return super.addNote(note);
  }
}

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
