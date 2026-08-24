import 'package:flutter_clean_notes/features/notes/data/datasources/local_note_datasource.dart';
import 'package:flutter_clean_notes/features/notes/data/models/note_model.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/reminder_command.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_reminder_gateway_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'one interface override isolates note and outbox repositories',
    () async {
      final dataSource = _FakeNotesPersistenceDataSource();
      final container = ProviderContainer(
        overrides: [localNoteDataSourceProvider.overrideWithValue(dataSource)],
      );
      addTearDown(container.dispose);

      expect(container.read(localNoteDataSourceProvider), same(dataSource));
      expect(await container.read(noteRepositoryProvider).getNotes(), isEmpty);
      expect(
        await container.read(reminderOutboxRepositoryProvider).pending(),
        const [
          ReminderCommand(
            generation: 41,
            noteId: 7,
            operation: ReminderCommandOperation.cancel,
          ),
        ],
      );
      expect(dataSource.noteReads, 1);
      expect(dataSource.outboxReads, 1);
    },
  );
}

final class _FakeNotesPersistenceDataSource extends Fake
    implements NotesPersistenceDataSource {
  int noteReads = 0;
  int outboxReads = 0;

  @override
  Future<List<NoteModel>> getNotes() async {
    noteReads += 1;
    return const [];
  }

  @override
  Future<List<ReminderCommand>> pendingReminderCommands({int? noteId}) async {
    outboxReads += 1;
    return const [
      ReminderCommand(
        generation: 41,
        noteId: 7,
        operation: ReminderCommandOperation.cancel,
      ),
    ];
  }
}
