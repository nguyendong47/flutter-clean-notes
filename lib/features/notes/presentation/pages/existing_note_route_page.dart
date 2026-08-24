import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_clean_notes/app/widgets/aurora_background.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/add_edit_note_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';

/// Resolves an existing note without ever fabricating editable data.
class ExistingNoteRoutePage extends ConsumerStatefulWidget {
  const ExistingNoteRoutePage({
    required this.noteId,
    required this.onClose,
    super.key,
  });

  final String noteId;
  final VoidCallback onClose;

  @override
  ConsumerState<ExistingNoteRoutePage> createState() =>
      _ExistingNoteRoutePageState();
}

class _ExistingNoteRoutePageState extends ConsumerState<ExistingNoteRoutePage> {
  AddEditNotePage? _resolvedEditor;

  @override
  void didUpdateWidget(covariant ExistingNoteRoutePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.noteId != widget.noteId) _resolvedEditor = null;
  }

  @override
  Widget build(BuildContext context) {
    final parsedId = int.tryParse(widget.noteId);
    final notes = parsedId == null ? null : ref.watch(notesProvider);
    final freshNotes =
        notes is AsyncData<List<Note>> && !notes.isLoading && !notes.hasError
        ? notes.value
        : null;
    if (parsedId != null && _resolvedEditor == null && freshNotes != null) {
      final resolved = _findNote(freshNotes, parsedId);
      if (resolved != null) {
        _resolvedEditor = AddEditNotePage(
          key: ValueKey('existing-note-editor-$parsedId'),
          note: resolved,
          onClose: widget.onClose,
        );
      }
    }

    final editor = _resolvedEditor;
    if (editor != null) return editor;

    final child = parsedId == null
        ? _notFound()
        : notes!.when(
            skipLoadingOnRefresh: false,
            skipLoadingOnReload: false,
            loading: () => _RouteStateScaffold(
              key: const Key('existing-note-loading'),
              title: 'Opening note',
              message: 'Loading your note…',
              icon: Icons.hourglass_top_rounded,
              onClose: widget.onClose,
              loading: true,
            ),
            error: (error, stackTrace) => _RouteStateScaffold(
              key: const Key('existing-note-error'),
              title: 'Could not open note',
              message: 'Please try again.',
              icon: Icons.error_outline_rounded,
              onClose: widget.onClose,
              onRetry: () => ref.invalidate(notesProvider),
              announceTitle: true,
            ),
            data: (notes) => _notFound(),
          );

    final canPop = Navigator.of(context).canPop();
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) widget.onClose();
      },
      child: child,
    );
  }

  Widget _notFound() {
    return _RouteStateScaffold(
      key: const Key('existing-note-not-found'),
      title: 'Note not found',
      message: 'This note does not exist or is no longer available.',
      icon: Icons.search_off_rounded,
      onClose: widget.onClose,
    );
  }

  Note? _findNote(List<Note> notes, int id) {
    for (final note in notes) {
      if (note.id == id) return note;
    }
    return null;
  }
}

class _RouteStateScaffold extends StatelessWidget {
  const _RouteStateScaffold({
    required this.title,
    required this.message,
    required this.icon,
    required this.onClose,
    super.key,
    this.loading = false,
    this.onRetry,
    this.announceTitle = false,
  });

  final String title;
  final String message;
  final IconData icon;
  final VoidCallback onClose;
  final bool loading;
  final VoidCallback? onRetry;
  final bool announceTitle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        leading: BackButton(onPressed: onClose),
        title: const Text('Notes'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: AuroraBackground(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (loading)
                          const SizedBox.square(
                            dimension: 40,
                            child: CircularProgressIndicator(),
                          )
                        else
                          Icon(icon, size: 48, color: colorScheme.primary),
                        const SizedBox(height: 20),
                        Semantics(
                          container: true,
                          header: true,
                          liveRegion: announceTitle,
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        if (onRetry case final retry?) ...[
                          const SizedBox(height: 24),
                          ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 48),
                            child: FilledButton.icon(
                              key: const Key('existing-note-retry'),
                              onPressed: retry,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Try again'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
