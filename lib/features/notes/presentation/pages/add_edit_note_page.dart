import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';

class AddEditNotePage extends ConsumerStatefulWidget {
  final Note? note;

  const AddEditNotePage({super.key, this.note});

  @override
  ConsumerState<AddEditNotePage> createState() => _AddEditNotePageState();
}

class _AddEditNotePageState extends ConsumerState<AddEditNotePage> {
  late TextEditingController _titleController;
  late TextEditingController _contentController;
  late TextEditingController _tagController;
  late Color _selectedColor;
  late List<String> _tags;
  late DateTime? _reminder;
  bool _previewMode = false;

  final List<Color> _colors = [
    Colors.white,
    Colors.red.shade100,
    Colors.blue.shade100,
    Colors.green.shade100,
    Colors.yellow.shade100,
    Colors.purple.shade100,
    Colors.orange.shade100,
  ];

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.note?.title ?? '');
    _contentController = TextEditingController(
      text: widget.note?.content ?? '',
    );
    _tagController = TextEditingController();
    _selectedColor = widget.note != null
        ? Color(widget.note!.color)
        : _colors[0];
    _tags = List.of(widget.note?.tags ?? const []);
    _reminder = widget.note?.reminder;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    _tagController.dispose();
    super.dispose();
  }

  void _addTag(String raw) {
    final tag = raw.trim();
    if (tag.isEmpty) return;
    if (_tags.contains(tag)) {
      _tagController.clear();
      return;
    }
    setState(() {
      _tags.add(tag);
      _tagController.clear();
    });
  }

  void _applyFormat(String before, String after) {
    final text = _contentController.text;
    final sel = _contentController.selection;
    if (sel.isValid && !sel.isCollapsed) {
      final selected = text.substring(sel.start, sel.end);
      final newText = text.replaceRange(
        sel.start,
        sel.end,
        '$before$selected$after',
      );
      final newStart = sel.start + before.length;
      _contentController.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: newStart,
          extentOffset: newStart + selected.length,
        ),
      );
    } else {
      final inserted = '$before$after';
      final pos = sel.isValid ? sel.end : text.length;
      _contentController.value = TextEditingValue(
        text: text.substring(0, pos) + inserted + text.substring(pos),
        selection: TextSelection.collapsed(offset: pos + before.length),
      );
    }
  }

  void _toggleLinePrefix(String prefix) {
    final text = _contentController.text;
    final sel = _contentController.selection;
    var lineStart = sel.isValid ? sel.start : text.length;
    lineStart = text.lastIndexOf('\n', lineStart) + 1;
    var lineEnd = text.indexOf('\n', lineStart);
    if (lineEnd == -1) lineEnd = text.length;
    final line = text.substring(lineStart, lineEnd);
    final regex = RegExp('^\\s*${RegExp.escape(prefix)}');
    final newLine = regex.hasMatch(line)
        ? line.replaceFirst(regex, '')
        : '$prefix$line';
    final newText = text.replaceRange(lineStart, lineEnd, newLine);
    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: lineStart + newLine.length),
    );
  }

  Widget _formatButton(IconData icon, VoidCallback onTap, {String? label}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: label != null
          ? InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                child: Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            )
          : IconButton(
              icon: Icon(icon, size: 20),
              onPressed: onTap,
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
            ),
    );
  }

  Widget _buildFormatBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _formatButton(Icons.format_bold, () => _applyFormat('**', '**')),
          _formatButton(Icons.format_italic, () => _applyFormat('*', '*')),
          _formatButton(
            Icons.format_strikethrough,
            () => _applyFormat('~~', '~~'),
          ),
          _formatButton(Icons.code, () => _applyFormat('`', '`')),
          _formatButton(Icons.format_quote, () => _toggleLinePrefix('> ')),
          _formatButton(
            Icons.title,
            () => _toggleLinePrefix('# '),
            label: 'H1',
          ),
          _formatButton(
            Icons.text_fields,
            () => _toggleLinePrefix('## '),
            label: 'H2',
          ),
          _formatButton(
            Icons.format_list_bulleted,
            () => _toggleLinePrefix('- '),
          ),
          _formatButton(
            Icons.check_box_outlined,
            () => _toggleLinePrefix('- [ ] '),
          ),
        ],
      ),
    );
  }

  Future<void> _pickReminder() async {
    final now = DateTime.now();
    final initial = _reminder ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10),
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null) return;
    setState(() {
      _reminder = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _openLinkedNote(String title) async {
    final notes = ref.read(notesProvider).value ?? const [];
    final match = notes.where((n) =>
        n.title.trim().toLowerCase() == title.toLowerCase() && n.id != null);
    if (match.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Linked note not found. Create it first.')),
      );
      return;
    }
    if (!mounted) return;
    context.push('/note/${match.first.id}');
  }

  void _saveNote() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Note cannot be empty!')));
      return;
    }

    final note = Note(
      id: widget.note?.id,
      title: title,
      content: content,
      color: _selectedColor.toARGB32(),
      createdAt: widget.note?.createdAt ?? DateTime.now(),
      tags: _tags,
      status: widget.note?.status ?? NoteStatus.active,
      reminder: _reminder,
    );

    if (widget.note == null) {
      ref.read(notesProvider.notifier).addNote(note);
    } else {
      ref.read(notesProvider.notifier).updateNote(note);
    }

    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _selectedColor,
      appBar: AppBar(
        title: Text(widget.note == null ? 'Add Note' : 'Edit Note'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_previewMode ? Icons.edit : Icons.visibility),
            tooltip: _previewMode ? 'Edit' : 'Preview',
            onPressed: () => setState(() => _previewMode = !_previewMode),
          ),
          IconButton(icon: const Icon(Icons.save), onPressed: _saveNote),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildColorSwatches(),
            _buildTagEditor(),
            _buildReminderRow(),
            const Divider(),
            TextField(
              controller: _titleController,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: 'Title',
                border: InputBorder.none,
              ),
              maxLines: null,
            ),
            if (!_previewMode) _buildFormatBar(),
            const SizedBox(height: 8),
            TextField(
              controller: _contentController,
              style: const TextStyle(fontSize: 18),
              decoration: const InputDecoration(
                hintText: 'Type something...',
                border: InputBorder.none,
              ),
              minLines: 14,
              maxLines: null,
            ),
            if (_previewMode) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.black.withValues(alpha: 0.04),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: MarkdownBody(
                    data: _contentController.text.isEmpty
                        ? '_Nothing to preview._'
                        : _contentController.text,
                    onTapLink: (text, href, title) {
                      if (href != null && href.startsWith('note://')) {
                        final title = href.substring('note://'.length);
                        _openLinkedNote(title);
                      }
                    },
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildColorSwatches() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: _colors.map((color) {
          final selected = _selectedColor == color;
          return GestureDetector(
            onTap: () => setState(() => _selectedColor = color),
            child: Container(
              margin: const EdgeInsets.only(right: 10, bottom: 8),
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? Colors.black87 : Colors.grey.shade300,
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check, size: 20)
                  : const SizedBox(height: 0),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTagEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _tagController,
          onSubmitted: _addTag,
          decoration: const InputDecoration(
            hintText: 'Add tags (press enter)',
            border: InputBorder.none,
          ),
        ),
        if (_tags.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _tags.map((tag) {
              return InputChip(
                label: Text(tag),
                onDeleted: () => setState(() => _tags.remove(tag)),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildReminderRow() {
    final text = _reminder == null
        ? 'Add reminder'
        : 'Reminder: ${DateFormat('MMM d, yyyy h:mm a').format(_reminder!)}';
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.alarm_add),
          onPressed: _pickReminder,
          tooltip: 'Add reminder',
        ),
        Expanded(
          child: InkWell(
            onTap: _pickReminder,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(text, style: const TextStyle(fontSize: 14)),
            ),
          ),
        ),
        if (_reminder != null)
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => setState(() => _reminder = null),
            tooltip: 'Remove reminder',
          ),
      ],
    );
  }
}
