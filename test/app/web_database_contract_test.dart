import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Web database release contract', () {
    test('uses the Dart 3.11-compatible official web factory', () {
      // Mutation caught: removing the web backend, or allowing pub to select the
      // Dart 3.12-only release, makes the checked-in web target fail at runtime.
      final pubspec = File('pubspec.yaml').readAsStringSync();

      expect(
        pubspec,
        matches(
          RegExp(r'^  sqflite_common_ffi_web: \^1\.1\.1$', multiLine: true),
        ),
      );
    });

    test('initializes the web factory before creating providers', () {
      // Mutation caught: the first notes provider reaches getDatabasesPath(),
      // which throws when the global sqflite factory is still uninitialized.
      final mainSource = File('lib/main.dart').readAsStringSync();
      final webGuard = mainSource.indexOf('if (kIsWeb)');
      final webFactory = mainSource.indexOf(
        'databaseFactory = databaseFactoryFfiWeb;',
      );
      final databaseInitialization = mainSource.indexOf(
        '_initializeDatabase();',
      );
      final providerContainer = mainSource.indexOf(
        '(createContainer ?? _createAppContainer)(notifications);',
      );

      expect(
        mainSource,
        contains("package:sqflite_common_ffi_web/sqflite_ffi_web.dart"),
      );
      expect(webGuard, isNonNegative);
      expect(webFactory, greaterThan(webGuard));
      expect(databaseInitialization, isNonNegative);
      expect(providerContainer, greaterThan(databaseInitialization));
    });

    test('ships the worker and WebAssembly runtime assets', () {
      // Mutation caught: a successful Dart-to-JavaScript compile is insufficient;
      // the web factory loads both files at runtime from the application origin.
      final wasm = File('web/sqlite3.wasm');
      final worker = File('web/sqflite_sw.js');
      final gitignore = File('.gitignore').readAsStringSync();

      expect(wasm.existsSync(), isTrue, reason: 'Missing web/sqlite3.wasm');
      expect(worker.existsSync(), isTrue, reason: 'Missing web/sqflite_sw.js');
      expect(
        wasm.readAsBytesSync().take(4),
        orderedEquals(const [0x00, 0x61, 0x73, 0x6D]),
      );
      expect(worker.lengthSync(), greaterThan(1000));
      expect(
        gitignore,
        matches(RegExp(r'^!web/sqflite_sw\.js$', multiLine: true)),
        reason: 'The generated worker must be included in release checkouts',
      );
    });

    test('keeps Flutter engine resources on the application origin', () {
      final workflow = File('.github/workflows/quality.yml').readAsStringSync();
      final releaseGuide = File('docs/release.md').readAsStringSync();

      expect(
        workflow,
        contains('flutter build web --release --no-pub --no-web-resources-cdn'),
      );
      expect(
        releaseGuide,
        contains('flutter build web --release --no-web-resources-cdn'),
      );
    });

    test('bundles the Roboto text font and its license', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final font = File('assets/fonts/Roboto-Variable.ttf');
      final license = File('assets/fonts/OFL.txt');

      expect(pubspec, contains('asset: assets/fonts/Roboto-Variable.ttf'));
      expect(font.existsSync(), isTrue, reason: 'Missing bundled Roboto font');
      expect(
        font.readAsBytesSync().take(4),
        orderedEquals(const [0x00, 0x01, 0x00, 0x00]),
      );
      expect(
        license.readAsStringSync(),
        contains('SIL OPEN FONT LICENSE Version 1.1'),
      );
    });

    test('keeps dynamic Web font fallback on the application origin', () {
      final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();
      final gitignore = File('.gitignore').readAsStringSync();
      final license = File('web/fallback_fonts/OFL.txt');
      final fallbackPaths = <String>[
        'notosanssymbols/v43/'
            'rP2up3q65FkAtHfwd-eIS2brbDN6gxP34F9jRRCe4W3gfQ8gb_VFRkzrbQ.woff2',
        'notosansarabic/v28/'
            'nwpxtLGrOAZMl5nJ_wfgRg3DrWFZWsnVBJ_sS6tlqHHFlhQ5l3sQWIHPqzCfyGyvvnCBFQLaig.woff2',
        'notocoloremoji/v32/'
            'Yq6P-KqIXTD0t4D9z1ESnKM3-HpFabsE4tq3luCC7p-aXxcn.8.woff2',
        'notosanssc/v37/'
            'k3kCo84MPvpLmixcA63oeAL7Iqp5IZJF9bmaG9_FnYkldv7JjxkkgFsFSSOPMOkySAZ73y9ViAt3acb8NexQ2w.114.woff2',
        'notosanssc/v37/'
            'k3kCo84MPvpLmixcA63oeAL7Iqp5IZJF9bmaG9_FnYkldv7JjxkkgFsFSSOPMOkySAZ73y9ViAt3acb8NexQ2w.116.woff2',
      ];

      expect(bootstrap, contains("fontFallbackBaseUrl: 'fallback_fonts/'"));
      expect(bootstrap, isNot(contains('fonts.gstatic.com')));
      expect(
        gitignore,
        matches(RegExp(r'^!web/flutter_bootstrap\.js$', multiLine: true)),
        reason: 'The custom bootstrap must survive a clean release checkout',
      );
      for (final relativePath in fallbackPaths) {
        final fallback = File('web/fallback_fonts/$relativePath');
        expect(
          fallback.existsSync(),
          isTrue,
          reason: 'Missing tested fallback: $relativePath',
        );
        expect(
          fallback.readAsBytesSync().take(4),
          orderedEquals('wOF2'.codeUnits),
          reason: 'Invalid WOFF2 header: $relativePath',
        );
      }
      expect(
        license.readAsStringSync(),
        contains('SIL OPEN FONT LICENSE Version 1.1'),
      );
    });

    test('documents Web as a supported release candidate', () {
      final releaseGuide = File('docs/release.md').readAsStringSync();
      final qaMatrix = File('docs/qa.md').readAsStringSync();

      expect(releaseGuide, contains('Web is a supported release candidate'));
      expect(releaseGuide, contains('flutter build web --release'));
      expect(qaMatrix, contains('| Web (supported candidate) |'));
      expect(qaMatrix, contains('sqflite_sw.js'));
      expect(qaMatrix, contains('sqlite3.wasm'));
      expect(qaMatrix, contains('IndexedDB'));
    });
  });
}
