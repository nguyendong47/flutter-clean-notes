import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/widget_sync_payload.dart';
import 'package:flutter_clean_notes/features/notes/domain/services/widget_sync_gateway.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/in_memory_note_repository.dart';

class _CapturingWidgetSyncGateway implements WidgetSyncGateway {
  final List<WidgetSyncPayload> payloads = [];

  @override
  Future<void> syncPayload(WidgetSyncPayload payload) async {
    payloads.add(payload);
  }
}

void main() {
  group('WidgetSync integration with NotesNotifier', () {
    test('syncs payload on build and note mutations', () async {
      final fakeGateway = _CapturingWidgetSyncGateway();
      final repository = InMemoryNoteRepository.seeded(const []);

      final container = ProviderContainer(
        overrides: [
          noteRepositoryProvider.overrideWithValue(repository),
          widgetSyncGatewayProvider.overrideWithValue(fakeGateway),
        ],
      );
      addTearDown(container.dispose);

      // 1. Initial build with empty repo -> empty payload synced
      await container.read(notesProvider.future);
      await pumpEventQueue();

      expect(fakeGateway.payloads, isNotEmpty);
      expect(fakeGateway.payloads.last.hasPinned, isFalse);

      // 2. Add an unpinned note -> still no pinned note synced
      final unpinnedNote = Note(
        title: 'Draft note',
        content: 'Random content',
        color: 0xFFFFFFFF,
        createdAt: DateTime(2026, 9, 1),
        isPinned: false,
      );
      await container.read(notesProvider.notifier).addNote(unpinnedNote);
      await pumpEventQueue();

      expect(fakeGateway.payloads.last.hasPinned, isFalse);

      // 3. Add a pinned note with checklist -> widget synced with pinned note and checklist
      final pinnedNote = Note(
        title: 'Weekly Groceries',
        content: '- [ ] Milk\n- [x] Apples\n- [ ] Bread',
        color: 0xFFFF5722,
        createdAt: DateTime(2026, 9, 2),
        isPinned: true,
      );
      await container.read(notesProvider.notifier).addNote(pinnedNote);
      await pumpEventQueue();

      final lastPayload = fakeGateway.payloads.last;
      expect(lastPayload.hasPinned, isTrue);
      expect(lastPayload.title, 'Weekly Groceries');
      expect(lastPayload.colorValue, 0xFFFF5722);
      expect(lastPayload.checklist.length, 3);
      expect(lastPayload.checklist[0].text, 'Milk');
      expect(lastPayload.checklist[0].isDone, isFalse);
      expect(lastPayload.checklist[1].text, 'Apples');
      expect(lastPayload.checklist[1].isDone, isTrue);

      // 4. Toggle pin on the note (unpin) -> widget updates to empty
      final currentNotes = await container.read(notesProvider.future);
      final persistedPinned = currentNotes.firstWhere(
        (n) => n.title == 'Weekly Groceries',
      );

      await container.read(notesProvider.notifier).togglePin(persistedPinned);
      await pumpEventQueue();

      expect(fakeGateway.payloads.last.hasPinned, isFalse);

      // 5. Toggle pin back (pin) -> widget updates to pinned
      final updatedNotes = await container.read(notesProvider.future);
      final persistedUnpinned = updatedNotes.firstWhere(
        (n) => n.title == 'Weekly Groceries',
      );

      await container.read(notesProvider.notifier).togglePin(persistedUnpinned);
      await pumpEventQueue();

      expect(fakeGateway.payloads.last.hasPinned, isTrue);
      expect(fakeGateway.payloads.last.title, 'Weekly Groceries');

      // 6. Trash the pinned note -> widget updates to empty
      final rePinnedNotes = await container.read(notesProvider.future);
      final toTrash = rePinnedNotes.firstWhere(
        (n) => n.title == 'Weekly Groceries',
      );

      await container.read(notesProvider.notifier).trashNote(toTrash);
      await pumpEventQueue();

      expect(fakeGateway.payloads.last.hasPinned, isFalse);
    });
  });
}
