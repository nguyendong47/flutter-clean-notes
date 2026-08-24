import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

const _safeFoundationVersion = '2.5.1';

void main() {
  test('iOS path provider stays on the method-channel dependency graph', () {
    // Mutations caught: removing the override, resolving the Foundation plugin
    // to its native-assets release, or reintroducing objective_c can restore
    // the iOS launch crash and malformed App Store IPA failure mode.
    final pubspec = _yamlMap(loadYaml(_read('pubspec.yaml')));
    final overrides = _yamlMap(pubspec['dependency_overrides']);
    final lockfile = _yamlMap(loadYaml(_read('pubspec.lock')));
    final packages = _yamlMap(lockfile['packages']);
    final foundation = _yamlMap(packages['path_provider_foundation']);

    expect(overrides['path_provider_foundation'], _safeFoundationVersion);
    expect(foundation['version'], _safeFoundationVersion);
    expect(
      packages.containsKey('objective_c'),
      isFalse,
      reason:
          'The reviewed Foundation plugin graph must not bundle native '
          'objective_c code assets.',
    );
  });
}

YamlMap _yamlMap(Object? value) {
  expect(value, isA<YamlMap>());
  return value! as YamlMap;
}

String _read(String path) => File(path).readAsStringSync();
