import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'package:flutter_clean_notes/features/notes/data/repositories/audio_attachment_repository.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/audio_attachment_repository_provider.dart';

class AudioPlayerBlock extends ConsumerStatefulWidget {
  const AudioPlayerBlock({
    required this.attachmentId,
    this.onDeleted,
    this.player,
    super.key,
  });

  final String attachmentId;
  final VoidCallback? onDeleted;
  final AudioPlayer? player;

  @override
  ConsumerState<AudioPlayerBlock> createState() => _AudioPlayerBlockState();
}

class _AudioPlayerBlockState extends ConsumerState<AudioPlayerBlock> {
  AudioAttachment? _attachment;
  bool _fileMissing = false;
  bool _loaded = false;
  late final AudioPlayer _player;
  late final bool _ownsPlayer;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _speed = 1.0;
  bool _hasError = false;

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  static const List<double> _speeds = [1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    if (widget.player != null) {
      _player = widget.player!;
      _ownsPlayer = false;
    } else {
      _player = AudioPlayer();
      _ownsPlayer = true;
    }

    _playerStateSub = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      setState(() {
        _isPlaying = state.playing;
        if (state.processingState == ProcessingState.completed) {
          _isPlaying = false;
          _position = Duration.zero;
        }
      });
    });

    _positionSub = _player.positionStream.listen((pos) {
      if (!mounted) return;
      setState(() => _position = pos);
    });

    _durationSub = _player.durationStream.listen((dur) {
      if (!mounted || dur == null) return;
      setState(() => _duration = dur);
    });

    _loadAttachment();
  }

  Future<void> _loadAttachment() async {
    AudioAttachment? attachment;
    try {
      attachment = await ref
          .read(audioAttachmentRepositoryProvider)
          .getAttachment(widget.attachmentId);
    } catch (_) {
      attachment = null;
    }

    // A row that exists but whose file has been moved/deleted/corrupted
    // outside the app is a distinct case from "no such attachment at all":
    // per the spec, it still shows the unavailable placeholder, but keeps
    // its delete affordance so the user can clear the dead reference -
    // whereas a genuinely missing row has nothing valid left to delete by id.
    final fileMissing =
        attachment != null && !File(attachment.filePath).existsSync();

    if (!mounted) return;
    setState(() {
      _attachment = attachment;
      _fileMissing = fileMissing;
      _loaded = true;
      if (attachment != null) {
        _duration = Duration(milliseconds: attachment.durationMs);
      }
    });
  }

  Future<void> _togglePlay() async {
    final attachment = _attachment;
    if (attachment == null) return;
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        if (_position == Duration.zero || _player.audioSource == null) {
          await _player.setFilePath(attachment.filePath);
        }
        await _player.play();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _hasError = true);
      }
    }
  }

  Future<void> _cycleSpeed() async {
    final currentIndex = _speeds.indexOf(_speed);
    final nextIndex = (currentIndex + 1) % _speeds.length;
    final nextSpeed = _speeds[nextIndex];
    setState(() => _speed = nextSpeed);
    try {
      await _player.setSpeed(nextSpeed);
    } catch (_) {}
  }

  Future<void> _skip(Duration delta) async {
    final targetMs = (_position + delta).inMilliseconds.clamp(
      0,
      _duration.inMilliseconds,
    );
    final newPos = Duration(milliseconds: targetMs);
    setState(() => _position = newPos);
    try {
      await _player.seek(newPos);
    } catch (_) {}
  }

  Future<void> _delete() async {
    try {
      await ref
          .read(audioAttachmentRepositoryProvider)
          .deleteAttachment(widget.attachmentId);
    } catch (_) {}
    widget.onDeleted?.call();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    if (_ownsPlayer) {
      _player.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loaded && (_attachment == null || _fileMissing)) {
      final deletableId = _attachment?.id;
      return Semantics(
        key: const Key('editor-markdown-image-placeholder'),
        container: true,
        image: true,
        label: 'editor.audioUnavailable'.tr(),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: 0.72,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.image_not_supported_outlined,
                    size: 20,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                // A missing DB row has nothing valid to delete by id; a
                // missing file with a row still present keeps the delete
                // affordance so the user can clear the dead reference.
                if (deletableId != null)
                  IconButton(
                    key: Key('audio-player-delete-$deletableId'),
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    color: theme.colorScheme.error,
                    tooltip: 'Delete audio',
                    onPressed: _delete,
                  ),
              ],
            ),
          ),
        ),
      );
    }

    if (!_loaded) {
      return const SizedBox(height: 72);
    }

    final attachment = _attachment!;
    final waveform = attachment.waveform;
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (waveform.isNotEmpty)
            SizedBox(
              height: 36,
              child: CustomPaint(
                painter: _WaveformPainter(
                  waveform: waveform,
                  progress: progress,
                  playedColor: theme.colorScheme.primary,
                  unplayedColor: theme.colorScheme.primary.withValues(
                    alpha: 0.3,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  size: 28,
                ),
                color: theme.colorScheme.primary,
                tooltip: _isPlaying ? 'Pause' : 'Play',
                onPressed: _togglePlay,
              ),
              GestureDetector(
                onLongPress: () => _skip(const Duration(seconds: -10)),
                child: IconButton(
                  icon: const Icon(Icons.replay_5_rounded, size: 22),
                  tooltip: 'Rewind 5s (long press 10s)',
                  onPressed: () => _skip(const Duration(seconds: -5)),
                ),
              ),
              GestureDetector(
                onLongPress: () => _skip(const Duration(seconds: 10)),
                child: IconButton(
                  icon: const Icon(Icons.forward_5_rounded, size: 22),
                  tooltip: 'Forward 5s (long press 10s)',
                  onPressed: () => _skip(const Duration(seconds: 5)),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${_formatDuration(_position)} / ${_formatDuration(_duration)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _cycleSpeed,
                style: TextButton.styleFrom(
                  minimumSize: const Size(40, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: Text(
                  '${_speed}x',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                key: Key('audio-player-delete-${widget.attachmentId}'),
                icon: const Icon(Icons.delete_outline_rounded, size: 22),
                color: theme.colorScheme.error,
                tooltip: 'Delete audio',
                onPressed: _delete,
              ),
            ],
          ),
          if (_hasError)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'editor.audioRecordError'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.waveform,
    required this.progress,
    required this.playedColor,
    required this.unplayedColor,
  });

  final List<double> waveform;
  final double progress;
  final Color playedColor;
  final Color unplayedColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (waveform.isEmpty) return;
    final barCount = waveform.length;
    const spacing = 2.0;
    final totalSpacing = spacing * (barCount - 1);
    final barWidth = ((size.width - totalSpacing) / barCount).clamp(1.0, 8.0);
    final paint = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.fill;

    for (var i = 0; i < barCount; i++) {
      final x = i * (barWidth + spacing);
      final heightRatio = waveform[i].clamp(0.1, 1.0);
      final barHeight = heightRatio * size.height;
      final y = (size.height - barHeight) / 2;

      final barProgress = (i + 1) / barCount;
      paint.color = barProgress <= progress ? playedColor : unplayedColor;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.waveform != waveform ||
      oldDelegate.playedColor != playedColor ||
      oldDelegate.unplayedColor != unplayedColor;
}
