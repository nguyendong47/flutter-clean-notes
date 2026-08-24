import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:flutter_clean_notes/app/app_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/add_edit_note_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/existing_note_route_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_home_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_library_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_search_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_shell_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/search_focus_request.dart';

part 'router.g.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'root navigator',
);
final notesNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'notes navigator',
);
final searchNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'search navigator',
);
final libraryNavigatorKey = GlobalKey<NavigatorState>(
  debugLabel: 'library navigator',
);

/// Application router with persistent Notes, Search, and Library branches.
@Riverpod(keepAlive: true)
GoRouter router(Ref ref) {
  final notificationService = ref.watch(notificationServiceProvider);
  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            NotesShellPage(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            navigatorKey: notesNavigatorKey,
            routes: [
              GoRoute(
                path: '/',
                builder: (context, state) => NotesHomePage(
                  onOpenSearch: () {
                    ref
                        .read(searchFocusRequestProvider.notifier)
                        .requestFocus();
                    StatefulNavigationShell.of(
                      context,
                    ).goBranch(1, initialLocation: false);
                  },
                  onCreateNote: () => context.push('/note/new'),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: searchNavigatorKey,
            preload: true,
            routes: [
              GoRoute(
                path: '/search',
                builder: (context, state) => const NotesSearchPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: libraryNavigatorKey,
            routes: [
              GoRoute(
                path: '/library',
                builder: (context, state) => NotesLibraryPage(
                  onShowNotes: () => StatefulNavigationShell.of(
                    context,
                  ).goBranch(0, initialLocation: false),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/note/new',
        builder: (context, state) =>
            AddEditNotePage(onClose: () => _closeEditor(context)),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/note/:id',
        builder: (context, state) => ExistingNoteRoutePage(
          noteId: state.pathParameters['id']!,
          onClose: () => _closeEditor(context),
        ),
      ),
    ],
    debugLogDiagnostics: kDebugMode,
  );
  notificationService
    ..onNotificationTap = (note, _) {
      final id = note.id;
      if (id != null) router.push<void>('/note/$id');
    }
    ..attachContext(rootNavigatorKey);

  ref.onDispose(() {
    notificationService.onNotificationTap = null;
    router.dispose();
  });
  return router;
}

void _closeEditor(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/');
  }
}
