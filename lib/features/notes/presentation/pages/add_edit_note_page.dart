import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_clean_notes/app/widgets/aurora_background.dart';
import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_reminder_gateway_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/invalid_note_reminder_exception.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/persisted_note_save_exception.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/editor_formatting_bar.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/note_metadata_sheet.dart';

class AddEditNotePage extends ConsumerStatefulWidget {
  const AddEditNotePage({super.key, this.note, this.onClose, this.now});

  final Note? note;
  final VoidCallback? onClose;
  final DateTime Function()? now;

  @override
  ConsumerState<AddEditNotePage> createState() => _AddEditNotePageState();
}

class _AddEditNotePageState extends ConsumerState<AddEditNotePage>
    implements PopEntry<Object?> {
  static const _reminderValidationMessage =
      'Open Note details to choose a future reminder.';

  late final TextEditingController _titleController;
  late final TextEditingController _contentController;
  late final FocusNode _titleFocusNode;
  late final FocusNode _contentFocusNode;
  late final FocusNode _metadataFocusNode;
  late final ScrollController _shortLayoutScrollController;
  late final DateTime _createdAt;
  late final NoteStatus _status;
  late final bool _isPinned;
  ModalRoute<dynamic>? _route;

  @override
  late final ValueNotifier<bool> canPopNotifier;

  int? _persistedId;
  late Color _selectedColor;
  late List<String> _tags;
  late DateTime? _reminder;
  late DateTime? _persistedReminder;
  late _EditorSnapshot _cleanSnapshot;
  bool _previewMode = false;
  bool _saving = false;
  bool _closed = false;
  bool _closePending = false;
  bool _closeRetryScheduled = false;
  bool _discardDialogOpen = false;
  bool _discardConfirmed = false;
  bool _allowPop = false;
  bool _hasPartialSave = false;
  bool _reminderReconciliationPending = false;
  bool _isDirty = false;
  String? _validationMessage;
  _EditorSaveError? _saveError;
  _EditorFocusIntent _focusIntent = _EditorFocusIntent.none;
  bool _shortScrollPending = false;
  bool _shortScrollToEnd = false;

  @override
  void initState() {
    super.initState();
    canPopNotifier = ValueNotifier<bool>(false);
    final note = widget.note;
    _titleController = TextEditingController(text: note?.title ?? '');
    _contentController = TextEditingController(text: note?.content ?? '');
    _titleFocusNode = FocusNode(debugLabel: 'Note title');
    _contentFocusNode = FocusNode(debugLabel: 'Note content');
    _metadataFocusNode = FocusNode(debugLabel: 'Note details');
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
    _persistedReminder = note?.id == null ? null : note?.reminder;
    _cleanSnapshot = _currentSnapshot();
    _titleController.addListener(_handleDraftChanged);
    _contentController.addListener(_handleDraftChanged);
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
    _titleController.removeListener(_handleDraftChanged);
    _contentController.removeListener(_handleDraftChanged);
    _titleController.dispose();
    _contentController.dispose();
    _titleFocusNode.removeListener(_handleTitleFocus);
    _contentFocusNode.removeListener(_handleContentFocus);
    _titleFocusNode.dispose();
    _contentFocusNode.dispose();
    _metadataFocusNode.dispose();
    _shortLayoutScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(notesProvider);
    final routeIsCurrent = ModalRoute.isCurrentOf(context) ?? false;
    _schedulePendingCloseIfCurrent(routeIsCurrent);
    _syncCanPop();
    final media = MediaQuery.of(context);
    final duration = media.disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 200);

    return Scaffold(
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
    );
  }

  Widget _buildPageLayout(BoxConstraints constraints) {
    final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
    final textScaler = MediaQuery.textScalerOf(context);
    final labelFontSize =
        Theme.of(context).textTheme.labelLarge?.fontSize ?? 14;
    final effectiveTextScale = textScaler.scale(labelFontSize) / labelFontSize;
    final shortKeyboardLayout =
        !_previewMode &&
        keyboardVisible &&
        constraints.maxHeight < (constraints.maxWidth >= 480 ? 260 : 480);
    final highScalePortraitLayout =
        !_previewMode &&
        constraints.maxWidth < 480 &&
        effectiveTextScale >= 2.5;
    if (shortKeyboardLayout || highScalePortraitLayout) {
      final editorHeight = constraints.maxWidth >= 480
          ? 144.0
          : highScalePortraitLayout
          ? 440 * effectiveTextScale
          : (440 * effectiveTextScale).clamp(480.0, 960.0).toDouble();
      if (_validationMessage != null) {
        _scheduleShortFieldReveal(toEnd: false);
      } else if (_titleFocusNode.hasFocus) {
        _scheduleShortFieldReveal(toEnd: false);
      } else if (_contentFocusNode.hasFocus) {
        _scheduleShortFieldReveal(toEnd: true);
      }
      return Column(
        children: [
          _buildTopBar(),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              key: const Key('editor-short-layout-scroll'),
              controller: _shortLayoutScrollController,
              child: SizedBox(
                height: editorHeight,
                child: _buildEditorSurface(),
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
    final doneFontSize = Theme.of(context).textTheme.labelLarge?.fontSize ?? 14;
    final compactDoneAction =
        MediaQuery.textScalerOf(context).scale(doneFontSize) >=
        doneFontSize * 2.5;
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
              style: IconButton.styleFrom(
                minimumSize: const Size.square(48),
                tapTargetSize: MaterialTapTargetSize.padded,
                visualDensity: VisualDensity.standard,
              ),
            ),
            IconButton(
              key: const Key('editor-preview-toggle'),
              tooltip: _previewMode ? 'Edit' : 'Preview',
              onPressed: _saving ? null : _togglePreview,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: Icon(
                _previewMode ? Icons.edit_rounded : Icons.visibility_rounded,
              ),
            ),
            IconButton(
              key: const Key('editor-metadata-button'),
              tooltip: 'Note details',
              onPressed: _saving ? null : _openMetadata,
              focusNode: _metadataFocusNode,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.tune_rounded),
            ),
            const Spacer(),
            TextButton(
              key: const Key('editor-done-button'),
              onPressed: _saving ? null : _saveNote,
              style: TextButton.styleFrom(
                minimumSize: const Size(64, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                tapTargetSize: MaterialTapTargetSize.padded,
                visualDensity: VisualDensity.standard,
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
                  : compactDoneAction
                  ? Semantics(
                      label: 'Done',
                      child: const ExcludeSemantics(
                        child: Icon(Icons.check_rounded),
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
          final padding = EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          );
          if (_previewMode) {
            return SizedBox(
              key: const Key('editor-preview'),
              width: double.infinity,
              child: Padding(padding: padding, child: _buildPreview()),
            );
          }
          return Padding(
            padding: padding,
            child: constraints.maxHeight < 260 && constraints.maxWidth >= 480
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
            imageBuilder: (_, _, altText) {
              final alt = altText?.trim();
              final label = alt == null || alt.isEmpty
                  ? 'Image unavailable'
                  : 'Image unavailable: $alt';
              return Semantics(
                key: const Key('editor-markdown-image-placeholder'),
                container: true,
                image: true,
                label: label,
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              );
            },
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
                constraints: const BoxConstraints(minHeight: 48),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
        now: widget.now,
        supportsReminderScheduling: ref
            .read(noteReminderGatewayProvider)
            .supportsScheduling,
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
      _isDirty = _currentSnapshot() != _cleanSnapshot;
    });
    _syncCanPop();
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

    final reminder = _reminder;
    final persistedReminderBeforeSave = _persistedReminder;
    final reconciliationWasPending = _reminderReconciliationPending;
    final reminderChanged = reminder != persistedReminderBeforeSave;
    final reminderNeedsReconciliation =
        reminderChanged || reconciliationWasPending;
    final now = widget.now?.call() ?? DateTime.now();
    if (reminderNeedsReconciliation &&
        reminder != null &&
        !reminder.isAfter(now)) {
      _showReminderValidationError();
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
    _syncCanPop();

    try {
      final notifier = ref.read(notesProvider.notifier);
      if (_persistedId == null) {
        await notifier.addNote(note, now: widget.now);
      } else {
        await notifier.updateNote(
          note,
          now: widget.now,
          persistedReminder: _persistedReminder,
          forceReminderReconciliation: reconciliationWasPending,
        );
      }
      if (!mounted) return;
      _saving = false;
      _reminderReconciliationPending = false;
      _markDraftClean();
      _syncCanPop();
      _requestClose();
    } on InvalidNoteReminderException {
      if (!mounted) return;
      _showReminderValidationError();
    } on PersistedNoteSaveException catch (error) {
      final persistedId = error.persistedNote.id;
      if (persistedId != null) _persistedId = persistedId;
      _persistedReminder = error.persistedNote.reminder;
      _hasPartialSave = true;
      final reminderWasInvolved =
          reconciliationWasPending ||
          reminder != null ||
          persistedReminderBeforeSave != null;
      _reminderReconciliationPending = reminderWasInvolved;
      if (!mounted) return;
      _markDraftClean();
      ref.invalidate(notesProvider);
      setState(() {
        _saving = false;
        _saveError = _EditorSaveError(
          heading: 'Couldn’t finish saving note',
          detail: reminderWasInvolved
              ? 'Your note is saved, but its reminder is not confirmed. '
                    'Retry or update the reminder.'
              : 'Your note is saved, but the note list could not be '
                    'refreshed. Retry to finish.',
        );
      });
      _syncCanPop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = const _EditorSaveError(
          heading: 'Couldn’t save note',
          detail: 'Your changes are still here. Try again.',
        );
      });
      _syncCanPop();
    }
  }

  void _showReminderValidationError() {
    setState(() {
      _saving = false;
      _previewMode = false;
      _validationMessage = _reminderValidationMessage;
      _saveError = null;
    });
    _syncCanPop();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _metadataFocusNode.requestFocus();
    });
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
    if (_saving || _closed || _discardDialogOpen) return;

    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? false;
    if (!routeIsCurrent) {
      if (!_closePending) setState(() => _closePending = true);
      return;
    }

    if (_isDirty && !_discardConfirmed) {
      _showDiscardChangesDialog();
      return;
    }

    _finishCloseRequest();
  }

  @override
  void onPopInvoked(bool didPop) {
    onPopInvokedWithResult(didPop, null);
  }

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {
    if (!mounted || didPop || _saving) return;
    _requestClose();
  }

  Future<void> _showDiscardChangesDialog() async {
    _discardDialogOpen = true;
    _closePending = false;
    var choiceResolved = false;
    final discard = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        void resolve(bool value) {
          if (choiceResolved) return;
          choiceResolved = true;
          Navigator.of(dialogContext).pop(value);
        }

        return AlertDialog(
          key: const Key('discard-changes-dialog'),
          semanticLabel: 'Unsaved changes',
          title: const Text('Discard changes?'),
          content: const Text('Your unsaved changes will be lost.'),
          actions: [
            TextButton(
              key: const Key('discard-changes-button'),
              onPressed: () => resolve(true),
              child: const Text('Discard changes'),
            ),
            FilledButton(
              key: const Key('keep-editing-button'),
              autofocus: true,
              onPressed: () => resolve(false),
              child: const Text('Keep editing'),
            ),
          ],
        );
      },
    );
    _discardDialogOpen = false;
    if (!mounted || discard != true || _saving || _closed) return;
    _discardConfirmed = true;
    _requestClose();
  }

  void _finishCloseRequest() {
    final callback = widget.onClose;
    final needsPopFrame =
        (_hasPartialSave || _discardConfirmed) &&
        !_allowPop &&
        Navigator.of(context).canPop();
    if (needsPopFrame) {
      setState(() {
        _allowPop = true;
        _closePending = true;
      });
      _syncCanPop();
      _schedulePendingCloseIfCurrent(true);
      return;
    }

    _closePending = false;
    _closed = true;
    if (_hasPartialSave) ref.invalidate(notesProvider);
    if (callback != null) {
      callback();
      return;
    }
    if (context.canPop()) context.pop();
  }

  _EditorSnapshot _currentSnapshot() {
    return _EditorSnapshot(
      title: _titleController.text,
      body: _contentController.text,
      color: _selectedColor.toARGB32(),
      tags: _tags,
      reminder: _reminder,
    );
  }

  void _handleDraftChanged() {
    if (!mounted) return;
    final isDirty = _currentSnapshot() != _cleanSnapshot;
    if (_isDirty == isDirty) return;
    setState(() => _isDirty = isDirty);
    _syncCanPop();
  }

  void _markDraftClean() {
    _cleanSnapshot = _currentSnapshot();
    _isDirty = false;
    _discardConfirmed = false;
  }

  void _syncCanPop() {
    if (!mounted) return;
    final navigatorCanPop = Navigator.of(context).canPop();
    canPopNotifier.value =
        !_saving &&
        (_allowPop || (navigatorCanPop && !_isDirty && !_hasPartialSave));
  }

  void _schedulePendingCloseIfCurrent(bool routeIsCurrent) {
    if (!_closePending || !routeIsCurrent || _closeRetryScheduled) return;
    _closeRetryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _closeRetryScheduled = false;
      if (mounted) _requestClose();
    });
  }
}

enum _EditorFocusIntent { none, title, content }

class _EditorSaveError {
  const _EditorSaveError({required this.heading, required this.detail});

  final String heading;
  final String detail;
}

class _EditorSnapshot {
  _EditorSnapshot({
    required this.title,
    required this.body,
    required this.color,
    required List<String> tags,
    required this.reminder,
  }) : tags = List<String>.unmodifiable(tags);

  final String title;
  final String body;
  final int color;
  final List<String> tags;
  final DateTime? reminder;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _EditorSnapshot &&
            title == other.title &&
            body == other.body &&
            color == other.color &&
            listEquals(tags, other.tags) &&
            reminder == other.reminder;
  }

  @override
  int get hashCode =>
      Object.hash(title, body, color, Object.hashAll(tags), reminder);
}
