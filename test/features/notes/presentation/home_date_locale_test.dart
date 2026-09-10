import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_clean_notes/app/theme/aurora_theme.dart';
import 'package:flutter_clean_notes/features/notes/presentation/pages/notes_home_page.dart';
import 'package:flutter_clean_notes/features/notes/presentation/providers/note_providers.dart';

import '../../../helpers/in_memory_note_repository.dart';
import '../../../support/localization_test_wrapper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await initializeDateFormatting('vi');
  });

  tearDown(() => rootBundle.clear());

  testWidgets('Home header date renders with Vietnamese month/weekday names', (
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

    // DateFormat('EEEE, MMMM d', 'vi') always renders a Vietnamese weekday
    // name starting with "Thứ" (Monday-Saturday) or the literal "Chủ Nhật"
    // (Sunday) — assert one of those substrings is present rather than a
    // single fixed date string, since the test's pass/fail must not depend
    // on which day it happens to run.
    final matches = find.byWidgetPredicate((widget) {
      if (widget is! Text || widget.data == null) return false;
      final text = widget.data!;
      return text.startsWith('Thứ') || text.startsWith('Chủ Nhật');
    });
    expect(matches, findsOneWidget);
  });
}
