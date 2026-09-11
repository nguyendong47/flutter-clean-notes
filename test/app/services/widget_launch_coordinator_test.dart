import 'dart:async';

import 'package:flutter_clean_notes/app/services/widget_launch_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _FakeGoRouter implements GoRouter {
  final List<String> pushedPaths = [];

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

      expect(fakeRouter.pushedPaths, ['/note/new']);
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
        expect(fakeRouter.pushedPaths, isEmpty);

        streamController.add(Uri.parse('clean-notes://search'));
        await Future<void>.delayed(Duration.zero);
        expect(fakeRouter.pushedPaths, ['/search']);

        streamController.add(null);
        streamController.add(Uri.parse('clean-notes://unknown'));
        await Future<void>.delayed(Duration.zero);
        expect(fakeRouter.pushedPaths, ['/search']);

        streamController.add(Uri.parse('clean-notes://note?id=99'));
        await Future<void>.delayed(Duration.zero);
        expect(fakeRouter.pushedPaths, ['/search', '/note/99']);

        coordinator.dispose();
        await streamController.close();
      },
    );
  });
}
