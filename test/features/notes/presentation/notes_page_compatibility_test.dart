import 'package:flutter/material.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/in_memory_note_repository.dart';
import '../../../helpers/note_fixtures.dart';

void main() {
  testWidgets('keeps cached notes visible when a mutation fails', (
    tester,
  ) async {
    final repository = InMemoryNoteRepository.seeded(sampleNotes);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: NotesPage()),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NotesPage)),
    );
    final initial = container.read(notesProvider).requireValue;
    repository.updateError = StateError('write failed');

    await expectLater(
      container.read(notesProvider.notifier).togglePin(initial.first),
      throwsStateError,
    );
    await tester.pump();

    expect(find.text(sampleNote.title), findsOneWidget);
    expect(find.textContaining('Error: StateError'), findsNothing);
  });
}
