import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_clean_notes/app/widgets/aurora_background.dart';
import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/search_focus_request.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/persisted_note_mutation_exception.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/glass_note_card.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/note_filter_sheet.dart';

const _searchHeaderItemCount = 5;

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
    final viewState = _resolveSearchViewState(
      notesState: notesState,
      query: query,
      results: results,
    );
    final activeFilterCount =
        (selectedTag == null ? 0 : 1) + (sort == NoteSort.newest ? 0 : 1);
    final duration = mediaQuery.disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 200);
    final showingResults = viewState == _SearchViewState.results;
    final resultCount = showingResults ? results.length : 0;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AuroraBackground(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalInset = _horizontalInset(constraints.maxWidth);
            return ListView.builder(
              key: const PageStorageKey('notes-search-scroll'),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                horizontalInset,
                24,
                horizontalInset,
                mediaQuery.viewInsets.bottom + 120,
              ),
              itemCount: _searchHeaderItemCount + resultCount,
              findChildIndexCallback: (key) {
                if (!showingResults) return null;
                final resultIndex = results.indexWhere(
                  (note) =>
                      key == ValueKey<String>('search-result-note-${note.id}'),
                );
                if (resultIndex == -1) return null;
                return _searchHeaderItemCount + resultIndex;
              },
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Text(
                    'Search',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  );
                }
                if (index == 1 || index == 3) {
                  return const SizedBox(height: 16);
                }
                if (index == 2) {
                  return _buildSearchBar(query, activeFilterCount);
                }
                if (index == 4) {
                  return _buildState(
                    viewState: viewState,
                    query: query,
                    results: results,
                    tags: tags,
                    selectedTag: selectedTag,
                    sort: sort,
                    duration: duration,
                  );
                }

                final resultIndex = index - _searchHeaderItemCount;
                final note = results[resultIndex];
                return Padding(
                  key: ValueKey<String>('search-result-note-${note.id}'),
                  padding: EdgeInsets.only(
                    bottom: resultIndex == results.length - 1 ? 0 : 12,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: GlassNoteCard(
                      note: note,
                      onOpen: () => _openNote(note),
                      onTogglePin: () => _togglePin(note),
                      onArchive: () => _archive(note),
                      onTrash: () => _trash(note),
                      onRestore: () => _restore(note),
                      onDelete: () => _delete(note),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildSearchBar(String query, int activeFilterCount) {
    final colorScheme = Theme.of(context).colorScheme;
    final filterLabel = 'Search filters, $activeFilterCount active';
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
              label: filterLabel,
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
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Icon(Icons.tune),
                      if (activeFilterCount > 0)
                        PositionedDirectional(
                          top: -8,
                          end: -10,
                          child: Container(
                            key: const Key('notes-search-filter-badge'),
                            constraints: const BoxConstraints(
                              minWidth: 18,
                              minHeight: 18,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$activeFilterCount',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: colorScheme.onPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildState({
    required _SearchViewState viewState,
    required String query,
    required List<Note> results,
    required List<String> tags,
    required String? selectedTag,
    required NoteSort sort,
    required Duration duration,
  }) {
    final state = switch (viewState) {
      _SearchViewState.loading => const _LoadingState(key: ValueKey('loading')),
      _SearchViewState.initialError => _InitialErrorState(
        key: const ValueKey('initial-error'),
        onRetry: _retry,
      ),
      _SearchViewState.noNotes => const _NoNotesState(
        key: ValueKey('no-notes'),
      ),
      _SearchViewState.invitation => _SearchInvitation(
        key: const ValueKey('invitation'),
        tags: tags,
        onTagSelected: _searchTag,
      ),
      _SearchViewState.noMatches => _NoMatchesState(
        key: const ValueKey('no-matches'),
        query: query.trim(),
        hasFilters: selectedTag != null || sort != NoteSort.newest,
        onClear: _clearSearch,
        onResetFilters: _resetFilters,
      ),
      _SearchViewState.results => const SizedBox.shrink(
        key: ValueKey('results'),
      ),
    };
    final searchStatus = switch (viewState) {
      _SearchViewState.results => _SearchStatus(
        label:
            '${results.length} ${results.length == 1 ? 'result' : 'results'}',
        visible: true,
      ),
      _SearchViewState.noMatches => const _SearchStatus(
        label: 'No notes match your search',
        visible: false,
      ),
      _ => null,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (searchStatus != null) ...[
          searchStatus,
          if (viewState == _SearchViewState.results) const SizedBox(height: 12),
        ],
        AnimatedSwitcher(
          key: const Key('notes-search-switcher'),
          duration: duration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: state,
        ),
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
      useRootNavigator: true,
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
    } catch (_) {
      _showError('Could not refresh notes. Try again.');
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

  Future<void> _togglePin(Note note) async {
    await _runMutation(() => ref.read(notesProvider.notifier).togglePin(note));
  }

  Future<void> _archive(Note note) async {
    final result = await _runMutation(
      () => ref.read(notesProvider.notifier).archiveNote(note),
    );
    if (result != _MutationResult.failed) {
      _showUndo(
        note,
        'Note archived',
        refreshFailed: result == _MutationResult.persistedRefreshFailure,
      );
    }
  }

  Future<void> _trash(Note note) async {
    final result = await _runMutation(
      () => ref.read(notesProvider.notifier).trashNote(note),
    );
    if (result != _MutationResult.failed) {
      _showUndo(
        note,
        'Note moved to trash',
        refreshFailed: result == _MutationResult.persistedRefreshFailure,
      );
    }
  }

  Future<void> _restore(Note note) async {
    await _runMutation(
      () => ref.read(notesProvider.notifier).restoreNote(note),
    );
  }

  Future<void> _delete(Note note) async {
    final id = note.id;
    if (id == null) return;
    await _runMutation(() => ref.read(notesProvider.notifier).deleteNote(id));
  }

  Future<_MutationResult> _runMutation(Future<void> Function() mutation) async {
    try {
      await mutation();
      return _MutationResult.succeeded;
    } on PersistedNoteMutationException {
      return _MutationResult.persistedRefreshFailure;
    } catch (_) {
      _showError('Could not update this note. Try again.');
      return _MutationResult.failed;
    }
  }

  void _showUndo(Note note, String message, {required bool refreshFailed}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            refreshFailed
                ? '$message. Could not refresh notes; showing saved notes.'
                : message,
          ),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => unawaited(_restore(note)),
          ),
        ),
      );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
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
      body: 'Please try again in a moment.',
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

class _SearchStatus extends StatelessWidget {
  const _SearchStatus({required this.label, required this.visible});

  final String label;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const Key('notes-search-status'),
      container: true,
      liveRegion: true,
      label: label,
      child: visible
          ? ExcludeSemantics(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            )
          : const SizedBox.shrink(),
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

enum _SearchViewState {
  loading,
  initialError,
  noNotes,
  invitation,
  noMatches,
  results,
}

enum _MutationResult { succeeded, persistedRefreshFailure, failed }

_SearchViewState _resolveSearchViewState({
  required AsyncValue<List<Note>> notesState,
  required String query,
  required List<Note> results,
}) {
  if (!notesState.hasValue && notesState.isLoading) {
    return _SearchViewState.loading;
  }
  if (!notesState.hasValue && notesState.hasError) {
    return _SearchViewState.initialError;
  }

  final notes = notesState.value ?? const <Note>[];
  if (notes.isEmpty) return _SearchViewState.noNotes;
  if (query.trim().isEmpty) return _SearchViewState.invitation;
  if (results.isEmpty) return _SearchViewState.noMatches;
  return _SearchViewState.results;
}
