import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter_clean_notes/features/notes/data/repositories/audio_attachment_repository.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/audio_attachment_repository_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/audio_recording_service_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/audio_recording_service.dart';

class AudioRecordButton extends ConsumerStatefulWidget {
  const AudioRecordButton({
    required this.controller,
    required this.ensureNoteId,
    this.enabled = true,
    this.autoStart = false,
    super.key,
  });

  final TextEditingController controller;
  final Future<int> Function() ensureNoteId;
  final bool enabled;
  final bool autoStart;

  @override
  ConsumerState<AudioRecordButton> createState() => _AudioRecordButtonState();
}

class _AudioRecordButtonState extends ConsumerState<AudioRecordButton> {
  AudioRecordingState _state = AudioRecordingState.idle;
  AudioRecordingService? _service;
  StreamSubscription<AudioRecordingState>? _stateSub;
  int? _pendingInsertOffset;
  bool _autoStarted = false;

  @override
  Widget build(BuildContext context) {
    final service = ref.watch(audioRecordingServiceProvider);
    _subscribeIfNeeded(service);
    _maybeAutoStart(service);
    return IconButton(
      tooltip: _state == AudioRecordingState.unavailable
          ? 'editor.audioRecordUnavailable'.tr()
          : 'editor.audioRecord'.tr(),
      icon: Icon(
        _state == AudioRecordingState.recording
            ? Icons.stop_circle_rounded
            : Icons.fiber_manual_record_outlined,
      ),
      onPressed:
          (!widget.enabled ||
              !_isSupported ||
              _state == AudioRecordingState.unavailable)
          ? null
          : () => _toggle(service),
    );
  }

  bool get _isSupported =>
      isAudioRecordingSupported() ||
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.android ||
              defaultTargetPlatform == TargetPlatform.iOS));

  void _subscribeIfNeeded(AudioRecordingService service) {
    if (identical(_service, service)) return;
    _stateSub?.cancel();
    _service = service;
    _state = service.currentState;
    _stateSub = service.stateStream.listen(_handleState);
  }

  void _maybeAutoStart(AudioRecordingService service) {
    if (_autoStarted || !widget.autoStart) return;
    _autoStarted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _toggle(service));
  }

  void _handleState(AudioRecordingState state) {
    if (!mounted) return;
    setState(() => _state = state);
    if (state == AudioRecordingState.error) {
      _showSnackBar('editor.audioRecordError'.tr());
    } else if (state == AudioRecordingState.unavailable) {
      _showSnackBar('editor.audioRecordUnavailable'.tr());
    } else if (state == AudioRecordingState.permissionDenied) {
      _showSnackBar('editor.dictationPermissionDenied'.tr());
    } else if (state == AudioRecordingState.permissionPermanentlyDenied) {
      _showSnackBar('editor.dictationPermissionPermanentlyDenied'.tr());
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggle(AudioRecordingService service) async {
    if (_state == AudioRecordingState.recording) {
      final result = await service.stop();
      if (result == null || !mounted) return;
      final noteId = await widget.ensureNoteId();
      final repo = ref.read(audioAttachmentRepositoryProvider);
      final id = await repo.addAttachment(
        noteId: noteId,
        filePath: result.filePath,
        durationMs: result.durationMs,
        waveform: result.waveform,
      );
      _insertEmbed(id);
    } else {
      _pendingInsertOffset = widget.controller.selection.isValid
          ? widget.controller.selection.start
          : widget.controller.text.length;
      await widget.ensureNoteId();
      await service.start();
    }
  }

  void _insertEmbed(String attachmentId) {
    final controller = widget.controller;
    final offset = _pendingInsertOffset ?? controller.text.length;
    final embed = buildAudioEmbed(attachmentId);
    final newText = controller.text.replaceRange(offset, offset, embed);
    controller.value = controller.value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: offset + embed.length),
      composing: TextRange.empty,
    );
  }

  @override
  void dispose() {
    _stateSub?.cancel();
    super.dispose();
  }
}
