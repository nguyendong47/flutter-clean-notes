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

enum NotesTransferResult { completed, cancelled, unavailable, busy, failed }

enum NotesTransferOutcomeStatus { completed, shareSheetOpened }

class NotesTransferOutcome {
  const NotesTransferOutcome({
    required this.operation,
    this.importedCount,
    this.status = NotesTransferOutcomeStatus.completed,
  });

  final NotesTransferOperation operation;
  final int? importedCount;
  final NotesTransferOutcomeStatus status;
}

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
  FutureOr<NotesTransferOutcome?> build() => null;

  void beginSession() {
    if (_running) return;
    _operation = null;
    state = const AsyncData(null);
  }

  Future<NotesTransferResult> exportText({Rect? sharePositionOrigin}) {
    return _run(NotesTransferOperation.exportText, () async {
      final notes = await _notes();
      final shareResult = await ref
          .read(notesTransferGatewayProvider)
          .shareText(
            text: NoteExportFormatter.toText(notes),
            subject: 'My Notes',
            sharePositionOrigin: sharePositionOrigin,
          );
      return _shareOutcome(NotesTransferOperation.exportText, shareResult);
    });
  }

  Future<NotesTransferResult> backupJson({Rect? sharePositionOrigin}) {
    return _run(NotesTransferOperation.backupJson, () async {
      final notes = await _notes();
      final shareResult = await ref
          .read(notesTransferGatewayProvider)
          .shareFile(
            text: NoteExportFormatter.toJson(notes),
            fileName: 'notes_backup.json',
            mimeType: 'application/json',
            sharePositionOrigin: sharePositionOrigin,
          );
      return _shareOutcome(NotesTransferOperation.backupJson, shareResult);
    });
  }

  Future<NotesTransferResult> exportMarkdown({Rect? sharePositionOrigin}) {
    return _run(NotesTransferOperation.exportMarkdown, () async {
      final notes = await _notes();
      final shareResult = await ref
          .read(notesTransferGatewayProvider)
          .shareFile(
            text: NoteExportFormatter.toMarkdown(notes),
            fileName: 'notes.md',
            mimeType: 'text/markdown',
            sharePositionOrigin: sharePositionOrigin,
          );
      return _shareOutcome(NotesTransferOperation.exportMarkdown, shareResult);
    });
  }

  Future<NotesTransferResult> importBackup() {
    return _run(NotesTransferOperation.importBackup, () async {
      final payload = await ref
          .read(notesTransferGatewayProvider)
          .pickJsonText();
      if (payload == null) return null;
      final notes = NoteExportFormatter.fromJson(payload);
      await ref.read(notesProvider.notifier).importBackup(notes);
      return NotesTransferOutcome(
        operation: NotesTransferOperation.importBackup,
        importedCount: notes.length,
      );
    });
  }

  Future<List<Note>> _notes() async {
    final cached = ref.read(notesProvider).value;
    return cached ?? await ref.read(notesProvider.future);
  }

  NotesTransferOutcome? _shareOutcome(
    NotesTransferOperation operation,
    NotesShareResult shareResult,
  ) {
    return switch (shareResult) {
      NotesShareResult.completed => NotesTransferOutcome(operation: operation),
      NotesShareResult.dismissed => null,
      NotesShareResult.unavailable => NotesTransferOutcome(
        operation: operation,
        status: NotesTransferOutcomeStatus.shareSheetOpened,
      ),
    };
  }

  Future<NotesTransferResult> _run(
    NotesTransferOperation operation,
    Future<NotesTransferOutcome?> Function() action,
  ) async {
    if (_running) return NotesTransferResult.busy;
    _running = true;
    _operation = operation;
    state = const AsyncLoading();
    try {
      final outcome = await action();
      if (outcome == null) {
        _operation = null;
        state = const AsyncData(null);
        return NotesTransferResult.cancelled;
      }
      state = AsyncData(outcome);
      if (outcome.status == NotesTransferOutcomeStatus.shareSheetOpened) {
        return NotesTransferResult.unavailable;
      }
      return NotesTransferResult.completed;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return NotesTransferResult.failed;
    } finally {
      _running = false;
    }
  }
}
