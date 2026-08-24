import 'package:flutter/material.dart';

import 'package:flutter_clean_notes/app/widgets/aurora_background.dart';
import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';

/// Offline privacy disclosure for the behavior implemented by this app build.
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return PopScope(
      canPop: canPop,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) onClose();
      },
      child: Scaffold(
        key: const Key('privacy-page'),
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          leading: BackButton(
            key: const Key('privacy-back-button'),
            onPressed: onClose,
          ),
          title: const Text('Privacy'),
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
        body: AuroraBackground(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final horizontalPadding = constraints.maxWidth >= 600
                  ? 32.0
                  : 16.0;
              return SingleChildScrollView(
                key: const Key('privacy-scroll'),
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  16,
                  horizontalPadding,
                  32,
                ),
                child: Center(
                  child: ConstrainedBox(
                    key: const Key('privacy-content'),
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _PrivacyHero(),
                        SizedBox(height: 16),
                        _PrivacyCard(
                          key: Key('privacy-storage-card'),
                          icon: Icons.storage_outlined,
                          title: 'Where your notes live',
                          body:
                              'On Android, iOS, macOS, Windows, and Linux, '
                              'notes use a local SQLite database. On Web, notes '
                              'use IndexedDB for this site\'s current browser '
                              'profile and origin. Clearing app or site data, '
                              'uninstalling the app, or deleting that browser '
                              'profile can remove the local copy. Create and '
                              'keep a JSON backup if you need recovery. Clean '
                              'Notes does not add its own encryption layer; '
                              'protection depends on device and browser '
                              'settings. Android managed cloud backup and '
                              'device transfer are disabled. On other '
                              'platforms, operating-system backup or device '
                              'transfer may copy app data; behavior depends on '
                              'platform settings.',
                        ),
                        SizedBox(height: 12),
                        _PrivacyCard(
                          key: Key('privacy-reminders-card'),
                          icon: Icons.notifications_none_rounded,
                          title: 'Reminders use platform services',
                          body:
                              'Reminder time stays with the local note. On '
                              'Android, iOS, and macOS, Clean Notes gives the '
                              'operating system a generic message and an opaque '
                              'local note ID; app-supplied notification text '
                              'does not include the note title or body. The '
                              'system may show the app name, timing, generic '
                              'copy, or actions on lock screens and connected '
                              'devices. Permission and platform settings control '
                              'delivery. Scheduling is unavailable on Web, '
                              'Windows, and Linux.',
                        ),
                        SizedBox(height: 12),
                        _PrivacyCard(
                          key: Key('privacy-transfer-card'),
                          icon: Icons.swap_vert_circle_outlined,
                          title: 'Import, export, and backup',
                          body:
                              'Text and Markdown exports include title, '
                              'content, and tags from Active and Archive '
                              'notes, not Trash. JSON backup additionally '
                              'includes IDs, color, creation time, pin state, '
                              'status, and reminder times for Active, Archive, '
                              'and Trash. Import reads one JSON file you '
                              'select, then appends Active copies with new IDs '
                              'and cleared reminders.',
                        ),
                        SizedBox(height: 12),
                        _PrivacyCard(
                          key: Key('privacy-external-transfer-card'),
                          icon: Icons.ios_share_outlined,
                          title: 'You control app-initiated transfers',
                          body:
                              'Clean Notes starts an export only when you '
                              'choose Export or Backup. Content is handed to '
                              'the platform share, save, or download flow. The '
                              'destination you choose controls later storage, '
                              'delivery, and deletion. The platform or share '
                              'plugin may create temporary or cache copies; '
                              'Clean Notes has no cleanup job for those copies. '
                              'Import reads only the file you pick; that source '
                              'file remains outside Clean Notes.',
                        ),
                        SizedBox(height: 12),
                        _PrivacyCard(
                          key: Key('privacy-retention-card'),
                          icon: Icons.delete_outline_rounded,
                          title: 'Retention and deletion',
                          body:
                              'Active, archived, and trashed notes remain until '
                              'you delete them. Trash is not automatically '
                              'emptied in this version. Permanent delete '
                              'removes the local database row and asks the '
                              'operating system to cancel its reminder. Shared '
                              'files and copies held by other apps are outside '
                              'Clean Notes\' control.',
                        ),
                        SizedBox(height: 20),
                        Text(
                          'This notice describes behavior in this installed '
                          'version and is available offline.',
                          textAlign: TextAlign.center,
                          key: Key('privacy-offline-note'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PrivacyHero extends StatelessWidget {
  const _PrivacyHero();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return GlassSurface(
      borderRadius: const BorderRadius.all(Radius.circular(24)),
      blur: 18,
      opacity: 0.8,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            key: const Key('privacy-primary-heading'),
            header: true,
            child: Text(
              'Your notes stay under your control',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Clean Notes is local-first. This installed version has no account '
            'or cloud sync. Notes and app preferences use local app storage. '
            'In-app transfers and reminder scheduling use platform services; '
            'platform-managed backup behavior is described below.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text('Local-first')),
              Chip(label: Text('No account')),
              Chip(label: Text('You choose transfers')),
            ],
          ),
        ],
      ),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return GlassSurface(
      borderRadius: const BorderRadius.all(Radius.circular(20)),
      blur: 16,
      opacity: 0.72,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ExcludeSemantics(
                child: SizedBox.square(
                  dimension: 40,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(
                        alpha: 0.72,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      icon,
                      size: 22,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            body,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
