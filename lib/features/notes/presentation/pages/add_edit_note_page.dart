import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_clean_notes/app/widgets/aurora_background.dart';
import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/persisted_note_save_exception.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/editor_formatting_bar.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/note_metadata_sheet.dart';

class AddEditNotePage extends ConsumerStatefulWidget {
  const AddEditNotePage({super.key, this.note, this.onClose});

  final Note? note;
  final VoidCallback? onClose;

  @override
  ConsumerState<AddEditNotePage> createState() => _AddEditNotePageState();
}

class _AddEditNotePageState extends ConsumerState<AddEditNotePage> {
  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final FocusNode _titleFocusNode;
  late final FocusNode _contentFocusNode;
  late final ScrollController _shortLayoutScrollController;
  late final DateTime _createdAt;
  late final NoteStatus _status;
  late final bool _isPinned;

  int? _persistedId;
  late Color _selectedColor;
  late List<String> _tags;
  late DateTime? _reminder;
  bool _previewMode = false;
  bool _saving = false;
  bool _closed = false;
  bool _allowPop = false;
  bool _hasPartialSave = false;
  String? _validationMessage;
  _EditorSaveError? _saveError;
  _EditorFocusIntent _focusIntent = _EditorFocusIntent.none;
  bool _shortScrollPending = false;
  bool _shortScrollToEnd = false;

  @override
  void initState() {
    super.initState();
    final note = widget.note;
    _titleController = TextEditingController(text: note?.title ?? '');
    _contentController = TextEditingController(text: note?.content ?? '');
    _titleFocusNode = FocusNode(debugLabel: 'Note title');
    _contentFocusNode = FocusNode(debugLabel: 'Note content');
    _shortLayoutScrollController = ScrollController();
    _titleFocusNode.addListener(_handleTitleFocus);
    _contentFocusNode.addListener(_handleContentFocus);
    _persistedId = note?.id;
    _createdAt = note?.createdAt ?? DateTime.now();
    _status = note?.status ?? NoteStatus.active;
    _isPinned = note?.isPinned ?? false;
    _selectedColor = note == null ? Colors.white : Color(note.color);
    _tags = List<String>.of(note?.tags ?? const []);
    _reminder = note?.reminder;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _titleFocusNode.removeListener(_handleTitleFocus);
    _contentFocusNode.removeListener(_handleContentFocus);
    _titleFocusNode.dispose();
    _contentFocusNode.dispose();
    _shortLayoutScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notesProvider);
    final navigatorCanPop = Navigator.of(context).canPop();
    final canPop =
        !_saving && (_allowPop || (navigatorCanPop && !_hasPartialSave));
    final media = MediaQuery.of(context);
    final duration = media.disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 200);

    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || _saving) return;
        _requestClose();
      },
      child: Scaffold(
        key: const Key('note-editor-page'),
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: AuroraBackground(
          child: AnimatedPadding(
            duration: duration,
            curve: Curves.easeOutCubic,
            padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final gutter = constraints.maxWidth >= 600 ? 24.0 : 16.0;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: gutter),
                      child: _buildPageLayout(constraints),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPageLayout(BoxConstraints constraints) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final shortKeyboardLayout =
        !_previewMode &&
        keyboardVisible &&
        constraints.maxHeight < (constraints.maxWidth >= 480 ? 260 : 480);
    if (shortKeyboardLayout) {
      final textScale = MediaQuery.textScalerOf(context).scale(1);
      final editorHeight = constraints.maxWidth >= 480
          ? 144.0
          : (440 * textScale).clamp(480.0, 960.0).toDouble();
      if (_titleFocusNode.hasFocus) {
        _scheduleShortFieldReveal(toEnd: false);
      } else if (_contentFocusNode.hasFocus) {
        _scheduleShortFieldReveal(toEnd: true);
      }
      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              key: const Key('editor-short-layout-scroll'),
              controller: _shortLayoutScrollController,
              child: Column(
                children: [
                  _buildTopBar(),
                  const SizedBox(height: 8),
                  SizedBox(height: editorHeight, child: _buildEditorSurface()),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildFormattingSurface(),
        ],
      );
    }

    return Column(
      children: [
        _buildTopBar(),
        const SizedBox(height: 8),
        Expanded(child: _buildEditorSurface()),
        if (!_previewMode) ...[
          const SizedBox(height: 8),
          _buildFormattingSurface(),
        ],
      ],
    );
  }

  Widget _buildTopBar() {
    return SizedBox(
      key: const Key('editor-top-bar'),
      height: 56,
      child: GlassSurface(
        opacity: 0.78,
        blur: 18,
        borderRadius: BorderRadius.circular(16),
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            BackButton(
              key: const Key('editor-back-button'),
              onPressed: _saving ? null : _requestClose,
            ),
            IconButton(
              key: const Key('editor-preview-toggle'),
              tooltip: _previewMode ? 'Edit' : 'Preview',
              onPressed: _saving ? null : _togglePreview,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: Icon(
                _previewMode ? Icons.edit_rounded : Icons.visibility_rounded,
              ),
            ),
            IconButton(
              key: const Key('editor-metadata-button'),
              tooltip: 'Note details',
              onPressed: _saving ? null : _openMetadata,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              icon: const Icon(Icons.tune_rounded),
            ),
            const Spacer(),
            TextButton(
              key: const Key('editor-done-button'),
              onPressed: _saving ? null : _saveNote,
              style: TextButton.styleFrom(
                minimumSize: const Size(64, 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: _saving
                  ? Semantics(
                      liveRegion: true,
                      label: 'Saving note',
                      child: const SizedBox(
                        key: Key('editor-save-progress'),
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    )
                  : const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditorSurface() {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GlassSurface(
      key: const Key('editor-surface'),
      opacity: dark ? 0.92 : 0.90,
      blur: 18,
      borderRadius: BorderRadius.circular(28),
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth >= 600 ? 24.0 : 16.0;
          final verticalPadding = constraints.maxHeight < 160
              ? 8.0
              : horizontalPadding;
          return Padding(
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: _previewMode
                ? _buildPreview()
                : constraints.maxHeight < 260 && constraints.maxWidth >= 480
                ? _buildLandscapeEditor()
                : _buildEditor(),
          );
        },
      ),
    );
  }

  Widget _buildEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFieldLabel('Title'),
        const SizedBox(height: 4),
        _buildTitleField(maxLines: 2),
        ..._buildEditorFeedback(),
        const SizedBox(height: 16),
        _buildFieldLabel('Note content'),
        const SizedBox(height: 4),
        Expanded(child: _buildBodyField()),
      ],
    );
  }

  Widget _buildLandscapeEditor() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 2,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFieldLabel('Title'),
                const SizedBox(height: 4),
                _buildTitleField(maxLines: 1),
                ..._buildEditorFeedback(),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFieldLabel('Note content'),
              const SizedBox(height: 4),
              Expanded(child: _buildBodyField()),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFieldLabel(String label) {
    final theme = Theme.of(context);
    return ExcludeSemantics(
      child: Text(
        label,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildTitleField({required int maxLines}) {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Title',
      child: TextField(
        key: const Key('editor-title-field'),
        controller: _titleController,
        focusNode: _titleFocusNode,
        enabled: !_saving,
        maxLines: maxLines,
        minLines: 1,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => _contentFocusNode.requestFocus(),
        style: theme.textTheme.headlineMedium?.copyWith(
          fontSize: 28,
          height: 32 / 28,
          fontWeight: FontWeight.w700,
        ),
        decoration: const InputDecoration(
          hintText: 'Untitled note',
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 4),
        ),
      ),
    );
  }

  Widget _buildBodyField() {
    final theme = Theme.of(context);
    return Semantics(
      label: 'Note content',
      child: TextField(
        key: const Key('editor-body-field'),
        controller: _contentController,
        focusNode: _contentFocusNode,
        enabled: !_saving,
        expands: true,
        minLines: null,
        maxLines: null,
        textAlignVertical: TextAlignVertical.top,
        keyboardType: TextInputType.multiline,
        style: theme.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
        decoration: const InputDecoration(
          hintText: 'Start writing…',
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(vertical: 4),
        ),
      ),
    );
  }

  List<Widget> _buildEditorFeedback() {
    final theme = Theme.of(context);
    return [
      if (_validationMessage case final message?) ...[
        const SizedBox(height: 6),
        Semantics(
          key: const Key('editor-validation'),
          liveRegion: true,
          child: Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
      if (_saveError case final error?) ...[
        const SizedBox(height: 8),
        _buildSaveError(error),
      ],
    ];
  }

  Widget _buildPreview() {
    final theme = Theme.of(context);
    final title = _titleController.text.trim();
    final content = _contentController.text;
    return SingleChildScrollView(
      key: const Key('editor-preview'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Title',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title.isEmpty ? 'Untitled note' : title,
            key: const Key('editor-preview-title'),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontSize: 28,
              height: 32 / 28,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (_saveError case final error?) ...[
            const SizedBox(height: 12),
            _buildSaveError(error),
          ],
          const SizedBox(height: 24),
          Text(
            'Note content',
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          MarkdownBody(
            data: content.isEmpty ? '_Nothing to preview._' : content,
            onTapLink: _saving
                ? null
                : (text, href, title) {
                    if (href != null && href.startsWith('note://')) {
                      _openLinkedNote(href.substring('note://'.length));
                    }
                  },
          ),
        ],
      ),
    );
  }

  Widget _buildSaveError(_EditorSaveError error) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      key: const Key('editor-save-error'),
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                error.heading,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                error.detail,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: TextButton.icon(
                  key: const Key('editor-retry-button'),
                  onPressed: _saving ? null : _saveNote,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormattingSurface() {
    return GlassSurface(
      key: const Key('editor-formatting-bar'),
      opacity: 0.82,
      blur: 18,
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: EditorFormattingBar(
        controller: _contentController,
        enabled: !_saving,
      ),
    );
  }

  void _handleTitleFocus() {
    if (_titleFocusNode.hasFocus) _scheduleShortFieldReveal(toEnd: false);
  }

  void _handleContentFocus() {
    if (_contentFocusNode.hasFocus) _scheduleShortFieldReveal(toEnd: true);
  }

  void _scheduleShortFieldReveal({required bool toEnd}) {
    _shortScrollToEnd = toEnd;
    if (_shortScrollPending) return;
    _shortScrollPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _shortScrollPending = false;
      if (!mounted || !_shortLayoutScrollController.hasClients) return;
      final position = _shortLayoutScrollController.position;
      final target = _shortScrollToEnd
          ? position.maxScrollExtent
          : 64.0.clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((position.pixels - target).abs() < 0.5) return;
      if (MediaQuery.of(context).disableAnimations) {
        _shortLayoutScrollController.jumpTo(target);
      } else {
        _shortLayoutScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  void _togglePreview() {
    if (_previewMode) {
      setState(() => _previewMode = false);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (_focusIntent) {
          case _EditorFocusIntent.title:
            _titleFocusNode.requestFocus();
          case _EditorFocusIntent.content:
            _contentFocusNode.requestFocus();
          case _EditorFocusIntent.none:
            break;
        }
      });
      return;
    }

    _focusIntent = _titleFocusNode.hasFocus
        ? _EditorFocusIntent.title
        : _contentFocusNode.hasFocus
        ? _EditorFocusIntent.content
        : _EditorFocusIntent.none;
    FocusScope.of(context).unfocus();
    setState(() => _previewMode = true);
  }

  Future<void> _openMetadata() async {
    final value = await showModalBottomSheet<NoteMetadataValue>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (context) => NoteMetadataSheet(
        initialValue: NoteMetadataValue(
          color: _selectedColor,
          tags: _tags,
          reminder: _reminder,
        ),
      ),
    );
    if (!mounted || value == null) return;
    setState(() {
      _selectedColor = value.color;
      _tags = List<String>.of(value.tags);
      _reminder = value.reminder;
    });
  }

  Future<void> _saveNote() async {
    if (_saving || _closed) return;
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();
    if (title.isEmpty && content.isEmpty) {
      setState(() {
        _previewMode = false;
        _validationMessage = 'Add a title or some content';
        _saveError = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _titleFocusNode.requestFocus();
      });
      return;
    }

    final note = Note(
      id: _persistedId,
      title: title,
      content: content,
      color: _selectedColor.toARGB32(),
      createdAt: _createdAt,
      isPinned: _isPinned,
      tags: List<String>.unmodifiable(_tags),
      status: _status,
      reminder: _reminder,
    );
    setState(() {
      _saving = true;
      _validationMessage = null;
      _saveError = null;
    });

    try {
      final notifier = ref.read(notesProvider.notifier);
      if (_persistedId == null) {
        await notifier.addNote(note);
      } else {
        await notifier.updateNote(note);
      }
      if (!mounted) return;
      _saving = false;
      _requestClose();
    } on PersistedNoteSaveException catch (error) {
      final persistedId = error.persistedNote.id;
      if (persistedId != null) _persistedId = persistedId;
      _hasPartialSave = true;
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = const _EditorSaveError(
          heading: 'Couldn’t finish saving note',
          detail: 'Your note is saved, but finishing needs another try.',
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = const _EditorSaveError(
          heading: 'Couldn’t save note',
          detail: 'Your changes are still here. Try again.',
        );
      });
    }
  }

  void _openLinkedNote(String title) {
    final notes = ref.read(notesProvider).value ?? const <Note>[];
    final normalized = title.trim().toLowerCase();
    final match = notes.where(
      (note) =>
          note.title.trim().toLowerCase() == normalized && note.id != null,
    );
    if (match.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Linked note not found. Create it first.'),
        ),
      );
      return;
    }
    if (!mounted) return;
    context.push('/note/${match.first.id}');
  }

  void _requestClose() {
    if (_saving || _closed) return;
    _closed = true;
    if (_hasPartialSave) ref.invalidate(notesProvider);

    final callback = widget.onClose;
    if (callback != null) {
      final needsPopFrame = _hasPartialSave && Navigator.of(context).canPop();
      if (needsPopFrame) {
        setState(() => _allowPop = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) callback();
        });
      } else {
        callback();
      }
      return;
    }
    if (context.canPop()) context.pop();
  }
}

enum _EditorFocusIntent { none, title, content }

class _EditorSaveError {
  const _EditorSaveError({required this.heading, required this.detail});

  final String heading;
  final String detail;
}
