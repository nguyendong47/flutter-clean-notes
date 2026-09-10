import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_clean_notes/app/widgets/busy_aware_modal_bottom_sheet.dart';
import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';

class TagManagerSheet extends ConsumerStatefulWidget {
  const TagManagerSheet({super.key, this.modalController});

  final BusyAwareModalController? modalController;

  static Future<void> show(BuildContext context) {
    return showBusyAwareModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.54),
      builder: (_, controller) => TagManagerSheet(modalController: controller),
    );
  }

  @override
  ConsumerState<TagManagerSheet> createState() => _TagManagerSheetState();
}

class _TagManagerSheetState extends ConsumerState<TagManagerSheet>
    implements PopEntry<Object?> {
  static final _confirmationBusySource = Object();
  static final _retryBusySource = Object();

  ModalRoute<dynamic>? _route;

  @override
  late final ValueNotifier<bool> canPopNotifier;

  bool _confirmationOpen = false;
  bool _retrying = false;

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

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final notesState = ref.watch(notesProvider);
    final usage = ref.watch(tagUsageProvider);
    final busy = _confirmationOpen || _retrying;
    final topPadding = media.padding.top > 0
        ? media.padding.top
        : media.viewPadding.top;

    return PopScope(
      canPop: !busy,
      child: Padding(
        key: const Key('tag-sheet-insets'),
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
                    ? media.size.height - topPadding - 24
                    : media.size.height * 0.9,
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
                    key: const Key('tag-manager-sheet'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Manage tags',
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          IconButton(
                            constraints: const BoxConstraints(
                              minWidth: 48,
                              minHeight: 48,
                            ),
                            tooltip: 'tags.closeTooltip'.tr(),
                            onPressed: busy
                                ? null
                                : () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Counts include active, archived, and trashed notes.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (!notesState.hasValue && notesState.isLoading)
                        const _TagLoading()
                      else if (!notesState.hasValue && notesState.hasError)
                        _TagLoadError(onRetry: _retry)
                      else ...[
                        if (_retrying || notesState.hasError) ...[
                          _TagRefreshError(
                            onRetry: _retry,
                            refreshing: _retrying,
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (usage.isEmpty)
                          const _EmptyTags()
                        else
                          for (
                            var index = 0;
                            index < usage.length;
                            index++
                          ) ...[
                            _TagRow(
                              usage: usage[index],
                              enabled: !busy,
                              onRemove: () => _requestRemoval(usage[index]),
                            ),
                            if (index != usage.length - 1)
                              const SizedBox(height: 8),
                          ],
                      ],
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

  Future<void> _retry() async {
    if (_retrying) return;
    widget.modalController?.setBusy(_retryBusySource, busy: true);
    setState(() => _retrying = true);
    _syncCanPop();
    ref.invalidate(notesProvider);
    try {
      await ref.read(notesProvider.future);
    } catch (_) {
      // The provider retains cached data and exposes the refreshed error state.
    } finally {
      widget.modalController?.setBusy(_retryBusySource, busy: false);
      if (mounted) {
        setState(() => _retrying = false);
        _syncCanPop();
      }
    }
  }

  Future<void> _requestRemoval(TagUsage usage) async {
    if (_confirmationOpen || _retrying) return;
    final originFocus = FocusManager.instance.primaryFocus;
    widget.modalController?.setBusy(_confirmationBusySource, busy: true);
    setState(() => _confirmationOpen = true);
    _syncCanPop();
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) => _RemoveTagDialog(
          usage: usage,
          onRemove: () => ref.read(notesProvider.notifier).removeTag(usage.tag),
        ),
      );
    } finally {
      widget.modalController?.setBusy(_confirmationBusySource, busy: false);
      if (mounted) {
        setState(() => _confirmationOpen = false);
        _syncCanPop();
      }
      if (mounted && originFocus?.canRequestFocus == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && originFocus?.canRequestFocus == true) {
            originFocus!.requestFocus();
          }
        });
      }
    }
  }

  @override
  void onPopInvoked(bool didPop) {}

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {}

  void _syncCanPop() {
    if (!mounted) return;
    canPopNotifier.value = !_confirmationOpen && !_retrying;
  }
}

class _TagLoading extends StatelessWidget {
  const _TagLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text('tags.loading'.tr())),
          ],
        ),
      ),
    );
  }
}

class _TagLoadError extends StatelessWidget {
  const _TagLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _TagErrorPanel(
      message: 'Could not load tags. Try again.',
      onRetry: onRetry,
    );
  }
}

class _TagRefreshError extends StatelessWidget {
  const _TagRefreshError({required this.onRetry, required this.refreshing});

  final VoidCallback onRetry;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    return _TagErrorPanel(
      message: refreshing
          ? 'Refreshing tag counts…'
          : 'Could not refresh tag counts. Showing saved counts.',
      onRetry: onRetry,
      compact: true,
      refreshing: refreshing,
    );
  }
}

class _TagErrorPanel extends StatelessWidget {
  const _TagErrorPanel({
    required this.message,
    required this.onRetry,
    this.compact = false,
    this.refreshing = false,
  });

  final String message;
  final VoidCallback onRetry;
  final bool compact;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 0 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              message,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: refreshing ? colorScheme.primary : colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                child: OutlinedButton.icon(
                  key: const Key('tag-retry'),
                  onPressed: refreshing ? null : onRetry,
                  icon: refreshing
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text('tags.retry'.tr()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({
    required this.usage,
    required this.enabled,
    required this.onRemove,
  });

  final TagUsage usage;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final countLabel = usage.count == 1 ? '1 note' : '${usage.count} notes';
    return Semantics(
      key: Key('tag-row-${usage.tag}'),
      label: usage.tag,
      value: countLabel,
      container: true,
      explicitChildNodes: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(18),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
            child: Row(
              children: [
                Expanded(
                  child: ExcludeSemantics(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          usage.tag,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          countLabel,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  button: true,
                  enabled: enabled,
                  label: 'tags.removeTagSemantics'.tr(
                    namedArgs: {'tag': usage.tag},
                  ),
                  onTap: enabled ? onRemove : null,
                  excludeSemantics: true,
                  child: IconButton(
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    tooltip: 'tags.removeTagTooltip'.tr(
                      namedArgs: {'tag': usage.tag},
                    ),
                    onPressed: enabled ? onRemove : null,
                    color: colorScheme.error,
                    icon: const Icon(Icons.delete_outline),
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

class _RemoveTagDialog extends StatefulWidget {
  const _RemoveTagDialog({required this.usage, required this.onRemove});

  final TagUsage usage;
  final Future<void> Function() onRemove;

  @override
  State<_RemoveTagDialog> createState() => _RemoveTagDialogState();
}

class _RemoveTagDialogState extends State<_RemoveTagDialog>
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

  Future<void> _remove() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    _syncCanPop();
    try {
      await widget.onRemove();
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
    if (mounted) Navigator.of(context).pop();
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
    final tag = widget.usage.tag;
    final count = widget.usage.count;
    final removeButton = FilledButton(
      onPressed: _busy ? null : _remove,
      style: FilledButton.styleFrom(
        backgroundColor: colorScheme.error,
        foregroundColor: colorScheme.onError,
      ),
      child: _busy
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text('tags.removing'.tr()),
              ],
            )
          : Text('tags.remove'.tr()),
    );
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        scrollable: true,
        title: Text(
          'Remove “$tag” from $count ${count == 1 ? 'note' : 'notes'}?',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This removes the tag from active, archived, and trashed notes.',
            ),
            if (_failed) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  'Could not remove “$tag”. Try again.',
                  style: TextStyle(color: colorScheme.error),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: Text('tags.cancel'.tr()),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 120, minHeight: 48),
            child: _busy
                ? Semantics(
                    key: const Key('remove-tag-progress'),
                    container: true,
                    excludeSemantics: true,
                    liveRegion: true,
                    button: true,
                    enabled: false,
                    label: 'tags.removingTagSemantics'.tr(),
                    child: removeButton,
                  )
                : removeButton,
          ),
        ],
      ),
    );
  }
}

class _EmptyTags extends StatelessWidget {
  const _EmptyTags();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Icon(
              Icons.sell_outlined,
              size: 36,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No tags yet',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Tags added to notes will appear here.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
