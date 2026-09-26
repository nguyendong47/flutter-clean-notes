import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

const String _defaultAppPath = 'build/ios/iphonesimulator/Runner.app';
const String _widgetExtensionRelativePath =
    'PlugIns/CleanNotesWidgetExtension.appex';
const String _appGroupsKey = 'com.apple.security.application-groups';
const String _requiredAppGroup = 'group.com.cleannotes.app';

final class BundleEntitlementResult {
  const BundleEntitlementResult({
    required this.bundlePath,
    required this.bundleName,
    required this.rawXml,
    required this.appGroups,
    required this.hasRequiredGroup,
    this.errorMessage,
  });

  final String bundlePath;
  final String bundleName;
  final String rawXml;
  final List<String> appGroups;
  final bool hasRequiredGroup;
  final String? errorMessage;
}

/// Extracts application groups from an XML plist entitlements string.
List<String> extractAppGroups(String xmlContent) {
  final groups = <String>[];
  if (xmlContent.trim().isEmpty) return groups;

  try {
    final doc = XmlDocument.parse(xmlContent);
    final dicts = doc.findAllElements('dict');
    for (final dict in dicts) {
      final children = dict.children.whereType<XmlElement>().toList();
      for (var i = 0; i < children.length; i++) {
        final child = children[i];
        if (child.name.local == 'key' && child.innerText.trim() == _appGroupsKey) {
          if (i + 1 < children.length) {
            final valueElement = children[i + 1];
            if (valueElement.name.local == 'array') {
              for (final stringElem in valueElement.findAllElements('string')) {
                final text = stringElem.innerText.trim();
                if (text.isNotEmpty && !groups.contains(text)) {
                  groups.add(text);
                }
              }
            }
          }
        }
      }
    }
  } catch (_) {
    // Fallback regex parser in case XML structure has formatting quirks
    final regex = RegExp(
      r'<key>\s*com\.apple\.security\.application-groups\s*<\/key>\s*<array>(.*?)<\/array>',
      dotAll: true,
    );
    final match = regex.firstMatch(xmlContent);
    if (match != null) {
      final arrayContent = match.group(1) ?? '';
      final stringRegex = RegExp(r'<string>\s*(.*?)\s*<\/string>');
      for (final strMatch in stringRegex.allMatches(arrayContent)) {
        final val = strMatch.group(1)?.trim();
        if (val != null && val.isNotEmpty && !groups.contains(val)) {
          groups.add(val);
        }
      }
    }
  }

  return groups;
}

/// Extracts the raw entitlements plist XML from an `otool -s __TEXT
/// __entitlements` hex dump. iOS Simulator builds embed real entitlements in
/// this Mach-O section for `launchd_sim` to read — NOT in the code signature
/// blob `codesign -d --entitlements` reads, which is reliably an empty
/// `<dict/>` for ad-hoc/local simulator signing regardless of whether the
/// entitlements are actually correct. A fat binary prints one
/// "Contents of (__TEXT,__entitlements) section" block per architecture;
/// they're expected to be identical, so the first one that decodes to valid
/// non-empty XML is used.
List<String> _parseOtoolEntitlementsSections(String otoolOutput) {
  final sections = <String>[];
  final lines = const LineSplitter().convert(otoolOutput);
  var i = 0;
  while (i < lines.length) {
    if (lines[i].trim() == 'Contents of (__TEXT,__entitlements) section') {
      final bytes = <int>[];
      var j = i + 1;
      while (j < lines.length &&
          !lines[j].trim().startsWith('Contents of') &&
          RegExp(r'^[0-9a-fA-F]{16}\t').hasMatch(lines[j])) {
        final hexPart = lines[j].split('\t').last.trim();
        final hexGroups = hexPart.split(RegExp(r'\s+'));
        for (final group in hexGroups) {
          for (var k = 0; k + 1 < group.length; k += 2) {
            final byte = int.tryParse(group.substring(k, k + 2), radix: 16);
            if (byte != null) bytes.add(byte);
          }
        }
        j++;
      }
      if (bytes.isNotEmpty) {
        // otool pads the section to a word boundary with trailing NULs.
        final trimmed = bytes.takeWhile((b) => b != 0).toList();
        sections.add(utf8.decode(trimmed, allowMalformed: true));
      }
      i = j;
    } else {
      i++;
    }
  }
  return sections;
}

/// Reads entitlements from the Mach-O `__TEXT,__entitlements` section of a
/// bundle's executable via `otool`. See [_parseOtoolEntitlementsSections] for
/// why this is used instead of `codesign -d --entitlements`.
Future<BundleEntitlementResult> checkBundleEntitlements(
  String bundlePath, {
  required String bundleName,
}) async {
  final dir = Directory(bundlePath);
  if (!dir.existsSync()) {
    return BundleEntitlementResult(
      bundlePath: bundlePath,
      bundleName: bundleName,
      rawXml: '',
      appGroups: const [],
      hasRequiredGroup: false,
      errorMessage: 'Bundle directory not found: $bundlePath',
    );
  }

  final executablePath = path.join(
    bundlePath,
    path.basenameWithoutExtension(bundlePath),
  );
  if (!File(executablePath).existsSync()) {
    return BundleEntitlementResult(
      bundlePath: bundlePath,
      bundleName: bundleName,
      rawXml: '',
      appGroups: const [],
      hasRequiredGroup: false,
      errorMessage: 'Executable not found at expected path: $executablePath',
    );
  }

  final ProcessResult result;
  try {
    result = await Process.run('otool', [
      '-s',
      '__TEXT',
      '__entitlements',
      executablePath,
    ]);
  } on ProcessException catch (e) {
    return BundleEntitlementResult(
      bundlePath: bundlePath,
      bundleName: bundleName,
      rawXml: '',
      appGroups: const [],
      hasRequiredGroup: false,
      errorMessage: 'Failed to run otool: ${e.message}',
    );
  }

  if (result.exitCode != 0) {
    return BundleEntitlementResult(
      bundlePath: bundlePath,
      bundleName: bundleName,
      rawXml: '',
      appGroups: const [],
      hasRequiredGroup: false,
      errorMessage: 'otool exited with code ${result.exitCode}.\n'
          'Stderr: ${result.stderr}',
    );
  }

  final sections = _parseOtoolEntitlementsSections(
    (result.stdout as String?) ?? '',
  );

  var rawXml = '';
  var appGroups = <String>[];
  for (final section in sections) {
    final groups = extractAppGroups(section);
    if (groups.isNotEmpty) {
      rawXml = section;
      appGroups = groups;
      break;
    }
    if (rawXml.isEmpty) rawXml = section;
  }

  final hasRequired = appGroups.contains(_requiredAppGroup);

  return BundleEntitlementResult(
    bundlePath: bundlePath,
    bundleName: bundleName,
    rawXml: rawXml,
    appGroups: appGroups,
    hasRequiredGroup: hasRequired,
  );
}

void _printUsage() {
  stdout.writeln('Usage: dart run tool/verify_ios_widget_entitlements.dart [app_path]');
  stdout.writeln('');
  stdout.writeln('Verifies that both Runner.app and CleanNotesWidgetExtension.appex');
  stdout.writeln('contain the required "$_requiredAppGroup" entitlement in "$_appGroupsKey".');
  stdout.writeln('');
  stdout.writeln('Arguments:');
  stdout.writeln('  [app_path]              Path to built Runner.app bundle.');
  stdout.writeln('                          Defaults to: $_defaultAppPath');
  stdout.writeln('  --app-path <path>       Alternative flag to specify Runner.app path.');
  stdout.writeln('  -h, --help              Show this help message.');
}

Future<void> main(List<String> args) async {
  String appPath = _defaultAppPath;

  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '-h' || arg == '--help') {
      _printUsage();
      exitCode = 0;
      return;
    } else if (arg == '--app-path') {
      if (i + 1 >= args.length) {
        stderr.writeln('Error: --app-path requires a path argument.');
        exitCode = 64;
        return;
      }
      appPath = args[++i];
    } else if (arg.startsWith('--app-path=')) {
      appPath = arg.substring('--app-path='.length);
    } else if (arg.startsWith('-')) {
      stderr.writeln('Error: Unknown flag $arg');
      _printUsage();
      exitCode = 64;
      return;
    } else {
      appPath = arg;
    }
  }

  final resolvedAppPath = path.normalize(path.absolute(appPath));
  final appDir = Directory(resolvedAppPath);
  if (!appDir.existsSync()) {
    stderr.writeln('Error: Application bundle not found at: $resolvedAppPath');
    exitCode = 64;
    return;
  }

  final extensionPath = path.normalize(
    path.join(resolvedAppPath, _widgetExtensionRelativePath),
  );
  final extensionDir = Directory(extensionPath);
  if (!extensionDir.existsSync()) {
    stderr.writeln('Error: Widget extension bundle not found at: $extensionPath');
    exitCode = 1;
    return;
  }

  stdout.writeln('Verifying iOS widget entitlements...');
  stdout.writeln('  App bundle:       $resolvedAppPath');
  stdout.writeln('  Extension bundle: $extensionPath');
  stdout.writeln('  Required group:   $_requiredAppGroup');
  stdout.writeln('');

  final appResult = await checkBundleEntitlements(
    resolvedAppPath,
    bundleName: 'Runner.app',
  );
  final extResult = await checkBundleEntitlements(
    extensionPath,
    bundleName: 'CleanNotesWidgetExtension.appex',
  );

  var failed = false;

  void reportResult(BundleEntitlementResult res) {
    if (res.errorMessage != null) {
      stderr.writeln('FAIL [${res.bundleName}]: ${res.errorMessage}');
      failed = true;
      return;
    }

    if (!res.hasRequiredGroup) {
      stderr.writeln('FAIL [${res.bundleName}]: Missing required App Group entitlement!');
      stderr.writeln('  Expected: "$_appGroupsKey" containing "$_requiredAppGroup"');
      stderr.writeln('  Found groups: ${res.appGroups.isEmpty ? "(none)" : res.appGroups.join(", ")}');
      stderr.writeln('  Actual entitlements XML:');
      if (res.rawXml.trim().isEmpty) {
        stderr.writeln('    (empty or no entitlements found)');
      } else {
        for (final line in const LineSplitter().convert(res.rawXml)) {
          stderr.writeln('    $line');
        }
      }
      failed = true;
    } else {
      stdout.writeln('PASS [${res.bundleName}]: Found "$_requiredAppGroup" in "$_appGroupsKey".');
      stdout.writeln('  Registered groups: ${res.appGroups.join(", ")}');
    }
  }

  reportResult(appResult);
  reportResult(extResult);

  stdout.writeln('');
  if (failed) {
    stderr.writeln('Entitlements verification FAILED.');
    exitCode = 1;
  } else {
    stdout.writeln('All iOS widget entitlements checks PASSED.');
    exitCode = 0;
  }
}
