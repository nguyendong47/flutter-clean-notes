import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps [child] with the same [EasyLocalization] configuration production
/// code installs in `main.dart`, so widgets using `.tr()`/`context.locale`
/// work in widget tests. Must run after `TestWidgetsFlutterBinding
/// .ensureInitialized()` (flutter_test does this automatically).
///
/// This deliberately does NOT add a `MaterialApp`/`Scaffold` ancestor: it is
/// meant to sit as a thin layer above a widget tree that already contains
/// its own `MaterialApp` (e.g. a `ProviderScope` wrapping a screen's own
/// `MaterialApp`), so wrapping it here would nest a second `MaterialApp`.
/// Callers whose [child] has no `MaterialApp`/`Localizations` ancestor of
/// its own (e.g. a bare `Builder`/`Text`) must supply one themselves, wiring
/// `localizationsDelegates: context.localizationDelegates`,
/// `supportedLocales: context.supportedLocales`, and
/// `locale: context.locale` from a `BuildContext` under this widget —
/// otherwise `.tr()` never resolves because Flutter's `Localizations`
/// widget (which is what actually drives the async translation-asset load)
/// is never installed in the tree.
Widget wrapWithTestLocalization(
  Widget child, {
  Locale locale = const Locale('en'),
}) {
  return EasyLocalization(
    supportedLocales: const [Locale('en'), Locale('vi')],
    path: 'assets/translations',
    fallbackLocale: const Locale('en'),
    startLocale: locale,
    useOnlyLangCode: true,
    child: child,
  );
}

/// Pumps [widget] wrapped with [wrapWithTestLocalization] and settles.
Future<void> pumpLocalized(
  WidgetTester tester,
  Widget widget, {
  Locale locale = const Locale('en'),
}) async {
  await tester.pumpWidget(wrapWithTestLocalization(widget, locale: locale));
  await tester.pumpAndSettle();
}
