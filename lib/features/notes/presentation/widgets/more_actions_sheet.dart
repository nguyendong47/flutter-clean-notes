import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_clean_notes/app/app_providers.dart';
import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/notes_transfer_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/tag_manager_sheet.dart';

class MoreActionsSheet extends ConsumerStatefulWidget {
  const MoreActionsSheet({super.key});

  static Future<void> show(BuildContext context) {
    ProviderScope.containerOf(
      context,
    ).read(notesTransferProvider.notifier).beginSession();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.54),
      builder: (_) => const MoreActionsSheet(),
    );
  }

  @override
  ConsumerState<MoreActionsSheet> createState() => _MoreActionsSheetState();
}

class _MoreActionsSheetState extends ConsumerState<MoreActionsSheet> {
  final FocusNode _manageTagsFocusNode = FocusNode(debugLabel: 'Manage tags');
  final FocusNode _importFocusNode = FocusNode(debugLabel: 'Import backup');

  bool _themeChoicesVisible = true;
  bool _themeBusy = false;
  ThemeMode? _pendingTheme;
  String? _themeError;

  @override
  void dispose() {
    _manageTagsFocusNode.dispose();
    _importFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final transferState = ref.watch(notesTransferProvider);
    final transferNotifier = ref.read(notesTransferProvider.notifier);
    final transferBusy = transferState.isLoading;
    final busy = transferBusy || _themeBusy;
    final selectedTheme = ref.watch(appThemeProvider).value ?? ThemeMode.system;

    return PopScope(
      canPop: !busy,
      child: Padding(
        key: const Key('more-sheet-insets'),
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 600,
                maxHeight: media.size.height * 0.92,
              ),
              child: GlassSurface(
                borderRadius: const BorderRadius.all(Radius.circular(28)),
                blur: 18,
                opacity: 0.82,
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    key: const Key('more-actions-sheet'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SheetHeader(
                        title: 'More',
                        closeEnabled: !busy,
                        onClose: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(height: 16),
                      const _SectionLabel('Appearance'),
                      const SizedBox(height: 8),
                      _ActionRow(
                        key: const Key('more-row-theme'),
                        icon: Icons.palette_outlined,
                        label: 'Theme',
                        description: _themeLabel(selectedTheme),
                        enabled: !busy,
                        trailing: Icon(
                          _themeChoicesVisible
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                        onPressed: (_) {
                          setState(
                            () => _themeChoicesVisible = !_themeChoicesVisible,
                          );
                        },
                      ),
                      if (_themeChoicesVisible) ...[
                        const SizedBox(height: 8),
                        _ThemeChoiceRow(
                          key: const Key('theme-mode-system'),
                          mode: ThemeMode.system,
                          label: 'System',
                          description: 'Match this device',
                          selected: selectedTheme == ThemeMode.system,
                          loading:
                              _themeBusy && _pendingTheme == ThemeMode.system,
                          enabled: !busy,
                          onSelected: _setTheme,
                        ),
                        const SizedBox(height: 8),
                        _ThemeChoiceRow(
                          key: const Key('theme-mode-light'),
                          mode: ThemeMode.light,
                          label: 'Light',
                          description: 'Always use light appearance',
                          selected: selectedTheme == ThemeMode.light,
                          loading:
                              _themeBusy && _pendingTheme == ThemeMode.light,
                          enabled: !busy,
                          onSelected: _setTheme,
                        ),
                        const SizedBox(height: 8),
                        _ThemeChoiceRow(
                          key: const Key('theme-mode-dark'),
                          mode: ThemeMode.dark,
                          label: 'Dark',
                          description: 'Always use dark appearance',
                          selected: selectedTheme == ThemeMode.dark,
                          loading:
                              _themeBusy && _pendingTheme == ThemeMode.dark,
                          enabled: !busy,
                          onSelected: _setTheme,
                        ),
                      ],
                      if (_themeError case final error?) ...[
                        const SizedBox(height: 8),
                        Semantics(
                          liveRegion: true,
                          child: Text(
                            error,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      const _SectionLabel('Organization'),
                      const SizedBox(height: 8),
                      _ActionRow(
                        key: const Key('more-row-manage-tags'),
                        focusNode: _manageTagsFocusNode,
                        icon: Icons.sell_outlined,
                        label: 'Manage tags',
                        description: 'Review usage and remove tags everywhere',
                        enabled: !busy,
                        onPressed: (_) => _showTags(),
                      ),
                      const SizedBox(height: 24),
                      const _SectionLabel('Transfer'),
                      const SizedBox(height: 8),
                      _TransferRow(
                        key: const Key('more-row-export-text'),
                        operation: NotesTransferOperation.exportText,
                        icon: Icons.ios_share_outlined,
                        label: 'Export text',
                        description: 'Share a readable text copy',
                        state: transferState,
                        activeOperation: transferNotifier.operation,
                        enabled: !busy,
                        onPressed: (origin) => transferNotifier.exportText(
                          sharePositionOrigin: origin,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _TransferRow(
                        key: const Key('more-row-backup-json'),
                        operation: NotesTransferOperation.backupJson,
                        icon: Icons.data_object_outlined,
                        label: 'Backup JSON',
                        description: 'Share a restorable backup file',
                        state: transferState,
                        activeOperation: transferNotifier.operation,
                        enabled: !busy,
                        onPressed: (origin) => transferNotifier.backupJson(
                          sharePositionOrigin: origin,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _TransferRow(
                        key: const Key('more-row-export-markdown'),
                        operation: NotesTransferOperation.exportMarkdown,
                        icon: Icons.text_snippet_outlined,
                        label: 'Export Markdown',
                        description: 'Share notes with Markdown formatting',
                        state: transferState,
                        activeOperation: transferNotifier.operation,
                        enabled: !busy,
                        onPressed: (origin) => transferNotifier.exportMarkdown(
                          sharePositionOrigin: origin,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _TransferRow(
                        key: const Key('more-row-import-backup'),
                        focusNode: _importFocusNode,
                        operation: NotesTransferOperation.importBackup,
                        icon: Icons.file_open_outlined,
                        label: 'Import backup',
                        description: 'Append notes from a JSON backup',
                        state: transferState,
                        activeOperation: transferNotifier.operation,
                        enabled: !busy,
                        onPressed: (_) => _importBackup(),
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

  Future<void> _setTheme(ThemeMode mode) async {
    if (_themeBusy) return;
    setState(() {
      _themeBusy = true;
      _pendingTheme = mode;
      _themeError = null;
    });
    try {
      await ref.read(appThemeProvider.notifier).setMode(mode);
    } catch (_) {
      if (mounted) {
        setState(() {
          _themeError = 'Could not save theme preference. Try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _themeBusy = false;
          _pendingTheme = null;
        });
      }
    }
  }

  Future<void> _showTags() async {
    await TagManagerSheet.show(context);
    _restoreFocus(_manageTagsFocusNode);
  }

  Future<NotesTransferResult> _importBackup() async {
    final result = await ref
        .read(notesTransferProvider.notifier)
        .importBackup();
    _restoreFocus(_importFocusNode);
    return result;
  }

  void _restoreFocus(FocusNode node) {
    if (!mounted || !node.canRequestFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && node.canRequestFocus) node.requestFocus();
    });
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader({
    required this.title,
    required this.closeEnabled,
    required this.onClose,
  });

  final String title;
  final bool closeEnabled;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: 'Close $title',
          onPressed: closeEnabled ? onClose : null,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _ThemeChoiceRow extends StatelessWidget {
  const _ThemeChoiceRow({
    required this.mode,
    required this.label,
    required this.description,
    required this.selected,
    required this.loading,
    required this.enabled,
    required this.onSelected,
    super.key,
  });

  final ThemeMode mode;
  final String label;
  final String description;
  final bool selected;
  final bool loading;
  final bool enabled;
  final ValueChanged<ThemeMode> onSelected;

  @override
  Widget build(BuildContext context) {
    return _ActionRow(
      icon: selected ? Icons.radio_button_checked : Icons.radio_button_off,
      label: label,
      description: description,
      selected: selected,
      enabled: enabled,
      trailing: loading
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(selected ? Icons.check : Icons.chevron_right),
      onPressed: (_) => onSelected(mode),
    );
  }
}

class _TransferRow extends StatelessWidget {
  const _TransferRow({
    required this.operation,
    required this.icon,
    required this.label,
    required this.description,
    required this.state,
    required this.activeOperation,
    required this.enabled,
    required this.onPressed,
    this.focusNode,
    super.key,
  });

  final NotesTransferOperation operation;
  final IconData icon;
  final String label;
  final String description;
  final AsyncValue<NotesTransferOutcome?> state;
  final NotesTransferOperation? activeOperation;
  final bool enabled;
  final FocusNode? focusNode;
  final Future<NotesTransferResult> Function(Rect? origin) onPressed;

  @override
  Widget build(BuildContext context) {
    final active = activeOperation == operation;
    final loading = active && state.isLoading;
    final error = active && state.hasError
        ? _transferError(operation, state.error)
        : null;
    final outcome = state.value;
    final success = outcome?.operation == operation
        ? _transferSuccess(outcome!)
        : null;
    final status = loading ? _transferProgress(operation) : error ?? success;
    return _ActionRow(
      focusNode: focusNode,
      icon: icon,
      label: label,
      description: description,
      status: status,
      statusIsError: error != null,
      statusKey: Key(
        error != null
            ? 'more-transfer-error-${operation.name}'
            : 'more-transfer-status-${operation.name}',
      ),
      enabled: enabled,
      loading: loading,
      reserveDescriptionForStatus: true,
      onPressed: (rowContext) => onPressed(_shareOrigin(rowContext)),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.description,
    required this.enabled,
    this.onPressed,
    this.focusNode,
    this.trailing,
    this.status,
    this.statusKey,
    this.statusIsError = false,
    this.loading = false,
    this.reserveDescriptionForStatus = false,
    this.selected,
    super.key,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool enabled;
  final FutureOr<void> Function(BuildContext context)? onPressed;
  final FocusNode? focusNode;
  final Widget? trailing;
  final String? status;
  final Key? statusKey;
  final bool statusIsError;
  final bool loading;
  final bool reserveDescriptionForStatus;
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveEnabled = enabled && onPressed != null;
    return Semantics(
      button: true,
      enabled: effectiveEnabled,
      selected: selected,
      label: label,
      value: status ?? description,
      child: Material(
        color: selected == true
            ? colorScheme.primaryContainer.withValues(alpha: 0.7)
            : colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Builder(
          builder: (rowContext) => InkWell(
            focusNode: focusNode,
            onTap: effectiveEnabled
                ? () => unawaited(Future.sync(() => onPressed!(rowContext)))
                : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ExcludeSemantics(
                      child: SizedBox.square(
                        dimension: 44,
                        child: Center(child: Icon(icon, size: 24)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          _ActionRowStatus(
                            description: description,
                            status: status,
                            statusKey: statusKey,
                            statusIsError: statusIsError,
                            reserveDescription: reserveDescriptionForStatus,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox.square(
                      dimension: 44,
                      child: Center(
                        child: loading
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : trailing ?? const Icon(Icons.chevron_right),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionRowStatus extends StatelessWidget {
  const _ActionRowStatus({
    required this.description,
    required this.status,
    required this.statusKey,
    required this.statusIsError,
    required this.reserveDescription,
  });

  final String description;
  final String? status;
  final Key? statusKey;
  final bool statusIsError;
  final bool reserveDescription;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final descriptionWidget = Text(
      description,
      style: theme.textTheme.bodySmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
    );
    final message = status;
    if (message == null) return descriptionWidget;

    final statusWidget = Semantics(
      key: statusKey,
      liveRegion: true,
      child: Text(
        message,
        style: theme.textTheme.bodySmall?.copyWith(
          color: statusIsError ? colorScheme.error : colorScheme.primary,
          fontWeight: statusIsError ? FontWeight.w500 : FontWeight.w700,
        ),
      ),
    );
    if (!reserveDescription) return statusWidget;

    return Stack(
      alignment: AlignmentDirectional.topStart,
      children: [
        ExcludeSemantics(child: Opacity(opacity: 0, child: descriptionWidget)),
        statusWidget,
      ],
    );
  }
}

String _themeLabel(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => 'Follow device setting',
    ThemeMode.light => 'Light appearance selected',
    ThemeMode.dark => 'Dark appearance selected',
  };
}

String _transferError(NotesTransferOperation operation, Object? error) {
  if (operation == NotesTransferOperation.importBackup &&
      error is FormatException) {
    return error.message;
  }
  return switch (operation) {
    NotesTransferOperation.exportText => 'Could not export text. Try again.',
    NotesTransferOperation.backupJson => 'Could not share backup. Try again.',
    NotesTransferOperation.exportMarkdown =>
      'Could not export Markdown. Try again.',
    NotesTransferOperation.importBackup =>
      'Could not import backup. Try again.',
  };
}

String _transferProgress(NotesTransferOperation operation) {
  return switch (operation) {
    NotesTransferOperation.exportText => 'Exporting text…',
    NotesTransferOperation.backupJson => 'Sharing backup…',
    NotesTransferOperation.exportMarkdown => 'Exporting Markdown…',
    NotesTransferOperation.importBackup => 'Importing backup…',
  };
}

String _transferSuccess(NotesTransferOutcome outcome) {
  return switch (outcome.operation) {
    NotesTransferOperation.exportText => 'Text export complete.',
    NotesTransferOperation.backupJson => 'Backup sharing complete.',
    NotesTransferOperation.exportMarkdown => 'Markdown export complete.',
    NotesTransferOperation.importBackup => switch (outcome.importedCount ?? 0) {
      1 => 'Imported 1 note.',
      final count => 'Imported $count notes.',
    },
  };
}

Rect? _shareOrigin(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
