import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_clean_notes/app/app_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/note_card.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/add_edit_note_page.dart';
import 'package:share_plus/share_plus.dart';

class NotesPage extends ConsumerStatefulWidget {
  const NotesPage({super.key});

  @override
  ConsumerState<NotesPage> createState() => _NotesPageState();
}

class _NotesPageState extends ConsumerState<NotesPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<List<dynamic>> _currentNotes() async {
    return ref.read(notesProvider).value ?? const [];
  }

  Future<void> _exportAsText() async {
    final notes = await _currentNotes();
    final buffer = StringBuffer();
    for (final note in notes) {
      if (note.title.isNotEmpty) buffer.writeln('# ${note.title}');
      buffer.writeln(note.content);
      if (note.tags.isNotEmpty) buffer.writeln('Tags: ${note.tags.join(', ')}');
      buffer.writeln();
    }
    await SharePlus.instance.share(
      ShareParams(
        text: buffer.toString().trim().isEmpty
            ? 'No notes to export.'
            : buffer.toString(),
        subject: 'My Notes',
      ),
    );
  }

  Future<void> _showSortDialog(BuildContext context, WidgetRef ref) async {
    final sort = await showDialog<NoteSort>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sort Notes'),
        content: SimpleDialog(
          children: NoteSort.values
              .map(
                (option) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(context, option),
                  child: Text(_sortLabel(option)),
                ),
              )
              .toList(),
        ),
      ),
    );
    if (sort != null) {
      ref.read(sortOrderProvider.notifier).set(sort);
    }
  }

  String _sortLabel(NoteSort sort) {
    switch (sort) {
      case NoteSort.newest:
        return 'Newest first';
      case NoteSort.oldest:
        return 'Oldest first';
      case NoteSort.titleAZ:
        return 'Title A-Z';
      case NoteSort.titleZA:
        return 'Title Z-A';
    }
  }

  Future<void> _showTagManager(BuildContext context, WidgetRef ref) async {
    final allTags = ref.watch(allTagsProvider);
    await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Manage Tags'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final tag in allTags)
                ListTile(
                  title: Text('#$tag'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () => _deleteTag(tag, ref),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTag(String tag, WidgetRef ref) async {
    final notes = ref.read(notesProvider).value ?? const [];
    for (final note in notes) {
      if (note.tags.contains(tag)) {
        final updatedTags = note.tags.where((t) => t != tag).toList();
        final updatedNote = note.copyWith(tags: updatedTags);
        await ref.read(notesProvider.notifier).updateNote(updatedNote);
      }
    }
  }

  Future<void> _exportAsJson() async {
    final notes = ref.read(notesProvider).value ?? const [];
    final payload = notes
        .map(
          (note) => {
            'title': note.title,
            'content': note.content,
            'color': note.color,
            'createdAt': note.createdAt.toIso8601String(),
            'isPinned': note.isPinned,
            'tags': note.tags,
            'status': note.status.name,
            'reminder': note.reminder?.toIso8601String(),
          },
        )
        .toList();
    final file = XFile.fromData(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
      mimeType: 'application/json',
    );
    await SharePlus.instance.share(
      ShareParams(files: [file], fileNameOverrides: ['notes_backup.json']),
    );
  }

  Future<void> _exportAsMarkdown() async {
    final notes = ref.read(notesProvider).value ?? const [];
    final buffer = StringBuffer();
    for (final note in notes) {
      buffer.writeln('# ${note.title}');
      buffer.writeln('');
      buffer.writeln(note.content);
      if (note.tags.isNotEmpty) {
        buffer.writeln('');
        buffer.writeln('Tags: ${note.tags.map((t) => '#$t').join(', ')}');
      }
      buffer.writeln('');
      buffer.writeln('---');
      buffer.writeln('');
    }
    final file = XFile.fromData(
      utf8.encode(buffer.toString()),
      mimeType: 'text/markdown',
    );
    await SharePlus.instance.share(
      ShareParams(files: [file], fileNameOverrides: ['notes.md']),
    );
  }

  Future<void> _importBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final content = await file.xFile.readAsString();
    final jsonList = json.decode(content) as List<dynamic>;
    final data = jsonList.cast<Map<String, dynamic>>();
    await ref.read(notesProvider.notifier).importBackup(data);
  }

  @override
  Widget build(BuildContext context) {
    final notesState = ref.watch(notesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'My Notes',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Toggle theme',
            icon: const Icon(Icons.brightness_6_outlined),
            onPressed: () {
              final current =
                  ref.read(appThemeProvider).value ?? ThemeMode.system;
              final next = current == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark;
              ref.read(appThemeProvider.notifier).setMode(next);
            },
          ),
          IconButton(
            tooltip: 'Sort notes',
            icon: const Icon(Icons.sort),
            onPressed: () => _showSortDialog(context, ref),
          ),
          IconButton(
            tooltip: 'Tag manager',
            icon: const Icon(Icons.label),
            onPressed: () => _showTagManager(context, ref),
          ),
          PopupMenuButton<String>(
            tooltip: 'Export',
            icon: const Icon(Icons.ios_share),
            onSelected: (value) {
              if (value == 'text') {
                _exportAsText();
              } else if (value == 'json') {
                _exportAsJson();
              } else if (value == 'markdown') {
                _exportAsMarkdown();
              } else if (value == 'import') {
                _importBackup();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'text', child: Text('Export as text')),
              PopupMenuItem(value: 'json', child: Text('Backup as JSON')),
              PopupMenuItem(
                value: 'markdown',
                child: Text('Export as Markdown'),
              ),
              PopupMenuItem(value: 'import', child: Text('Import backup')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<NoteMode>(
                segments: const [
                  ButtonSegment(value: NoteMode.active, label: Text('Notes')),
                  ButtonSegment(
                    value: NoteMode.archived,
                    label: Text('Archive'),
                  ),
                  ButtonSegment(value: NoteMode.trashed, label: Text('Trash')),
                ],
                selected: {ref.watch(noteModeProvider)},
                onSelectionChanged: (selection) {
                  ref.read(noteModeProvider.notifier).set(selection.first);
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              controller: _searchController,
              onChanged: (value) =>
                  ref.read(searchQueryProvider.notifier).setQuery(value),
              decoration: InputDecoration(
                hintText: 'Search notes...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _searchController,
                  builder: (context, value, _) {
                    if (value.text.isEmpty) return const SizedBox.shrink();
                    return IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(searchQueryProvider.notifier).setQuery('');
                      },
                    );
                  },
                ),
                filled: true,
                fillColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: notesState.when(
              data: (notes) {
                final mode = ref.watch(noteModeProvider);
                final filteredNotes = ref.watch(filteredNotesProvider);
                final tags = ref.watch(allTagsProvider);
                final selectedTag = ref.watch(selectedTagProvider);
                if (filteredNotes.isEmpty) {
                  final base = switch (mode) {
                    NoteMode.active => 'No notes yet. Add one!',
                    NoteMode.archived => 'No archived notes.',
                    NoteMode.trashed => 'Trash is empty.',
                  };
                  return _EmptyState(
                    message: notes.isEmpty
                        ? base
                        : selectedTag == null
                        ? 'No notes match your search.'
                        : 'No notes have the tag "$selectedTag".',
                  );
                }
                return Column(
                  children: [
                    if (tags.isNotEmpty)
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: const Text('All'),
                                selected: selectedTag == null,
                                onSelected: (_) => ref
                                    .read(selectedTagProvider.notifier)
                                    .select(null),
                              ),
                            ),
                            for (final tag in tags)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(tag),
                                  selected: selectedTag == tag,
                                  onSelected: (_) => ref
                                      .read(selectedTagProvider.notifier)
                                      .select(tag),
                                ),
                              ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final width = constraints.maxWidth;
                          final crossAxisCount = width >= 1100
                              ? 4
                              : width >= 700
                              ? 3
                              : 2;
                          return GridView.builder(
                            padding: const EdgeInsets.all(16),
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: crossAxisCount,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                  childAspectRatio: 0.8,
                                ),
                            itemCount: filteredNotes.length,
                            itemBuilder: (context, index) {
                              final note = filteredNotes[index];
                              return NoteCard(
                                note: note,
                                onTap: () {
                                  context.push('/note/${note.id}');
                                },
                                onTogglePin: () {
                                  ref
                                      .read(notesProvider.notifier)
                                      .togglePin(note);
                                },
                                onArchive: () {
                                  ref
                                      .read(notesProvider.notifier)
                                      .archiveNote(note);
                                },
                                onRestore: () {
                                  ref
                                      .read(notesProvider.notifier)
                                      .restoreNote(note);
                                },
                                onTrash: () {
                                  ref
                                      .read(notesProvider.notifier)
                                      .trashNote(note);
                                },
                                onDelete: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Delete Note'),
                                      content: const Text(
                                        'Are you sure you want to delete this note?',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              context.pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              context.pop(true),
                                          child: const Text(
                                            'Delete',
                                            style: TextStyle(color: Colors.red),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    ref
                                        .read(notesProvider.notifier)
                                        .deleteNote(note.id!);
                                  }
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Text(
                  'Error: $error',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: ref.watch(noteModeProvider) == NoteMode.active
          ? FloatingActionButton(
              onPressed: () {
                context.push('/note/new');
              },
              tooltip: 'New note',
              elevation: 2,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;

  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sticky_note_2_outlined,
              size: 56,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
