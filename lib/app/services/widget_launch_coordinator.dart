import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';

/// Coordinates deep links and launches triggered by Home Screen Widgets.
class WidgetLaunchCoordinator {
  WidgetLaunchCoordinator({
    required this.router,
    Future<Uri?> Function()? initialUriFetcher,
    Stream<Uri?>? widgetClickedStream,
  }) : _initialUriFetcher = initialUriFetcher ?? _defaultInitialUriFetcher,
       _widgetClickedStream =
           widgetClickedStream ?? _defaultWidgetClickedStream;

  final GoRouter router;
  final Future<Uri?> Function() _initialUriFetcher;
  final Stream<Uri?> _widgetClickedStream;
  StreamSubscription<Uri?>? _subscription;

  static bool get isSupportedPlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<Uri?> _defaultInitialUriFetcher() async {
    if (!isSupportedPlatform) return null;
    try {
      return await HomeWidget.initiallyLaunchedFromHomeWidget();
    } catch (_) {
      return null;
    }
  }

  static Stream<Uri?> get _defaultWidgetClickedStream {
    if (!isSupportedPlatform) return const Stream.empty();
    try {
      return HomeWidget.widgetClicked;
    } catch (_) {
      return const Stream.empty();
    }
  }

  /// Start listening to widget click events and check for an initial launch URI.
  void initialize() {
    _subscription = _widgetClickedStream.listen(handleUri);
    _initialUriFetcher().then(handleUri);
  }

  /// Process a target URI and navigate to the matching route if valid.
  void handleUri(Uri? uri) {
    if (uri == null) return;
    final path = resolveRoute(uri);
    if (path != null) {
      router.push<void>(path);
    }
  }

  /// Resolve a clean-notes URI into an internal application route path.
  /// Supports:
  /// - clean-notes://new -> /note/new
  /// - clean-notes://search -> /search
  /// - clean-notes://note?id=42 -> /note/42
  /// - clean-notes://note/42 -> /note/42
  static String? resolveRoute(Uri uri) {
    final host = uri.host;
    final path = uri.path;

    if (host == 'new' || path == '/new' || path == 'new') {
      return '/note/new';
    }
    if (host == 'search' || path == '/search' || path == 'search') {
      return '/search';
    }
    if (host == 'note' || path.startsWith('/note')) {
      final id =
          uri.queryParameters['id'] ??
          (uri.pathSegments.isNotEmpty ? uri.pathSegments.last : null);
      if (id != null && id.isNotEmpty && id != 'note') {
        return '/note/$id';
      }
    }
    return null;
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}
