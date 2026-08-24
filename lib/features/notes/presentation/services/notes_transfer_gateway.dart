import 'dart:convert';
import 'dart:ui';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart' hide XFile;

enum NotesShareResult { completed, dismissed, unavailable }

typedef JsonFilePicker =
    Future<List<PlatformFile>?> Function({
      required FileType type,
      required List<String> allowedExtensions,
    });

class NotesTransferGateway {
  const NotesTransferGateway({
    @visibleForTesting Future<ShareResult> Function(ShareParams)? share,
    @visibleForTesting JsonFilePicker? pickJsonFiles,
  }) : _share = share,
       _pickJsonFiles = pickJsonFiles;

  final Future<ShareResult> Function(ShareParams)? _share;
  final JsonFilePicker? _pickJsonFiles;

  /// Caps decode and JSON parsing memory for imports on mobile devices.
  static const int _maxImportBytes = 10 * 1024 * 1024;

  Future<String?> pickJsonText() async {
    final List<PlatformFile>? result;
    try {
      final picker = _pickJsonFiles;
      result = picker == null
          ? await _pickSingleJsonFile()
          : await picker(
              type: FileType.custom,
              allowedExtensions: const ['json'],
            );
    } catch (_) {
      throw const FormatException('Could not open the file picker. Try again.');
    }
    if (result == null) return null;
    if (result.length != 1) {
      throw const FormatException('Choose one JSON backup file.');
    }

    final file = result.single;

    try {
      _checkImportSize(await file.length());
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        throw const FormatException('The selected backup file is empty.');
      }
      _checkImportSize(bytes.length);
      var text = utf8.decode(bytes, allowMalformed: false);
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      if (text.trim().isEmpty) {
        throw const FormatException('The selected backup file is empty.');
      }
      return text;
    } on FormatException catch (error) {
      if (error.message.contains('empty') ||
          error.message.contains('too large')) {
        rethrow;
      }
      throw const FormatException('The backup file is not valid UTF-8 text.');
    } catch (_) {
      throw const FormatException(
        'The selected backup file could not be read.',
      );
    }
  }

  static Future<List<PlatformFile>?> _pickSingleJsonFile() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    return file == null ? null : [file];
  }

  static void _checkImportSize(int byteLength) {
    if (byteLength > _maxImportBytes) {
      throw const FormatException(
        'The selected backup file is too large. Choose a file up to 10 MB.',
      );
    }
  }

  Future<NotesShareResult> shareText({
    required String text,
    required String subject,
    Rect? sharePositionOrigin,
  }) async {
    if (text.trim().isEmpty) {
      throw const FormatException('Nothing to share.');
    }
    return _shareContent(
      ShareParams(
        text: text,
        subject: subject,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  Future<NotesShareResult> shareFile({
    required String text,
    required String fileName,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    if (text.trim().isEmpty) {
      throw const FormatException('Nothing to share.');
    }
    if (fileName.trim().isEmpty || mimeType.trim().isEmpty) {
      throw const FormatException('Shared file details are invalid.');
    }

    final file = XFile.fromData(
      Uint8List.fromList(utf8.encode(text)),
      mimeType: mimeType,
      name: fileName,
    );
    return _shareContent(
      ShareParams(
        files: [file],
        fileNameOverrides: [fileName],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  Future<NotesShareResult> _shareContent(ShareParams params) async {
    final result =
        await (_share?.call(params) ?? SharePlus.instance.share(params));
    return switch (result.status) {
      ShareResultStatus.success => NotesShareResult.completed,
      ShareResultStatus.dismissed => NotesShareResult.dismissed,
      ShareResultStatus.unavailable => NotesShareResult.unavailable,
    };
  }
}
