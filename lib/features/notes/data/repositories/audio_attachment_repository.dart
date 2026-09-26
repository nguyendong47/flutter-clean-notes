import 'dart:convert';
import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';

final class AudioAttachment {
  const AudioAttachment({
    required this.id,
    required this.noteId,
    required this.filePath,
    required this.durationMs,
    required this.waveform,
    required this.createdAt,
  });

  final String id;
  final int noteId;
  final String filePath;
  final int durationMs;
  final List<double> waveform;
  final DateTime createdAt;
}

String buildAudioEmbed(String attachmentId) =>
    '![audio](attachment://$attachmentId)';

String removeAudioEmbed(String noteText, String attachmentId) {
  final embed = buildAudioEmbed(attachmentId);
  return noteText.replaceAll('$embed\n', '').replaceAll(embed, '');
}

abstract interface class AudioAttachmentRepository {
  Future<String> addAttachment({
    required int noteId,
    required String filePath,
    required int durationMs,
    required List<double> waveform,
  });

  Future<void> deleteAttachment(String id);

  Future<void> deleteAttachmentsForNote(int noteId);

  Future<List<AudioAttachment>> attachmentsForNote(int noteId);

  Future<AudioAttachment?> getAttachment(String id);
}

class AudioAttachmentRepositoryImpl implements AudioAttachmentRepository {
  AudioAttachmentRepositoryImpl({
    required AudioAttachmentDataSource dataSource,
    Uuid? uuid,
  }) : _dataSource = dataSource,
       _uuid = uuid ?? const Uuid();

  final AudioAttachmentDataSource _dataSource;
  final Uuid _uuid;

  @override
  Future<String> addAttachment({
    required int noteId,
    required String filePath,
    required int durationMs,
    required List<double> waveform,
  }) async {
    final id = _uuid.v4();
    await _dataSource.insertAudioAttachment(
      id: id,
      noteId: noteId,
      filePath: filePath,
      durationMs: durationMs,
      waveformData: jsonEncode(waveform),
      createdAt: DateTime.now().toIso8601String(),
    );
    return id;
  }

  @override
  Future<void> deleteAttachment(String id) async {
    final row = await _dataSource.getAudioAttachment(id);
    await _dataSource.deleteAudioAttachment(id);
    if (row != null) {
      await File(
        row['filePath'] as String,
      ).delete().catchError((_) => File(row['filePath'] as String));
    }
  }

  @override
  Future<void> deleteAttachmentsForNote(int noteId) async {
    final rows = await _dataSource.audioAttachmentsForNote(noteId);
    for (final row in rows) {
      await File(
        row['filePath'] as String,
      ).delete().catchError((_) => File(row['filePath'] as String));
    }
    await _dataSource.deleteAudioAttachmentsForNote(noteId);
  }

  @override
  Future<List<AudioAttachment>> attachmentsForNote(int noteId) async {
    final rows = await _dataSource.audioAttachmentsForNote(noteId);
    return rows.map(_fromRow).toList();
  }

  @override
  Future<AudioAttachment?> getAttachment(String id) async {
    final row = await _dataSource.getAudioAttachment(id);
    return row == null ? null : _fromRow(row);
  }

  AudioAttachment _fromRow(Map<String, Object?> row) {
    return AudioAttachment(
      id: row['id'] as String,
      noteId: row['noteId'] as int,
      filePath: row['filePath'] as String,
      durationMs: row['durationMs'] as int,
      waveform: (jsonDecode(row['waveformData'] as String) as List)
          .cast<num>()
          .map((n) => n.toDouble())
          .toList(),
      createdAt: DateTime.parse(row['createdAt'] as String),
    );
  }
}
