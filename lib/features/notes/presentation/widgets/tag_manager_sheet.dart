import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';

class TagManagerSheet extends ConsumerStatefulWidget {
  const TagManagerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.54),
      builder: (_) => const TagManagerSheet(),
    );
  }

  @override
  ConsumerState<TagManagerSheet> createState() => _TagManagerSheetState();
}

class _TagManagerSheetState extends ConsumerState<TagManagerSheet> {
  bool _confirmationOpen = false;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final notesState = ref.watch(notesProvider);
    final usage = ref.watch(tagUsageProvider);

    return Padding(
      key: const Key('tag-sheet-insets'),
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 600,
              maxHeight: media.size.height * 0.9,
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
                          tooltip: 'Close Manage tags',
                          onPressed: _confirmationOpen
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
                      if (notesState.hasError) ...[
                        _TagRefreshError(onRetry: _retry),
                        const SizedBox(height: 12),
                      ],
                      if (usage.isEmpty)
                        const _EmptyTags()
                      else
                        for (var index = 0; index < usage.length; index++) ...[
                          _TagRow(
                            usage: usage[index],
                            enabled: !_confirmationOpen,
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
    );
  }

  void _retry() {
    ref.invalidate(notesProvider);
  }

  Future<void> _requestRemoval(TagUsage usage) async {
    if (_confirmationOpen) return;
    final originFocus = FocusManager.instance.primaryFocus;
    setState(() => _confirmationOpen = true);
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
      if (mounted) setState(() => _confirmationOpen = false);
      if (mounted && originFocus?.canRequestFocus == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && originFocus?.canRequestFocus == true) {
            originFocus!.requestFocus();
          }
        });
      }
    }
  }
}

class _TagLoading extends StatelessWidget {
  const _TagLoading();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Loading tags…')),
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
  const _TagRefreshError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _TagErrorPanel(
      message: 'Could not refresh tag counts. Showing saved counts.',
      onRetry: onRetry,
      compact: true,
    );
  }
}

class _TagErrorPanel extends StatelessWidget {
  const _TagErrorPanel({
    required this.message,
    required this.onRetry,
    this.compact = false,
  });

  final String message;
  final VoidCallback onRetry;
  final bool compact;

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
                color: colorScheme.error,
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
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
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
      label: '${usage.tag}, $countLabel',
      container: true,
      child: DecoratedBox(
        key: Key('tag-row-${usage.tag}'),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        usage.tag,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        countLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  constraints: const BoxConstraints(
                    minWidth: 48,
                    minHeight: 48,
                  ),
                  tooltip: 'Remove ${usage.tag} tag',
                  onPressed: enabled ? onRemove : null,
                  color: colorScheme.error,
                  icon: const Icon(Icons.delete_outline),
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

class _RemoveTagDialogState extends State<_RemoveTagDialog> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _remove() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await widget.onRemove();
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = true;
        });
      }
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tag = widget.usage.tag;
    final count = widget.usage.count;
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
            child: const Text('Cancel'),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 120, minHeight: 48),
            child: FilledButton(
              onPressed: _busy ? null : _remove,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              child: _busy
                  ? const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text('Removing…'),
                      ],
                    )
                  : const Text('Remove'),
            ),
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
