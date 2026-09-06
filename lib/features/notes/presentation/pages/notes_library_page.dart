import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_clean_notes/app/widgets/aurora_background.dart';
import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_reminder_gateway_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/persisted_note_mutation_exception.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/library_segmented_control.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/notes_collection.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/notes_state_view.dart';

export 'package:flutter_clean_notes/features/notes/presentation/widgets/library_segmented_control.dart'
    show LibrarySection;

class NotesLibraryPage extends ConsumerStatefulWidget {
  const NotesLibraryPage({super.key, this.onOpenNote, this.onShowNotes});

  final ValueChanged<Note>? onOpenNote;
  final VoidCallback? onShowNotes;

  @override
  ConsumerState<NotesLibraryPage> createState() => _NotesLibraryPageState();
}

class _NotesLibraryPageState extends ConsumerState<NotesLibraryPage> {
  final ScrollController _scrollController = ScrollController();
  final Set<int> _committedDeletedNoteIds = <int>{};
  final Set<int> _reminderCancellationRetries = <int>{};

  Future<void>? _refreshInFlight;
  LibrarySection _section = LibrarySection.archived;
  bool _deleteDialogOpen = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<Note>>>(notesProvider, (previous, next) {
      if (next is AsyncData<List<Note>>) {
        _committedDeletedNoteIds.clear();
      }
    });

    final notesState = ref.watch(notesProvider);
    final selectedNotes = ref.watch(
      notesByStatusProvider(_statusFor(_section)),
    );
    final supportsReminderScheduling = ref
        .watch(noteReminderGatewayProvider)
        .supportsScheduling;
    final visibleNotes = notesState.hasError && notesState.hasValue
        ? selectedNotes
              .where((note) => !_committedDeletedNoteIds.contains(note.id))
              .toList(growable: false)
        : selectedNotes;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AuroraBackground(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _ContentSliver(
                child: Semantics(
                  header: true,
                  namesRoute: true,
                  child: Text(
                    'Library',
                    key: const Key('notes-library-heading'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              _ContentSliver(
                child: LibrarySegmentedControl(
                  selected: _section,
                  onSelected: _selectSection,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              if (!notesState.hasValue && notesState.isLoading)
                const NotesSkeleton()
              else if (!notesState.hasValue && notesState.hasError)
                NotesErrorState(onRetry: () => unawaited(_refresh()))
              else ...[
                if (notesState.hasError) ...[
                  _ContentSliver(
                    child: _CachedErrorNotice(
                      onRetry: () => unawaited(_refresh()),
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 12)),
                ],
                if (visibleNotes.isEmpty)
                  _LibraryEmptyState(section: _section, onShowNotes: _showNotes)
                else
                  NotesCollection(
                    key: ValueKey('notes-library-${_section.name}'),
                    notes: visibleNotes,
                    onOpen: _openNote,
                    onTogglePin: _unusedAction,
                    onArchive: _unusedAction,
                    onTrash: _trash,
                    onRestore: _restore,
                    onDelete: _requestDelete,
                    supportsReminderScheduling: supportsReminderScheduling,
                  ),
              ],
              const SliverPadding(
                key: Key('notes-library-bottom-padding'),
                padding: EdgeInsets.only(bottom: 120),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _selectSection(LibrarySection section) {
    if (_section == section) return;
    setState(() => _section = section);
  }

  void _showNotes() {
    final callback = widget.onShowNotes;
    if (callback != null) {
      callback();
      return;
    }
    context.go('/');
  }

  void _openNote(Note note) {
    final callback = widget.onOpenNote;
    if (callback != null) {
      callback(note);
      return;
    }
    final id = note.id;
    if (id != null) context.push('/note/$id');
  }

  Future<void> _refresh() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;

    final refresh = _performRefresh();
    _refreshInFlight = refresh;
    return refresh.whenComplete(() {
      if (identical(_refreshInFlight, refresh)) {
        _refreshInFlight = null;
      }
    });
  }

  Future<void> _performRefresh() async {
    try {
      final refresh = ref.refresh(notesProvider.future);
      await refresh;
    } catch (_) {
      // Initial failures use the stable error state; cached failures announce
      // through the provider listener without replacing visible notes.
    }
  }

  Future<void> _unusedAction(Note note) async {}

  Future<void> _trash(Note note) async {
    if (_section != LibrarySection.archived) return;
    final succeeded = await _runMutation(
      () => ref.read(notesProvider.notifier).trashNote(note),
    );
    if (succeeded) {
      _showUndo(
        '${_displayTitle(note)} moved to trash',
        () => ref.read(notesProvider.notifier).archiveNote(note),
      );
    }
  }

  Future<void> _restore(Note note) async {
    final source = _section;
    final succeeded = await _runMutation(
      () => ref.read(notesProvider.notifier).restoreNote(note),
    );
    if (!succeeded) return;

    final inverse = switch (source) {
      LibrarySection.archived =>
        () => ref.read(notesProvider.notifier).archiveNote(note),
      LibrarySection.trash =>
        () => ref.read(notesProvider.notifier).trashNote(note),
    };
    _showUndo('${_displayTitle(note)} restored', inverse);
  }

  Future<bool> _runMutation(Future<void> Function() mutation) async {
    try {
      await mutation();
      return true;
    } on PersistedNoteMutationException {
      return true;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..removeCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              content: Text('library.updateError'.tr()),
            ),
          );
      }
      return false;
    }
  }

  void _showUndo(String message, Future<void> Function() inverse) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(message),
          action: SnackBarAction(
            label: 'library.undo'.tr(),
            onPressed: () => unawaited(_runMutation(inverse)),
          ),
        ),
      );
  }

  Future<void> _requestDelete(Note note) {
    if (_deleteDialogOpen || note.id == null) return Future.value();
    _deleteDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _deleteDialogOpen = false;
        return;
      }
      unawaited(_showDeleteDialog(note));
    });
    return Future.value();
  }

  Future<void> _showDeleteDialog(Note note) async {
    final originFocus = FocusManager.instance.primaryFocus;
    try {
      final result =
          await showDialog<
            ({int noteId, PersistedNoteMutationFailureKind? failureKind})
          >(
            context: context,
            builder: (context) => _DeleteForeverDialog(
              note: note,
              onDelete: () =>
                  ref.read(notesProvider.notifier).deleteNote(note.id!),
            ),
          );
      if (result != null && mounted) {
        setState(() => _committedDeletedNoteIds.add(result.noteId));
        if (result.failureKind ==
            PersistedNoteMutationFailureKind.reminderCancellation) {
          _showReminderCancellationWarning(result.noteId);
        }
      }
    } finally {
      _deleteDialogOpen = false;
      if (mounted && originFocus?.canRequestFocus == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && originFocus?.canRequestFocus == true) {
            originFocus!.requestFocus();
          }
        });
      }
    }
  }

  void _showReminderCancellationWarning(int noteId) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Semantics(
            liveRegion: true,
            child: const Text(
              'Note deleted, but its reminder could not be cancelled.',
            ),
          ),
          action: SnackBarAction(
            label: 'library.retry'.tr(),
            onPressed: () => unawaited(_retryReminderCancellation(noteId)),
          ),
        ),
      );
  }

  Future<void> _retryReminderCancellation(int noteId) async {
    if (!_reminderCancellationRetries.add(noteId)) return;
    try {
      await ref.read(notesProvider.notifier).retryReminderCancellation(noteId);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..removeCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Semantics(
              liveRegion: true,
              child: Text('library.reminderCancelled'.tr()),
            ),
          ),
        );
    } catch (_) {
      if (mounted) _showReminderCancellationWarning(noteId);
    } finally {
      _reminderCancellationRetries.remove(noteId);
    }
  }
}

class _DeleteForeverDialog extends StatefulWidget {
  const _DeleteForeverDialog({required this.note, required this.onDelete});

  final Note note;
  final Future<void> Function() onDelete;

  @override
  State<_DeleteForeverDialog> createState() => _DeleteForeverDialogState();
}

class _DeleteForeverDialogState extends State<_DeleteForeverDialog>
    implements PopEntry<Object?> {
  ModalRoute<dynamic>? _route;

  @override
  late final ValueNotifier<bool> canPopNotifier;

  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    canPopNotifier = ValueNotifier<bool>(true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextRoute = ModalRoute.of(context);
    if (nextRoute != _route) {
      _route?.unregisterPopEntry(this);
      _route = nextRoute;
      _route?.registerPopEntry(this);
    }
    _syncCanPop();
  }

  @override
  void dispose() {
    _route?.unregisterPopEntry(this);
    canPopNotifier.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    _syncCanPop();
    PersistedNoteMutationFailureKind? failureKind;
    try {
      await widget.onDelete();
    } on PersistedNoteMutationException catch (error) {
      failureKind = error.kind;
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
        _syncCanPop();
      }
      return;
    }
    if (mounted) {
      Navigator.of(
        context,
      ).pop((noteId: widget.note.id!, failureKind: failureKind));
    }
  }

  @override
  void onPopInvoked(bool didPop) {}

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {}

  void _syncCanPop() {
    if (!mounted) return;
    canPopNotifier.value = !_busy;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = _displayTitle(widget.note);
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(
          'library.deleteForeverTitle'.tr(namedArgs: {'title': title}),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('library.deleteForeverBody'.tr()),
            if (_failed) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  'Could not delete “$title”. Try again.',
                  style: TextStyle(color: colorScheme.error),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text('library.cancel'.tr()),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 148, minHeight: 48),
            child: FilledButton(
              onPressed: _busy ? null : _delete,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              child: _busy
                  ? Semantics(
                      liveRegion: true,
                      label: 'library.deletingSemantics'.tr(
                        namedArgs: {'title': title},
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 10),
                          Text('library.deleting'.tr()),
                        ],
                      ),
                    )
                  : Text('library.deleteForever'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibraryEmptyState extends StatelessWidget {
  const _LibraryEmptyState({required this.section, required this.onShowNotes});

  final LibrarySection section;
  final VoidCallback onShowNotes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = switch (section) {
      LibrarySection.archived => (
        icon: Icons.archive_outlined,
        title: 'library.noArchivedNotes'.tr(),
        body: 'Notes you archive will appear here.',
        action: 'Browse notes',
      ),
      LibrarySection.trash => (
        icon: Icons.delete_outline,
        title: 'library.trashEmpty'.tr(),
        body:
            'Deleted notes stay here until you restore or delete them forever.',
        action: 'Back to notes',
      ),
    };

    return _ContentSliver(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: GlassSurface(
            borderRadius: const BorderRadius.all(Radius.circular(20)),
            blur: 18,
            opacity: 0.74,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    content.icon,
                    size: 36,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 12),
                Semantics(
                  header: true,
                  child: Text(
                    content.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  content.body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: FilledButton(
                    onPressed: onShowNotes,
                    child: Text(content.action),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CachedErrorNotice extends StatelessWidget {
  const _CachedErrorNotice({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              liveRegion: true,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Icon(
                      Icons.info_outline,
                      color: colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Could not update library. Showing saved notes.',
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                key: const Key('notes-library-cached-retry'),
                onPressed: onRetry,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: colorScheme.onErrorContainer,
                ),
                icon: const Icon(Icons.refresh),
                label: Text('library.retry'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ContentSliver extends StatelessWidget {
  const _ContentSliver({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        return SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: _horizontalInset(constraints.crossAxisExtent),
          ),
          sliver: SliverToBoxAdapter(child: child),
        );
      },
    );
  }
}

NoteStatus _statusFor(LibrarySection section) {
  return switch (section) {
    LibrarySection.archived => NoteStatus.archived,
    LibrarySection.trash => NoteStatus.trashed,
  };
}

double _horizontalInset(double viewportWidth) {
  final gutter = viewportWidth >= 600 ? 24.0 : 16.0;
  return ((viewportWidth - 840) / 2).clamp(gutter, double.infinity).toDouble();
}

String _displayTitle(Note note) {
  final title = note.title.trim();
  return title.isEmpty ? 'Untitled note' : title;
}
