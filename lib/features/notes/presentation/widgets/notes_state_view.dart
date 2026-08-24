import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/notes_grid_layout.dart';

class NotesSkeleton extends StatelessWidget {
  const NotesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SliverSemantics(
      container: true,
      liveRegion: true,
      label: 'Loading notes',
      excludeSemantics: true,
      sliver: SliverLayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth = constraints.crossAxisExtent;
          final horizontalInset = notesGridHorizontalInset(viewportWidth);
          final colorScheme = Theme.of(context).colorScheme;

          return SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: horizontalInset),
            sliver: SliverMasonryGrid.count(
              crossAxisCount: notesGridColumnCount(viewportWidth),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childCount: 4,
              itemBuilder: (context, index) => GlassSurface(
                key: Key('notes-skeleton-card-$index'),
                borderRadius: const BorderRadius.all(Radius.circular(20)),
                blur: 18,
                opacity: 0.78,
                child: SizedBox(
                  height: index.isEven ? 150 : 184,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SkeletonLine(
                        widthFactor: index.isEven ? 0.64 : 0.78,
                        color: colorScheme.surfaceContainerHighest,
                      ),
                      const SizedBox(height: 16),
                      _SkeletonLine(
                        widthFactor: 1,
                        color: colorScheme.surfaceContainerHighest,
                      ),
                      const SizedBox(height: 10),
                      _SkeletonLine(
                        widthFactor: 0.82,
                        color: colorScheme.surfaceContainerHighest,
                      ),
                      const Spacer(),
                      _SkeletonLine(
                        widthFactor: 0.48,
                        color: colorScheme.surfaceContainerHighest,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class NotesEmptyState extends StatelessWidget {
  const NotesEmptyState({
    required this.onCreate,
    super.key,
    this.title = 'Create your first note',
    this.supportsReminderScheduling = true,
  });

  final VoidCallback onCreate;
  final String title;
  final bool supportsReminderScheduling;

  @override
  Widget build(BuildContext context) {
    return _StateSliver(
      child: GlassSurface(
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        blur: 18,
        opacity: 0.74,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.note_add_outlined,
              size: 36,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 12),
            Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              supportsReminderScheduling
                  ? 'Capture an idea, plan, or reminder and keep it close.'
                  : 'Capture an idea or plan and keep it close.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Create note'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class NotesErrorState extends StatelessWidget {
  const NotesErrorState({required this.onRetry, super.key});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _StateSliver(
      child: GlassSurface(
        borderRadius: const BorderRadius.all(Radius.circular(20)),
        blur: 18,
        opacity: 0.74,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 36,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(height: 12),
            Semantics(
              container: true,
              header: true,
              liveRegion: true,
              child: Text(
                'Could not load notes',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try again. Your saved notes are unchanged.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateSliver extends StatelessWidget {
  const _StateSliver({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        return SliverPadding(
          padding: EdgeInsets.symmetric(
            horizontal: notesGridHorizontalInset(constraints.crossAxisExtent),
          ),
          sliver: SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.widthFactor, required this.color});

  final double widthFactor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const SizedBox(height: 12),
      ),
    );
  }
}
