import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_clean_notes/app/app_providers.dart';
import 'package:flutter_clean_notes/app/widgets/busy_aware_modal_bottom_sheet.dart';
import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/notes_transfer_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/tag_manager_sheet.dart';

class MoreActionsSheet extends ConsumerStatefulWidget {
  const MoreActionsSheet({super.key, this.modalController});

  final BusyAwareModalController? modalController;

  static Future<void> show(BuildContext context) {
    ProviderScope.containerOf(
      context,
    ).read(notesTransferProvider.notifier).beginSession();
    return showBusyAwareModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.54),
      builder: (_, controller) => MoreActionsSheet(modalController: controller),
    );
  }

  @override
  ConsumerState<MoreActionsSheet> createState() => _MoreActionsSheetState();
}

class _MoreActionsSheetState extends ConsumerState<MoreActionsSheet>
    implements PopEntry<Object?> {
  static final _themeBusySource = Object();
  static final _transferBusySource = Object();

  final FocusNode _manageTagsFocusNode = FocusNode(debugLabel: 'Manage tags');
  final FocusNode _importFocusNode = FocusNode(debugLabel: 'Import backup');
  late final ProviderSubscription<AsyncValue<NotesTransferOutcome?>>
  _transferSubscription;
  ModalRoute<dynamic>? _route;

  @override
  late final ValueNotifier<bool> canPopNotifier;

  bool _themeChoicesVisible = false;
  bool _languageChoicesVisible = false;
  bool _themeBusy = false;
  bool _transferBusy = false;
  ThemeMode? _pendingTheme;
  String? _themeError;

  @override
  void initState() {
    super.initState();
    canPopNotifier = ValueNotifier<bool>(true);
    _transferSubscription = ref.listenManual<AsyncValue<NotesTransferOutcome?>>(
      notesTransferProvider,
      (previous, next) {
        _transferBusy = next.isLoading;
        widget.modalController?.setBusy(
          _transferBusySource,
          busy: _transferBusy,
        );
        _syncCanPop();
      },
      fireImmediately: true,
    );
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
    _transferSubscription.close();
    _route?.unregisterPopEntry(this);
    canPopNotifier.dispose();
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
    final topPadding = media.padding.top;

    return PopScope(
      canPop: !busy,
      child: Padding(
        key: const Key('more-sheet-insets'),
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: SafeArea(
          top: true,
          minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 600,
                maxHeight: topPadding > 0
                    ? media.size.height - topPadding - 16
                    : media.size.height * 0.92,
              ),
              child: GlassSurface(
                borderRadius: const BorderRadius.all(Radius.circular(28)),
                blur: 18,
                opacity: 0.82,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  child: Column(
                    key: const Key('more-actions-sheet'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SheetHeader(
                        title: 'more.title'.tr(),
                        closeEnabled: !busy,
                        privacyEnabled: !busy,
                        onPrivacy: () => unawaited(_openPrivacy()),
                        onClose: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(height: 8),
                      _SectionLabel('more.sectionAppearance'.tr()),
                      const SizedBox(height: 6),
                      _ActionRow(
                        key: const Key('more-row-theme'),
                        icon: Icons.palette_outlined,
                        label: 'more.themeRowLabel'.tr(),
                        description: _themeLabel(context, selectedTheme),
                        expanded: _themeChoicesVisible,
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
                          label: 'more.themeSystem'.tr(),
                          description: 'more.themeSystemDescription'.tr(),
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
                          label: 'more.themeLight'.tr(),
                          description: 'more.themeLightDescription'.tr(),
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
                          label: 'more.themeDark'.tr(),
                          description: 'more.themeDarkDescription'.tr(),
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
                      const SizedBox(height: 10),
                      _SectionLabel('more.sectionLanguage'.tr()),
                      const SizedBox(height: 6),
                      _ActionRow(
                        key: const Key('more-row-language'),
                        icon: Icons.translate_outlined,
                        label: 'more.languageRowLabel'.tr(),
                        description: _languageLabel(context),
                        expanded: _languageChoicesVisible,
                        enabled: !busy,
                        trailing: Icon(
                          _languageChoicesVisible
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                        onPressed: (_) {
                          setState(
                            () => _languageChoicesVisible =
                                !_languageChoicesVisible,
                          );
                        },
                      ),
                      if (_languageChoicesVisible) ...[
                        const SizedBox(height: 8),
                        _LanguageChoiceRow(
                          key: const Key('language-mode-system'),
                          locale: null,
                          label: 'more.languageSystem'.tr(),
                          selected:
                              context.locale.languageCode ==
                              context.deviceLocale.languageCode,
                          enabled: !busy,
                          onSelected: _setLanguage,
                        ),
                        const SizedBox(height: 8),
                        _LanguageChoiceRow(
                          key: const Key('language-mode-vi'),
                          locale: const Locale('vi'),
                          label: 'more.languageVietnamese'.tr(),
                          selected: context.locale == const Locale('vi'),
                          enabled: !busy,
                          onSelected: _setLanguage,
                        ),
                        const SizedBox(height: 8),
                        _LanguageChoiceRow(
                          key: const Key('language-mode-en'),
                          locale: const Locale('en'),
                          label: 'more.languageEnglish'.tr(),
                          selected: context.locale == const Locale('en'),
                          enabled: !busy,
                          onSelected: _setLanguage,
                        ),
                      ],
                      const SizedBox(height: 10),
                      _SectionLabel('more.sectionOrganization'.tr()),
                      const SizedBox(height: 6),
                      _ActionRow(
                        key: const Key('more-row-manage-tags'),
                        focusNode: _manageTagsFocusNode,
                        icon: Icons.sell_outlined,
                        label: 'more.manageTags'.tr(),
                        description: 'more.manageTagsDescription'.tr(),
                        enabled: !busy,
                        onPressed: (_) => _showTags(),
                      ),
                      const SizedBox(height: 10),
                      _SectionLabel('more.sectionTransfer'.tr()),
                      const SizedBox(height: 6),
                      _TransferRow(
                        key: const Key('more-row-export-text'),
                        operation: NotesTransferOperation.exportText,
                        icon: Icons.ios_share_outlined,
                        label: 'more.exportText'.tr(),
                        description: 'more.exportTextDescription'.tr(),
                        state: transferState,
                        activeOperation: transferNotifier.operation,
                        enabled: !busy,
                        onPressed: (origin) => transferNotifier.exportText(
                          sharePositionOrigin: origin,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _TransferRow(
                        key: const Key('more-row-backup-json'),
                        operation: NotesTransferOperation.backupJson,
                        icon: Icons.data_object_outlined,
                        label: 'more.backupJson'.tr(),
                        description: 'more.backupJsonDescription'.tr(),
                        state: transferState,
                        activeOperation: transferNotifier.operation,
                        enabled: !busy,
                        onPressed: (origin) => transferNotifier.backupJson(
                          sharePositionOrigin: origin,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _TransferRow(
                        key: const Key('more-row-export-markdown'),
                        operation: NotesTransferOperation.exportMarkdown,
                        icon: Icons.text_snippet_outlined,
                        label: 'more.exportMarkdown'.tr(),
                        description: 'more.exportMarkdownDescription'.tr(),
                        state: transferState,
                        activeOperation: transferNotifier.operation,
                        enabled: !busy,
                        onPressed: (origin) => transferNotifier.exportMarkdown(
                          sharePositionOrigin: origin,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _TransferRow(
                        key: const Key('more-row-import-backup'),
                        focusNode: _importFocusNode,
                        operation: NotesTransferOperation.importBackup,
                        icon: Icons.file_open_outlined,
                        label: 'more.importBackup'.tr(),
                        description: 'more.importBackupDescription'.tr(),
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
    widget.modalController?.setBusy(_themeBusySource, busy: true);
    setState(() {
      _themeBusy = true;
      _pendingTheme = mode;
      _themeError = null;
    });
    _syncCanPop();
    try {
      await ref.read(appThemeProvider.notifier).setMode(mode);
    } catch (_) {
      if (mounted) {
        setState(() {
          _themeError = 'more.themeSaveError'.tr();
        });
      }
    } finally {
      widget.modalController?.setBusy(_themeBusySource, busy: false);
      if (mounted) {
        setState(() {
          _themeBusy = false;
          _pendingTheme = null;
        });
        _syncCanPop();
      }
    }
  }

  Future<void> _setLanguage(Locale? locale) async {
    if (locale == null) {
      await context.resetLocale();
    } else {
      await context.setLocale(locale);
    }
  }

  String _languageLabel(BuildContext context) {
    if (context.locale == const Locale('vi')) {
      return 'more.languageVietnamese'.tr();
    }
    if (context.locale == const Locale('en')) {
      return 'more.languageEnglish'.tr();
    }
    return 'more.languageSystem'.tr();
  }

  @override
  void onPopInvoked(bool didPop) {}

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {}

  void _syncCanPop() {
    if (!mounted) return;
    canPopNotifier.value = !_themeBusy && !_transferBusy;
  }

  Future<void> _showTags() async {
    await TagManagerSheet.show(context);
    _restoreFocus(_manageTagsFocusNode);
  }

  Future<void> _openPrivacy() async {
    final navigator = Navigator.of(context);
    final router = GoRouter.of(context);
    final dismissed = await navigator.maybePop();
    if (dismissed) unawaited(router.push<void>('/privacy'));
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
    required this.privacyEnabled,
    required this.onPrivacy,
    required this.onClose,
  });

  final String title;
  final bool closeEnabled;
  final bool privacyEnabled;
  final VoidCallback onPrivacy;
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
        const SizedBox(width: 8),
        Semantics(
          key: const Key('more-privacy-button'),
          button: true,
          enabled: privacyEnabled,
          label: 'more.privacy'.tr(),
          hint: 'more.privacyHint'.tr(),
          onTap: privacyEnabled ? onPrivacy : null,
          excludeSemantics: true,
          child: TextButton.icon(
            onPressed: privacyEnabled ? onPrivacy : null,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            icon: const Icon(Icons.privacy_tip_outlined, size: 20),
            label: Text('more.privacy'.tr()),
          ),
        ),
        const SizedBox(width: 4),
        IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          tooltip: 'more.closeTooltip'.tr(namedArgs: {'title': title}),
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
      status: loading ? 'more.themeSaving'.tr() : null,
      selected: selected,
      enabled: enabled,
      loading: loading,
      reserveDescriptionForStatus: true,
      trailing: selected ? const Icon(Icons.check) : const SizedBox.shrink(),
      onPressed: (_) => onSelected(mode),
    );
  }
}

class _LanguageChoiceRow extends StatelessWidget {
  const _LanguageChoiceRow({
    required this.locale,
    required this.label,
    required this.selected,
    required this.enabled,
    required this.onSelected,
    super.key,
  });

  final Locale? locale;
  final String label;
  final bool selected;
  final bool enabled;
  final ValueChanged<Locale?> onSelected;

  @override
  Widget build(BuildContext context) {
    return _ActionRow(
      icon: selected ? Icons.radio_button_checked : Icons.radio_button_off,
      label: label,
      description: '',
      selected: selected,
      enabled: enabled,
      trailing: selected ? const Icon(Icons.check) : const SizedBox.shrink(),
      onPressed: (_) => onSelected(locale),
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
        ? _transferError(context, operation, state.error)
        : null;
    final outcome = state.value;
    final success = outcome?.operation == operation
        ? _transferSuccess(context, outcome!)
        : null;
    final status = loading
        ? _transferProgress(context, operation)
        : error ?? success;
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
    this.expanded,
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
  final bool? expanded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final effectiveEnabled = enabled && onPressed != null;
    final dimmed = !effectiveEnabled && !loading;
    final surfaceColor = selected == true
        ? colorScheme.primaryContainer.withValues(alpha: dimmed ? 0.28 : 0.7)
        : colorScheme.surfaceContainerHighest.withValues(
            alpha: dimmed ? 0.16 : 0.42,
          );
    return Builder(
      builder: (rowContext) {
        void activate() {
          unawaited(Future.sync(() => onPressed!(rowContext)));
        }

        return Semantics(
          key: statusKey,
          container: true,
          button: true,
          enabled: effectiveEnabled,
          selected: selected,
          expanded: expanded,
          label: label,
          value: status ?? description,
          liveRegion: status != null,
          onTap: effectiveEnabled ? activate : null,
          excludeSemantics: true,
          child: Material(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              focusNode: focusNode,
              onTap: effectiveEnabled ? activate : null,
              child: Opacity(
                opacity: dimmed ? 0.48 : 1,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
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
      },
    );
  }
}

class _ActionRowStatus extends StatelessWidget {
  const _ActionRowStatus({
    required this.description,
    required this.status,
    required this.statusIsError,
    required this.reserveDescription,
  });

  final String description;
  final String? status;
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

    final statusWidget = Text(
      message,
      style: theme.textTheme.bodySmall?.copyWith(
        color: statusIsError ? colorScheme.error : colorScheme.primary,
        fontWeight: statusIsError ? FontWeight.w500 : FontWeight.w700,
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

String _themeLabel(BuildContext context, ThemeMode mode) {
  return switch (mode) {
    ThemeMode.system => 'more.themeFollowDevice'.tr(),
    ThemeMode.light => 'more.themeLightSelected'.tr(),
    ThemeMode.dark => 'more.themeDarkSelected'.tr(),
  };
}

String _transferError(
  BuildContext context,
  NotesTransferOperation operation,
  Object? error,
) {
  if (operation == NotesTransferOperation.importBackup &&
      error is FormatException) {
    return error.message;
  }
  return switch (operation) {
    NotesTransferOperation.exportText => 'more.transferExportTextError'.tr(),
    NotesTransferOperation.backupJson => 'more.transferBackupError'.tr(),
    NotesTransferOperation.exportMarkdown =>
      'more.transferExportMarkdownError'.tr(),
    NotesTransferOperation.importBackup => 'more.transferImportError'.tr(),
  };
}

String _transferProgress(
  BuildContext context,
  NotesTransferOperation operation,
) {
  return switch (operation) {
    NotesTransferOperation.exportText => 'more.transferExportTextProgress'.tr(),
    NotesTransferOperation.backupJson => 'more.transferBackupProgress'.tr(),
    NotesTransferOperation.exportMarkdown =>
      'more.transferExportMarkdownProgress'.tr(),
    NotesTransferOperation.importBackup => 'more.transferImportProgress'.tr(),
  };
}

String _transferSuccess(BuildContext context, NotesTransferOutcome outcome) {
  if (outcome.status == NotesTransferOutcomeStatus.webShareOrDownloadStarted) {
    return switch (outcome.operation) {
      NotesTransferOperation.exportText =>
        'more.transferExportTextHandedOff'.tr(),
      NotesTransferOperation.backupJson => 'more.transferBackupHandedOff'.tr(),
      NotesTransferOperation.exportMarkdown =>
        'more.transferExportMarkdownHandedOff'.tr(),
      NotesTransferOperation.importBackup =>
        'more.transferImportHandedOff'.tr(),
    };
  }
  if (outcome.status == NotesTransferOutcomeStatus.shareSheetOpened) {
    return 'more.transferShareSheetOpened'.tr();
  }
  return switch (outcome.operation) {
    NotesTransferOperation.exportText => 'more.transferExportTextComplete'.tr(),
    NotesTransferOperation.backupJson => 'more.transferBackupComplete'.tr(),
    NotesTransferOperation.exportMarkdown =>
      'more.transferExportMarkdownComplete'.tr(),
    NotesTransferOperation.importBackup => switch (outcome.importedCount ?? 0) {
      1 => 'more.transferImportedOne'.tr(),
      final count => 'more.transferImportedMany'.tr(
        namedArgs: {'count': '$count'},
      ),
    },
  };
}

Rect? _shareOrigin(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}
