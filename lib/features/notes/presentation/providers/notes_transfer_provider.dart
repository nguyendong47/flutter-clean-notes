import 'dart:async';
import 'dart:ui';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/note_export_formatter.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/notes_transfer_gateway.dart';

part 'notes_transfer_provider.g.dart';

enum NotesTransferOperation {
  exportText,
  backupJson,
  exportMarkdown,
  importBackup,
}

enum NotesTransferResult { completed, cancelled, busy, failed }

@Riverpod(keepAlive: true)
NotesTransferGateway notesTransferGateway(Ref ref) {
  return const NotesTransferGateway();
}

@Riverpod(keepAlive: true)
class NotesTransfer extends _$NotesTransfer {
  NotesTransferOperation? _operation;
  bool _running = false;

  NotesTransferOperation? get operation => _operation;

  @override
  FutureOr<NotesTransferOperation?> build() => null;

  Future<NotesTransferResult> exportText({Rect? sharePositionOrigin}) {
    return _run(NotesTransferOperation.exportText, () async {
      final notes = await _notes();
      await ref
          .read(notesTransferGatewayProvider)
          .shareText(
            text: NoteExportFormatter.toText(notes),
            subject: 'My Notes',
            sharePositionOrigin: sharePositionOrigin,
          );
      return true;
    });
  }

  Future<NotesTransferResult> backupJson({Rect? sharePositionOrigin}) {
    return _run(NotesTransferOperation.backupJson, () async {
      final notes = await _notes();
      await ref
          .read(notesTransferGatewayProvider)
          .shareFile(
            text: NoteExportFormatter.toJson(notes),
            fileName: 'notes_backup.json',
            mimeType: 'application/json',
            sharePositionOrigin: sharePositionOrigin,
          );
      return true;
    });
  }

  Future<NotesTransferResult> exportMarkdown({Rect? sharePositionOrigin}) {
    return _run(NotesTransferOperation.exportMarkdown, () async {
      final notes = await _notes();
      await ref
          .read(notesTransferGatewayProvider)
          .shareFile(
            text: NoteExportFormatter.toMarkdown(notes),
            fileName: 'notes.md',
            mimeType: 'text/markdown',
            sharePositionOrigin: sharePositionOrigin,
          );
      return true;
    });
  }

  Future<NotesTransferResult> importBackup() {
    return _run(NotesTransferOperation.importBackup, () async {
      final payload = await ref
          .read(notesTransferGatewayProvider)
          .pickJsonText();
      if (payload == null) return false;
      final notes = NoteExportFormatter.fromJson(payload);
      await ref.read(notesProvider.notifier).importBackup(notes);
      return true;
    });
  }

  Future<List<Note>> _notes() async {
    final cached = ref.read(notesProvider).value;
    return cached ?? await ref.read(notesProvider.future);
  }

  Future<NotesTransferResult> _run(
    NotesTransferOperation operation,
    Future<bool> Function() action,
  ) async {
    if (_running) return NotesTransferResult.busy;
    _running = true;
    _operation = operation;
    state = const AsyncLoading();
    try {
      final completed = await action();
      if (!completed) {
        _operation = null;
        state = const AsyncData(null);
        return NotesTransferResult.cancelled;
      }
      state = AsyncData(operation);
      return NotesTransferResult.completed;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return NotesTransferResult.failed;
    } finally {
      _running = false;
    }
  }
}
