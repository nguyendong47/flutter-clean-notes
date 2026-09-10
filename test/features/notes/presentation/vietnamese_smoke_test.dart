import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_home_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';
import 'package:flutter_clean_notes/features/notes/presentation/widgets/more_actions_sheet.dart';

import '../../../helpers/in_memory_note_repository.dart';
import '../../../support/localization_test_wrapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  // See test/features/notes/presentation/more_actions_sheet_test.dart for
  // why this is required: a stale rootBundle cache entry from an earlier
  // test's disposed EasyLocalization instance otherwise hangs every
  // subsequent wrapWithTestLocalization(...) build in this file
  // (aissat/easy_localization#268/#362).
  tearDown(() => rootBundle.clear());

  testWidgets('Home renders Vietnamese chrome when locale is vi', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithTestLocalization(
        ProviderScope(
          overrides: [
            noteRepositoryProvider.overrideWithValue(
              InMemoryNoteRepository.seeded(const []),
            ),
          ],
          child: Builder(
            builder: (localizationContext) => MaterialApp(
              theme: AuroraTheme.light(),
              localizationsDelegates: localizationContext.localizationDelegates,
              supportedLocales: localizationContext.supportedLocales,
              locale: localizationContext.locale,
              home: const NotesHomePage(),
            ),
          ),
        ),
        locale: const Locale('vi'),
      ),
    );
    await tester.pumpAndSettle();

    // Empty-notes state renders home.createFirstNote — a fixed string
    // (unlike the greeting, which depends on wall-clock hour) so it's a
    // reliable real-Vietnamese assertion for this screen.
    expect(find.text('Tạo ghi chú đầu tiên của bạn'), findsOneWidget);
    expect(find.textContaining('home.'), findsNothing);
  });

  testWidgets('More sheet renders Vietnamese chrome when locale is vi', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrapWithTestLocalization(
        ProviderScope(
          overrides: [
            noteRepositoryProvider.overrideWithValue(
              InMemoryNoteRepository.seeded(const []),
            ),
          ],
          child: Builder(
            builder: (localizationContext) => MaterialApp(
              theme: AuroraTheme.light(),
              localizationsDelegates: localizationContext.localizationDelegates,
              supportedLocales: localizationContext.supportedLocales,
              locale: localizationContext.locale,
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => MoreActionsSheet.show(context),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        ),
        locale: const Locale('vi'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Ngôn ngữ / Language'), findsOneWidget);
    expect(find.text('Giao diện'), findsOneWidget);
    expect(find.textContaining('more.'), findsNothing);
  });
}
