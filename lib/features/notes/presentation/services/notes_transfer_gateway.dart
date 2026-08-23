import 'dart:convert';
import 'dart:ui';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart' hide XFile;

class NotesTransferGateway {
  const NotesTransferGateway();

  Future<String?> pickJsonText() async {
    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        allowMultiple: false,
        withData: kIsWeb,
      );
    } catch (_) {
      throw const FormatException('Could not open the file picker. Try again.');
    }
    if (result == null) return null;
    if (result.files.length != 1) {
      throw const FormatException('Choose one JSON backup file.');
    }

    final file = result.files.single;
    final bytes = file.bytes;
    final XFile xFile;
    if (bytes != null) {
      if (bytes.isEmpty) {
        throw const FormatException('The selected backup file is empty.');
      }
      xFile = XFile.fromData(
        bytes,
        name: file.name,
        length: bytes.length,
        mimeType: 'application/json',
      );
    } else if (!kIsWeb) {
      final path = file.path;
      if (path == null || path.trim().isEmpty) {
        throw const FormatException(
          'The selected backup file could not be read.',
        );
      }
      xFile = XFile(
        path,
        name: file.name,
        length: file.size > 0 ? file.size : null,
      );
    } else {
      throw const FormatException(
        'The selected backup file could not be read.',
      );
    }

    try {
      var text = await xFile.readAsString(encoding: utf8);
      if (bytes != null) {
        text = utf8.decode(bytes, allowMalformed: false);
      }
      if (text.startsWith('\uFEFF')) text = text.substring(1);
      if (text.trim().isEmpty) {
        throw const FormatException('The selected backup file is empty.');
      }
      return text;
    } on FormatException catch (error) {
      if (error.message.contains('empty')) rethrow;
      throw const FormatException('The backup file is not valid UTF-8 text.');
    } catch (_) {
      throw const FormatException(
        'The selected backup file could not be read.',
      );
    }
  }

  Future<void> shareText({
    required String text,
    required String subject,
    Rect? sharePositionOrigin,
  }) async {
    if (text.trim().isEmpty) {
      throw const FormatException('Nothing to share.');
    }
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        subject: subject,
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }

  Future<void> shareFile({
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
    await SharePlus.instance.share(
      ShareParams(
        files: [file],
        fileNameOverrides: [fileName],
        sharePositionOrigin: sharePositionOrigin,
      ),
    );
  }
}
