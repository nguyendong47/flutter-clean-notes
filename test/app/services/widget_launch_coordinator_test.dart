import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_clean_notes/app/services/widget_launch_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeGoRouter implements GoRouter {
  final List<String> navigatedPaths = [];
  final List<String> pushedPaths = [];

  @override
  void go(String location, {Object? extra}) {
    navigatedPaths.add(location);
  }

  @override
  Future<T?> push<T extends Object?>(String location, {Object? extra}) async {
    pushedPaths.add(location);
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('WidgetLaunchCoordinator.resolveRoute', () {
    test('resolves new note URIs correctly', () {
      expect(
        WidgetLaunchCoordinator.resolveRoute(Uri.parse('clean-notes://new')),
        '/note/new',
      );
      expect(
        WidgetLaunchCoordinator.resolveRoute(Uri.parse('clean-notes:///new')),
        '/note/new',
      );
      expect(
        WidgetLaunchCoordinator.resolveRoute(
          Uri.parse('clean-notes://new?template=checklist'),
        ),
        '/note/new?template=checklist',
      );
      expect(
        WidgetLaunchCoordinator.resolveRoute(
          Uri.parse('clean-notes://new?action=record'),
        ),
        '/note/new?action=record',
      );
    });

    test('resolves search URIs correctly', () {
      expect(
        WidgetLaunchCoordinator.resolveRoute(Uri.parse('clean-notes://search')),
        '/search',
      );
      expect(
        WidgetLaunchCoordinator.resolveRoute(
          Uri.parse('clean-notes:///search'),
        ),
        '/search',
      );
    });

    test('resolves note with query parameter or path segment', () {
      expect(
        WidgetLaunchCoordinator.resolveRoute(
          Uri.parse('clean-notes://note?id=123'),
        ),
        '/note/123',
      );
      expect(
        WidgetLaunchCoordinator.resolveRoute(
          Uri.parse('clean-notes:///note/123'),
        ),
        '/note/123',
      );
    });

    test('resolves pinned notes URIs correctly', () {
      expect(
        WidgetLaunchCoordinator.resolveRoute(Uri.parse('clean-notes://pinned')),
        '/',
      );
      expect(
        WidgetLaunchCoordinator.resolveRoute(
          Uri.parse('clean-notes:///pinned'),
        ),
        '/',
      );
    });

    test('returns null for unknown or empty note URIs', () {
      expect(
        WidgetLaunchCoordinator.resolveRoute(
          Uri.parse('clean-notes://unknown'),
        ),
        isNull,
      );
      expect(
        WidgetLaunchCoordinator.resolveRoute(Uri.parse('clean-notes://note')),
        isNull,
      );
    });
  });

  group('WidgetLaunchCoordinator runtime behavior', () {
    test('handles initial URI on initialization', () async {
      final fakeRouter = _FakeGoRouter();
      final coordinator = WidgetLaunchCoordinator(
        router: fakeRouter,
        initialUriFetcher: () async => Uri.parse('clean-notes://new'),
        widgetClickedStream: const Stream.empty(),
      );

      coordinator.initialize();
      await Future<void>.delayed(Duration.zero);

      expect(fakeRouter.navigatedPaths, ['/note/new']);
      coordinator.dispose();
    });

    test(
      'handles clicked stream events and ignores null/invalid URIs',
      () async {
        final fakeRouter = _FakeGoRouter();
        final streamController = StreamController<Uri?>();
        final coordinator = WidgetLaunchCoordinator(
          router: fakeRouter,
          initialUriFetcher: () async => null,
          widgetClickedStream: streamController.stream,
        );

        coordinator.initialize();
        await Future<void>.delayed(Duration.zero);
        expect(fakeRouter.navigatedPaths, isEmpty);

        streamController.add(Uri.parse('clean-notes://search'));
        await Future<void>.delayed(Duration.zero);
        expect(fakeRouter.navigatedPaths, ['/search']);

        streamController.add(null);
        streamController.add(Uri.parse('clean-notes://unknown'));
        await Future<void>.delayed(Duration.zero);
        expect(fakeRouter.navigatedPaths, ['/search']);

        streamController.add(Uri.parse('clean-notes://note?id=99'));
        await Future<void>.delayed(Duration.zero);
        expect(fakeRouter.navigatedPaths, ['/search', '/note/99']);

        coordinator.dispose();
        await streamController.close();
      },
    );

    test(
      'deduplicates rapid identical URI events within debounce window',
      () async {
        final fakeRouter = _FakeGoRouter();
        final streamController = StreamController<Uri?>();
        final coordinator = WidgetLaunchCoordinator(
          router: fakeRouter,
          initialUriFetcher: () async => null,
          widgetClickedStream: streamController.stream,
        );

        coordinator.initialize();
        await Future<void>.delayed(Duration.zero);

        final uri = Uri.parse('clean-notes://new');
        streamController.add(uri);
        await Future<void>.delayed(Duration.zero);
        expect(fakeRouter.navigatedPaths, ['/note/new']);

        // Immediate second emission should be deduplicated
        streamController.add(uri);
        await Future<void>.delayed(Duration.zero);
        expect(fakeRouter.navigatedPaths, ['/note/new']);

        coordinator.dispose();
        await streamController.close();
      },
    );

    test(
      'triggers onSearchRequested when navigating to search route',
      () async {
        final fakeRouter = _FakeGoRouter();
        final streamController = StreamController<Uri?>();
        var searchRequested = false;
        final coordinator = WidgetLaunchCoordinator(
          router: fakeRouter,
          onSearchRequested: () => searchRequested = true,
          initialUriFetcher: () async => null,
          widgetClickedStream: streamController.stream,
        );

        coordinator.initialize();
        await Future<void>.delayed(Duration.zero);

        streamController.add(Uri.parse('clean-notes://search'));
        await Future<void>.delayed(Duration.zero);

        expect(fakeRouter.navigatedPaths, ['/search']);
        expect(searchRequested, isTrue);

        coordinator.dispose();
        await streamController.close();
      },
    );

    test(
      'rechecks initial URI on didChangeAppLifecycleState resumed',
      () async {
        final fakeRouter = _FakeGoRouter();
        var fetchCount = 0;
        final coordinator = WidgetLaunchCoordinator(
          router: fakeRouter,
          initialUriFetcher: () async {
            fetchCount++;
            if (fetchCount == 2) {
              return Uri.parse('clean-notes://search');
            }
            return null;
          },
          widgetClickedStream: const Stream.empty(),
        );

        coordinator.initialize();
        await Future<void>.delayed(Duration.zero);
        expect(fakeRouter.navigatedPaths, isEmpty);

        coordinator.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await Future<void>.delayed(Duration.zero);
        expect(fakeRouter.navigatedPaths, ['/search']);

        coordinator.dispose();
      },
    );
  });
}
