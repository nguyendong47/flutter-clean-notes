import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_clean_notes/app/widgets/aurora_background.dart';
import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/search_focus_request.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/glass_note_card.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/note_filter_sheet.dart';

class NotesSearchPage extends ConsumerStatefulWidget {
  const NotesSearchPage({super.key, this.onOpenNote});

  final ValueChanged<Note>? onOpenNote;

  @override
  ConsumerState<NotesSearchPage> createState() => _NotesSearchPageState();
}

class _NotesSearchPageState extends ConsumerState<NotesSearchPage> {
  late final SearchController _controller;
  late final FocusNode _focusNode;
  late final ProviderSubscription<String> _querySubscription;
  late final ProviderSubscription<int> _focusSubscription;

  bool _syncingQuery = false;
  bool _filtersOpen = false;

  @override
  void initState() {
    super.initState();
    _controller = SearchController()..addListener(_publishControllerText);
    _focusNode = FocusNode(debugLabel: 'notes-search-field');
    _querySubscription = ref.listenManual<String>(
      searchQueryProvider,
      (previous, next) => _synchronizeController(next),
      fireImmediately: true,
    );
    _focusSubscription = ref.listenManual<int>(searchFocusRequestProvider, (
      previous,
      next,
    ) {
      if (previous != null && previous != next) _focusAfterFrame();
    });
  }

  @override
  void dispose() {
    _querySubscription.close();
    _focusSubscription.close();
    _controller
      ..removeListener(_publishControllerText)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final notesState = ref.watch(notesProvider);
    final query = ref.watch(searchQueryProvider);
    final results = ref.watch(searchResultsProvider);
    final tags = ref.watch(homeTagsProvider);
    final selectedTag = ref.watch(selectedTagProvider);
    final sort = ref.watch(sortOrderProvider);
    final duration = mediaQuery.disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 200);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AuroraBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalInset = _horizontalInset(constraints.maxWidth);
            return ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                horizontalInset,
                24,
                horizontalInset,
                mediaQuery.viewInsets.bottom + 120,
              ),
              children: [
                Text(
                  'Search',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSearchBar(query),
                const SizedBox(height: 16),
                AnimatedSwitcher(
                  key: const Key('notes-search-switcher'),
                  duration: duration,
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _buildState(
                    notesState: notesState,
                    query: query,
                    results: results,
                    tags: tags,
                    selectedTag: selectedTag,
                    sort: sort,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchBar(String query) {
    final colorScheme = Theme.of(context).colorScheme;
    return GlassSurface(
      borderRadius: const BorderRadius.all(Radius.circular(16)),
      padding: EdgeInsets.zero,
      blur: 18,
      opacity: 0.74,
      child: Semantics(
        label: 'Search notes and tags',
        textField: true,
        child: SearchBar(
          key: const Key('notes-search-field'),
          controller: _controller,
          focusNode: _focusNode,
          hintText: 'Search titles, content, and tags',
          constraints: const BoxConstraints(minHeight: 52),
          elevation: const WidgetStatePropertyAll(0),
          backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: const WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
          ),
          leading: SizedBox.square(
            dimension: 48,
            child: ExcludeSemantics(
              child: Icon(Icons.search, color: colorScheme.onSurfaceVariant),
            ),
          ),
          trailing: [
            if (query.isNotEmpty)
              SizedBox.square(
                dimension: 48,
                child: IconButton(
                  key: const Key('notes-search-clear-icon'),
                  tooltip: 'Clear search',
                  onPressed: _clearSearch,
                  icon: const Icon(Icons.close),
                ),
              ),
            Semantics(
              label: 'Filter search results',
              button: true,
              expanded: _filtersOpen,
              onTap: _openFilters,
              excludeSemantics: true,
              child: SizedBox.square(
                key: const Key('notes-search-filter'),
                dimension: 48,
                child: IconButton(
                  tooltip: 'Filter search results',
                  onPressed: _openFilters,
                  icon: const Icon(Icons.tune),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildState({
    required AsyncValue<List<Note>> notesState,
    required String query,
    required List<Note> results,
    required List<String> tags,
    required String? selectedTag,
    required NoteSort sort,
  }) {
    if (!notesState.hasValue && notesState.isLoading) {
      return const _LoadingState(key: ValueKey('loading'));
    }
    if (!notesState.hasValue && notesState.hasError) {
      return _InitialErrorState(
        key: const ValueKey('initial-error'),
        onRetry: _retry,
      );
    }

    final notes = notesState.value ?? const <Note>[];
    final cachedError = notesState.hasError;
    final state = switch ((
      notes.isEmpty,
      query.trim().isEmpty,
      results.isEmpty,
    )) {
      (true, _, _) => const _NoNotesState(key: ValueKey('no-notes')),
      (false, true, _) => _SearchInvitation(
        key: const ValueKey('invitation'),
        tags: tags,
        onTagSelected: _searchTag,
      ),
      (false, false, true) => _NoMatchesState(
        key: ValueKey('no-match-$query-$selectedTag-$sort'),
        query: query.trim(),
        hasFilters: selectedTag != null || sort != NoteSort.newest,
        onClear: _clearSearch,
        onResetFilters: _resetFilters,
      ),
      _ => _SearchResults(
        key: ValueKey('results-$query-$selectedTag-$sort'),
        notes: results,
        onOpen: _openNote,
        onTogglePin: _togglePin,
        onArchive: _archive,
        onTrash: _trash,
        onRestore: _restore,
        onDelete: _delete,
      ),
    };

    return Column(
      key: ValueKey('search-state-$query-$selectedTag-$sort-$cachedError'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cachedError) ...[
          const _CachedErrorNotice(),
          const SizedBox(height: 12),
        ],
        state,
      ],
    );
  }

  void _publishControllerText() {
    if (_syncingQuery) return;
    final text = _controller.text;
    if (ref.read(searchQueryProvider) != text) {
      ref.read(searchQueryProvider.notifier).setQuery(text);
    }
  }

  void _synchronizeController(String query) {
    if (_controller.text == query) return;
    final selection = _controller.selection;
    final baseOffset = selection.isValid
        ? selection.baseOffset.clamp(0, query.length)
        : query.length;
    final extentOffset = selection.isValid
        ? selection.extentOffset.clamp(0, query.length)
        : query.length;
    _syncingQuery = true;
    _controller.value = TextEditingValue(
      text: query,
      selection: TextSelection(
        baseOffset: baseOffset,
        extentOffset: extentOffset,
      ),
    );
    _syncingQuery = false;
  }

  void _clearSearch() {
    ref.read(searchQueryProvider.notifier).setQuery('');
    _focusAfterFrame();
  }

  void _searchTag(String tag) {
    ref.read(searchQueryProvider.notifier).setQuery(tag);
    _focusAfterFrame();
  }

  void _resetFilters() {
    ref.read(selectedTagProvider.notifier).select(null);
    ref.read(sortOrderProvider.notifier).set(NoteSort.newest);
  }

  void _focusAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _openFilters() async {
    if (_filtersOpen) return;
    setState(() => _filtersOpen = true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NoteFilterSheet(),
    );
    if (mounted) setState(() => _filtersOpen = false);
  }

  Future<void> _retry() async {
    try {
      final refresh = ref.refresh(notesProvider.future);
      await refresh;
    } catch (error) {
      _showError(error);
    }
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

  Future<void> _togglePin(Note note) {
    return _runMutation(() => ref.read(notesProvider.notifier).togglePin(note));
  }

  Future<void> _archive(Note note) {
    return _runMutation(
      () => ref.read(notesProvider.notifier).archiveNote(note),
    );
  }

  Future<void> _trash(Note note) {
    return _runMutation(() => ref.read(notesProvider.notifier).trashNote(note));
  }

  Future<void> _restore(Note note) {
    return _runMutation(
      () => ref.read(notesProvider.notifier).restoreNote(note),
    );
  }

  Future<void> _delete(Note note) {
    final id = note.id;
    if (id == null) return Future.value();
    return _runMutation(() => ref.read(notesProvider.notifier).deleteNote(id));
  }

  Future<void> _runMutation(Future<void> Function() mutation) async {
    try {
      await mutation();
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Could not update notes: $error'),
        ),
      );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      key: Key('notes-search-loading'),
      height: 160,
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _InitialErrorState extends StatelessWidget {
  const _InitialErrorState({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _CenteredState(
      icon: Icons.cloud_off_outlined,
      title: 'Could not load notes',
      body: 'Check your connection and try again.',
      action: SizedBox(
        height: 48,
        child: FilledButton(onPressed: onRetry, child: const Text('Try again')),
      ),
    );
  }
}

class _NoNotesState extends StatelessWidget {
  const _NoNotesState({super.key});

  @override
  Widget build(BuildContext context) {
    return _CenteredState(
      icon: Icons.note_add_outlined,
      title: 'No notes yet',
      body: 'Create a note, then come back here to find it quickly.',
      action: SizedBox(
        height: 48,
        child: FilledButton.icon(
          onPressed: () => context.push('/note/new'),
          icon: const Icon(Icons.add),
          label: const Text('Create note'),
        ),
      ),
    );
  }
}

class _SearchInvitation extends StatelessWidget {
  const _SearchInvitation({
    required this.tags,
    required this.onTagSelected,
    super.key,
  });

  final List<String> tags;
  final ValueChanged<String> onTagSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Search your thoughts',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Look through note titles, content, and tags.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (tags.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Suggested tags',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in tags)
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: ActionChip(
                    key: ValueKey('suggested-tag-$tag'),
                    label: Text(tag),
                    tooltip: 'Search tag $tag',
                    onPressed: () => onTagSelected(tag),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _NoMatchesState extends StatelessWidget {
  const _NoMatchesState({
    required this.query,
    required this.hasFilters,
    required this.onClear,
    required this.onResetFilters,
    super.key,
  });

  final String query;
  final bool hasFilters;
  final VoidCallback onClear;
  final VoidCallback onResetFilters;

  @override
  Widget build(BuildContext context) {
    return _CenteredState(
      icon: Icons.search_off,
      title: 'No notes match “$query”',
      body: 'Try another phrase or adjust your filters.',
      action: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: onClear,
              child: const Text('Clear search'),
            ),
          ),
          if (hasFilters)
            SizedBox(
              height: 48,
              child: TextButton(
                onPressed: onResetFilters,
                child: const Text('Reset filters'),
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchResults extends StatelessWidget {
  const _SearchResults({
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
  final ValueChanged<Note> onOpen;
  final Future<void> Function(Note) onTogglePin;
  final Future<void> Function(Note) onArchive;
  final Future<void> Function(Note) onTrash;
  final Future<void> Function(Note) onRestore;
  final Future<void> Function(Note) onDelete;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${notes.length} ${notes.length == 1 ? 'result' : 'results'}',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        for (var index = 0; index < notes.length; index++) ...[
          if (index > 0) const SizedBox(height: 12),
          SizedBox(
            key: ValueKey('search-result-note-${notes[index].id}'),
            width: double.infinity,
            child: GlassNoteCard(
              note: notes[index],
              onOpen: () => onOpen(notes[index]),
              onTogglePin: () => onTogglePin(notes[index]),
              onArchive: () => onArchive(notes[index]),
              onTrash: () => onTrash(notes[index]),
              onRestore: () => onRestore(notes[index]),
              onDelete: () => onDelete(notes[index]),
            ),
          ),
        ],
      ],
    );
  }
}

class _CachedErrorNotice extends StatelessWidget {
  const _CachedErrorNotice();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, color: colorScheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Could not refresh notes. Showing saved notes.',
                  style: TextStyle(color: colorScheme.onErrorContainer),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.body,
    required this.action,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 40, color: theme.colorScheme.primary),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          action,
        ],
      ),
    );
  }
}

double _horizontalInset(double viewportWidth) {
  final gutter = viewportWidth >= 600 ? 24.0 : 16.0;
  return ((viewportWidth - 840) / 2).clamp(gutter, double.infinity).toDouble();
}
