import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
// XML is already resolved by Flutter tooling but is not re-exported.
// ignore: depend_on_referenced_packages
import 'package:xml/xml.dart';

const _androidNamespace = 'http://schemas.android.com/apk/res/android';

String? _androidAttribute(XmlElement element, String name) {
  return element.getAttribute(name, namespaceUri: _androidNamespace);
}

void main() {
  test(
    'Android reminder manifest declares permission and receiver contract',
    () async {
      final document = XmlDocument.parse(
        await File('android/app/src/main/AndroidManifest.xml').readAsString(),
      );
      final permissions = document
          .findAllElements('uses-permission')
          .map((element) => _androidAttribute(element, 'name'))
          .whereType<String>()
          .toSet();
      final receivers = <String, XmlElement>{};
      for (final receiver in document.findAllElements('receiver')) {
        final name = _androidAttribute(receiver, 'name');
        if (name != null) receivers[name] = receiver;
      }

      expect(
        permissions,
        containsAll(<String>{
          'android.permission.POST_NOTIFICATIONS',
          'android.permission.RECEIVE_BOOT_COMPLETED',
        }),
      );
      expect(
        permissions,
        isNot(contains('android.permission.SCHEDULE_EXACT_ALARM')),
      );
      expect(
        permissions,
        isNot(contains('android.permission.USE_EXACT_ALARM')),
      );

      for (final receiver in <String>{
        'com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver',
        'com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver',
        'com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver',
      }) {
        expect(receivers, contains(receiver));
        expect(_androidAttribute(receivers[receiver]!, 'exported'), 'false');
      }

      final bootReceiver =
          receivers['com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver']!;
      final actions = bootReceiver
          .findAllElements('action')
          .map((element) => _androidAttribute(element, 'name'))
          .whereType<String>()
          .toSet();
      expect(
        actions,
        containsAll(<String>{
          'android.intent.action.BOOT_COMPLETED',
          'android.intent.action.MY_PACKAGE_REPLACED',
          'android.intent.action.QUICKBOOT_POWERON',
          'com.htc.intent.action.QUICKBOOT_POWERON',
        }),
      );
    },
  );
}
