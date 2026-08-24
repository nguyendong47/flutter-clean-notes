import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart' hide XFile;

import 'notes_transfer_web_options.dart'
    if (dart.library.js_interop) 'notes_transfer_web_options.web.dart';

enum NotesShareResult {
  completed,
  dismissed,
  unavailable,
  webShareOrDownloadStarted,
}

typedef JsonFilePicker =
    Future<List<PlatformFile>?> Function({
      required FileType type,
      required List<String> allowedExtensions,
      required bool withData,
      required bool withReadStream,
    });

class NotesTransferGateway {
  const NotesTransferGateway({
    @visibleForTesting Future<ShareResult> Function(ShareParams)? share,
    @visibleForTesting JsonFilePicker? pickJsonFiles,
    @visibleForTesting bool? isWeb,
  }) : _share = share,
       _pickJsonFiles = pickJsonFiles,
       _isWeb = isWeb ?? kIsWeb;

  final Future<ShareResult> Function(ShareParams)? _share;
  final JsonFilePicker? _pickJsonFiles;
  final bool _isWeb;

  /// Caps decode and JSON parsing memory for imports on mobile devices.
  static const int _maxImportBytes = 10 * 1024 * 1024;

  Future<String?> pickJsonText() async {
    final List<PlatformFile>? result;
    try {
      final picker = _pickJsonFiles ?? _pickSingleJsonFile;
      result = await picker(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: false,
        withReadStream: true,
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
      final bytes = await _readImportBytes(file);
      if (bytes.isEmpty) {
        throw const FormatException('The selected backup file is empty.');
      }
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

  static Future<List<PlatformFile>?> _pickSingleJsonFile({
    required FileType type,
    required List<String> allowedExtensions,
    required bool withData,
    required bool withReadStream,
  }) async {
    final file = await FilePicker.pickFile(
      type: type,
      allowedExtensions: allowedExtensions,
      webOptions: notesTransferWebOptions(
        withData: withData,
        withReadStream: withReadStream,
      ),
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

  static Future<Uint8List> _readImportBytes(PlatformFile file) async {
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in file.readAsByteStream()) {
      _checkImportSize(bytes.length + chunk.length);
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  Future<NotesShareResult> shareText({
    required String text,
    required String subject,
    Rect? sharePositionOrigin,
  }) async {
    if (text.trim().isEmpty) {
      throw const FormatException('Nothing to share.');
    }
    if (_isWeb) {
      const fileName = 'notes.txt';
      final file = XFile.fromData(
        Uint8List.fromList(utf8.encode(text)),
        mimeType: 'text/plain',
        name: fileName,
      );
      return _shareContent(
        ShareParams(
          title: subject,
          files: [file],
          fileNameOverrides: const [fileName],
          sharePositionOrigin: sharePositionOrigin,
          downloadFallbackEnabled: true,
          mailToFallbackEnabled: false,
        ),
      );
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
        downloadFallbackEnabled: true,
        mailToFallbackEnabled: false,
      ),
    );
  }

  Future<NotesShareResult> _shareContent(ShareParams params) async {
    final result =
        await (_share?.call(params) ?? SharePlus.instance.share(params));
    return switch (result.status) {
      ShareResultStatus.success => NotesShareResult.completed,
      ShareResultStatus.dismissed => NotesShareResult.dismissed,
      ShareResultStatus.unavailable =>
        _isWeb
            ? NotesShareResult.webShareOrDownloadStarted
            : NotesShareResult.unavailable,
    };
  }
}
