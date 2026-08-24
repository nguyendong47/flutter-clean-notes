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
      final providerContainer = mainSource.indexOf('ProviderContainer()');

      expect(
        mainSource,
        contains("package:sqflite_common_ffi_web/sqflite_ffi_web.dart"),
      );
      expect(webGuard, isNonNegative);
      expect(webFactory, greaterThan(webGuard));
      expect(providerContainer, greaterThan(webFactory));
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
