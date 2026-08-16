import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/add_edit_note_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';

/// Application router for Flutter Clean Notes.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => const NotesPage(),
      ),
      GoRoute(
        path: '/note/new',
        builder: (context, state) => const AddEditNotePage(),
      ),
      GoRoute(
        path: '/note/:id',
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          final notes = ref.read(notesProvider).value ?? const [];
          final note = notes.firstWhere(
            (n) => n.id == int.tryParse(id),
            orElse: () => Note(
              id: int.tryParse(id),
              title: '',
              content: '',
              color: 0xFF1E3A8A,
              createdAt: DateTime.now(),
              tags: const [],
              status: NoteStatus.active,
              reminder: null,
            ),
          );
          return AddEditNotePage(note: note);
        },
      ),
    ],
    debugLogDiagnostics: true,
  );
});