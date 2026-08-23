import 'package:flutter/material.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_home_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/in_memory_note_repository.dart';
import '../../../helpers/note_fixtures.dart';

void main() {
  testWidgets('delegates the compatibility entry point to the modern home', (
    tester,
  ) async {
    await _pumpNotesPage(
      tester,
      repository: InMemoryNoteRepository.seeded(sampleNotes),
    );

    expect(find.byType(NotesPage), findsOneWidget);
    expect(find.byType(NotesHomePage), findsOneWidget);
    expect(find.byKey(const Key('notes-home-header')), findsOneWidget);
    expect(find.byKey(const Key('notes-home-search')), findsOneWidget);
    expect(find.text(sampleNote.title), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byTooltip('Toggle theme'), findsNothing);
  });

  testWidgets('keeps cached notes visible when a mutation fails', (
    tester,
  ) async {
    final repository = InMemoryNoteRepository.seeded(sampleNotes);
    await _pumpNotesPage(tester, repository: repository);
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
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.byType(NotesHomePage), findsOneWidget);
    expect(find.text(sampleNote.title), findsOneWidget);
    expect(find.textContaining('write failed'), findsOneWidget);
  });
}

Future<void> _pumpNotesPage(
  WidgetTester tester, {
  required InMemoryNoteRepository repository,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [noteRepositoryProvider.overrideWithValue(repository)],
      child: const MaterialApp(home: NotesPage()),
    ),
  );
  await tester.pumpAndSettle();
}
