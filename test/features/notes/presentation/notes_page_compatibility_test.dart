import 'package:flutter/material.dart';
import 'package:flutter_clean_notes/app/app_providers.dart';
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

  testWidgets('legacy theme toggle awaits failure and shows safe feedback', (
    tester,
  ) async {
    final repository = InMemoryNoteRepository.seeded(sampleNotes);
    final store = _FailingThemeModeStore();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          noteRepositoryProvider.overrideWithValue(repository),
          themeModeStoreProvider.overrideWithValue(store),
        ],
        child: Consumer(
          builder: (context, ref, _) {
            final mode = ref.watch(appThemeProvider).value ?? ThemeMode.system;
            return MaterialApp(
              theme: ThemeData.light(),
              darkTheme: ThemeData.dark(),
              themeMode: mode,
              home: const NotesPage(),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NotesPage)),
    );

    await tester.tap(find.byTooltip('Toggle theme'));
    await tester.pumpAndSettle();

    expect(store.writeCalls, 1);
    expect(store.mode, ThemeMode.system);
    expect(container.read(appThemeProvider).requireValue, ThemeMode.system);
    expect(
      find.text('Could not save theme preference. Try again.'),
      findsOneWidget,
    );
    expect(find.textContaining('private settings path'), findsNothing);
  });
}

class _FailingThemeModeStore implements ThemeModeStore {
  ThemeMode mode = ThemeMode.system;
  int writeCalls = 0;

  @override
  Future<ThemeMode> readMode() async => mode;

  @override
  Future<void> writeMode(ThemeMode mode) async {
    writeCalls += 1;
    throw StateError('private settings path failed');
  }
}
