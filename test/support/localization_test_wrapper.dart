import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps [child] with the same [EasyLocalization] configuration production
/// code installs in `main.dart`, so widgets using `.tr()`/`context.locale`
/// work in widget tests. Must run after `TestWidgetsFlutterBinding
/// .ensureInitialized()` (flutter_test does this automatically).
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
    child: MaterialApp(
      home: Scaffold(
        body: child,
      ),
    ),
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
