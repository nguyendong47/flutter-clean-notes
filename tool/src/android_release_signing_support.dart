import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

const _gradleAndJvmOptionSources = <String>{
  'GRADLE_HOME',
  'GRADLE_OPTS',
  'GRADLE_USER_HOME',
  'JAVA_OPTS',
  'JAVA_TOOL_OPTIONS',
  '_JAVA_OPTIONS',
  'JDK_JAVA_OPTIONS',
};

typedef DirectoryDeletion = Future<void> Function(Directory directory);
typedef FileSystemEntityDeletion =
    Future<void> Function(FileSystemEntity entity);
typedef RetryDelay = Future<void> Function(Duration duration);

enum AndroidSigningVerificationMode {
  help,
  contractOnly,
  contractAndPositive,
  positiveOnly,
}

const _gradle814UnixLauncherSha256 =
    'b187b4c52e749f5760afdd6fadc31b2a98ad35fb249bf0dff03b72650f320409';
const _gradle814WindowsLauncherSha256 =
    '1d297e00bd21de3ace22b4d7f2de1f9dfa858883d66bbf7c1ccbecccec8f4f3b';

Map<String, String> sanitizedGitEnvironment(
  Map<String, String> inheritedEnvironment,
) =>
    Map<String, String>.from(inheritedEnvironment)
      ..removeWhere((key, _) => key.toUpperCase().startsWith('GIT_'));

Map<String, String> sanitizedJavaEnvironment(
  Map<String, String> inheritedEnvironment,
) {
  const forbidden = <String>{
    'JAVA_TOOL_OPTIONS',
    '_JAVA_OPTIONS',
    'JDK_JAVA_OPTIONS',
    'JAVA_OPTS',
    'CLASSPATH',
  };
  return Map<String, String>.from(inheritedEnvironment)
    ..removeWhere((key, _) => forbidden.contains(key.toUpperCase()));
}

String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

String trustedGradleLauncherShim({
  required String javaExecutablePath,
  required String wrapperJarPath,
  required bool windows,
}) {
  final targetPath = path.Context(
    style: windows ? path.Style.windows : path.Style.posix,
  );
  if (!targetPath.isAbsolute(javaExecutablePath) ||
      !targetPath.isAbsolute(wrapperJarPath)) {
    throw StateError('Trusted Gradle launcher inputs must be absolute.');
  }
  if (windows) {
    const forbidden = <String>[
      '"',
      '\r',
      '\n',
      '\x00',
      '%',
      '!',
      '^',
      '&',
      '|',
      '<',
      '>',
    ];
    if (forbidden.any(
      (character) =>
          javaExecutablePath.contains(character) ||
          wrapperJarPath.contains(character),
    )) {
      throw StateError('Trusted Gradle launcher inputs are unsafe.');
    }
    return '@echo off\r\n'
        'setlocal DisableDelayedExpansion\r\n'
        '"$javaExecutablePath" -Dorg.gradle.appname=gradlew '
        '-jar "$wrapperJarPath" %*\r\n'
        'if errorlevel 1 exit /b 1\r\n'
        'if not errorlevel 0 exit /b 1\r\n'
        'exit /b 0\r\n';
  }
  if (javaExecutablePath.contains('\x00') ||
      wrapperJarPath.contains('\x00') ||
      javaExecutablePath.contains('\r') ||
      wrapperJarPath.contains('\r') ||
      javaExecutablePath.contains('\n') ||
      wrapperJarPath.contains('\n')) {
    throw StateError('Trusted Gradle launcher inputs are unsafe.');
  }
  final escapedJava = javaExecutablePath.replaceAll("'", "'\\''");
  final escapedJar = wrapperJarPath.replaceAll("'", "'\\''");
  return "#!/bin/sh\nexec '$escapedJava' -Dorg.gradle.appname=gradlew "
      "-jar '$escapedJar' \"\$@\"\n";
}

Future<T> runWithTrustedGradleLauncherShim<T>({
  required File candidateLauncher,
  required List<int> trustedLauncherBytes,
  required List<int> shimBytes,
  required Future<T> Function() operation,
  Future<void> Function(File launcher)? makeExecutable,
}) async {
  final expectedParent = _stableLauncherParent(candidateLauncher.parent);
  _assertStableLauncherParent(candidateLauncher.parent, expectedParent);
  if (FileSystemEntity.typeSync(candidateLauncher.path, followLinks: false) !=
      FileSystemEntityType.file) {
    throw StateError('The isolated candidate launcher is not a regular file.');
  }
  final originalBytes = await candidateLauncher.readAsBytes();
  if (sha256Hex(originalBytes) != sha256Hex(trustedLauncherBytes)) {
    throw StateError('The isolated candidate launcher changed before use.');
  }

  final random = Random.secure();
  final nonce = List<int>.generate(
    16,
    (_) => random.nextInt(256),
  ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  final backup = File('${candidateLauncher.path}.clean-notes-$nonce.original');
  final stagedShim = File('${candidateLauncher.path}.clean-notes-$nonce.shim');
  if (<File>[backup, stagedShim].any(
    (file) =>
        FileSystemEntity.typeSync(file.path, followLinks: false) !=
        FileSystemEntityType.notFound,
  )) {
    throw StateError('Unable to reserve a launcher backup safely.');
  }

  _assertStableLauncherParent(candidateLauncher.parent, expectedParent);
  await candidateLauncher.rename(backup.path);
  var shimInstalled = false;
  var stagedShimCreated = false;
  StateError? integrityFailure;
  try {
    _assertStableLauncherParent(candidateLauncher.parent, expectedParent);
    await stagedShim.create(exclusive: true);
    stagedShimCreated = true;
    if (FileSystemEntity.typeSync(stagedShim.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw StateError('Unable to create the trusted Gradle launcher shim.');
    }
    _assertStableLauncherParent(candidateLauncher.parent, expectedParent);
    final output = await stagedShim.open(mode: FileMode.writeOnly);
    try {
      if (FileSystemEntity.typeSync(stagedShim.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw StateError('Unable to open the trusted Gradle launcher shim.');
      }
      await output.writeFrom(shimBytes);
      await output.flush();
    } finally {
      await output.close();
    }
    if (makeExecutable != null) await makeExecutable(stagedShim);
    if (!_isRegularFileWithSha(stagedShim, sha256Hex(shimBytes))) {
      throw StateError('Unable to install the trusted Gradle launcher shim.');
    }
    if (FileSystemEntity.typeSync(candidateLauncher.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('The isolated launcher path was unexpectedly replaced.');
    }
    _assertStableLauncherParent(candidateLauncher.parent, expectedParent);
    await stagedShim.rename(candidateLauncher.path);
    stagedShimCreated = false;
    shimInstalled = true;
    if (!_isRegularFileWithSha(candidateLauncher, sha256Hex(shimBytes))) {
      throw StateError('Unable to install the trusted Gradle launcher shim.');
    }

    final result = await operation();
    _assertStableLauncherParent(candidateLauncher.parent, expectedParent);
    if (!_isRegularFileWithSha(candidateLauncher, sha256Hex(shimBytes))) {
      throw StateError('The trusted Gradle launcher shim changed during use.');
    }
    return result;
  } finally {
    _assertStableLauncherParent(candidateLauncher.parent, expectedParent);
    if (stagedShimCreated) {
      final stagedType = FileSystemEntity.typeSync(
        stagedShim.path,
        followLinks: false,
      );
      if (stagedType == FileSystemEntityType.file) {
        await stagedShim.delete();
      } else if (stagedType != FileSystemEntityType.notFound) {
        throw StateError(
          'The staged launcher became an unsafe filesystem object.',
        );
      }
    }
    final candidateType = FileSystemEntity.typeSync(
      candidateLauncher.path,
      followLinks: false,
    );
    if (candidateType == FileSystemEntityType.file) {
      if (shimInstalled &&
          !_isRegularFileWithSha(candidateLauncher, sha256Hex(shimBytes))) {
        integrityFailure = StateError(
          'The trusted Gradle launcher shim changed during use.',
        );
      }
      await candidateLauncher.delete();
    } else if (candidateType != FileSystemEntityType.notFound) {
      throw StateError(
        'The candidate launcher became an unsafe filesystem object.',
      );
    }
    if (FileSystemEntity.typeSync(backup.path, followLinks: false) !=
            FileSystemEntityType.file ||
        sha256Hex(await backup.readAsBytes()) != sha256Hex(originalBytes)) {
      throw StateError('The isolated launcher backup changed during use.');
    }
    if (FileSystemEntity.typeSync(candidateLauncher.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw StateError('The isolated launcher cannot be restored safely.');
    }
    await backup.rename(candidateLauncher.path);
    if (!_isRegularFileWithSha(candidateLauncher, sha256Hex(originalBytes))) {
      throw StateError('The isolated candidate launcher was not restored.');
    }
    if (integrityFailure != null) throw integrityFailure;
  }
}

bool _isRegularFileWithSha(File file, String expectedSha256) =>
    FileSystemEntity.typeSync(file.path, followLinks: false) ==
        FileSystemEntityType.file &&
    sha256Hex(file.readAsBytesSync()) == expectedSha256;

String _stableLauncherParent(Directory parent) {
  try {
    if (FileSystemEntity.typeSync(parent.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FileSystemException('launcher parent is not a directory');
    }
    final direct = path.normalize(path.absolute(parent.path));
    final resolved = path.normalize(parent.resolveSymbolicLinksSync());
    if (!_sameFilesystemPath(direct, resolved)) {
      throw const FileSystemException('launcher parent traverses a link');
    }
    return resolved;
  } on Object {
    throw StateError('The isolated launcher parent is unsafe.');
  }
}

void _assertStableLauncherParent(Directory parent, String expected) {
  final current = _stableLauncherParent(parent);
  if (!_sameFilesystemPath(current, expected)) {
    throw StateError('The isolated launcher parent changed during use.');
  }
}

bool _sameFilesystemPath(String left, String right) => Platform.isWindows
    ? left.toLowerCase() == right.toLowerCase()
    : left == right;

Directory resolveSystemTemporaryDirectory({Directory Function()? provider}) {
  try {
    final directory = provider == null ? Directory.systemTemp : provider();
    return Directory(directory.resolveSymbolicLinksSync());
  } on Object {
    throw StateError('Unable to resolve the system temporary directory.');
  }
}

String parseSingleApplicationId(String stdout, {required int exitCode}) {
  final values = stdout
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (exitCode != 0 ||
      values.length != 1 ||
      !RegExp(
        r'^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$',
      ).hasMatch(values.single)) {
    throw StateError('Artifact inspection returned an invalid application ID.');
  }
  return values.single;
}

String parseApksignerSha256(String stdout, {required int exitCode}) {
  final matches = RegExp(
    r'^Signer #\d+ certificate SHA-256 digest: ([0-9A-Fa-f]{64})\s*$',
    multiLine: true,
  ).allMatches(stdout).toList(growable: false);
  if (exitCode != 0 || matches.length != 1) {
    throw StateError('APK inspection did not report exactly one signer.');
  }
  return matches.single.group(1)!.toLowerCase();
}

String parseKeytoolSha256(String stdout, {required int exitCode}) {
  final matches = RegExp(
    r'^\s*SHA256:\s*([0-9A-Fa-f:]+)\s*$',
    multiLine: true,
  ).allMatches(stdout).toList(growable: false);
  final normalized = matches
      .map((match) => match.group(1)!.replaceAll(':', '').toLowerCase())
      .where((value) => RegExp(r'^[0-9a-f]{64}$').hasMatch(value))
      .toList(growable: false);
  if (exitCode != 0 || normalized.length != 1) {
    throw StateError(
      'Signed bundle inspection did not report one certificate.',
    );
  }
  return normalized.single;
}

File resolveTrustedGitExecutable(
  Directory repository,
  Map<String, String> environment,
) {
  final configured = environment['CLEAN_NOTES_GIT_EXECUTABLE'];
  final candidates = configured != null && configured.trim().isNotEmpty
      ? <String>[configured.trim()]
      : Platform.isWindows
      ? const <String>[
          r'C:\Program Files\Git\cmd\git.exe',
          r'C:\Program Files\Git\bin\git.exe',
        ]
      : const <String>['/usr/bin/git', '/opt/homebrew/bin/git'];
  for (final candidate in candidates) {
    try {
      if (!path.isAbsolute(candidate) ||
          FileSystemEntity.typeSync(candidate, followLinks: false) !=
              FileSystemEntityType.file) {
        continue;
      }
      final canonical = File(candidate).resolveSymbolicLinksSync();
      final repositoryPath = repository.resolveSymbolicLinksSync();
      if (!path.equals(canonical, repositoryPath) &&
          !path.isWithin(repositoryPath, canonical)) {
        return File(canonical);
      }
    } on Object {
      continue;
    }
  }
  throw StateError('A trusted absolute Git executable is required.');
}

void validateGradleWrapperLauncherDigests({
  required String unixSha256,
  required String windowsSha256,
}) {
  if (unixSha256.toLowerCase() != _gradle814UnixLauncherSha256 ||
      windowsSha256.toLowerCase() != _gradle814WindowsLauncherSha256) {
    throw StateError('The Gradle 8.14 wrapper launchers are not authentic.');
  }
}

void validateGradleWrapperProperties(
  String contents, {
  required String expectedDistributionUrl,
  required String expectedDistributionSha256,
}) {
  final properties = <String, String>{};
  for (final line in contents.replaceAll('\r\n', '\n').split('\n')) {
    if (line.isEmpty) continue;
    final match = RegExp(r'^([A-Za-z][A-Za-z0-9]*)=(.*)$').firstMatch(line);
    if (match == null) {
      throw StateError('The Gradle wrapper properties are not canonical.');
    }
    final key = match.group(1)!;
    if (properties.containsKey(key)) {
      throw StateError('The Gradle wrapper properties contain duplicates.');
    }
    properties[key] = match.group(2)!;
  }

  final expected = <String, String>{
    'distributionBase': 'GRADLE_USER_HOME',
    'distributionPath': 'wrapper/dists',
    'distributionSha256Sum': expectedDistributionSha256,
    'distributionUrl': expectedDistributionUrl,
    'networkTimeout': '10000',
    'validateDistributionUrl': 'true',
    'zipStoreBase': 'GRADLE_USER_HOME',
    'zipStorePath': 'wrapper/dists',
  };
  if (properties.length != expected.length ||
      expected.entries.any((entry) => properties[entry.key] != entry.value)) {
    throw StateError('The Gradle wrapper properties are not pinned exactly.');
  }
}

AndroidSigningVerificationMode parseAndroidSigningVerificationMode(
  List<String> arguments,
) {
  const positiveFlag = '--build-positive-release-artifacts';
  const positiveOnlyFlag = '--build-positive-release-artifacts-only';
  if (arguments.isEmpty) {
    return AndroidSigningVerificationMode.contractOnly;
  }
  if (arguments.length == 1) {
    return switch (arguments.single) {
      '--help' => AndroidSigningVerificationMode.help,
      positiveFlag => AndroidSigningVerificationMode.contractAndPositive,
      positiveOnlyFlag => AndroidSigningVerificationMode.positiveOnly,
      _ => throw const FormatException('Unknown verifier argument.'),
    };
  }
  final modes = arguments.toSet();
  if (modes.contains(positiveFlag) && modes.contains(positiveOnlyFlag)) {
    throw const FormatException('Conflicting verifier modes.');
  }
  throw const FormatException('Unknown verifier argument.');
}

String redactSensitiveText(
  String input,
  Iterable<String> sensitiveValues, {
  Iterable<String> sensitivePaths = const [],
}) {
  final variants = <({String value, bool caseInsensitive})>[];
  for (final value in sensitiveValues) {
    if (value.isEmpty) continue;
    variants.add((value: value, caseInsensitive: false));
  }
  for (final value in sensitivePaths) {
    if (value.isEmpty) continue;
    final caseInsensitive = RegExp(
      r'^(?:[A-Za-z]:[\\/]|[\\/]{2})',
    ).hasMatch(value);
    for (final variant in <String>{
      value,
      value.replaceAll('\\', '/'),
      value.replaceAll('/', '\\'),
    }) {
      variants.add((value: variant, caseInsensitive: caseInsensitive));
    }
  }
  variants.sort(
    (left, right) => right.value.length.compareTo(left.value.length),
  );
  return variants.fold(
    input,
    (sanitized, entry) => entry.caseInsensitive
        ? sanitized.replaceAll(
            RegExp(RegExp.escape(entry.value), caseSensitive: false),
            '[REDACTED]',
          )
        : sanitized.replaceAll(entry.value, '[REDACTED]'),
  );
}

Future<void> deleteFileSystemEntityWithRetries(
  FileSystemEntity entity, {
  int maxAttempts = 5,
  Duration initialDelay = const Duration(milliseconds: 250),
  FileSystemEntityDeletion? deleteEntity,
  RetryDelay? delay,
}) async {
  if (maxAttempts < 1) {
    throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be positive');
  }
  final remove = deleteEntity ?? _deleteFileSystemEntity;
  final wait = delay ?? Future<void>.delayed;

  for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
    try {
      await remove(entity);
      return;
    } on FileSystemException {
      if (attempt + 1 == maxAttempts) rethrow;
      await wait(
        Duration(milliseconds: initialDelay.inMilliseconds * (attempt + 1)),
      );
    }
  }
}

Future<void> _deleteFileSystemEntity(FileSystemEntity entity) async {
  if (entity is Directory) {
    await entity.delete(recursive: true);
  } else if (entity is Link) {
    await entity.delete();
  } else if (entity is File) {
    await entity.delete();
  } else {
    throw const FileSystemException('Unsupported filesystem entity type.');
  }
}

Future<void> deleteTemporaryDirectoryWithRetries(
  Directory directory, {
  int maxAttempts = 5,
  Duration initialDelay = const Duration(milliseconds: 250),
  DirectoryDeletion? deleteDirectory,
  RetryDelay? delay,
}) async {
  await deleteFileSystemEntityWithRetries(
    directory,
    maxAttempts: maxAttempts,
    initialDelay: initialDelay,
    deleteEntity: deleteDirectory == null
        ? null
        : (entity) => deleteDirectory(entity as Directory),
    delay: delay,
  );
}

Map<String, String> hermeticGradleEnvironment({
  required Map<String, String> inheritedEnvironment,
  required Map<String, String> projectProperties,
  required Directory gradleUserHome,
}) {
  final controlledKeys = projectProperties.keys
      .map((key) => key.toUpperCase())
      .toSet();
  final environment = Map<String, String>.from(inheritedEnvironment)
    ..removeWhere((key, _) {
      final normalizedKey = key.toUpperCase();
      return normalizedKey.startsWith('ORG_GRADLE_PROJECT_') ||
          _gradleAndJvmOptionSources.contains(normalizedKey) ||
          controlledKeys.contains(normalizedKey);
    });
  environment['GRADLE_USER_HOME'] = gradleUserHome.absolute.path;
  for (final entry in projectProperties.entries) {
    environment[entry.key] = entry.value;
  }
  return environment;
}

Future<List<String>> protectedRepositoryRoots(
  Directory repository, {
  File? gitExecutable,
}) async {
  final trustedGit =
      gitExecutable ??
      resolveTrustedGitExecutable(repository, Platform.environment);
  final topLevel = await _gitPath(repository, trustedGit, '--show-toplevel');
  final commonDirectory = await _gitPath(
    repository,
    trustedGit,
    '--git-common-dir',
  );
  final candidates = <String>{topLevel, commonDirectory};
  if (path.basename(commonDirectory).toLowerCase() == '.git') {
    candidates.add(path.dirname(commonDirectory));
  }
  final listedWorktrees = await _gitWorktreePaths(repository, trustedGit);
  final metadataWorktrees = _metadataWorktreePaths(commonDirectory);
  final listedWorktreeKeys = listedWorktrees.map(_canonicalPathKey).toSet();
  for (final metadataWorktree in metadataWorktrees) {
    if (!listedWorktreeKeys.contains(_canonicalPathKey(metadataWorktree))) {
      throw StateError('Git linked-worktree metadata is inconsistent.');
    }
  }
  candidates
    ..addAll(listedWorktrees)
    ..addAll(metadataWorktrees);

  final rootsByKey = <String, String>{};
  for (final candidate in candidates) {
    final canonical = _canonicalExistingDirectory(candidate);
    final key = Platform.isWindows ? canonical.toLowerCase() : canonical;
    rootsByKey[key] = canonical;
  }
  return rootsByKey.values.toList(growable: false);
}

List<String> _metadataWorktreePaths(String commonDirectory) {
  final metadataRoot = Directory(path.join(commonDirectory, 'worktrees'));
  if (!metadataRoot.existsSync()) return const [];
  late List<FileSystemEntity> entries;
  try {
    entries = metadataRoot.listSync(followLinks: false);
  } on FileSystemException {
    throw StateError('Git linked-worktree metadata is unreadable.');
  }
  final worktrees = <String>[];
  for (final entry in entries) {
    if (entry is! Directory) {
      throw StateError('Git linked-worktree metadata is malformed.');
    }
    final marker = File(path.join(entry.path, 'gitdir'));
    late String configuredGitFile;
    try {
      if (!FileSystemEntity.isFileSync(marker.path)) {
        throw const FileSystemException('Missing gitdir marker');
      }
      configuredGitFile = marker.readAsStringSync(encoding: utf8).trim();
    } on FileSystemException {
      throw StateError('Git linked-worktree metadata is unreadable.');
    }
    if (configuredGitFile.isEmpty) {
      throw StateError('Git linked-worktree metadata is malformed.');
    }
    final linkedGitFile = path.normalize(
      path.isAbsolute(configuredGitFile)
          ? configuredGitFile
          : path.join(entry.path, configuredGitFile),
    );
    if (!FileSystemEntity.isFileSync(linkedGitFile)) {
      throw StateError('A registered linked worktree is unavailable.');
    }
    final worktree = path.dirname(linkedGitFile);
    if (!Directory(worktree).existsSync()) {
      throw StateError('A registered linked worktree is unavailable.');
    }
    worktrees.add(worktree);
  }
  return worktrees;
}

String _canonicalPathKey(String value) {
  final canonical = _canonicalExistingDirectory(value);
  return Platform.isWindows ? canonical.toLowerCase() : canonical;
}

String _canonicalExistingDirectory(String candidate) {
  try {
    final normalized = path.normalize(path.absolute(candidate));
    if (!Directory(normalized).existsSync()) {
      throw StateError('A registered Git/worktree root is unavailable.');
    }
    return Directory(normalized).resolveSymbolicLinksSync();
  } on StateError {
    rethrow;
  } on Object {
    throw StateError('A registered Git/worktree root is unavailable.');
  }
}

Future<String> _gitPath(
  Directory repository,
  File gitExecutable,
  String selector,
) async {
  final result = await Process.run(
    gitExecutable.path,
    ['-C', repository.path, 'rev-parse', '--path-format=absolute', selector],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
    environment: sanitizedGitEnvironment(Platform.environment),
    includeParentEnvironment: false,
    runInShell: false,
  );
  if (result.exitCode != 0) {
    throw StateError('Unable to resolve $selector safely.');
  }
  final resolved = (result.stdout as String).trim();
  if (resolved.isEmpty || !path.isAbsolute(resolved)) {
    throw StateError('Git returned an invalid absolute path for $selector.');
  }
  return resolved;
}

Future<List<String>> _gitWorktreePaths(
  Directory repository,
  File gitExecutable,
) async {
  final result = await Process.run(
    gitExecutable.path,
    ['-C', repository.path, 'worktree', 'list', '--porcelain', '-z'],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
    environment: sanitizedGitEnvironment(Platform.environment),
    includeParentEnvironment: false,
    runInShell: false,
  );
  if (result.exitCode != 0) {
    throw StateError('Unable to enumerate linked Git worktrees safely.');
  }
  final worktrees = (result.stdout as String)
      .split('\x00')
      .where((field) => field.startsWith('worktree '))
      .map((field) => field.substring('worktree '.length))
      .toList(growable: false);
  if (worktrees.isEmpty || worktrees.any((entry) => !path.isAbsolute(entry))) {
    throw StateError('Git returned malformed linked-worktree metadata.');
  }
  return worktrees;
}
