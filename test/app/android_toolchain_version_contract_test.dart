import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _requiredAgpVersion = '8.12.3';
const _requiredGradleVersion = '8.14';
const _requiredKotlinVersion = '2.2.20';

void main() {
  test('Android toolchain stays on the validated version set', () {
    // Mutations caught: downgrading, omitting, or independently changing AGP,
    // Gradle, or Kotlin breaks the validated Android build combination.
    final settings = File('android/settings.gradle.kts').readAsStringSync();
    final wrapper = _readProperties(
      'android/gradle/wrapper/gradle-wrapper.properties',
    );

    expect(
      _pluginVersion(settings, 'com.android.application'),
      _requiredAgpVersion,
    );
    expect(
      wrapper['distributionUrl'],
      'https://services.gradle.org/distributions/'
      'gradle-$_requiredGradleVersion-all.zip',
    );
    expect(
      _pluginVersion(settings, 'org.jetbrains.kotlin.android'),
      _requiredKotlinVersion,
    );
  });

  test('Android Kotlin target uses the typed compiler options DSL', () {
    // Mutations caught: restoring the deprecated kotlinOptions block or
    // assigning the JVM target through a string silently reintroduces the
    // Kotlin Gradle plugin deprecation.
    final buildScript = File('android/app/build.gradle.kts').readAsStringSync();

    expect(
      buildScript,
      contains('import org.jetbrains.kotlin.gradle.dsl.JvmTarget'),
    );
    expect(
      buildScript,
      matches(
        RegExp(
          r'kotlin\s*\{\s*compilerOptions\s*\{\s*'
          r'jvmTarget\s*=\s*JvmTarget\.JVM_17\s*\}\s*\}',
          multiLine: true,
        ),
      ),
    );
    expect(buildScript, isNot(contains('kotlinOptions')));
    expect(
      buildScript,
      isNot(
        matches(
          RegExp(
            r'jvmTarget\s*=\s*(?:"17"|JavaVersion\.VERSION_17\.toString\(\))',
          ),
        ),
      ),
    );
  });
}

String? _pluginVersion(String settings, String pluginId) {
  final declaration = RegExp(
    'id\\("${RegExp.escape(pluginId)}"\\)\\s+'
    'version\\s+"([^"]+)"',
  ).firstMatch(settings);
  return declaration?.group(1);
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
    properties[trimmed.substring(0, separator).trim()] = trimmed
        .substring(separator + 1)
        .trim()
        .replaceAll(r'\:', ':');
  }
  return properties;
}
