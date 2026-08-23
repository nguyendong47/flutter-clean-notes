import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _androidNamespace = 'http://schemas.android.com/apk/res/android';
const _expectedExclusions = <({String domain, String path})>{
  (domain: 'root', path: '.'),
  (domain: 'file', path: '.'),
  (domain: 'database', path: '.'),
  (domain: 'sharedpref', path: '.'),
  (domain: 'external', path: '.'),
  (domain: 'device_root', path: '.'),
  (domain: 'device_file', path: '.'),
  (domain: 'device_database', path: '.'),
  (domain: 'device_sharedpref', path: '.'),
};

String? _androidAttribute(XmlElement element, String name) {
  return element.getAttribute(name, namespaceUri: _androidNamespace);
}

void main() {
  test('Android manifest disables every managed-backup path', () async {
    final document = XmlDocument.parse(
      await File('android/app/src/main/AndroidManifest.xml').readAsString(),
    );
    final applications = document.findAllElements('application').toList();

    expect(applications, hasLength(1));
    final application = applications.single;
    expect(_androidAttribute(application, 'allowBackup'), 'false');
    expect(_androidAttribute(application, 'fullBackupContent'), 'false');
    expect(
      _androidAttribute(application, 'dataExtractionRules'),
      '@xml/data_extraction_rules',
    );
  });

  test(
    'Android 12 rules exclude every storage domain from cloud and device transfer',
    () async {
      final rulesFile = File(
        'android/app/src/main/res/xml/data_extraction_rules.xml',
      );
      final rulesExist = await rulesFile.exists();
      expect(
        rulesExist,
        isTrue,
        reason: 'Manifest backup rules resource must exist.',
      );
      if (!rulesExist) return;

      final document = XmlDocument.parse(await rulesFile.readAsString());
      final root = document.rootElement;
      expect(root.name.local, 'data-extraction-rules');
      expect(document.findAllElements('include'), isEmpty);

      final sections = root.childElements.toList();
      expect(
        sections.map((section) => section.name.local),
        orderedEquals(<String>['cloud-backup', 'device-transfer']),
      );

      for (final section in sections) {
        final rules = section.childElements.toList();
        expect(
          rules.map((rule) => rule.name.local),
          everyElement('exclude'),
          reason: '${section.name.local} must contain exclusions only.',
        );
        expect(rules, hasLength(_expectedExclusions.length));

        final exclusions = rules
            .map(
              (rule) => (
                domain: rule.getAttribute('domain'),
                path: rule.getAttribute('path'),
              ),
            )
            .toList();
        expect(exclusions, unorderedEquals(_expectedExclusions));
      }
    },
  );
}
