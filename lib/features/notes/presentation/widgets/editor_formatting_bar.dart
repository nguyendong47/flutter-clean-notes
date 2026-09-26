import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:flutter_clean_notes/features/notes/presentation/widgets/audio_record_button.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/dictation_mic_button.dart';

class EditorFormattingBar extends StatelessWidget {
  const EditorFormattingBar({
    required this.controller,
    this.ensureNoteId,
    this.autoStartRecording = false,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;
  final Future<int> Function()? ensureNoteId;
  final bool autoStartRecording;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final controls = <Widget>[
      _iconControl(
        keyName: 'bold',
        label: 'editor.bold'.tr(),
        icon: Icons.format_bold_rounded,
        onPressed: () => _applyFormat('**', '**'),
      ),
      _iconControl(
        keyName: 'italic',
        label: 'editor.italic'.tr(),
        icon: Icons.format_italic_rounded,
        onPressed: () => _applyFormat('*', '*'),
      ),
      _iconControl(
        keyName: 'strike',
        label: 'editor.strikethrough'.tr(),
        icon: Icons.format_strikethrough_rounded,
        onPressed: () => _applyFormat('~~', '~~'),
      ),
      _iconControl(
        keyName: 'code',
        label: 'editor.inlineCode'.tr(),
        icon: Icons.code_rounded,
        onPressed: () => _applyFormat('`', '`'),
      ),
      _iconControl(
        keyName: 'quote',
        label: 'editor.quote'.tr(),
        icon: Icons.format_quote_rounded,
        onPressed: () => _toggleLinePrefix('> '),
      ),
      _textControl(
        keyName: 'h1',
        label: 'editor.heading1'.tr(),
        text: 'H1',
        highScaleIcon: Icons.looks_one_rounded,
        onPressed: () => _toggleLinePrefix('# '),
      ),
      _textControl(
        keyName: 'h2',
        label: 'editor.heading2'.tr(),
        text: 'H2',
        highScaleIcon: Icons.looks_two_rounded,
        onPressed: () => _toggleLinePrefix('## '),
      ),
      _iconControl(
        keyName: 'bullet',
        label: 'editor.bulletedList'.tr(),
        icon: Icons.format_list_bulleted_rounded,
        onPressed: () => _toggleLinePrefix('- '),
      ),
      _iconControl(
        keyName: 'checklist',
        label: 'editor.checklist'.tr(),
        icon: Icons.check_box_outlined,
        onPressed: () => _toggleLinePrefix('- [ ] '),
      ),
      DictationMicButton(controller: controller, enabled: enabled),
      AudioRecordButton(
        controller: controller,
        ensureNoteId: ensureNoteId ?? () async => 0,
        enabled: enabled,
        autoStart: autoStartRecording,
      ),
    ];

    return Semantics(
      container: true,
      label: 'editor.formattingTools'.tr(),
      child: SingleChildScrollView(
        key: const Key('editor-formatting-scroll'),
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var index = 0; index < controls.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              controls[index],
            ],
          ],
        ),
      ),
    );
  }

  Widget _iconControl({
    required String keyName,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox.square(
      key: Key('editor-format-$keyName'),
      dimension: 48,
      child: IconButton(
        tooltip: label,
        onPressed: enabled ? onPressed : null,
        icon: Icon(icon, size: 20),
      ),
    );
  }

  Widget _textControl({
    required String keyName,
    required String label,
    required String text,
    required IconData highScaleIcon,
    required VoidCallback onPressed,
  }) {
    return SizedBox.square(
      key: Key('editor-format-$keyName'),
      dimension: 48,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: Tooltip(
          message: label,
          child: TextButton(
            onPressed: enabled ? onPressed : null,
            style: TextButton.styleFrom(
              minimumSize: const Size.square(48),
              padding: EdgeInsets.zero,
            ),
            child: Builder(
              builder: (context) {
                final fontSize =
                    Theme.of(context).textTheme.labelLarge?.fontSize ?? 14;
                final useCompactIcon =
                    MediaQuery.textScalerOf(context).scale(fontSize) >=
                    fontSize * 2.5;
                return useCompactIcon
                    ? ExcludeSemantics(child: Icon(highScaleIcon, size: 20))
                    : Text(
                        text,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _applyFormat(String before, String after) {
    final text = controller.text;
    final selection = controller.selection;
    if (selection.isValid && !selection.isCollapsed) {
      final selected = text.substring(selection.start, selection.end);
      final newText = text.replaceRange(
        selection.start,
        selection.end,
        '$before$selected$after',
      );
      final newStart = selection.start + before.length;
      controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection(
          baseOffset: newStart,
          extentOffset: newStart + selected.length,
        ),
      );
      return;
    }

    final inserted = '$before$after';
    final position = selection.isValid ? selection.end : text.length;
    controller.value = TextEditingValue(
      text: text.substring(0, position) + inserted + text.substring(position),
      selection: TextSelection.collapsed(offset: position + before.length),
    );
  }

  void _toggleLinePrefix(String prefix) {
    final text = controller.text;
    final selection = controller.selection;
    var lineStart = selection.isValid ? selection.start : text.length;
    lineStart = text.lastIndexOf('\n', lineStart) + 1;
    var lineEnd = text.indexOf('\n', lineStart);
    if (lineEnd == -1) lineEnd = text.length;
    final line = text.substring(lineStart, lineEnd);
    final regex = RegExp('^\\s*${RegExp.escape(prefix)}');
    final newLine = regex.hasMatch(line)
        ? line.replaceFirst(regex, '')
        : '$prefix$line';
    final newText = text.replaceRange(lineStart, lineEnd, newLine);
    controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: lineStart + newLine.length),
    );
  }
}
