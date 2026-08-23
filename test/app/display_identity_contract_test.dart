import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _displayName = 'Clean Notes';
const _androidNamespace = 'http://schemas.android.com/apk/res/android';

void main() {
  group('display identity contract', () {
    test(
      'Android displays Clean Notes without changing identity or backup policy',
      () {
        // Mutation caught: changing the launcher label, package identity, or
        // backup opt-out while updating Android display metadata.
        final manifest = XmlDocument.parse(
          _read('android/app/src/main/AndroidManifest.xml'),
        );
        final application = manifest.findAllElements('application').single;
        final gradle = _read('android/app/build.gradle.kts');

        expect(_androidAttribute(application, 'label'), _displayName);
        expect(_androidAttribute(application, 'name'), r'${applicationName}');
        expect(_androidAttribute(application, 'allowBackup'), 'false');
        expect(_androidAttribute(application, 'fullBackupContent'), 'false');
        expect(
          _androidAttribute(application, 'dataExtractionRules'),
          '@xml/data_extraction_rules',
        );
        expect(
          _capture(gradle, RegExp(r'namespace\s*=\s*"([^"]+)"')),
          'com.example.flutter_clean_notes',
        );
        expect(
          _capture(gradle, RegExp(r'applicationId\s*=\s*"([^"]+)"')),
          'com.example.flutter_clean_notes',
        );
      },
    );

    test('iOS displays Clean Notes without changing bundle identity', () {
      // Mutation caught: renaming the executable or bundle ID while changing
      // the Home Screen and system-facing app names.
      final info = XmlDocument.parse(_read('ios/Runner/Info.plist'));
      final project = _read('ios/Runner.xcodeproj/project.pbxproj');

      expect(_plistString(info, 'CFBundleDisplayName'), _displayName);
      expect(_plistString(info, 'CFBundleName'), _displayName);
      expect(_plistString(info, 'CFBundleExecutable'), r'$(EXECUTABLE_NAME)');
      expect(
        _plistString(info, 'CFBundleIdentifier'),
        r'$(PRODUCT_BUNDLE_IDENTIFIER)',
      );
      final applicationBundleIds =
          RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);')
              .allMatches(project)
              .map((match) => match.group(1)!)
              .where((identifier) => !identifier.endsWith('.RunnerTests'));
      expect(applicationBundleIds.toSet(), {'com.example.flutterCleanNotes'});
    });

    test('web install and browser surfaces display Clean Notes', () {
      // Mutation caught: leaving a generated framework/project name on any
      // browser or installed-PWA surface.
      final manifest =
          jsonDecode(_read('web/manifest.json')) as Map<String, Object?>;
      final index = _read('web/index.html');

      expect(manifest['name'], _displayName);
      expect(manifest['short_name'], _displayName);
      expect(
        manifest['description'],
        'Clean Notes is a local-first note-taking app.',
      );
      expect(_capture(index, RegExp(r'<title>([^<]+)</title>')), _displayName);
      expect(
        _capture(index, RegExp(r'<meta name="description" content="([^"]+)">')),
        'Clean Notes is a local-first note-taking app.',
      );
      expect(
        _capture(
          index,
          RegExp(r'<meta name="apple-mobile-web-app-title" content="([^"]+)">'),
        ),
        _displayName,
      );
    });

    test('Windows displays Clean Notes without renaming the executable', () {
      // Mutation caught: changing the binary identity while aligning the
      // window title and Explorer-visible product metadata.
      final resource = _read('windows/runner/Runner.rc');
      final runner = _read('windows/runner/main.cpp');

      expect(_resourceValue(resource, 'FileDescription'), _displayName);
      expect(_resourceValue(resource, 'ProductName'), _displayName);
      expect(_resourceValue(resource, 'InternalName'), 'flutter_clean_notes');
      expect(
        _resourceValue(resource, 'OriginalFilename'),
        'flutter_clean_notes.exe',
      );
      expect(
        _capture(runner, RegExp(r'window\.Create\(L"([^"]+)"')),
        _displayName,
      );
    });

    test(
      'Linux displays Clean Notes without renaming application identity',
      () {
        // Mutation caught: changing the Linux binary/application ID while
        // replacing the generated window title.
        final runner = _read('linux/runner/my_application.cc');
        final cmake = _read('linux/CMakeLists.txt');

        expect(
          _capture(
            runner,
            RegExp(r'gtk_header_bar_set_title\([^,]+,\s*"([^"]+)"\)'),
          ),
          _displayName,
        );
        expect(
          _capture(
            runner,
            RegExp(r'gtk_window_set_title\([^,]+,\s*"([^"]+)"\)'),
          ),
          _displayName,
        );
        expect(
          _capture(cmake, RegExp(r'set\(BINARY_NAME\s+"([^"]+)"\)')),
          'flutter_clean_notes',
        );
        expect(
          _capture(cmake, RegExp(r'set\(APPLICATION_ID\s+"([^"]+)"\)')),
          'com.example.flutter_clean_notes',
        );
      },
    );

    test('macOS displays Clean Notes without renaming its product target', () {
      // Mutation caught: changing the macOS product, executable, or bundle ID
      // instead of adding a user-facing display name.
      final info = XmlDocument.parse(_read('macos/Runner/Info.plist'));
      final appInfo = _read('macos/Runner/Configs/AppInfo.xcconfig');

      expect(_plistString(info, 'CFBundleDisplayName'), _displayName);
      expect(_plistString(info, 'CFBundleName'), r'$(PRODUCT_NAME)');
      expect(_plistString(info, 'CFBundleExecutable'), r'$(EXECUTABLE_NAME)');
      expect(
        _plistString(info, 'CFBundleIdentifier'),
        r'$(PRODUCT_BUNDLE_IDENTIFIER)',
      );
      expect(
        _capture(
          appInfo,
          RegExp(r'^PRODUCT_NAME\s*=\s*(\S+)\s*$', multiLine: true),
        ),
        'flutter_clean_notes',
      );
      expect(
        _capture(
          appInfo,
          RegExp(
            r'^PRODUCT_BUNDLE_IDENTIFIER\s*=\s*(\S+)\s*$',
            multiLine: true,
          ),
        ),
        'com.example.flutterCleanNotes',
      );
    });
  });
}

String _read(String path) => File(path).readAsStringSync();

String? _androidAttribute(XmlElement element, String name) =>
    element.getAttribute(name, namespaceUri: _androidNamespace);

String? _plistString(XmlDocument document, String key) {
  final entries = document
      .findAllElements('dict')
      .first
      .children
      .whereType<XmlElement>()
      .toList(growable: false);
  for (var index = 0; index < entries.length - 1; index += 1) {
    if (entries[index].name.local == 'key' && entries[index].innerText == key) {
      return entries[index + 1].innerText;
    }
  }
  return null;
}

String? _resourceValue(String source, String key) =>
    _capture(source, RegExp('VALUE\\s+"${RegExp.escape(key)}",\\s+"([^"]+)"'));

String? _capture(String source, RegExp pattern) =>
    pattern.firstMatch(source)?.group(1);
