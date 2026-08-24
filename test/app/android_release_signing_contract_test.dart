import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/android_release_signing_support.dart';

void main() {
  group('Android release signing contract', () {
    late String gradle;

    setUpAll(() {
      gradle = File('android/app/build.gradle.kts').readAsStringSync();
    });

    test(
      'release uses an external release signer and never the debug signer',
      () {
        // Mutation caught: restoring Flutter's generated debug-signing fallback
        // would make a distributable artifact look release-like while using the
        // public debug certificate.
        final releaseBlock = _braceBlock(gradle, '        release {');
        expect(gradle, contains('create("release")'));
        expect(
          releaseBlock,
          contains('signingConfig = signingConfigs.getByName("release")'),
        );
        expect(
          releaseBlock,
          isNot(contains('signingConfigs.getByName("debug")')),
        );
        expect(
          releaseBlock,
          isNot(contains('signingConfig = signingConfigs.debug')),
        );
      },
    );

    test('configured profile identity is isolated from production', () {
      // Flutter creates profile from debug before this script configures the
      // debug suffix. An explicit profile suffix prevents a debug-signed
      // profile artifact from reusing the configured production identity.
      expect(gradle, contains('getByName("profile")'));
      expect(gradle, contains('applicationIdSuffix = ".profile"'));
      final profileBlock = _braceBlock(gradle, 'getByName("profile") {');
      expect(
        profileBlock,
        contains('signingConfig = signingConfigs.getByName("debug")'),
      );
    });

    test('linked-worktree layouts require explicit common Git metadata', () {
      // Mutation caught: treating a missing commondir marker as a normal main
      // checkout drops the main checkout and sibling worktrees from protection.
      expect(gradle, contains('data class GitDirectoryLayout'));
      expect(gradle, contains('isLinkedWorktree'));
      expect(
        gradle,
        contains('Linked-worktree Git common-directory metadata is missing'),
      );
      expect(gradle, contains('verifyRepositoryProtectionFixture'));
      expect(gradle, contains('CLEAN_NOTES_REPOSITORY_PROTECTION_FIXTURE'));
      expect(gradle, contains('data class RepositoryProtectionState'));
      expect(gradle, contains('repositoryProtectionState.resolutionFailed'));
    });

    test('release validation blocks template IDs and missing credentials', () {
      // Mutation caught: detaching validation from preReleaseBuild or accepting
      // com.example would allow an owner-unconfigured bundle to be produced.
      expect(gradle, contains('validateReleaseConfiguration'));
      expect(gradle, contains('preReleaseBuild'));
      expect(gradle, contains('mustRunAfter(validateReleaseConfiguration)'));
      expect(gradle, contains('validationErrors'));
      expect(gradle, contains('isPlaceholderApplicationId'));
      for (final property in <String>[
        'CLEAN_NOTES_APPLICATION_ID',
        'CLEAN_NOTES_STORE_FILE',
        'CLEAN_NOTES_STORE_PASSWORD',
        'CLEAN_NOTES_KEY_ALIAS',
        'CLEAN_NOTES_KEY_PASSWORD',
        'CLEAN_NOTES_UPLOAD_CERT_SHA256',
      ]) {
        expect(gradle, contains(property));
      }
      expect(gradle, contains('certificateSha256'));
      expect(gradle, contains('Android Debug'));
    });

    test('direct environment selects before safe file fallback', () {
      // Mutation caught: reversing source precedence can silently make CI use a
      // developer's local credential file; resolving a relative external file
      // against android/ instead of its own directory selects the wrong key.
      expect(
        gradle,
        contains('configuredValue ?: keyProperties.getProperty(keyName)'),
      );
      expect(gradle, contains('System.getenv(name)'));
      expect(gradle, contains('hasCompleteDirectReleaseConfiguration'));
      expect(gradle, contains('configuredStorePath != null'));
      expect(gradle, contains('rootProject.projectDir'));
      expect(gradle, contains('keyPropertiesFile?.parentFile'));
      expect(gradle, contains('CLEAN_NOTES_KEY_PROPERTIES_FILE'));
      expect(gradle, contains('repositoryProtectionRoots'));
      expect(gradle, contains('commondir'));
      expect(gradle, contains('worktrees'));
      expect(gradle, contains('isRepositoryLocal'));
      expect(gradle, isNot(contains('providers.gradleProperty')));
    });

    test(
      'tracked example is placeholders only and private keys stay ignored',
      () async {
        // Mutation caught: committing a usable password/key path, or weakening an
        // ignore rule, makes release credentials easy to leak.
        final example = File('android/key.properties.example');
        expect(example.existsSync(), isTrue);

        final entries = <String, String>{};
        for (final line in example.readAsLinesSync()) {
          final trimmed = line.trim();
          if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
          final separator = trimmed.indexOf('=');
          expect(separator, greaterThan(0));
          entries[trimmed.substring(0, separator)] = trimmed.substring(
            separator + 1,
          );
        }
        expect(entries.keys.toSet(), {
          'applicationId',
          'storeFile',
          'storePassword',
          'keyAlias',
          'keyPassword',
          'uploadCertificateSha256',
        });
        expect(
          entries.values,
          everyElement(allOf(startsWith('<'), endsWith('>'))),
        );

        for (final path in <String>[
          'key.properties',
          'upload.jks',
          'private/upload.keystore',
          'private/upload.p12',
          'private/upload.pfx',
          'android/key.properties',
          'android/private/upload.jks',
          'android/private/upload.keystore',
          'android/private/upload.p12',
          'android/private/upload.pfx',
          'secrets/android/upload.jks',
          'secrets/android/upload.keystore',
          'secrets/android/upload.p12',
          'secrets/android/upload.pfx',
        ]) {
          final ignored = await _runGit([
            'check-ignore',
            '--quiet',
            '--no-index',
            path,
          ]);
          expect(ignored.exitCode, 0, reason: '$path must remain ignored');
        }

        final ignoredExample = await _runGit([
          'check-ignore',
          '--quiet',
          '--no-index',
          'android/key.properties.example',
        ]);
        expect(
          ignoredExample.exitCode,
          isNot(0),
          reason: 'ignore rules must not hide the placeholder example',
        );
        final trackedExample = await _runGit([
          'ls-files',
          '--error-unmatch',
          'android/key.properties.example',
        ]);
        expect(
          trackedExample.exitCode,
          0,
          reason: 'the safe placeholder example must be versioned',
        );

        final trackedFiles = await _runGit(['ls-files', '-z']);
        expect(trackedFiles.exitCode, 0);
        final trackedPrivateMaterial = (trackedFiles.stdout as String)
            .split('\x00')
            .where((entry) => entry.isNotEmpty)
            .where(
              (entry) => RegExp(
                r'(^|/)(key\.properties|[^/]+\.(jks|keystore|p12|pfx))$',
                caseSensitive: false,
              ).hasMatch(entry.replaceAll('\\', '/')),
            );
        expect(
          trackedPrivateMaterial,
          isEmpty,
          reason: 'private Android signing material must never be tracked',
        );

        final kotlinDiagnosticsIgnored = await _runGit([
          'check-ignore',
          '--quiet',
          '--no-index',
          'android/.kotlin/errors/example.log',
        ]);
        expect(kotlinDiagnosticsIgnored.exitCode, 0);
        final trackedKotlinDiagnostics = await _runGit([
          'ls-files',
          'android/.kotlin',
        ]);
        final indexedDiagnosticPaths =
            (trackedKotlinDiagnostics.stdout as String)
                .split(RegExp(r'\r?\n'))
                .where((entry) => entry.isNotEmpty);
        expect(
          indexedDiagnosticPaths,
          isEmpty,
          reason: 'Kotlin diagnostic logs must not remain in the index',
        );
      },
    );

    test('release docs require unambiguous Windows properties paths', () {
      // Mutation caught: a single-backslash C:\Users path is parsed by
      // java.util.Properties as escapes and can select the wrong keystore.
      final releaseGuide = File('docs/release.md').readAsStringSync();
      final example = File('android/key.properties.example').readAsStringSync();

      expect(releaseGuide, contains('C:/Users/'));
      expect(releaseGuide, contains(r'C:\\Users\\'));
      expect(example, contains('C:/Users/'));
    });

    test('Gradle wrapper launchers and executable jar are versioned', () async {
      final attributes = File('.gitattributes').readAsStringSync();
      expect(attributes, contains('android/gradlew text eol=lf'));
      expect(attributes, contains('android/gradlew.bat text eol=crlf'));
      expect(
        attributes,
        contains(
          'android/gradle/wrapper/gradle-wrapper.properties text eol=lf',
        ),
      );
      for (final wrapperPath in <String>[
        'android/gradlew',
        'android/gradlew.bat',
        'android/gradle/wrapper/gradle-wrapper.jar',
        'android/gradle/wrapper/gradle-wrapper.properties',
      ]) {
        final tracked = await _runGit([
          'ls-files',
          '--error-unmatch',
          wrapperPath,
        ]);
        expect(tracked.exitCode, 0, reason: '$wrapperPath must be versioned');
        final ignored = await _runGit([
          'check-ignore',
          '--quiet',
          '--no-index',
          wrapperPath,
        ]);
        expect(ignored.exitCode, 1, reason: '$wrapperPath is ignored');
      }
      final unixLauncherMode = await _runGit([
        'ls-files',
        '--stage',
        '--',
        'android/gradlew',
      ]);
      expect(unixLauncherMode.exitCode, 0);
      expect(
        unixLauncherMode.stdout,
        startsWith('100755 '),
        reason: 'android/gradlew must stay executable on Unix hosts',
      );
    });

    test(
      'Gradle contract verifier publishes modes and rejects unknown input',
      () async {
        final verifier = File('tool/verify_android_release_signing.dart');
        expect(verifier.existsSync(), isTrue);

        final help = await Process.run('dart', [
          verifier.path,
          '--help',
        ], runInShell: Platform.isWindows);
        expect(help.exitCode, 0, reason: '${help.stdout}\n${help.stderr}');
        expect(help.stdout, contains('--build-positive-release-artifacts'));
        expect(
          help.stdout,
          contains('--build-positive-release-artifacts-only'),
        );
        expect(help.stderr, isEmpty);

        const hostileArgument = '--unknown-private-contract-value';
        final unknown = await Process.run('dart', [
          verifier.path,
          hostileArgument,
        ], runInShell: Platform.isWindows);
        expect(unknown.exitCode, 64);
        expect(unknown.stdout, isEmpty);
        expect(unknown.stderr, contains('Unknown verifier argument.'));
        expect(unknown.stderr, isNot(contains(hostileArgument)));

        final conflict = await Process.run('dart', [
          verifier.path,
          '--build-positive-release-artifacts',
          '--build-positive-release-artifacts-only',
        ], runInShell: Platform.isWindows);
        expect(conflict.exitCode, 64);
        expect(conflict.stdout, isEmpty);
        expect(conflict.stderr, contains('Conflicting verifier modes.'));
      },
    );

    test(
      'positive proof routes Flutter release builds through verified wrapper',
      () {
        // A real Flutter release build filters development-only plugins. The
        // temporary launcher shim forwards Flutter's Gradle invocation to the
        // immutable, independently verified wrapper snapshot.
        final verifier = File(
          'tool/verify_android_release_signing.dart',
        ).readAsStringSync();
        final contractRunner = _braceBlock(
          verifier,
          'Future<_CommandResult> _runGradle(',
        );
        final apkBuild = verifier.indexOf("artifact: 'apk'");
        final apkInspection = verifier.indexOf('await _inspectApk(', apkBuild);
        final aabBuild = verifier.indexOf("artifact: 'appbundle'");
        final aabInspection = verifier.indexOf('await _inspectAab(', aabBuild);

        expect(apkBuild, isNonNegative);
        expect(apkInspection, greaterThan(apkBuild));
        expect(aabBuild, greaterThan(apkInspection));
        expect(aabInspection, greaterThan(aabBuild));
        expect(
          'await _runFlutterReleaseBuild('.allMatches(verifier),
          hasLength(2),
        );
        expect(verifier, contains("'--release'"));
        expect(verifier, isNot(contains("'--no-pub'")));
        expect(verifier, contains("'--no-android-gradle-daemon'"));
        expect(verifier, isNot(contains("'--config-only'")));
        expect(verifier, contains('trustedGradleLauncherShim'));
        expect(verifier, contains('runWithTrustedGradleLauncherShim'));
        expect(verifier, contains('_validateTrustedGradleWrapperSnapshot'));
        expect(verifier, isNot(contains('_stopGradleDaemons')));
        expect(contractRunner, contains('java.path'));
        expect(contractRunner, contains("'-jar'"));
        expect(contractRunner, isNot(contains('wrapper.path,')));
        expect(
          '_validateTrustedGradleWrapperSnapshot(wrapper)'.allMatches(
            contractRunner,
          ),
          hasLength(2),
        );
        expect(
          verifier,
          contains('_requireReleaseRegistrantExcludesDevPlugins'),
        );
      },
    );
  });
}

Future<ProcessResult> _runGit(List<String> arguments) {
  final gitExecutable = resolveTrustedGitExecutable(
    Directory.current.absolute,
    Platform.environment,
  );
  return Process.run(
    gitExecutable.path,
    arguments,
    environment: sanitizedGitEnvironment(Platform.environment),
    includeParentEnvironment: false,
    runInShell: false,
  );
}

String _braceBlock(String source, String marker) {
  final markerIndex = source.indexOf(marker);
  expect(markerIndex, isNonNegative, reason: 'missing block marker: $marker');
  final openingBrace = source.indexOf('{', markerIndex);
  expect(openingBrace, isNonNegative, reason: 'missing opening brace: $marker');
  var depth = 0;
  for (var index = openingBrace; index < source.length; index += 1) {
    switch (source[index]) {
      case '{':
        depth += 1;
      case '}':
        depth -= 1;
        if (depth == 0) return source.substring(markerIndex, index + 1);
    }
  }
  fail('missing closing brace: $marker');
}
