import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _requiredDeploymentTarget = '15.0';
const _runnerProjectPath = 'ios/Runner.xcodeproj/project.pbxproj';

// Native targets besides Runner itself that are allowed to declare their own
// explicit IPHONEOS_DEPLOYMENT_TARGET override (rather than inheriting the
// project-level default) — each must still target iOS 15.0. Update this list
// deliberately when adding a new target; anything not listed here showing up
// with its own override should fail the test below.
const _targetsWithExplicitOverride = {'CleanNotesWidgetExtension'};

void main() {
  test('Runner Debug, Release, and Profile consistently target iOS 15', () {
    // Mutations caught: removing a project configuration target, lowering one
    // below iOS 15, or an unlisted target adding a conflicting SDK override.
    final project = File(_runnerProjectPath).readAsStringSync();
    final configurations = _projectBuildConfigurations(project);

    expect(configurations.map((configuration) => configuration.name).toSet(), {
      'Debug',
      'Release',
      'Profile',
    });

    final targetOverrides = _targetDeploymentTargetOverrides(project);
    final unexpectedOverrides = targetOverrides.keys.toSet().difference(
      _targetsWithExplicitOverride,
    );
    expect(
      unexpectedOverrides,
      isEmpty,
      reason:
          'Unexpected target(s) declaring their own IPHONEOS_DEPLOYMENT_TARGET '
          'override: $unexpectedOverrides. Either remove the override or add '
          'the target to _targetsWithExplicitOverride if intentional.',
    );

    final allTargets = _deploymentTargets(project);
    final expectedTotal =
        configurations.length +
        targetOverrides.values.fold<int>(0, (sum, v) => sum + v.length);
    expect(
      allTargets,
      hasLength(expectedTotal),
      reason:
          'Every deployment-target declaration must belong to either the '
          'project-level default or a listed target override; extra/stray '
          'declarations are not allowed.',
    );

    for (final configuration in configurations) {
      final settings = _buildSettings(project, configuration);
      expect(_deploymentTargets(settings), [
        _requiredDeploymentTarget,
      ], reason: '${configuration.name} must explicitly target iOS 15.0.');
    }

    targetOverrides.forEach((bundleSuffix, values) {
      expect(
        values.toSet(),
        {_requiredDeploymentTarget},
        reason:
            '$bundleSuffix must consistently override to iOS 15.0 in every '
            'configuration that sets it explicitly.',
      );
    });
  });
}

/// Maps each non-Runner target's bundle-id suffix (e.g.
/// "CleanNotesWidgetExtension") to the list of IPHONEOS_DEPLOYMENT_TARGET
/// values it explicitly declares across its own XCBuildConfiguration blocks.
/// Blocks with no PRODUCT_BUNDLE_IDENTIFIER (the project-level defaults) are
/// excluded — those are covered separately by [_projectBuildConfigurations].
Map<String, List<String>> _targetDeploymentTargetOverrides(String project) {
  final result = <String, List<String>>{};
  final blocks = RegExp(
    r'isa = XCBuildConfiguration;(.*?)\n\t\t\};',
    dotAll: true,
  ).allMatches(project);

  for (final block in blocks) {
    final body = block.group(1)!;
    final deploymentTargets = _deploymentTargets(body);
    if (deploymentTargets.isEmpty) continue;

    final bundleId = RegExp(
      r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);',
    ).firstMatch(body)?.group(1);
    if (bundleId == null) continue; // project-level default, no target.

    final suffix = bundleId.contains('.')
        ? bundleId.substring(bundleId.lastIndexOf('.') + 1)
        : bundleId;
    result.putIfAbsent(suffix, () => []).addAll(deploymentTargets);
  }

  return result;
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
