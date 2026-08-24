import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _requiredDeploymentTarget = '15.0';
const _runnerProjectPath = 'ios/Runner.xcodeproj/project.pbxproj';

void main() {
  test('Runner Debug, Release, and Profile consistently target iOS 15', () {
    // Mutations caught: removing a project configuration target, lowering one
    // below iOS 15, or adding a conflicting target-level SDK override.
    final project = File(_runnerProjectPath).readAsStringSync();
    final configurations = _projectBuildConfigurations(project);

    expect(configurations.map((configuration) => configuration.name).toSet(), {
      'Debug',
      'Release',
      'Profile',
    });

    final allTargets = _deploymentTargets(project);
    expect(
      allTargets,
      hasLength(configurations.length),
      reason:
          'Every target declaration must belong to one Runner project '
          'configuration; extra SDK/target overrides are not allowed.',
    );

    for (final configuration in configurations) {
      final settings = _buildSettings(project, configuration);
      expect(
        _deploymentTargets(settings),
        [_requiredDeploymentTarget],
        reason: '${configuration.name} must explicitly target iOS 15.0.',
      );
    }
  });
}

List<({String id, String name})> _projectBuildConfigurations(String project) {
  final list = RegExp(
    r'/\* Build configuration list for PBXProject "Runner" \*/ = \{'
    r'\s*isa = XCConfigurationList;\s*buildConfigurations = \((.*?)\);',
    dotAll: true,
  ).firstMatch(project);
  expect(list, isNotNull, reason: 'Runner project configuration list missing.');

  return RegExp(r'([0-9A-F]{24}) /\* ([^*]+) \*/,')
      .allMatches(list!.group(1)!)
      .map((match) => (id: match.group(1)!, name: match.group(2)!.trim()))
      .toList(growable: false);
}

String _buildSettings(
  String project,
  ({String id, String name}) configuration,
) {
  final block = RegExp(
    '${RegExp.escape(configuration.id)} /\\* '
    '${RegExp.escape(configuration.name)} \\*/ = \\{'
    r'\s*isa = XCBuildConfiguration;.*?buildSettings = \{(.*?)\};'
    '\\s*name = ${RegExp.escape(configuration.name)};\\s*\\};',
    dotAll: true,
  ).firstMatch(project);
  expect(
    block,
    isNotNull,
    reason: '${configuration.name} build settings missing.',
  );
  return block!.group(1)!;
}

List<String> _deploymentTargets(String source) =>
    RegExp(
          r'^\s*"?IPHONEOS_DEPLOYMENT_TARGET(?:\[[^\]\r\n]+\])?"?\s*=\s*'
          r'"?([^";\r\n]+)"?;\s*$',
          multiLine: true,
        )
        .allMatches(source)
        .map((match) => match.group(1)!.trim())
        .toList(growable: false);
