import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_clean_notes/features/notes/domain/entities/note.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_home_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/in_memory_note_repository.dart';
import '../../../helpers/note_fixtures.dart';
import '../../../support/localization_test_wrapper.dart';

void main() {
  // easy_localization's RootBundleAssetLoader reads translation JSON via
  // rootBundle.loadString, which flutter's CachingAssetBundle caches by key.
  // A stale cache entry from an earlier test's (now-disposed) EasyLocalization
  // instance causes every subsequent wrapWithTestLocalization(...) build in
  // this file to hang forever awaiting that load (see
  // aissat/easy_localization#268/#362). Clearing the cache after each test
  // keeps every load a fresh read.
  tearDown(() => rootBundle.clear());

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
    expect(find.byKey(const Key('notes-home-theme-toggle')), findsOneWidget);
    expect(find.byTooltip('Use dark theme'), findsOneWidget);
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

    final state = container.read(notesProvider);
    expect(state, isA<AsyncData<List<Note>>>());
    expect(state.value, same(initial));
    expect(state.hasError, isFalse);
    expect(find.byType(NotesHomePage), findsOneWidget);
    expect(find.text(sampleNote.title), findsOneWidget);
    expect(find.textContaining('write failed'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });
}

Future<void> _pumpNotesPage(
  WidgetTester tester, {
  required InMemoryNoteRepository repository,
}) async {
  await tester.pumpWidget(
    wrapWithTestLocalization(
      ProviderScope(
        overrides: [noteRepositoryProvider.overrideWithValue(repository)],
        child: Builder(
          builder: (localizationContext) => MaterialApp(
            localizationsDelegates: localizationContext.localizationDelegates,
            supportedLocales: localizationContext.supportedLocales,
            locale: localizationContext.locale,
            home: const NotesPage(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
