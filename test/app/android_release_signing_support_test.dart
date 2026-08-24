import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

import '../../tool/src/android_release_signing_support.dart';

void main() {
  group('Android release signing verifier support', () {
    test('Gradle wrapper properties reject duplicate active assignments', () {
      const checksum =
          'efe9a3d147d948d7528a9887fa35abcf24ca1a43ad06439996490f77569b02d1';
      const expected =
          '''distributionBase=GRADLE_USER_HOME
distributionPath=wrapper/dists
distributionSha256Sum=$checksum
distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14-all.zip
networkTimeout=10000
validateDistributionUrl=true
zipStoreBase=GRADLE_USER_HOME
zipStorePath=wrapper/dists
''';

      expect(
        () => validateGradleWrapperProperties(
          expected,
          expectedDistributionUrl:
              r'https\://services.gradle.org/distributions/gradle-8.14-all.zip',
          expectedDistributionSha256: checksum,
        ),
        returnsNormally,
      );
      expect(
        () => validateGradleWrapperProperties(
          '$expected'
          'distributionUrl=https\\://attacker.invalid/gradle.zip\n',
          expectedDistributionUrl:
              r'https\://services.gradle.org/distributions/gradle-8.14-all.zip',
          expectedDistributionSha256: checksum,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => validateGradleWrapperProperties(
          expected.replaceFirst(
            'distributionUrl=https\\://services.gradle.org/distributions/'
                'gradle-8.14-all.zip',
            '# distributionUrl=https\\://services.gradle.org/distributions/'
                'gradle-8.14-all.zip\n'
                'distributionUrl=https\\://attacker.invalid/gradle.zip',
          ),
          expectedDistributionUrl:
              r'https\://services.gradle.org/distributions/gradle-8.14-all.zip',
          expectedDistributionSha256: checksum,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => validateGradleWrapperProperties(
          '$expected'
          'distributionSha256Sum=${List.filled(64, '0').join()}\n',
          expectedDistributionUrl:
              r'https\://services.gradle.org/distributions/gradle-8.14-all.zip',
          expectedDistributionSha256: checksum,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('Git subprocess environment strips repository control hooks', () {
      final environment = sanitizedGitEnvironment(const {
        'PATH': 'safe-path',
        'SystemRoot': r'C:\Windows',
        'GIT_DIR': r'C:\attacker\git-dir',
        'git_work_tree': r'C:\attacker\work-tree',
        'Git_Index_File': r'C:\attacker\index',
        'GIT_CONFIG_GLOBAL': r'C:\attacker\config',
        'UNRELATED': 'preserved',
      });

      expect(environment['PATH'], 'safe-path');
      expect(environment['SystemRoot'], r'C:\Windows');
      expect(environment['UNRELATED'], 'preserved');
      expect(
        environment.keys.map((key) => key.toUpperCase()),
        everyElement(isNot(startsWith('GIT_'))),
      );
    });

    test('Java subprocess environment strips JVM injection hooks', () {
      final environment = sanitizedJavaEnvironment(const {
        'PATH': 'safe-path',
        'JAVA_HOME': r'C:\trusted-jdk',
        'JAVA_TOOL_OPTIONS': '-javaagent:attacker.jar',
        '_java_options': '-Duser.home=attacker',
        'JDK_JAVA_OPTIONS': '--class-path attacker.jar',
        'CLASSPATH': 'attacker.jar',
        'UNRELATED': 'preserved',
      });

      expect(environment['PATH'], 'safe-path');
      expect(environment['JAVA_HOME'], r'C:\trusted-jdk');
      expect(environment['UNRELATED'], 'preserved');
      final normalizedKeys = environment.keys.map((key) => key.toUpperCase());
      for (final forbidden in <String>{
        'JAVA_TOOL_OPTIONS',
        '_JAVA_OPTIONS',
        'JDK_JAVA_OPTIONS',
        'JAVA_OPTS',
        'CLASSPATH',
      }) {
        expect(normalizedKeys, isNot(contains(forbidden)));
      }
    });

    test('SHA-256 is computed in-process from exact bytes', () {
      expect(
        sha256Hex(utf8.encode('abc')),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
    });

    test('artifact evidence parsers reject ambiguity and spoof text', () {
      const applicationId = 'dev.codex.cleannotes.contract';
      const fingerprint =
          'b7be5f7e7d91e971f20eb4cec6dd26fe40953eb6561148f8532fe40cefe58b5d';
      expect(
        parseSingleApplicationId('$applicationId\n', exitCode: 0),
        applicationId,
      );
      expect(
        parseApksignerSha256(
          'Signer #1 certificate SHA-256 digest: $fingerprint\n',
          exitCode: 0,
        ),
        fingerprint,
      );
      expect(
        parseKeytoolSha256(
          'Certificate fingerprints:\n\t SHA256: '
          '${fingerprint.replaceAllMapped(RegExp(r'..'), (match) => '${match.group(0)}:').replaceFirst(RegExp(r':$'), '')}\n',
          exitCode: 0,
        ),
        fingerprint,
      );
      expect(
        () => parseSingleApplicationId(
          '$applicationId\ncom.attacker.shadow\n',
          exitCode: 0,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => parseApksignerSha256(
          'path/$fingerprint/file.apk\n'
          'Signer #1 certificate SHA-256 digest: $fingerprint\n'
          'Signer #2 certificate SHA-256 digest: $fingerprint\n',
          exitCode: 0,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => parseKeytoolSha256('SHA256: $fingerprint\n', exitCode: 1),
        throwsA(isA<StateError>()),
      );
    });

    test('trusted Git resolves to an absolute executable outside the repo', () {
      final repository = Directory.current.absolute;
      final executable = resolveTrustedGitExecutable(
        repository,
        Platform.environment,
      );
      expect(path.isAbsolute(executable.path), isTrue);
      expect(executable.existsSync(), isTrue);
      expect(path.isWithin(repository.path, executable.path), isFalse);
    });

    test('trusted Git resolution does not expose an unresolvable repo path', () {
      final trustedGit = resolveTrustedGitExecutable(
        Directory.current.absolute,
        Platform.environment,
      );
      final privateRepositoryPath = path.join(
        Directory.systemTemp.path,
        'owner-private-missing-repository-${DateTime.now().microsecondsSinceEpoch}',
      );

      expect(
        () => resolveTrustedGitExecutable(Directory(privateRepositoryPath), {
          'CLEAN_NOTES_GIT_EXECUTABLE': trustedGit.path,
        }),
        throwsA(
          isA<StateError>().having(
            (error) => error.toString(),
            'diagnostic',
            isNot(contains(privateRepositoryPath)),
          ),
        ),
      );
    });

    test('system temp failures do not expose private candidate paths', () {
      final privatePath = path.join(
        Directory.systemTemp.path,
        'owner-private-missing-temp-${DateTime.now().microsecondsSinceEpoch}',
      );
      final providers = <Directory Function()>[
        () => throw FileSystemException('access denied', privatePath),
        () => Directory(privatePath),
      ];

      for (final provider in providers) {
        expect(
          () => resolveSystemTemporaryDirectory(provider: provider),
          throwsA(
            isA<StateError>().having(
              (error) => error.toString(),
              'diagnostic',
              isNot(contains(privatePath)),
            ),
          ),
        );
      }
    });

    test('official Gradle launchers reject any digest mutation', () {
      const unixDigest =
          'b187b4c52e749f5760afdd6fadc31b2a98ad35fb249bf0dff03b72650f320409';
      const windowsDigest =
          '1d297e00bd21de3ace22b4d7f2de1f9dfa858883d66bbf7c1ccbecccec8f4f3b';

      expect(
        () => validateGradleWrapperLauncherDigests(
          unixSha256: unixDigest,
          windowsSha256: windowsDigest,
        ),
        returnsNormally,
      );
      expect(
        () => validateGradleWrapperLauncherDigests(
          unixSha256: '${unixDigest.substring(0, 63)}0',
          windowsSha256: windowsDigest,
        ),
        throwsA(isA<StateError>()),
      );
      expect(
        () => validateGradleWrapperLauncherDigests(
          unixSha256: unixDigest,
          windowsSha256: '${windowsDigest.substring(0, 63)}0',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('verification mode parser rejects conflicting or unknown flags', () {
      expect(
        parseAndroidSigningVerificationMode(const []),
        AndroidSigningVerificationMode.contractOnly,
      );
      expect(
        parseAndroidSigningVerificationMode(const [
          '--build-positive-release-artifacts',
        ]),
        AndroidSigningVerificationMode.contractAndPositive,
      );
      expect(
        parseAndroidSigningVerificationMode(const [
          '--build-positive-release-artifacts-only',
        ]),
        AndroidSigningVerificationMode.positiveOnly,
      );
      expect(
        () => parseAndroidSigningVerificationMode(const [
          '--build-positive-release-artifacts',
          '--build-positive-release-artifacts-only',
        ]),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => parseAndroidSigningVerificationMode(const ['--unknown']),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'host Gradle properties and JVM option hooks cannot shadow inputs',
      () {
        // Mutations caught: preserving any inherited Gradle project property,
        // option hook, or user home can make local credentials replace the
        // verifier's controlled synthetic contract.
        final isolatedHome = Directory(
          path.join(Directory.systemTemp.path, 'contract-isolated-home'),
        );
        final environment = hermeticGradleEnvironment(
          inheritedEnvironment: const {
            'PATH': 'safe-path',
            'JAVA_HOME': 'safe-jdk',
            'GRADLE_USER_HOME': 'host-user-home',
            'gradle_opts': '-Dgradle.user.home=host-user-home',
            'JAVA_OPTS': '-Dorg.gradle.project.CLEAN_NOTES_KEY_ALIAS=host',
            'Java_Tool_Options': '-Dgradle.user.home=host-user-home',
            '_JAVA_OPTIONS': '-Dgradle.user.home=host-user-home',
            'JDK_JAVA_OPTIONS': '-Dgradle.user.home=host-user-home',
            'GRADLE_HOME': 'host-gradle-install',
            'ORG_GRADLE_PROJECT_CLEAN_NOTES_APPLICATION_ID': 'host.id',
            'CLEAN_NOTES_APPLICATION_ID': 'host-direct.id',
            'org_gradle_project_unrelated': 'host-project-value',
          },
          projectProperties: const {
            'CLEAN_NOTES_APPLICATION_ID': 'dev.contract.clean_notes',
            'CLEAN_NOTES_KEY_ALIAS': 'contract-upload',
          },
          gradleUserHome: isolatedHome,
        );

        expect(environment['PATH'], 'safe-path');
        expect(environment['JAVA_HOME'], 'safe-jdk');
        expect(environment['GRADLE_USER_HOME'], isolatedHome.path);
        expect(
          environment['CLEAN_NOTES_APPLICATION_ID'],
          'dev.contract.clean_notes',
        );
        expect(environment['CLEAN_NOTES_KEY_ALIAS'], 'contract-upload');
        final normalizedKeys = environment.keys.map((key) => key.toUpperCase());
        for (final forbidden in <String>{
          'GRADLE_HOME',
          'GRADLE_OPTS',
          'JAVA_OPTS',
          'JAVA_TOOL_OPTIONS',
          '_JAVA_OPTIONS',
          'JDK_JAVA_OPTIONS',
          'ORG_GRADLE_PROJECT_UNRELATED',
        }) {
          expect(normalizedKeys, isNot(contains(forbidden)));
        }
      },
    );

    test('protected roots include common Git data and every worktree', () async {
      // Mutations caught: checking only the current checkout or common checkout
      // misses external linked worktrees where a key could still be committed.
      final repository = Directory.current.absolute;
      final actual = await protectedRepositoryRoots(repository);
      final actualKeys = actual.map(_pathKey).toSet();

      final topLevel = await _gitPath(repository, '--show-toplevel');
      final commonDirectory = await _gitPath(repository, '--git-common-dir');
      final expected = <String>{topLevel, commonDirectory};
      if (path.basename(commonDirectory).toLowerCase() == '.git') {
        expected.add(path.dirname(commonDirectory));
      }
      expected.addAll(await _gitWorktreePaths(repository));

      expect(actual, isNotEmpty);
      expect(actual, everyElement(path.isAbsolute));
      for (final expectedRoot in expected) {
        expect(
          actualKeys,
          contains(_pathKey(expectedRoot)),
          reason: 'missing protected Git/worktree root',
        );
      }
    });

    test(
      'external linked worktrees are protected and malformed metadata fails closed',
      () async {
        // Mutations caught: relying only on the common checkout boundary misses
        // linked worktrees outside it; silently skipping a broken gitdir marker
        // turns that omission into a signing-secret escape path.
        final fixture = await Directory.systemTemp.createTemp(
          'clean-notes-worktree-contract-',
        );
        try {
          final mainRepository = Directory(path.join(fixture.path, 'main'))
            ..createSync();
          final externalWorktree = Directory(
            path.join(fixture.path, 'external-linked'),
          );
          await _runGit(mainRepository, ['init', '-b', 'main']);
          File(
            path.join(mainRepository.path, 'README.md'),
          ).writeAsStringSync('contract fixture\n', flush: true);
          await _runGit(mainRepository, ['add', 'README.md']);
          await _runGit(mainRepository, [
            '-c',
            'user.name=Clean Notes Contract',
            '-c',
            'user.email=contract@example.invalid',
            'commit',
            '-m',
            'fixture',
          ]);
          await _runGit(mainRepository, [
            'worktree',
            'add',
            '-b',
            'external-linked',
            externalWorktree.path,
          ]);

          final roots = await protectedRepositoryRoots(mainRepository);
          final rootKeys = roots.map(_pathKey).toSet();
          expect(
            rootKeys,
            contains(_pathKey(mainRepository.resolveSymbolicLinksSync())),
          );
          expect(
            rootKeys,
            contains(_pathKey(externalWorktree.resolveSymbolicLinksSync())),
          );
          expect(
            rootKeys,
            contains(
              _pathKey(
                Directory(
                  path.join(mainRepository.path, '.git'),
                ).resolveSymbolicLinksSync(),
              ),
            ),
          );

          final metadataDirectories = Directory(
            path.join(mainRepository.path, '.git', 'worktrees'),
          ).listSync().whereType<Directory>().toList(growable: false);
          expect(metadataDirectories, hasLength(1));
          File(
            path.join(metadataDirectories.single.path, 'gitdir'),
          ).writeAsStringSync('', flush: true);

          await expectLater(
            protectedRepositoryRoots(mainRepository),
            throwsA(isA<StateError>()),
          );
        } finally {
          if (fixture.existsSync()) fixture.deleteSync(recursive: true);
        }
      },
    );

    test('temporary cleanup retries transient Windows file locks', () async {
      var attempts = 0;
      final delays = <Duration>[];

      await deleteTemporaryDirectoryWithRetries(
        Directory('unused-contract-fixture'),
        deleteDirectory: (_) async {
          attempts += 1;
          if (attempts < 3) {
            throw const FileSystemException('fixture is still locked');
          }
        },
        delay: (duration) async => delays.add(duration),
      );

      expect(attempts, 3);
      expect(delays, const [
        Duration(milliseconds: 250),
        Duration(milliseconds: 500),
      ]);
    });

    test('diagnostics redact secrets and Windows path variants', () {
      const password = 'contract-secret-password';
      const windowsPath = r'C:\Users\owner\keys\upload.p12';
      final sanitized = redactSensitiveText(
        'password=$password at $windowsPath and '
        r'C:/Users/owner/keys/upload.p12 plus '
        r'c:\USERS\OWNER\KEYS\UPLOAD.P12',
        const [password],
        sensitivePaths: const [windowsPath],
      );

      expect(sanitized, contains('[REDACTED]'));
      expect(sanitized, isNot(contains(password)));
      expect(sanitized, isNot(contains(windowsPath)));
      expect(sanitized, isNot(contains(r'C:/Users/owner/keys/upload.p12')));
      expect(sanitized, isNot(contains(r'c:\USERS\OWNER\KEYS\UPLOAD.P12')));
    });

    test('secret matching remains exact for path-shaped values', () {
      const secret = r'C:\Secret\CaseSensitiveToken';
      const alteredSecret = r'c:\secret\casesensitivetoken';

      final sanitized = redactSensitiveText(
        'exact=$secret altered=$alteredSecret',
        const [secret],
      );

      expect(sanitized, contains('exact=[REDACTED]'));
      expect(sanitized, contains('altered=$alteredSecret'));
    });

    test('forward-slash UNC paths redact alternate case and separators', () {
      const sensitivePath = '//PrivateServer/OwnerShare/signing';
      const exposedVariant = r'\\privateserver\ownershare\SIGNING';

      final sanitized = redactSensitiveText(
        'failure at $exposedVariant',
        const [],
        sensitivePaths: const [sensitivePath],
      );

      expect(sanitized, 'failure at [REDACTED]');
    });

    test('symlink cleanup retries transient Windows file locks', () async {
      var attempts = 0;
      final delays = <Duration>[];

      await deleteFileSystemEntityWithRetries(
        Link('unused-contract-link'),
        deleteEntity: (_) async {
          attempts += 1;
          if (attempts < 3) {
            throw const FileSystemException('fixture link is still locked');
          }
        },
        delay: (duration) async => delays.add(duration),
      );

      expect(attempts, 3);
      expect(delays, const [
        Duration(milliseconds: 250),
        Duration(milliseconds: 500),
      ]);
    });

    test('cleanup retry exhaustion rethrows without false success', () async {
      var attempts = 0;
      final delays = <Duration>[];

      await expectLater(
        deleteFileSystemEntityWithRetries(
          Link('unused-contract-link'),
          maxAttempts: 3,
          deleteEntity: (_) async {
            attempts += 1;
            throw const FileSystemException('fixture remains locked');
          },
          delay: (duration) async => delays.add(duration),
        ),
        throwsA(isA<FileSystemException>()),
      );

      expect(attempts, 3);
      expect(delays, const [
        Duration(milliseconds: 250),
        Duration(milliseconds: 500),
      ]);
    });

    test('launcher shims avoid batch call reparsing and unsafe paths', () {
      final windowsShim = trustedGradleLauncherShim(
        javaExecutablePath: r'C:\Program Files\Java\bin\java.exe',
        wrapperJarPath: r'C:\Temp\wrapper\gradle-wrapper.jar',
        windows: true,
      );
      expect(windowsShim, contains('setlocal DisableDelayedExpansion'));
      expect(windowsShim, contains('-jar "C:\\Temp\\wrapper'));
      expect(windowsShim, contains('%*'));
      expect(windowsShim.toLowerCase(), isNot(contains('call ')));
      expect(windowsShim, isNot(contains('%ERRORLEVEL%')));
      expect(windowsShim, contains('if errorlevel 1 exit /b 1'));
      expect(windowsShim, contains('if not errorlevel 0 exit /b 1'));

      final unixShim = trustedGradleLauncherShim(
        javaExecutablePath: "/opt/Java's Home/bin/java",
        wrapperJarPath: "/tmp/wrapper's/gradle-wrapper.jar",
        windows: false,
      );
      expect(unixShim, startsWith('#!/bin/sh\nexec '));
      expect(unixShim, contains(r'"$@"'));
      expect(unixShim, contains("'\\''"));

      expect(
        () => trustedGradleLauncherShim(
          javaExecutablePath: r'C:\%TEMP%\java.exe',
          wrapperJarPath: r'C:\Temp\wrapper.jar',
          windows: true,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'Windows shim preserves positive and negative child failures',
      () async {
        if (!Platform.isWindows) return;
        final fixture = await Directory.systemTemp.createTemp(
          'clean-notes-shim-exit-test-',
        );
        addTearDown(() async {
          if (fixture.existsSync()) await fixture.delete(recursive: true);
        });
        final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
        final shim = trustedGradleLauncherShim(
          javaExecutablePath: path.join(systemRoot, 'System32', 'where.exe'),
          wrapperJarPath: path.join(fixture.path, 'missing-wrapper.jar'),
          windows: true,
        );
        final launcher = File(path.join(fixture.path, 'gradlew.bat'));
        await launcher.writeAsString(shim, flush: true);

        final result = await Process.run(
          launcher.path,
          const [],
          environment: {...Platform.environment, 'ERRORLEVEL': '0'},
          includeParentEnvironment: false,
          runInShell: true,
        );
        expect(result.exitCode, isNot(0));

        final negativeGuard = File(
          path.join(fixture.path, 'negative-exit-guard.bat'),
        );
        await negativeGuard.writeAsString(
          '@echo off\r\n'
          'cmd /d /c exit -1\r\n'
          'if errorlevel 1 exit /b 1\r\n'
          'if not errorlevel 0 exit /b 1\r\n'
          'exit /b 0\r\n',
          flush: true,
        );
        final negative = await Process.run(
          negativeGuard.path,
          const [],
          environment: {...Platform.environment, 'ERRORLEVEL': '0'},
          includeParentEnvironment: false,
          runInShell: true,
        );
        expect(negative.exitCode, isNot(0));
      },
    );

    test(
      'launcher shim restores the original after success and failure',
      () async {
        final fixture = await Directory.systemTemp.createTemp(
          'clean-notes-launcher-shim-test-',
        );
        addTearDown(() async {
          if (fixture.existsSync()) await fixture.delete(recursive: true);
        });
        final launcher = File(path.join(fixture.path, 'gradlew.bat'));
        const original = <int>[1, 2, 3, 4];
        const shim = <int>[9, 8, 7];
        await launcher.writeAsBytes(original, flush: true);

        final value = await runWithTrustedGradleLauncherShim<int>(
          candidateLauncher: launcher,
          trustedLauncherBytes: original,
          shimBytes: shim,
          operation: () async {
            expect(await launcher.readAsBytes(), shim);
            return 17;
          },
        );
        expect(value, 17);
        expect(await launcher.readAsBytes(), original);

        await expectLater(
          runWithTrustedGradleLauncherShim<void>(
            candidateLauncher: launcher,
            trustedLauncherBytes: original,
            shimBytes: shim,
            operation: () async => throw StateError('fixture failure'),
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              'fixture failure',
            ),
          ),
        );
        expect(await launcher.readAsBytes(), original);
        expect(fixture.listSync(), hasLength(1));
      },
    );

    test('launcher shim detects tampering and safely restores bytes', () async {
      final fixture = await Directory.systemTemp.createTemp(
        'clean-notes-launcher-tamper-test-',
      );
      addTearDown(() async {
        if (fixture.existsSync()) await fixture.delete(recursive: true);
      });
      final launcher = File(path.join(fixture.path, 'gradlew.bat'));
      const original = <int>[4, 3, 2, 1];
      const shim = <int>[7, 7, 7];
      await launcher.writeAsBytes(original, flush: true);

      await expectLater(
        runWithTrustedGradleLauncherShim<void>(
          candidateLauncher: launcher,
          trustedLauncherBytes: original,
          shimBytes: shim,
          operation: () async {
            await launcher.writeAsBytes(const [6, 6, 6], flush: true);
          },
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('changed during use'),
          ),
        ),
      );
      expect(await launcher.readAsBytes(), original);
      expect(fixture.listSync(), hasLength(1));
    });

    test('launcher shim rejects a linked parent directory', () async {
      final fixture = await Directory.systemTemp.createTemp(
        'clean-notes-launcher-parent-test-',
      );
      addTearDown(() async {
        if (fixture.existsSync()) await fixture.delete(recursive: true);
      });
      final realParent = Directory(path.join(fixture.path, 'real'))
        ..createSync();
      final linkedParent = Link(path.join(fixture.path, 'linked'));
      try {
        await linkedParent.create(realParent.path);
      } on FileSystemException {
        return;
      }
      final launcher = File(path.join(linkedParent.path, 'gradlew.bat'));
      const original = <int>[1, 3, 3, 7];
      await launcher.writeAsBytes(original, flush: true);

      await expectLater(
        runWithTrustedGradleLauncherShim<void>(
          candidateLauncher: launcher,
          trustedLauncherBytes: original,
          shimBytes: const [7, 3, 3, 1],
          operation: () async {},
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains('parent is unsafe'),
          ),
        ),
      );
      expect(await launcher.readAsBytes(), original);
    });
  });
}

Future<String> _gitPath(Directory repository, String selector) async {
  final gitExecutable = resolveTrustedGitExecutable(
    repository,
    Platform.environment,
  );
  final result = await Process.run(
    gitExecutable.path,
    ['-C', repository.path, 'rev-parse', '--path-format=absolute', selector],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
    environment: sanitizedGitEnvironment(Platform.environment),
    includeParentEnvironment: false,
    runInShell: false,
  );
  expect(result.exitCode, 0, reason: result.stderr as String);
  return (result.stdout as String).trim();
}

Future<List<String>> _gitWorktreePaths(Directory repository) async {
  final gitExecutable = resolveTrustedGitExecutable(
    repository,
    Platform.environment,
  );
  final result = await Process.run(
    gitExecutable.path,
    ['-C', repository.path, 'worktree', 'list', '--porcelain', '-z'],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
    environment: sanitizedGitEnvironment(Platform.environment),
    includeParentEnvironment: false,
    runInShell: false,
  );
  expect(result.exitCode, 0, reason: result.stderr as String);
  return (result.stdout as String)
      .split('\x00')
      .where((field) => field.startsWith('worktree '))
      .map((field) => field.substring('worktree '.length))
      .toList(growable: false);
}

Future<void> _runGit(Directory repository, List<String> arguments) async {
  final gitExecutable = resolveTrustedGitExecutable(
    repository,
    Platform.environment,
  );
  final result = await Process.run(
    gitExecutable.path,
    ['-C', repository.path, ...arguments],
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
    environment: sanitizedGitEnvironment(Platform.environment),
    includeParentEnvironment: false,
    runInShell: false,
  );
  expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
}

String _pathKey(String value) {
  final normalized = path.normalize(path.absolute(value));
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}
