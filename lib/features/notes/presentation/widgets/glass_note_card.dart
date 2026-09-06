import 'dart:async';

import 'package:characters/characters.dart' as chars;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';

class GlassNoteCard extends StatefulWidget {
  const GlassNoteCard({
    required this.note,
    required this.onOpen,
    required this.onTogglePin,
    required this.onArchive,
    required this.onTrash,
    required this.onRestore,
    required this.onDelete,
    required this.supportsReminderScheduling,
    super.key,
  });

  final Note note;
  final VoidCallback onOpen;
  final Future<void> Function() onTogglePin;
  final Future<void> Function() onArchive;
  final Future<void> Function() onTrash;
  final Future<void> Function() onRestore;
  final Future<void> Function() onDelete;
  final bool supportsReminderScheduling;

  @override
  State<GlassNoteCard> createState() => _GlassNoteCardState();
}

class _GlassNoteCardState extends State<GlassNoteCard> {
  // `EasyLocalization.of(context)` is null in the several page-level widget
  // trees (router/home/library/search) that embed this card without an
  // `EasyLocalization` ancestor in their test harnesses. `context.locale`
  // force-unwraps that lookup and crashes in exactly those trees, so read it
  // defensively and let `DateFormat` fall back to the platform default
  // locale when no `EasyLocalization` ancestor is present.
  DateFormat get _dateFormat => DateFormat(
    'MMM d, yyyy',
    EasyLocalization.of(context)?.locale.toString(),
  );
  DateFormat get _reminderFormat => DateFormat(
    'MMM d, h:mm a',
    EasyLocalization.of(context)?.locale.toString(),
  );
  static const _radius = BorderRadius.all(Radius.circular(20));

  bool _busy = false;

  Future<void> _runMutation(Future<void> Function() mutation) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await mutation();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final tintAlpha =
        (isDark ? 0.12 : 0.07) + (widget.note.isPinned ? 0.03 : 0);
    final noteTint = Color(widget.note.color).withValues(alpha: tintAlpha);
    final title = _displayTitle(widget.note);
    final openLabel = 'Open note $title';
    final preview = _notePreview(widget.note.content);
    final semanticValue = _noteSemanticValue(
      widget.note,
      preview,
      _dateFormat,
      _reminderFormat,
      widget.supportsReminderScheduling,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: _radius,
        border: widget.note.isPinned
            ? Border.all(color: colorScheme.primary.withValues(alpha: 0.32))
            : null,
      ),
      child: GlassSurface(
        borderRadius: _radius,
        padding: EdgeInsets.zero,
        blur: 18,
        opacity: 0.78,
        child: DecoratedBox(
          decoration: BoxDecoration(color: noteTint),
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                Tooltip(
                  message: openLabel,
                  excludeFromSemantics: true,
                  child: Semantics(
                    label: openLabel,
                    value: semanticValue,
                    button: true,
                    enabled: !_busy,
                    onTap: _busy ? null : widget.onOpen,
                    child: ExcludeSemantics(
                      child: InkWell(
                        onTap: _busy ? null : widget.onOpen,
                        borderRadius: _radius,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _CardContent(
                            note: widget.note,
                            title: title,
                            preview: preview,
                            dateFormat: _dateFormat,
                            reminderFormat: _reminderFormat,
                            supportsReminderScheduling:
                                widget.supportsReminderScheduling,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: 4,
                  end: 4,
                  child: _busy
                      ? Semantics(
                          container: true,
                          liveRegion: true,
                          label: _tr(
                            'common.updatingNoteSemantics',
                            namedArgs: {'title': title},
                            fallback: 'Updating note $title',
                          ),
                          excludeSemantics: true,
                          child: const SizedBox.square(
                            dimension: 48,
                            child: Padding(
                              padding: EdgeInsets.all(14),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : SizedBox.square(
                          dimension: 48,
                          child: PopupMenuButton<_NoteAction>(
                            tooltip: _tr(
                              'common.moreActionsForSemantics',
                              namedArgs: {'title': title},
                              fallback: 'More actions for $title',
                            ),
                            useRootNavigator: true,
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.more_horiz),
                            onSelected: (action) =>
                                unawaited(_runMutation(_callbackFor(action))),
                            itemBuilder: _buildActions,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> Function() _callbackFor(_NoteAction action) {
    return switch (action) {
      _NoteAction.togglePin => widget.onTogglePin,
      _NoteAction.archive => widget.onArchive,
      _NoteAction.trash => widget.onTrash,
      _NoteAction.restore => widget.onRestore,
      _NoteAction.delete => widget.onDelete,
    };
  }

  List<PopupMenuEntry<_NoteAction>> _buildActions(BuildContext context) {
    final note = widget.note;
    return switch (note.status) {
      NoteStatus.active => [
        _actionItem(
          _NoteAction.togglePin,
          note.isPinned ? 'Unpin note' : 'Pin note',
          note.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
        ),
        _actionItem(_NoteAction.archive, 'Archive', Icons.archive_outlined),
        _actionItem(_NoteAction.trash, 'Move to trash', Icons.delete_outline),
      ],
      NoteStatus.archived => [
        _actionItem(_NoteAction.restore, 'Restore', Icons.restore),
        _actionItem(_NoteAction.trash, 'Move to trash', Icons.delete_outline),
      ],
      NoteStatus.trashed => [
        _actionItem(_NoteAction.restore, 'Restore', Icons.restore),
        _actionItem(
          _NoteAction.delete,
          'Delete forever',
          Icons.delete_forever_outlined,
        ),
      ],
    };
  }

  PopupMenuItem<_NoteAction> _actionItem(
    _NoteAction value,
    String label,
    IconData icon,
  ) {
    return PopupMenuItem(
      value: value,
      child: Row(
        children: [
          ExcludeSemantics(child: Icon(icon, size: 20)),
          const SizedBox(width: 12),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }
}

class _CardContent extends StatelessWidget {
  const _CardContent({
    required this.note,
    required this.title,
    required this.preview,
    required this.dateFormat,
    required this.reminderFormat,
    required this.supportsReminderScheduling,
  });

  final Note note;
  final String title;
  final String preview;
  final DateFormat dateFormat;
  final DateFormat reminderFormat;
  final bool supportsReminderScheduling;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final visibleTags = note.tags.take(2).toList(growable: false);
    final hiddenTagCount = note.tags.length - visibleTags.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(end: 44),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (preview.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            preview,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
        if (visibleTags.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tag in visibleTags) _NoteTag(label: tag),
              if (hiddenTagCount > 0) _NoteTag(label: '+$hiddenTagCount'),
            ],
          ),
        ],
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (note.isPinned)
              _Metadata(
                icon: Icons.push_pin,
                label: _tr('common.pinned', fallback: 'Pinned'),
                color: colorScheme.primary,
              ),
            _Metadata(
              icon: Icons.calendar_today_outlined,
              label: dateFormat.format(note.createdAt),
            ),
            if (note.reminder case final reminder?)
              _Metadata(
                icon: supportsReminderScheduling
                    ? Icons.notifications_none
                    : Icons.notifications_off_outlined,
                label: supportsReminderScheduling
                    ? reminderFormat.format(reminder)
                    : 'Stored reminder · ${reminderFormat.format(reminder)}',
              ),
          ],
        ),
      ],
    );
  }
}

class _NoteTag extends StatelessWidget {
  const _NoteTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: colorScheme.onSecondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _Metadata extends StatelessWidget {
  const _Metadata({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(child: Icon(icon, size: 16, color: foreground)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: foreground),
          ),
        ),
      ],
    );
  }
}

enum _NoteAction { togglePin, archive, trash, restore, delete }

String _notePreview(String content) {
  const limit = 180;
  final value = content.trim();
  final graphemes = chars.Characters(value);
  if (graphemes.length <= limit) return value;
  return '${graphemes.take(limit - 1).toString().trimRight()}…';
}

String _noteSemanticValue(
  Note note,
  String preview,
  DateFormat dateFormat,
  DateFormat reminderFormat,
  bool supportsReminderScheduling,
) {
  final visibleTags = note.tags.take(2).toList(growable: false);
  final hiddenTagCount = note.tags.length - visibleTags.length;
  final tagsExtra = hiddenTagCount > 0 ? ', $hiddenTagCount more' : '';
  return [
    if (preview.isNotEmpty) preview,
    if (visibleTags.isNotEmpty)
      _tr(
        'common.tagsSemantics',
        namedArgs: {'tags': visibleTags.join(', '), 'extra': tagsExtra},
        fallback: 'Tags ${visibleTags.join(', ')}$tagsExtra',
      ),
    if (note.isPinned) _tr('common.pinned', fallback: 'Pinned'),
    _tr(
      'common.createdSemantics',
      namedArgs: {'date': dateFormat.format(note.createdAt)},
      fallback: 'Created ${dateFormat.format(note.createdAt)}',
    ),
    if (note.reminder case final reminder?)
      if (supportsReminderScheduling)
        _tr(
          'common.reminderSemantics',
          namedArgs: {'date': reminderFormat.format(reminder)},
          fallback: 'Reminder ${reminderFormat.format(reminder)}',
        )
      else
        '${_tr('common.storedReminderSemantics', namedArgs: {'date': reminderFormat.format(reminder)}, fallback: 'Stored reminder date ${reminderFormat.format(reminder)}. ')}Notifications unavailable on this device',
  ].join('. ');
}

String _displayTitle(Note note) {
  final title = note.title.trim();
  return title.isEmpty
      ? _tr('common.untitledNote', fallback: 'Untitled note')
      : title;
}

/// Resolves [key] through easy_localization's `Localization.instance`
/// singleton, falling back to [fallback] when the key isn't loaded there.
///
/// `.tr()` never throws for a missing ancestor — it reads the global
/// `Localization.instance` singleton directly (see easy_localization's
/// `public.dart`) — but several page-level widget trees that embed this
/// card (router/home/library/search) pump a bare `MaterialApp` in their
/// tests without ever building an `EasyLocalization` widget, so that
/// singleton never loads real translations there and `.tr()` would
/// silently return the raw key instead. Checking `trExists()` first keeps
/// those already-established test expectations intact while still
/// resolving real translations everywhere `EasyLocalization` is actually
/// wired up (the production app, and this widget's own test file).
String _tr(
  String key, {
  Map<String, String>? namedArgs,
  required String fallback,
}) {
  return key.trExists() ? key.tr(namedArgs: namedArgs) : fallback;
}
