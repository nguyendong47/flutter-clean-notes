import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/notes_transfer_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/note_export_formatter.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/notes_transfer_gateway.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/persisted_note_mutation_exception.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart'
    show ShareParams, ShareResult, ShareResultStatus;

import '../../../helpers/in_memory_note_repository.dart';
import '../../../helpers/note_fixtures.dart';

void main() {
  test('generated gateway provider is overridable', () {
    final gateway = _FakeNotesTransferGateway();
    final container = ProviderContainer(
      overrides: [notesTransferGatewayProvider.overrideWithValue(gateway)],
    );
    addTearDown(container.dispose);

    expect(container.read(notesTransferGatewayProvider), same(gateway));
  });

  test(
    'platform gateway rejects empty share payloads with readable errors',
    () {
      const gateway = NotesTransferGateway();

      expect(
        () => gateway.shareText(text: '  ', subject: 'Notes'),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('Nothing to share'),
          ),
        ),
      );
      expect(
        () => gateway.shareFile(
          text: '',
          fileName: 'notes.md',
          mimeType: 'text/markdown',
        ),
        throwsA(isA<FormatException>()),
      );
    },
  );

  test('platform gateway maps text and file share results', () async {
    const cases = [
      (
        platform: ShareResult('com.example.target', ShareResultStatus.success),
        expected: NotesShareResult.completed,
      ),
      (
        platform: ShareResult('', ShareResultStatus.dismissed),
        expected: NotesShareResult.dismissed,
      ),
      (
        platform: ShareResult.unavailable,
        expected: NotesShareResult.unavailable,
      ),
    ];

    for (final testCase in cases) {
      final gateway = NotesTransferGateway(
        share: (ShareParams _) async => testCase.platform,
      );

      expect(
        await gateway.shareText(text: 'Readable notes', subject: 'Notes'),
        testCase.expected,
      );
      expect(
        await gateway.shareFile(
          text: '{"notes":[]}',
          fileName: 'notes.json',
          mimeType: 'application/json',
        ),
        testCase.expected,
      );
    }
  });

  test(
    'web text export uses a downloadable file without a mailto body',
    () async {
      // Mutation caught: sending the note as ShareParams.text lets the web
      // fallback copy private note content into an email draft.
      ShareParams? captured;
      final gateway = NotesTransferGateway(
        isWeb: true,
        share: (params) async {
          captured = params;
          return ShareResult.unavailable;
        },
      );
      const origin = Rect.fromLTWH(8, 12, 44, 44);

      expect(
        await gateway.shareText(
          text: 'Private note body',
          subject: 'My Notes',
          sharePositionOrigin: origin,
        ),
        NotesShareResult.webShareOrDownloadStarted,
      );

      final params = captured!;
      expect(params.text, isNull);
      expect(params.subject, isNull);
      expect(params.title, 'My Notes');
      expect(params.files, hasLength(1));
      expect(params.fileNameOverrides, ['notes.txt']);
      expect(params.files!.single.mimeType, 'text/plain');
      expect(
        utf8.decode(await params.files!.single.readAsBytes()),
        'Private note body',
      );
      expect(params.mailToFallbackEnabled, isFalse);
      expect(params.downloadFallbackEnabled, isTrue);
      expect(params.sharePositionOrigin, origin);
    },
  );

  test('native text export keeps the direct platform share contract', () async {
    // Mutation caught: applying the web file workaround to native platforms
    // would replace their established plain-text share-sheet experience.
    ShareParams? captured;
    final gateway = NotesTransferGateway(
      isWeb: false,
      share: (params) async {
        captured = params;
        return ShareResult.unavailable;
      },
    );
    const origin = Rect.fromLTWH(4, 6, 44, 44);

    await gateway.shareText(
      text: 'Readable notes',
      subject: 'My Notes',
      sharePositionOrigin: origin,
    );

    final params = captured!;
    expect(params.text, 'Readable notes');
    expect(params.subject, 'My Notes');
    expect(params.files, isNull);
    expect(params.sharePositionOrigin, origin);
  });

  test('file export keeps download fallback and disables mailto', () async {
    ShareParams? captured;
    final gateway = NotesTransferGateway(
      share: (params) async {
        captured = params;
        return ShareResult.unavailable;
      },
    );

    await gateway.shareFile(
      text: '{"notes":[]}',
      fileName: 'notes.json',
      mimeType: 'application/json',
    );

    expect(captured!.downloadFallbackEnabled, isTrue);
    expect(captured!.mailToFallbackEnabled, isFalse);
  });

  test(
    'platform picker returns null on cancellation and configures JSON',
    () async {
      final picker = _FakeJsonFilePicker();
      final gateway = NotesTransferGateway(pickJsonFiles: picker.call);

      expect(await gateway.pickJsonText(), isNull);
      expect(picker.type, FileType.custom);
      expect(picker.allowedExtensions, ['json']);
      expect(picker.withData, isFalse);
      expect(picker.withReadStream, isTrue);
    },
  );

  test(
    'platform picker accepts unknown-size byte data and strips BOM',
    () async {
      final picker = _FakeJsonFilePicker()
        ..result = [
          _FakePlatformFile.memory(
            name: 'backup.json',
            bytes: Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x5B, 0x5D]),
            reportedLength: 0,
          ),
        ];
      final gateway = NotesTransferGateway(pickJsonFiles: picker.call);

      expect(await gateway.pickJsonText(), '[]');
    },
  );

  test('platform picker accepts exactly 10 MiB of UTF-8 data', () async {
    const maxImportBytes = NoteBackupImportLimits.maxUtf8Bytes;
    final bytes = Uint8List(maxImportBytes)..fillRange(0, maxImportBytes, 0x20);
    bytes[0] = 0x5B;
    bytes[maxImportBytes - 1] = 0x5D;
    final file = _FakePlatformFile.memory(name: 'backup.json', bytes: bytes);
    final picker = _FakeJsonFilePicker()..result = [file];
    final gateway = NotesTransferGateway(pickJsonFiles: picker.call);

    final text = await gateway.pickJsonText();

    expect(text, isNotNull);
    expect(utf8.encode(text!).length, maxImportBytes);
    expect(text.codeUnitAt(0), 0x5B);
    expect(text.codeUnitAt(text.length - 1), 0x5D);
    expect(file.lengthCalls, 1);
    expect(file.readAsByteStreamCalls, 1);
    expect(file.readAsBytesCalls, 0);
  });

  test('platform picker bounds unknown-size imports by actual bytes', () async {
    final file = _FakePlatformFile.memory(
      name: 'backup.json',
      bytes: Uint8List(NoteBackupImportLimits.maxUtf8Bytes + 1)
        ..fillRange(0, 1, 0x5B),
      reportedLength: 0,
    );
    final picker = _FakeJsonFilePicker()..result = [file];
    final gateway = NotesTransferGateway(pickJsonFiles: picker.call);

    await expectLater(
      gateway.pickJsonText(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'The selected backup file is too large. Choose a file up to 10 MB.',
        ),
      ),
    );
    expect(file.readAsByteStreamCalls, 1);
    expect(file.readAsBytesCalls, 0);
  });

  test(
    'platform picker stops unknown and misreported streams at 10 MiB plus one byte',
    () async {
      const maxImportBytes = NoteBackupImportLimits.maxUtf8Bytes;
      final maxSizedChunk = Uint8List(maxImportBytes);

      for (final reportedLength in [0, 1]) {
        final file = _FakePlatformFile.stream(
          name: 'backup.json',
          chunks: [
            maxSizedChunk,
            Uint8List.fromList([0x20]),
            Uint8List.fromList([0x5D]),
          ],
          reportedLength: reportedLength,
        );
        final picker = _FakeJsonFilePicker()..result = [file];
        final gateway = NotesTransferGateway(pickJsonFiles: picker.call);

        await expectLater(
          gateway.pickJsonText(),
          throwsA(
            isA<FormatException>().having(
              (error) => error.message,
              'message',
              'The selected backup file is too large. Choose a file up to 10 MB.',
            ),
          ),
        );
        expect(file.readAsByteStreamCalls, 1);
        expect(file.emittedChunkCount, 2);
        expect(file.streamCancelledEarly, isTrue);
        expect(file.readAsBytesCalls, 0);
      }
    },
  );

  test('platform picker accepts an unknown-size path-backed file', () async {
    final directory = await Directory.systemTemp.createTemp(
      'notes-transfer-gateway-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}backup.json');
    await file.writeAsString('[{"title":"path backed"}]');
    final pickedFile = _FakePlatformFile.path(
      name: 'backup.json',
      path: file.path,
      reportedLength: 0,
    );
    final picker = _FakeJsonFilePicker()..result = [pickedFile];
    final gateway = NotesTransferGateway(pickJsonFiles: picker.call);

    expect(await gateway.pickJsonText(), '[{"title":"path backed"}]');
    expect(pickedFile.lengthCalls, 1);
    expect(pickedFile.readAsByteStreamCalls, 1);
    expect(pickedFile.readAsBytesCalls, 0);
  });

  test('platform picker rejects a path-backed file over 10 MiB', () async {
    final directory = await Directory.systemTemp.createTemp(
      'notes-transfer-gateway-large-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}${Platform.pathSeparator}backup.json');
    final randomAccessFile = await file.open(mode: FileMode.write);
    await randomAccessFile.truncate(NoteBackupImportLimits.maxUtf8Bytes + 1);
    await randomAccessFile.close();
    final pickedFile = _FakePlatformFile.path(
      name: 'backup.json',
      path: file.path,
    );
    final picker = _FakeJsonFilePicker()..result = [pickedFile];
    final gateway = NotesTransferGateway(pickJsonFiles: picker.call);

    await expectLater(
      gateway.pickJsonText(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'The selected backup file is too large. Choose a file up to 10 MB.',
        ),
      ),
    );
    expect(pickedFile.lengthCalls, 1);
    expect(pickedFile.readAsByteStreamCalls, 0);
    expect(pickedFile.readAsBytesCalls, 0);
  });

  test('platform picker rejects multiple selected backup files', () async {
    final first = _FakePlatformFile.memory(
      name: 'first.json',
      bytes: Uint8List.fromList(utf8.encode('[]')),
    );
    final second = _FakePlatformFile.memory(
      name: 'second.json',
      bytes: Uint8List.fromList(utf8.encode('[]')),
    );
    final picker = _FakeJsonFilePicker()..result = [first, second];
    final gateway = NotesTransferGateway(pickJsonFiles: picker.call);

    await expectLater(
      gateway.pickJsonText(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          'Choose one JSON backup file.',
        ),
      ),
    );
    expect(first.lengthCalls, 0);
    expect(first.readAsBytesCalls, 0);
    expect(second.lengthCalls, 0);
    expect(second.readAsBytesCalls, 0);
  });

  test('platform picker rejects actual empty data after reading it', () async {
    final file = _FakePlatformFile.memory(
      name: 'backup.json',
      bytes: Uint8List(0),
    );
    final picker = _FakeJsonFilePicker()..result = [file];
    final gateway = NotesTransferGateway(pickJsonFiles: picker.call);

    await expectLater(
      gateway.pickJsonText(),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          contains('empty'),
        ),
      ),
    );
    expect(file.lengthCalls, 1);
    expect(file.readAsByteStreamCalls, 1);
    expect(file.readAsBytesCalls, 0);
  });

  test('platform picker exceptions are replaced with safe user copy', () async {
    final picker = _FakeJsonFilePicker()
      ..error = StateError(r'plugin leaked C:\private\backup.json');
    final gateway = NotesTransferGateway(pickJsonFiles: picker.call);

    await expectLater(
      gateway.pickJsonText(),
      throwsA(
        isA<FormatException>()
            .having(
              (error) => error.message,
              'message',
              'Could not open the file picker. Try again.',
            )
            .having(
              (error) => error.message,
              'sanitized message',
              isNot(contains('private')),
            ),
      ),
    );
  });

  test(
    'platform picker converts invalid input into readable format errors',
    () async {
      final picker = _FakeJsonFilePicker();
      final gateway = NotesTransferGateway(pickJsonFiles: picker.call);

      picker.result = [
        _FakePlatformFile.memory(
          name: 'backup.json',
          bytes: Uint8List.fromList([0xC3, 0x28]),
        ),
      ];
      await expectLater(
        gateway.pickJsonText(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('UTF-8'),
          ),
        ),
      );

      picker.result = [
        _FakePlatformFile.unreadable(name: 'backup.json', reportedLength: 5),
      ];
      await expectLater(
        gateway.pickJsonText(),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('could not be read'),
          ),
        ),
      );
    },
  );

  test(
    'share exposes loading then data and rejects overlapping work',
    () async {
      final gateway = _FakeNotesTransferGateway()
        ..shareGate = Completer<void>();
      final container = _container(gateway: gateway);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      final export = container
          .read(notesTransferProvider.notifier)
          .exportText(sharePositionOrigin: const Rect.fromLTWH(4, 8, 44, 44));

      expect(container.read(notesTransferProvider).isLoading, isTrue);
      expect(
        container.read(notesTransferProvider.notifier).operation,
        NotesTransferOperation.exportText,
      );
      await Future<void>.delayed(Duration.zero);
      expect(gateway.shareTextCalls, 1);
      expect(gateway.lastOrigin, const Rect.fromLTWH(4, 8, 44, 44));

      final overlap = await container
          .read(notesTransferProvider.notifier)
          .importBackup();
      expect(overlap, NotesTransferResult.busy);
      expect(gateway.pickCalls, 0);
      expect(container.read(notesTransferProvider).isLoading, isTrue);

      gateway.shareGate!.complete();
      expect(await export, NotesTransferResult.completed);
      expect(container.read(notesTransferProvider).hasValue, isTrue);
      expect(
        container.read(notesTransferProvider).value?.operation,
        NotesTransferOperation.exportText,
      );
      expect(gateway.lastSharedText, contains('Aurora design'));
    },
  );

  test(
    'readable exports include Active and Archive while excluding Trash',
    () async {
      // Mutation caught: passing the all-status collection directly to a
      // readable formatter would expose the trashed note in either payload.
      final gateway = _FakeNotesTransferGateway();
      final repository = InMemoryNoteRepository.seeded([
        _note(1, NoteStatus.active, const []),
        _note(2, NoteStatus.archived, const []),
        _note(3, NoteStatus.trashed, const []),
      ]);
      final container = _container(gateway: gateway, repository: repository);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      expect(
        await container.read(notesTransferProvider.notifier).exportText(),
        NotesTransferResult.completed,
      );
      expect(gateway.lastSharedText, contains('Note 1'));
      expect(gateway.lastSharedText, contains('Note 2'));
      expect(gateway.lastSharedText, isNot(contains('Note 3')));

      expect(
        await container.read(notesTransferProvider.notifier).exportMarkdown(),
        NotesTransferResult.completed,
      );
      expect(gateway.lastSharedText, contains('Note 1'));
      expect(gateway.lastSharedText, contains('Note 2'));
      expect(gateway.lastSharedText, isNot(contains('Note 3')));
    },
  );

  test(
    'readable exports reload committed statuses after a failed mutation refresh',
    () async {
      final gateway = _FakeNotesTransferGateway();
      final repository = InMemoryNoteRepository.seeded([
        _note(71, NoteStatus.active, const []),
        _note(72, NoteStatus.active, const []),
      ]);
      final container = _container(gateway: gateway, repository: repository);
      addTearDown(container.dispose);
      final cached = await container.read(notesProvider.future);
      final privateNote = cached.singleWhere((note) => note.id == 71);
      repository.getErrorAtCall = repository.getCalls + 1;

      await expectLater(
        container.read(notesProvider.notifier).trashNote(privateNote),
        throwsA(isA<PersistedNoteMutationException>()),
      );

      expect(
        repository.notes.singleWhere((note) => note.id == 71).status,
        NoteStatus.trashed,
      );
      expect(
        container
            .read(notesProvider)
            .value!
            .singleWhere((note) => note.id == 71)
            .status,
        NoteStatus.active,
      );
      repository.getErrorAtCall = null;

      expect(
        await container.read(notesTransferProvider.notifier).exportText(),
        NotesTransferResult.completed,
      );
      expect(gateway.lastSharedText, isNot(contains('Note 71')));
      expect(gateway.lastSharedText, contains('Note 72'));

      expect(
        await container.read(notesTransferProvider.notifier).exportMarkdown(),
        NotesTransferResult.completed,
      );
      expect(gateway.lastSharedText, isNot(contains('Note 71')));
      expect(gateway.lastSharedText, contains('Note 72'));
    },
  );

  test(
    'readable export waits for an in-flight Trash commit before sharing',
    () async {
      final gateway = _FakeNotesTransferGateway();
      final repository = _GatedStatusRepository.seeded([
        _note(81, NoteStatus.active, const []),
        _note(82, NoteStatus.active, const []),
      ]);
      final container = _container(gateway: gateway, repository: repository);
      addTearDown(container.dispose);
      final cached = await container.read(notesProvider.future);
      final privateNote = cached.singleWhere((note) => note.id == 81);

      final trash = container
          .read(notesProvider.notifier)
          .trashNote(privateNote);
      await repository.statusWriteEntered.future;
      final export = container
          .read(notesTransferProvider.notifier)
          .exportText();
      await Future<void>.delayed(Duration.zero);

      expect(gateway.shareTextCalls, 0);

      repository.releaseStatusWrite();
      await trash;
      expect(await export, NotesTransferResult.completed);
      expect(gateway.lastSharedText, isNot(contains('Note 81')));
      expect(gateway.lastSharedText, contains('Note 82'));
      expect(
        repository.notes.singleWhere((note) => note.id == 81).status,
        NoteStatus.trashed,
      );
    },
  );

  test('JSON backup includes Active, Archive, and Trash', () async {
    final gateway = _FakeNotesTransferGateway();
    final repository = InMemoryNoteRepository.seeded([
      _note(1, NoteStatus.active, const []),
      _note(2, NoteStatus.archived, const []),
      _note(3, NoteStatus.trashed, const []),
    ]);
    final container = _container(gateway: gateway, repository: repository);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);

    expect(
      await container.read(notesTransferProvider.notifier).backupJson(),
      NotesTransferResult.completed,
    );
    final payload = jsonDecode(gateway.lastSharedText!) as List<Object?>;
    final statuses = payload
        .cast<Map<String, Object?>>()
        .map((note) => note['status'])
        .toList(growable: false);

    expect(statuses, [0, 1, 2]);
  });

  test('invalid JSON backup is rejected before sharing private data', () async {
    const privateMarker = 'private-title-marker';
    final gateway = _FakeNotesTransferGateway();
    final repository = InMemoryNoteRepository.seeded([
      Note(
        id: 1,
        title:
            '$privateMarker${'x' * NoteBackupImportLimits.maxTitleCodeUnits}',
        content: '',
        color: 7,
        createdAt: DateTime.utc(2026, 8, 24),
      ),
    ]);
    final container = _container(gateway: gateway, repository: repository);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);

    final result = await container
        .read(notesTransferProvider.notifier)
        .backupJson();

    expect(result, NotesTransferResult.failed);
    expect(gateway.shareFileCalls, 0);
    expect(gateway.lastSharedText, isNull);
    expect(
      container.read(notesTransferProvider).error,
      isA<FormatException>().having(
        (error) => error.message,
        'sanitized message',
        isNot(contains(privateMarker)),
      ),
    );
  });

  test('dismissed share cancels and clears prior settled success', () async {
    final gateway = _FakeNotesTransferGateway();
    final container = _container(gateway: gateway);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);

    expect(
      await container.read(notesTransferProvider.notifier).exportText(),
      NotesTransferResult.completed,
    );
    expect(container.read(notesTransferProvider).requireValue, isNotNull);

    gateway.shareResult = NotesShareResult.dismissed;
    final result = await container
        .read(notesTransferProvider.notifier)
        .backupJson();

    expect(result, NotesTransferResult.cancelled);
    expect(container.read(notesTransferProvider).requireValue, isNull);
    expect(container.read(notesTransferProvider.notifier).operation, isNull);
  });

  test('unavailable share result remains a neutral settled outcome', () async {
    final gateway = _FakeNotesTransferGateway()
      ..shareResult = NotesShareResult.unavailable;
    final container = _container(gateway: gateway);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);

    final result = await container
        .read(notesTransferProvider.notifier)
        .exportMarkdown();

    expect(result, NotesTransferResult.unavailable);
    final outcome = container.read(notesTransferProvider).requireValue!;
    expect(outcome.operation, NotesTransferOperation.exportMarkdown);
    expect(outcome.status, NotesTransferOutcomeStatus.shareSheetOpened);
  });

  test('web share or download result exposes a truthful handoff', () async {
    final gateway = _FakeNotesTransferGateway()
      ..shareResult = NotesShareResult.webShareOrDownloadStarted;
    final container = _container(gateway: gateway);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);

    final result = await container
        .read(notesTransferProvider.notifier)
        .exportText();

    expect(result, NotesTransferResult.unavailable);
    final outcome = container.read(notesTransferProvider).requireValue!;
    expect(outcome.operation, NotesTransferOperation.exportText);
    expect(
      outcome.status,
      NotesTransferOutcomeStatus.webShareOrDownloadStarted,
    );
  });

  test(
    'picker cancellation is a silent no-op distinct from an error',
    () async {
      final gateway = _FakeNotesTransferGateway()..pickedJson = null;
      final repository = InMemoryNoteRepository.seeded(sampleNotes);
      final container = _container(gateway: gateway, repository: repository);
      addTearDown(container.dispose);
      final before = await container.read(notesProvider.future);

      final result = await container
          .read(notesTransferProvider.notifier)
          .importBackup();

      expect(result, NotesTransferResult.cancelled);
      expect(container.read(notesTransferProvider).hasError, isFalse);
      expect(container.read(notesTransferProvider).value, isNull);
      expect(repository.notes, hasLength(before.length));
    },
  );

  test(
    'import appends archived and trashed entries as Active copies without reminders',
    () async {
      final gateway = _FakeNotesTransferGateway()
        ..pickedJson = jsonEncode([
          {
            'id': 99,
            'title': 'Imported archive',
            'content': 'Safe append',
            'color': 17,
            'createdAt': '2026-08-22T10:00:00.000Z',
            'isPinned': 1,
            'tags': 'backup,work',
            'status': 1,
            'reminder': '2026-08-24T08:00:00.000Z',
          },
          {
            'id': 100,
            'title': 'Imported trash',
            'content': 'Safe append from Trash',
            'color': 18,
            'createdAt': '2026-08-23T10:00:00.000Z',
            'isPinned': 0,
            'tags': ['backup', 'trash'],
            'status': 2,
            'reminder': '2026-08-25T08:00:00.000Z',
          },
        ]);
      final repository = InMemoryNoteRepository.seeded(sampleNotes);
      final existingIds = repository.notes.map((note) => note.id).toSet();
      final container = _container(gateway: gateway, repository: repository);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      final result = await container
          .read(notesTransferProvider.notifier)
          .importBackup();

      expect(result, NotesTransferResult.completed);
      final importedArchive = repository.notes.singleWhere(
        (note) => note.title == 'Imported archive',
      );
      final importedTrash = repository.notes.singleWhere(
        (note) => note.title == 'Imported trash',
      );
      expect(importedArchive.id, isNot(99));
      expect(importedTrash.id, isNot(100));
      expect([
        importedArchive.status,
        importedTrash.status,
      ], everyElement(NoteStatus.active));
      expect([
        importedArchive.reminder,
        importedTrash.reminder,
      ], everyElement(isNull));
      expect(importedArchive.isPinned, isTrue);
      expect(importedArchive.tags, ['backup', 'work']);
      expect(importedTrash.tags, ['backup', 'trash']);
      expect(repository.notes.map((note) => note.id), containsAll(existingIds));
      expect(repository.notes, hasLength(sampleNotes.length + 2));
      final outcome = container.read(notesTransferProvider).requireValue!;
      expect(outcome.operation, NotesTransferOperation.importBackup);
      expect(outcome.importedCount, 2);
    },
  );

  test(
    'sequential legacy and current imports survive a malformed payload without discarding notes',
    () async {
      // Mutation caught: accepting only one historical JSON shape or clearing
      // the current collection after a later malformed import.
      final gateway = _FakeNotesTransferGateway()
        ..pickedJson = jsonEncode([
          {
            'title': 'Legacy backup note',
            'content': 'Legacy list tags and named status',
            'color': 17,
            'createdAt': '2026-08-22T10:00:00.000Z',
            'isPinned': true,
            'tags': ['legacy', 'work'],
            'status': 'archived',
            'reminder': null,
          },
        ]);
      final repository = InMemoryNoteRepository.seeded(sampleNotes);
      final originalIds = sampleNotes.map((note) => note.id).toSet();
      final container = _container(gateway: gateway, repository: repository);
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      expect(
        await container.read(notesTransferProvider.notifier).importBackup(),
        NotesTransferResult.completed,
      );
      gateway.pickedJson = jsonEncode([
        {
          'id': 904,
          'title': 'Current backup note',
          'content': 'Current comma tags and numeric status',
          'color': 18,
          'createdAt': '2026-08-23T10:00:00.000Z',
          'isPinned': 0,
          'tags': 'current,work',
          'status': 0,
          'reminder': null,
        },
      ]);
      expect(
        await container.read(notesTransferProvider.notifier).importBackup(),
        NotesTransferResult.completed,
      );
      final beforeMalformed = repository.notes.length;
      gateway.pickedJson = '{"not":"a list"}';

      expect(
        await container.read(notesTransferProvider.notifier).importBackup(),
        NotesTransferResult.failed,
      );
      expect(repository.notes, hasLength(beforeMalformed));
      expect(repository.notes, hasLength(sampleNotes.length + 2));
      expect(repository.notes.map((note) => note.id), containsAll(originalIds));
      expect(
        repository.notes.map((note) => note.title),
        containsAll(['Legacy backup note', 'Current backup note']),
      );
      expect(
        repository.notes.where((note) => note.title == 'Legacy backup note'),
        hasLength(1),
      );
      expect(
        repository.notes.where((note) => note.title == 'Current backup note'),
        hasLength(1),
      );
    },
  );

  test(
    'committed import stays successful when its follow-up refresh fails',
    () async {
      final gateway = _FakeNotesTransferGateway()
        ..pickedJson = jsonEncode([
          {
            'id': 88,
            'title': 'Committed import',
            'content': 'Do not offer a duplicate retry',
            'color': 9,
            'createdAt': '2026-08-23T10:00:00.000Z',
            'isPinned': 0,
            'tags': '',
            'status': 0,
            'reminder': null,
          },
        ]);
      final repository = InMemoryNoteRepository.seeded(sampleNotes);
      final container = _container(gateway: gateway, repository: repository);
      addTearDown(container.dispose);
      final cached = await container.read(notesProvider.future);
      repository.getErrorAtCall = repository.getCalls + 1;

      final result = await container
          .read(notesTransferProvider.notifier)
          .importBackup();

      expect(result, NotesTransferResult.completed);
      expect(
        repository.notes.where((note) => note.title == 'Committed import'),
        hasLength(1),
      );
      expect(container.read(notesTransferProvider).hasError, isFalse);
      expect(
        container.read(notesTransferProvider).requireValue?.importedCount,
        1,
      );
      expect(container.read(notesProvider).hasError, isTrue);
      expect(container.read(notesProvider).value, cached);

      repository.getErrorAtCall = null;
      container.invalidate(notesProvider);
      final refreshed = await container.read(notesProvider.future);

      expect(
        refreshed.where((note) => note.title == 'Committed import'),
        hasLength(1),
      );
      expect(
        repository.notes.where((note) => note.title == 'Committed import'),
        hasLength(1),
      );
    },
  );

  test('beginSession clears settled transfer state before reopening', () async {
    final gateway = _FakeNotesTransferGateway();
    final container = _container(gateway: gateway);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);

    expect(
      await container.read(notesTransferProvider.notifier).exportText(),
      NotesTransferResult.completed,
    );
    expect(container.read(notesTransferProvider).requireValue, isNotNull);

    container.read(notesTransferProvider.notifier).beginSession();

    expect(container.read(notesTransferProvider).requireValue, isNull);
  });

  test(
    'malformed import exposes an error and preserves existing notes',
    () async {
      final gateway = _FakeNotesTransferGateway()..pickedJson = '{}';
      final repository = InMemoryNoteRepository.seeded(sampleNotes);
      final container = _container(gateway: gateway, repository: repository);
      addTearDown(container.dispose);
      final before = await container.read(notesProvider.future);

      final result = await container
          .read(notesTransferProvider.notifier)
          .importBackup();

      expect(result, NotesTransferResult.failed);
      expect(container.read(notesTransferProvider).hasError, isTrue);
      expect(
        container.read(notesTransferProvider).error,
        isA<FormatException>(),
      );
      expect(repository.notes, hasLength(before.length));
      expect(
        repository.notes.map((note) => note.id),
        before.map((note) => note.id),
      );
    },
  );

  test(
    'over-limit backup fails before the repository import transaction',
    () async {
      final gateway = _FakeNotesTransferGateway()
        ..pickedJson = jsonEncode([
          {
            'title': 'Private oversized backup',
            'content': '',
            'color': 17,
            'createdAt': '2026-08-23T10:00:00.000Z',
            'isPinned': 0,
            'tags': List<String>.filled(
              NoteBackupImportLimits.maxTagsPerNote + 1,
              'private-tag',
            ),
            'status': 0,
            'reminder': null,
          },
        ]);
      final repository = _ImportCountingRepository.seeded(sampleNotes);
      final container = _container(gateway: gateway, repository: repository);
      addTearDown(container.dispose);
      final before = await container.read(notesProvider.future);

      final result = await container
          .read(notesTransferProvider.notifier)
          .importBackup();

      expect(result, NotesTransferResult.failed);
      expect(repository.importCalls, 0);
      expect(repository.addCalls, 0);
      expect(repository.notes, before);
      expect(
        container.read(notesTransferProvider).error,
        isA<FormatException>()
            .having(
              (error) => error.message,
              'message',
              contains('too many tags'),
            )
            .having(
              (error) => error.message,
              'sanitized message',
              isNot(contains('private-tag')),
            ),
      );
    },
  );

  test(
    'nested unknown backup data fails before the repository import transaction',
    () async {
      final gateway = _FakeNotesTransferGateway()
        ..pickedJson = jsonEncode([
          {
            'title': 'Valid title',
            'content': 'Valid content',
            'color': 7,
            'createdAt': '2026-08-24T09:00:00.000Z',
            'isPinned': 0,
            'tags': const <String>[],
            'status': 0,
            'reminder': null,
            'private-extension': [
              {'nested': 'private-value'},
            ],
          },
        ]);
      final repository = _ImportCountingRepository.seeded(sampleNotes);
      final container = _container(gateway: gateway, repository: repository);
      addTearDown(container.dispose);
      final before = await container.read(notesProvider.future);

      final result = await container
          .read(notesTransferProvider.notifier)
          .importBackup();

      expect(result, NotesTransferResult.failed);
      expect(repository.importCalls, 0);
      expect(repository.addCalls, 0);
      expect(repository.notes, before);
      expect(
        container.read(notesTransferProvider).error,
        isA<FormatException>()
            .having(
              (error) => error.message,
              'message',
              contains('nested data'),
            )
            .having(
              (error) => error.message,
              'sanitized message',
              isNot(contains('private')),
            ),
      );
    },
  );

  test('share failure becomes row-addressable provider error', () async {
    final gateway = _FakeNotesTransferGateway()
      ..shareError = StateError('share unavailable');
    final container = _container(gateway: gateway);
    addTearDown(container.dispose);
    await container.read(notesProvider.future);

    final result = await container
        .read(notesTransferProvider.notifier)
        .backupJson();

    expect(result, NotesTransferResult.failed);
    expect(container.read(notesTransferProvider).hasError, isTrue);
    expect(container.read(notesTransferProvider).error, isA<StateError>());
    expect(
      container.read(notesTransferProvider.notifier).operation,
      NotesTransferOperation.backupJson,
    );
  });

  test(
    'global tag usage is deterministic and legacy tags stay mode-aware',
    () async {
      final notes = [
        _note(1, NoteStatus.active, const ['shared', 'shared', 'active']),
        _note(2, NoteStatus.archived, const ['shared', 'archive']),
        _note(3, NoteStatus.trashed, const ['shared', 'trash']),
        _note(4, NoteStatus.active, const ['active']),
      ];
      final container = ProviderContainer(
        overrides: [
          noteRepositoryProvider.overrideWithValue(
            InMemoryNoteRepository.seeded(notes),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(notesProvider.future);

      expect(
        container
            .read(tagUsageProvider)
            .map((usage) => (usage.tag, usage.count)),
        [('active', 2), ('archive', 1), ('shared', 3), ('trash', 1)],
      );
      expect(container.read(allTagsProvider), ['active', 'shared']);

      container.read(noteModeProvider.notifier).set(NoteMode.archived);

      expect(container.read(allTagsProvider), ['archive', 'shared']);
      expect(
        container
            .read(tagUsageProvider)
            .map((usage) => (usage.tag, usage.count)),
        [('active', 2), ('archive', 1), ('shared', 3), ('trash', 1)],
      );
    },
  );

  test(
    'removeTag uses one global operation then performs one outer refetch',
    () async {
      final repository = _CountingRepository.seeded([
        _note(1, NoteStatus.active, const ['shared', 'shared', 'active']),
        _note(2, NoteStatus.archived, const ['shared', 'archive']),
        _note(3, NoteStatus.trashed, const ['shared', 'trash']),
        _note(4, NoteStatus.active, const ['active']),
      ]);
      final container = ProviderContainer(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(notesProvider.future);
      container.read(selectedTagProvider.notifier).select('shared');
      repository.resetTrace();

      await container.read(notesProvider.notifier).removeTag('shared');

      expect(repository.removeTagCalls, 1);
      expect(repository.updateCalls, 0);
      expect(repository.statusReadCalls, 3);
      expect(repository.events, ['remove:shared', 'read', 'read', 'read']);
      expect(
        repository.notes.expand((note) => note.tags),
        isNot(contains('shared')),
      );
      expect(container.read(selectedTagProvider), isNull);
      expect(
        container.read(notesProvider).value!.expand((note) => note.tags),
        isNot(contains('shared')),
      );
    },
  );

  test('failed removeTag is atomic and retains the selected filter', () async {
    final repository = _FailingAtomicTagRepository.seeded([
      _note(1, NoteStatus.active, const ['shared']),
      _note(2, NoteStatus.archived, const ['shared']),
    ]);
    final container = ProviderContainer(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final before = await container.read(notesProvider.future);
    container.read(selectedTagProvider.notifier).select('shared');

    await expectLater(
      container.read(notesProvider.notifier).removeTag('shared'),
      throwsStateError,
    );

    expect(container.read(selectedTagProvider), 'shared');
    final state = container.read(notesProvider);
    expect(state, isA<AsyncData<List<Note>>>());
    expect(state.hasError, isFalse);
    expect(state.value, same(before));
    expect(repository.removeTagCalls, 1);
    expect(
      repository.notes.expand((note) => note.tags),
      everyElement('shared'),
    );
  });
}

ProviderContainer _container({
  required _FakeNotesTransferGateway gateway,
  InMemoryNoteRepository? repository,
}) {
  return ProviderContainer(
    overrides: [
      notesTransferGatewayProvider.overrideWithValue(gateway),
      noteRepositoryProvider.overrideWithValue(
        repository ?? InMemoryNoteRepository.seeded(sampleNotes),
      ),
    ],
  );
}

Note _note(int id, NoteStatus status, List<String> tags) {
  return Note(
    id: id,
    title: 'Note $id',
    content: 'Content $id',
    color: id,
    createdAt: DateTime.utc(2026, 8, 23).add(Duration(minutes: id)),
    tags: tags,
    status: status,
  );
}

class _FakeNotesTransferGateway extends NotesTransferGateway {
  String? pickedJson;
  Object? pickError;
  Object? shareError;
  Completer<void>? shareGate;
  NotesShareResult shareResult = NotesShareResult.completed;

  int pickCalls = 0;
  int shareTextCalls = 0;
  int shareFileCalls = 0;
  String? lastSharedText;
  Rect? lastOrigin;

  @override
  Future<String?> pickJsonText() async {
    pickCalls += 1;
    if (pickError case final error?) throw error;
    return pickedJson;
  }

  @override
  Future<NotesShareResult> shareText({
    required String text,
    required String subject,
    Rect? sharePositionOrigin,
  }) async {
    shareTextCalls += 1;
    lastSharedText = text;
    lastOrigin = sharePositionOrigin;
    if (shareError case final error?) throw error;
    await shareGate?.future;
    return shareResult;
  }

  @override
  Future<NotesShareResult> shareFile({
    required String text,
    required String fileName,
    required String mimeType,
    Rect? sharePositionOrigin,
  }) async {
    shareFileCalls += 1;
    lastSharedText = text;
    lastOrigin = sharePositionOrigin;
    if (shareError case final error?) throw error;
    await shareGate?.future;
    return shareResult;
  }
}

class _FakeJsonFilePicker {
  List<PlatformFile>? result;
  Object? error;
  FileType? type;
  List<String>? allowedExtensions;
  bool? withData;
  bool? withReadStream;

  Future<List<PlatformFile>?> call({
    required FileType type,
    required List<String> allowedExtensions,
    bool? withData,
    bool? withReadStream,
  }) async {
    if (error case final error?) throw error;
    this.type = type;
    this.allowedExtensions = allowedExtensions;
    this.withData = withData;
    this.withReadStream = withReadStream;
    return result;
  }
}

final class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile.memory({
    required this.name,
    required Uint8List bytes,
    int? reportedLength,
  }) : _bytes = bytes,
       _streamChunks = null,
       _reportedLength = reportedLength ?? bytes.length,
       _readError = null,
       uri = Uri(scheme: 'memory', path: '/$name');

  _FakePlatformFile.path({
    required this.name,
    required String path,
    int? reportedLength,
  }) : _bytes = null,
       _streamChunks = null,
       _reportedLength = reportedLength,
       _readError = null,
       uri = Uri.file(path, windows: Platform.isWindows);

  _FakePlatformFile.unreadable({
    required this.name,
    required int reportedLength,
  }) : _bytes = null,
       _streamChunks = null,
       _reportedLength = reportedLength,
       _readError = StateError('Unreadable fake platform file'),
       uri = Uri(scheme: 'memory', path: '/$name');

  _FakePlatformFile.stream({
    required this.name,
    required List<Uint8List> chunks,
    required int reportedLength,
  }) : _bytes = null,
       _streamChunks = chunks,
       _reportedLength = reportedLength,
       _readError = null,
       uri = Uri(scheme: 'memory', path: '/$name');

  @override
  final String name;

  @override
  final Uri uri;

  final Uint8List? _bytes;
  final List<Uint8List>? _streamChunks;
  final int? _reportedLength;
  final Object? _readError;

  int lengthCalls = 0;
  int readAsBytesCalls = 0;
  int readAsByteStreamCalls = 0;
  int emittedChunkCount = 0;
  bool streamCancelledEarly = false;

  @override
  XFile get xFile {
    final bytes = _bytes;
    if (bytes != null) {
      return XFile.fromData(
        bytes,
        name: name,
        length: bytes.length,
        mimeType: 'application/json',
      );
    }
    final filePath = path;
    return XFile(filePath ?? uri.toString(), name: name);
  }

  @override
  Future<int> length() async {
    lengthCalls += 1;
    final reportedLength = _reportedLength;
    if (reportedLength != null) return reportedLength;
    final filePath = path;
    if (filePath == null) throw StateError('Fake file has no readable path');
    return File(filePath).length();
  }

  @override
  Future<Uint8List> readAsBytes() async {
    readAsBytesCalls += 1;
    if (_readError case final error?) throw error;
    final bytes = _bytes;
    if (bytes != null) return bytes;
    final filePath = path;
    if (filePath == null) throw StateError('Fake file has no readable path');
    return File(filePath).readAsBytes();
  }

  @override
  Stream<Uint8List> readAsByteStream() async* {
    readAsByteStreamCalls += 1;
    if (_readError case final error?) throw error;
    final chunks = _streamChunks;
    if (chunks != null) {
      try {
        for (final chunk in chunks) {
          emittedChunkCount += 1;
          yield chunk;
        }
      } finally {
        streamCancelledEarly = emittedChunkCount < chunks.length;
      }
      return;
    }
    final bytes = _bytes;
    if (bytes != null) {
      yield bytes;
      return;
    }
    final filePath = path;
    if (filePath == null) throw StateError('Fake file has no readable path');
    yield* File(filePath).openRead().map(Uint8List.fromList);
  }
}

class _CountingRepository extends InMemoryNoteRepository {
  _CountingRepository.seeded(super.notes) : super.seeded();

  int updateCalls = 0;
  int statusReadCalls = 0;
  final List<String> events = [];

  void resetTrace() {
    updateCalls = 0;
    removeTagCalls = 0;
    statusReadCalls = 0;
    events.clear();
  }

  @override
  Future<int> removeTag(String tag) async {
    removeTagCalls += 1;
    events.add('remove:$tag');
    final changed = notes.where((note) => note.tags.contains(tag)).toList();
    for (final note in changed) {
      await super.updateNote(
        note.copyWith(tags: note.tags.where((item) => item != tag).toList()),
      );
    }
    return changed.length;
  }

  @override
  Future<int> updateNote(Note note) async {
    updateCalls += 1;
    events.add('update:${note.id}');
    return super.updateNote(note);
  }

  @override
  Future<List<Note>> getNotesByStatus(NoteStatus status) async {
    statusReadCalls += 1;
    events.add('read');
    return super.getNotesByStatus(status);
  }
}

class _ImportCountingRepository extends InMemoryNoteRepository {
  _ImportCountingRepository.seeded(super.notes) : super.seeded();

  int importCalls = 0;

  @override
  Future<void> importNotes(List<Note> notes) async {
    importCalls += 1;
    await super.importNotes(notes);
  }
}

class _GatedStatusRepository extends InMemoryNoteRepository {
  _GatedStatusRepository.seeded(super.notes) : super.seeded();

  final statusWriteEntered = Completer<void>();
  final _statusWriteGate = Completer<void>();

  void releaseStatusWrite() => _statusWriteGate.complete();

  @override
  Future<int> setNoteStatus(int id, NoteStatus status) async {
    statusWriteEntered.complete();
    await _statusWriteGate.future;
    return super.setNoteStatus(id, status);
  }
}

class _FailingAtomicTagRepository extends InMemoryNoteRepository {
  _FailingAtomicTagRepository.seeded(super.notes) : super.seeded();

  int updateCalls = 0;

  @override
  Future<int> removeTag(String tag) async {
    removeTagCalls += 1;
    throw StateError('write failed');
  }

  @override
  Future<int> updateNote(Note note) async {
    updateCalls += 1;
    if (updateCalls == 2) throw StateError('write failed');
    return super.updateNote(note);
  }
}
