import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import 'package:flutter_clean_notes/app/widgets/aurora_background.dart';
import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/glass_note_card.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/notes_collection.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/notes_state_view.dart';

class NotesHomePage extends ConsumerStatefulWidget {
  const NotesHomePage({super.key, this.onOpenSearch, this.onCreateNote});

  final VoidCallback? onOpenSearch;
  final VoidCallback? onCreateNote;

  @override
  ConsumerState<NotesHomePage> createState() => _NotesHomePageState();
}

class _NotesHomePageState extends ConsumerState<NotesHomePage> {
  static final _dateFormat = DateFormat('EEEE, MMMM d');

  Object? _lastAnnouncedError;
  String? _pendingTagReset;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<List<Note>>>(notesProvider, (previous, next) {
      if (next.hasError && next.hasValue) {
        _announceError(next.error!);
      } else if (!next.hasError) {
        _lastAnnouncedError = null;
      }
    });
    ref.listen<List<String>>(homeTagsProvider, (previous, next) {
      final selectedTag = ref.read(selectedTagProvider);
      if (selectedTag != null && !next.contains(selectedTag)) {
        _scheduleTagReset(selectedTag);
      }
    });

    final notesState = ref.watch(notesProvider);
    final homeNotes = ref.watch(homeNotesProvider);
    final tags = ref.watch(homeTagsProvider);
    final selectedTag = ref.watch(selectedTagProvider);
    final pinned = homeNotes.where((note) => note.isPinned).toList();
    final unpinned = homeNotes.where((note) => !note.isPinned).toList();
    final hasVisibleData = notesState.hasValue;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AuroraBackground(
        child: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              _ContentSliver(
                child: _HomeHeader(
                  key: const Key('notes-home-header'),
                  date: _dateFormat.format(DateTime.now()),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
              _ContentSliver(child: _SearchSurface(onTap: _openSearch)),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              _ContentSliver(
                child: _TagStrip(
                  tags: tags,
                  selectedTag: selectedTag,
                  onSelected: (tag) =>
                      ref.read(selectedTagProvider.notifier).select(tag),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
              if (hasVisibleData && pinned.isNotEmpty)
                _ContentSliver(
                  child: _PinnedSection(
                    key: const Key('pinned-notes-section'),
                    notes: pinned,
                    onOpen: _openNote,
                    onTogglePin: _togglePin,
                    onArchive: _archive,
                    onTrash: _trash,
                    onRestore: _restore,
                    onDelete: _delete,
                  ),
                ),
              if (hasVisibleData && pinned.isNotEmpty)
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              if (!hasVisibleData && notesState.isLoading)
                const NotesSkeleton()
              else if (!hasVisibleData && notesState.hasError)
                NotesErrorState(onRetry: () => unawaited(_refresh()))
              else if (homeNotes.isEmpty)
                NotesEmptyState(onCreate: _createNote)
              else
                NotesCollection(
                  key: const Key('notes-collection'),
                  notes: unpinned,
                  onOpen: _openNote,
                  onTogglePin: _togglePin,
                  onArchive: _archive,
                  onTrash: _trash,
                  onRestore: _restore,
                  onDelete: _delete,
                ),
              const SliverPadding(
                key: Key('notes-home-bottom-padding'),
                padding: EdgeInsets.only(bottom: 120),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openSearch() => widget.onOpenSearch?.call();

  void _scheduleTagReset(String tag) {
    if (_pendingTagReset == tag) return;
    _pendingTagReset = tag;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pendingTagReset = null;
      if (!mounted || ref.read(selectedTagProvider) != tag) return;
      if (!ref.read(homeTagsProvider).contains(tag)) {
        ref.read(selectedTagProvider.notifier).select(null);
      }
    });
  }

  void _createNote() {
    final callback = widget.onCreateNote;
    if (callback != null) {
      callback();
      return;
    }
    context.push('/note/new');
  }

  void _openNote(Note note) {
    final id = note.id;
    if (id != null) context.push('/note/$id');
  }

  Future<void> _refresh() async {
    try {
      final refresh = ref.refresh(notesProvider.future);
      await refresh;
    } catch (error) {
      _announceError(error);
    }
  }

  Future<void> _togglePin(Note note) {
    return _runMutation(() => ref.read(notesProvider.notifier).togglePin(note));
  }

  Future<void> _archive(Note note) async {
    final succeeded = await _runMutation(
      () => ref.read(notesProvider.notifier).archiveNote(note),
    );
    if (succeeded) _showUndo(note, '${_displayTitle(note)} archived');
  }

  Future<void> _trash(Note note) async {
    final succeeded = await _runMutation(
      () => ref.read(notesProvider.notifier).trashNote(note),
    );
    if (succeeded) {
      _showUndo(note, '${_displayTitle(note)} moved to trash');
    }
  }

  Future<void> _restore(Note note) {
    return _runMutation(
      () => ref.read(notesProvider.notifier).restoreNote(note),
    );
  }

  Future<void> _delete(Note note) async {
    final id = note.id;
    if (id == null) return;
    await _runMutation(() => ref.read(notesProvider.notifier).deleteNote(id));
  }

  Future<bool> _runMutation(Future<void> Function() mutation) async {
    try {
      await mutation();
      return true;
    } catch (error) {
      _announceError(error);
      return false;
    }
  }

  void _showUndo(Note note, String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(message),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => unawaited(_restore(note)),
          ),
        ),
      );
  }

  void _announceError(Object error) {
    if (identical(_lastAnnouncedError, error)) return;
    _lastAnnouncedError = error;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not update notes: $error'),
        ),
      );
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.date, super.key});

  final String date;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          greeting,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          date,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _SearchSurface extends StatelessWidget {
  const _SearchSurface({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassSurface(
      key: const Key('notes-home-search'),
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      padding: EdgeInsets.zero,
      blur: 18,
      opacity: 0.74,
      child: Material(
        color: Colors.transparent,
        child: Semantics(
          container: true,
          button: true,
          label: 'Search notes',
          onTap: onTap,
          child: ExcludeSemantics(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 52),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Search notes',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
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

class _TagStrip extends StatelessWidget {
  const _TagStrip({
    required this.tags,
    required this.selectedTag,
    required this.onSelected,
  });

  final List<String> tags;
  final String? selectedTag;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          FilterChip(
            label: const Text('All'),
            selected: selectedTag == null,
            onSelected: (_) => onSelected(null),
            materialTapTargetSize: MaterialTapTargetSize.padded,
          ),
          for (final tag in tags) ...[
            const SizedBox(width: 8),
            FilterChip(
              label: Text(tag),
              selected: selectedTag == tag,
              onSelected: (_) => onSelected(tag),
              materialTapTargetSize: MaterialTapTargetSize.padded,
            ),
          ],
        ],
      ),
    );
  }
}

class _PinnedSection extends StatelessWidget {
  const _PinnedSection({
    required this.notes,
    required this.onOpen,
    required this.onTogglePin,
    required this.onArchive,
    required this.onTrash,
    required this.onRestore,
    required this.onDelete,
    super.key,
  });

  final List<Note> notes;
  final void Function(Note note) onOpen;
  final Future<void> Function(Note note) onTogglePin;
  final Future<void> Function(Note note) onArchive;
  final Future<void> Function(Note note) onTrash;
  final Future<void> Function(Note note) onRestore;
  final Future<void> Function(Note note) onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            ExcludeSemantics(
              child: Icon(Icons.push_pin, size: 20, color: colorScheme.primary),
            ),
            const SizedBox(width: 8),
            Text(
              'Pinned',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < notes.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          GlassNoteCard(
            key: ValueKey('pinned-note-card-${notes[index].id}'),
            note: notes[index],
            onOpen: () => onOpen(notes[index]),
            onTogglePin: () => onTogglePin(notes[index]),
            onArchive: () => onArchive(notes[index]),
            onTrash: () => onTrash(notes[index]),
            onRestore: () => onRestore(notes[index]),
            onDelete: () => onDelete(notes[index]),
          ),
        ],
      ],
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

double _horizontalInset(double viewportWidth) {
  final gutter = viewportWidth >= 600 ? 24.0 : 16.0;
  return ((viewportWidth - 840) / 2).clamp(gutter, double.infinity).toDouble();
}

String _displayTitle(Note note) {
  final title = note.title.trim();
  return title.isEmpty ? 'Untitled note' : title;
}
