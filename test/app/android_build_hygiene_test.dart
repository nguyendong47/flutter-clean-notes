import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _gradleDistributionUrl =
    'https://services.gradle.org/distributions/gradle-8.14-all.zip';
const _gradleDistributionSha256 =
    'efe9a3d147d948d7528a9887fa35abcf24ca1a43ad06439996490f77569b02d1';

void main() {
  group('Android build hygiene', () {
    test('tracked Gradle settings do not pin a developer machine JDK', () {
      // Mutation caught: checking a local Android Studio path into the shared
      // Gradle settings makes other developer and CI environments non-portable.
      final source = File('android/gradle.properties').readAsStringSync();
      final pinnedJdkProperty = RegExp(
        r'^\s*org\.gradle\.java\.home(?:\s*[:=]|\s+)',
        multiLine: true,
      );

      expect(pinnedJdkProperty.hasMatch(source), isFalse);
    });

    test('Gradle wrapper verifies the exact complete distribution', () {
      // Mutations caught: changing the distribution without its checksum or
      // removing the checksum permits an unverified Gradle download.
      final properties = _readProperties(
        'android/gradle/wrapper/gradle-wrapper.properties',
      );

      expect(properties['distributionUrl'], _gradleDistributionUrl);
      expect(properties['distributionSha256Sum'], _gradleDistributionSha256);
    });

    test('release router diagnostics cannot be unconditionally enabled', () {
      // Mutation caught: `true` enables GoRouter diagnostics in release builds,
      // where route values can include note identifiers.
      final routerSource = File('lib/app/router.dart').readAsStringSync();
      final diagnosticsExpression = RegExp(
        r'debugLogDiagnostics\s*:\s*([^,\r\n]+)',
      ).firstMatch(routerSource)?.group(1)?.trim();

      expect(diagnosticsExpression, anyOf('false', 'kDebugMode'));
    });
  });
}

Map<String, String> _readProperties(String path) {
  final properties = <String, String>{};
  final lines = const LineSplitter().convert(File(path).readAsStringSync());
  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#') || trimmed.startsWith('!')) {
      continue;
    }
    final separator = trimmed.indexOf('=');
    if (separator < 0) continue;
    final key = trimmed.substring(0, separator).trim();
    final value = trimmed
        .substring(separator + 1)
        .trim()
        .replaceAll(r'\:', ':');
    properties[key] = value;
  }
  return properties;
}
