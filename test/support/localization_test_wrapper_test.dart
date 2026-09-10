import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'localization_test_wrapper.dart';

void main() {
  testWidgets('wrapWithTestLocalization resolves a real translation key', (
    tester,
  ) async {
    await pumpLocalized(
      tester,
      Builder(
        builder: (context) => MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          home: Builder(builder: (context) => Text('common.cancel'.tr())),
        ),
      ),
    );

    expect(find.text('Cancel'), findsOneWidget);
  });

  testWidgets('pumpLocalized honors the requested locale', (tester) async {
    await pumpLocalized(
      tester,
      Builder(
        builder: (context) => MaterialApp(
          localizationsDelegates: context.localizationDelegates,
          supportedLocales: context.supportedLocales,
          locale: context.locale,
          home: Builder(
            builder: (context) => Text(context.locale.languageCode),
          ),
        ),
      ),
      locale: const Locale('vi'),
    );

    expect(find.text('vi'), findsOneWidget);
  });
}
