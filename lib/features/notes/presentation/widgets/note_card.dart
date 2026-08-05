import 'package:flutter/material.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:intl/intl.dart';

class NoteCard extends StatelessWidget {
  final Note note;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onArchive;
  final VoidCallback onRestore;
  final VoidCallback onTrash;
  final VoidCallback onDelete;

  const NoteCard({
    super.key,
    required this.note,
    required this.onTap,
    required this.onTogglePin,
    required this.onArchive,
    required this.onRestore,
    required this.onTrash,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Color(note.color),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        splashColor: Colors.black.withValues(alpha: 0.08),
        highlightColor: Colors.black.withValues(alpha: 0.05),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      note.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buildActions(context),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Text(
                  note.content,
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 10),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat('MMM dd, yyyy').format(note.createdAt),
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        if (note.reminder != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                Icon(
                  note.reminder!.isBefore(DateTime.now())
                      ? Icons.alarm_off
                      : Icons.alarm,
                  size: 14,
                  color: note.reminder!.isBefore(DateTime.now())
                      ? Colors.red.shade700
                      : Colors.black54,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    DateFormat('MMM d, h:mm a').format(note.reminder!),
                    style: TextStyle(
                      fontSize: 12,
                      color: note.reminder!.isBefore(DateTime.now())
                          ? Colors.red.shade700
                          : Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (note.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: note.tags
                .map(
                  (tag) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '#$tag',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildActions(BuildContext context) {
    if (note.status != NoteStatus.active) {
      return _MenuButton(
        onSelected: (value) {
          switch (value) {
            case 'restore':
              onRestore();
              break;
            case 'trash':
              onTrash();
              break;
            case 'delete':
              onDelete();
              break;
          }
        },
        items: [
          if (note.status == NoteStatus.archived)
            const PopupMenuItem(value: 'restore', child: Text('Unarchive')),
          if (note.status == NoteStatus.trashed)
            const PopupMenuItem(value: 'restore', child: Text('Restore')),
          const PopupMenuItem(value: 'trash', child: Text('Trash')),
          const PopupMenuItem(value: 'delete', child: Text('Delete forever')),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: IconButton(
            key: ValueKey(note.isPinned),
            icon: Icon(
              note.isPinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 20,
              color: note.isPinned ? Colors.amber.shade800 : Colors.black54,
            ),
            onPressed: onTogglePin,
            constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            padding: EdgeInsets.zero,
          ),
        ),
        _MenuButton(
          onSelected: (value) {
            switch (value) {
              case 'archive':
                onArchive();
                break;
              case 'trash':
                onTrash();
                break;
              case 'delete':
                onDelete();
                break;
            }
          },
          items: const [
            PopupMenuItem(value: 'archive', child: Text('Archive')),
            PopupMenuItem(value: 'trash', child: Text('Trash')),
            PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ],
    );
  }
}

class _MenuButton extends StatelessWidget {
  final void Function(String) onSelected;
  final List<PopupMenuItem<String>> items;

  const _MenuButton({required this.onSelected, required this.items});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, color: Colors.black54),
      onSelected: onSelected,
      itemBuilder: (context) => items,
      iconSize: 22,
    );
  }
}
