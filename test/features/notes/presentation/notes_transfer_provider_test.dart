import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/notes_transfer_provider.dart';
import 'package:flutter_clean_notes/features/notes/presentation/services/notes_transfer_gateway.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  test(
    'platform picker returns null on cancellation and configures JSON',
    () async {
      final picker = _FakeFilePicker();
      FilePicker.platform = picker;

      expect(await const NotesTransferGateway().pickJsonText(), isNull);
      expect(picker.type, FileType.custom);
      expect(picker.allowedExtensions, ['json']);
      expect(picker.allowMultiple, isFalse);
    },
  );

  test('platform picker strips a UTF-8 BOM from byte-backed JSON', () async {
    final picker = _FakeFilePicker()
      ..result = FilePickerResult([
        PlatformFile(
          name: 'backup.json',
          size: 5,
          bytes: Uint8List.fromList([0xEF, 0xBB, 0xBF, 0x5B, 0x5D]),
        ),
      ]);
    FilePicker.platform = picker;

    expect(await const NotesTransferGateway().pickJsonText(), '[]');
  });

  test(
    'platform picker converts invalid input into readable format errors',
    () async {
      final picker = _FakeFilePicker();
      FilePicker.platform = picker;
      const gateway = NotesTransferGateway();

      picker.result = FilePickerResult([
        PlatformFile(
          name: 'backup.json',
          size: 2,
          bytes: Uint8List.fromList([0xC3, 0x28]),
        ),
      ]);
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

      picker.result = FilePickerResult([
        PlatformFile(name: 'backup.json', size: 5),
      ]);
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
        container.read(notesTransferProvider).value,
        NotesTransferOperation.exportText,
      );
      expect(gateway.lastSharedText, contains('Aurora design'));
    },
  );

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
    'valid import appends while clearing imported identity and reminder',
    () async {
      final gateway = _FakeNotesTransferGateway()
        ..pickedJson = jsonEncode([
          {
            'id': 99,
            'title': 'Imported note',
            'content': 'Safe append',
            'color': 17,
            'createdAt': '2026-08-22T10:00:00.000Z',
            'isPinned': 1,
            'tags': 'backup,work',
            'status': 1,
            'reminder': '2026-08-24T08:00:00.000Z',
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
      final imported = repository.notes.singleWhere(
        (note) => note.title == 'Imported note',
      );
      expect(imported.id, isNot(99));
      expect(imported.status, NoteStatus.active);
      expect(imported.reminder, isNull);
      expect(imported.isPinned, isTrue);
      expect(imported.tags, ['backup', 'work']);
      expect(repository.notes.map((note) => note.id), containsAll(existingIds));
      expect(repository.notes, hasLength(sampleNotes.length + 1));
      expect(
        container.read(notesTransferProvider).value,
        NotesTransferOperation.importBackup,
      );
    },
  );

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
    'removeTag updates all statuses then performs one outer refetch',
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

      expect(repository.updateCalls, 3);
      expect(repository.statusReadCalls, 3);
      expect(repository.events, [
        'update:1',
        'update:2',
        'update:3',
        'read',
        'read',
        'read',
      ]);
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

  test('failed removeTag retains selected filter and cached notes', () async {
    final repository = _CountingRepository.seeded([
      _note(1, NoteStatus.active, const ['shared']),
    ])..updateError = StateError('write failed');
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
    expect(container.read(notesProvider).hasError, isTrue);
    expect(container.read(notesProvider).value, before);
    expect(repository.notes.single.tags, ['shared']);
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
  Future<void> shareText({
    required String text,
    required String subject,
    Rect? sharePositionOrigin,
  }) async {
    shareTextCalls += 1;
    lastSharedText = text;
    lastOrigin = sharePositionOrigin;
    if (shareError case final error?) throw error;
    await shareGate?.future;
  }

  @override
  Future<void> shareFile({
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
  }
}

class _FakeFilePicker extends FilePicker {
  FilePickerResult? result;
  FileType? type;
  List<String>? allowedExtensions;
  bool? allowMultiple;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    this.type = type;
    this.allowedExtensions = allowedExtensions;
    this.allowMultiple = allowMultiple;
    return result;
  }
}

class _CountingRepository extends InMemoryNoteRepository {
  _CountingRepository.seeded(super.notes) : super.seeded();

  int updateCalls = 0;
  int statusReadCalls = 0;
  final List<String> events = [];

  void resetTrace() {
    updateCalls = 0;
    statusReadCalls = 0;
    events.clear();
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
