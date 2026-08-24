import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:flutter_clean_notes/app/widgets/glass_surface.dart';

class NoteMetadataValue {
  NoteMetadataValue({
    required this.color,
    required List<String> tags,
    required this.reminder,
  }) : tags = List<String>.unmodifiable(tags);

  final Color color;
  final List<String> tags;
  final DateTime? reminder;
}

class NoteMetadataSheet extends StatefulWidget {
  const NoteMetadataSheet({required this.initialValue, this.now, super.key});

  final NoteMetadataValue initialValue;
  final DateTime Function()? now;

  @override
  State<NoteMetadataSheet> createState() => _NoteMetadataSheetState();
}

class _NoteMetadataSheetState extends State<NoteMetadataSheet> {
  static final _tints = <({String name, Color color})>[
    (name: 'white', color: Colors.white),
    (name: 'red', color: Colors.red.shade100),
    (name: 'blue', color: Colors.blue.shade100),
    (name: 'green', color: Colors.green.shade100),
    (name: 'yellow', color: Colors.yellow.shade100),
    (name: 'purple', color: Colors.purple.shade100),
    (name: 'orange', color: Colors.orange.shade100),
  ];

  late Color _color;
  late List<String> _tags;
  late DateTime? _reminder;
  final _tagController = TextEditingController();
  String? _tagError;
  String? _reminderError;
  int? _focusedTint;

  @override
  void initState() {
    super.initState();
    _color = widget.initialValue.color;
    _tags = List<String>.of(widget.initialValue.tags);
    _reminder = widget.initialValue.reminder;
  }

  @override
  void dispose() {
    _tagController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final duration = media.disableAnimations
        ? Duration.zero
        : const Duration(milliseconds: 200);

    return AnimatedPadding(
      duration: duration,
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        media.viewInsets.bottom + media.padding.bottom + 12,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          key: const Key('metadata-sheet'),
          constraints: BoxConstraints(
            maxWidth: 640,
            maxHeight: media.size.height * 0.9,
          ),
          child: GlassSurface(
            opacity: dark ? 0.94 : 0.92,
            blur: 18,
            borderRadius: BorderRadius.circular(28),
            padding: EdgeInsets.zero,
            child: SingleChildScrollView(
              key: const Key('metadata-scroll'),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Note details',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        key: const Key('metadata-close'),
                        tooltip: 'Cancel',
                        onPressed: _cancel,
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Tint',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [for (final tint in _tints) _tint(tint)],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Tags',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    key: const Key('metadata-tag-field'),
                    controller: _tagController,
                    textInputAction: TextInputAction.done,
                    enabled: true,
                    onSubmitted: _addTag,
                    decoration: InputDecoration(
                      labelText: 'New tag',
                      hintText: 'For example, work',
                      errorText: _tagError,
                      suffixIcon: IconButton(
                        key: const Key('metadata-add-tag'),
                        tooltip: 'Add tag',
                        onPressed: () => _addTag(_tagController.text),
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        icon: const Icon(Icons.add_rounded),
                      ),
                    ),
                  ),
                  if (_tags.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) => Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final tag in _tags)
                            _tag(tag, constraints.maxWidth),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    'Reminder',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: OutlinedButton.icon(
                          key: const Key('metadata-reminder-button'),
                          onPressed: _pickReminder,
                          icon: const Icon(Icons.alarm_rounded),
                          label: Text(
                            _reminder == null
                                ? 'Add reminder'
                                : DateFormat(
                                    'MMM d, yyyy h:mm a',
                                  ).format(_reminder!),
                          ),
                        ),
                      ),
                      if (_reminder != null)
                        ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 48),
                          child: TextButton.icon(
                            key: const Key('metadata-clear-reminder'),
                            onPressed: () => setState(() {
                              _reminder = null;
                              _reminderError = null;
                            }),
                            icon: const Icon(Icons.alarm_off_rounded),
                            label: const Text('Clear reminder'),
                          ),
                        ),
                    ],
                  ),
                  if (_reminderError case final error?) ...[
                    const SizedBox(height: 8),
                    Semantics(
                      key: const Key('metadata-reminder-error'),
                      liveRegion: true,
                      child: Text(
                        error,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Divider(color: colorScheme.outlineVariant),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: TextButton(
                          key: const Key('metadata-cancel'),
                          onPressed: _cancel,
                          child: const Text('Cancel'),
                        ),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: FilledButton(
                          key: const Key('metadata-apply'),
                          onPressed: _apply,
                          child: const Text('Apply'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tint(({String name, Color color}) option) {
    final tint = option.color;
    final tintValue = tint.toARGB32();
    final selected = tintValue == _color.toARGB32();
    final focused = tintValue == _focusedTint;
    final colorScheme = Theme.of(context).colorScheme;
    final foreground =
        _contrastRatio(tint, colorScheme.onSurface) >=
            _contrastRatio(tint, colorScheme.surface)
        ? colorScheme.onSurface
        : colorScheme.surface;
    return Semantics(
      key: ValueKey('metadata-tint-${tint.toARGB32()}'),
      button: true,
      selected: selected,
      label: selected
          ? 'Selected ${option.name} note tint'
          : 'Choose ${option.name} note tint',
      child: SizedBox.square(
        dimension: 48,
        child: Material(
          color: tint,
          shape: CircleBorder(
            side: BorderSide(
              color: foreground,
              width: selected || focused ? 3 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => setState(() => _color = tint),
            focusColor: Colors.transparent,
            onFocusChange: (hasFocus) {
              if (hasFocus) {
                setState(() => _focusedTint = tintValue);
              } else if (_focusedTint == tintValue) {
                setState(() => _focusedTint = null);
              }
            },
            child: selected
                ? Icon(Icons.check_rounded, color: foreground)
                : null,
          ),
        ),
      ),
    );
  }

  Widget _tag(String tag, double maxWidth) {
    final colorScheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Material(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(22),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Padding(
                padding: const EdgeInsets.only(left: 14),
                child: Text(tag),
              ),
            ),
            IconButton(
              key: ValueKey('metadata-remove-tag-$tag'),
              tooltip: 'Remove $tag tag',
              onPressed: () => setState(() => _tags.remove(tag)),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
      ),
    );
  }

  void _addTag(String raw) {
    final tag = raw.trim();
    if (tag.isEmpty) {
      setState(() => _tagError = 'Enter a tag');
      return;
    }
    if (_tags.contains(tag)) {
      setState(() => _tagError = 'Tag already added');
      return;
    }
    setState(() {
      _tags.add(tag);
      _tagController.clear();
      _tagError = null;
    });
  }

  Future<void> _pickReminder() async {
    final now = widget.now?.call() ?? DateTime.now();
    final roundedUpMinute = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 1));
    final futureDefault = roundedUpMinute.add(const Duration(minutes: 5));
    final initial = _reminder?.isAfter(now) ?? false
        ? _reminder!
        : futureDefault;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 10),
    );
    if (!mounted) return;
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (!mounted) return;
    if (time == null) return;
    final reminder = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    final validationNow = widget.now?.call() ?? DateTime.now();
    if (!reminder.isAfter(validationNow)) {
      setState(() => _reminderError = 'Choose a reminder time in the future');
      return;
    }
    setState(() {
      _reminder = reminder;
      _reminderError = null;
    });
  }

  void _cancel() => Navigator.of(context).pop();

  void _apply() {
    final reminder = _reminder;
    final reminderChanged = reminder != widget.initialValue.reminder;
    final now = widget.now?.call() ?? DateTime.now();
    if (reminderChanged && reminder != null && !reminder.isAfter(now)) {
      setState(() => _reminderError = 'Choose a reminder time in the future');
      return;
    }
    Navigator.of(
      context,
    ).pop(NoteMetadataValue(color: _color, tags: _tags, reminder: _reminder));
  }

  double _contrastRatio(Color first, Color second) {
    final firstLuminance = first.computeLuminance();
    final secondLuminance = second.computeLuminance();
    final lighter = firstLuminance >= secondLuminance
        ? firstLuminance
        : secondLuminance;
    final darker = firstLuminance < secondLuminance
        ? firstLuminance
        : secondLuminance;
    return (lighter + 0.05) / (darker + 0.05);
  }
}
