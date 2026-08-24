import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'src/android_release_signing_support.dart';

const _applicationId = 'dev.codex.cleannotes.contract';
const _templateApplicationId = 'com.example.flutter_clean_notes';
const _gradleWrapperJarSha256 =
    '7d3a4ac4de1c32b59bc6a4eb8ecb8e612ccd0cf1ae1e99f66902da64df296172';
const _gradleDistributionSha256 =
    'efe9a3d147d948d7528a9887fa35abcf24ca1a43ad06439996490f77569b02d1';
const _bundletoolSha256 =
    'a099cfa1543f55593bc2ed16a70a7c67fe54b1747bb7301f37fdfd6d91028e29';
const _propertyNames = <String>[
  'CLEAN_NOTES_APPLICATION_ID',
  'CLEAN_NOTES_STORE_FILE',
  'CLEAN_NOTES_STORE_PASSWORD',
  'CLEAN_NOTES_KEY_ALIAS',
  'CLEAN_NOTES_KEY_PASSWORD',
  'CLEAN_NOTES_UPLOAD_CERT_SHA256',
];

final class _CommandResult {
  const _CommandResult(this.exitCode, this.output);

  final int exitCode;
  final String output;
}

final class _HermeticBuildRunner {
  const _HermeticBuildRunner({
    required this.repository,
    required this.wrapper,
    required this.java,
    required this.gradleUserHome,
    required this.inheritedEnvironment,
  });

  final Directory repository;
  final File wrapper;
  final File java;
  final Directory gradleUserHome;
  final Map<String, String> inheritedEnvironment;

  Future<_CommandResult> runGradle(
    String task,
    Map<String, String> properties,
  ) => _runGradle(
    repository,
    wrapper,
    java,
    gradleUserHome,
    inheritedEnvironment,
    task,
    properties,
  );
}

final class _TrustedToolchain {
  const _TrustedToolchain({
    required this.flutter,
    required this.java,
    required this.keytool,
    required this.jarsigner,
    required this.apkanalyzer,
    required this.apksigner,
    required this.androidSdk,
    required this.flutterRoot,
    required this.environment,
    this.bundletool,
  });

  final File flutter;
  final File java;
  final File keytool;
  final File jarsigner;
  final File apkanalyzer;
  final File apksigner;
  final Directory androidSdk;
  final Directory flutterRoot;
  final Map<String, String> environment;
  final File? bundletool;
}

final class _ArtifactEvidence {
  const _ArtifactEvidence({
    required this.applicationId,
    required this.certificateSha256,
    required this.artifactSha256,
  });

  final String applicationId;
  final String certificateSha256;
  final String artifactSha256;
}

final class _PositiveReleaseEvidence {
  const _PositiveReleaseEvidence({
    required this.commit,
    required this.apk,
    required this.aab,
  });

  final String commit;
  final _ArtifactEvidence apk;
  final _ArtifactEvidence aab;
}

Future<void> main(List<String> arguments) async {
  const positiveReleaseFlag = '--build-positive-release-artifacts';
  const positiveReleaseOnlyFlag = '--build-positive-release-artifacts-only';
  late AndroidSigningVerificationMode mode;
  try {
    mode = parseAndroidSigningVerificationMode(arguments);
  } on FormatException catch (error) {
    stderr.writeln(error.message);
    exitCode = 64;
    return;
  }
  if (mode == AndroidSigningVerificationMode.help) {
    stdout.writeln(
      'Usage: dart run tool/verify_android_release_signing.dart '
      '[$positiveReleaseFlag|$positiveReleaseOnlyFlag]',
    );
    stdout.writeln(
      'Requires JAVA_HOME, CLEAN_NOTES_ANDROID_SDK_ROOT, and '
      'CLEAN_NOTES_FLUTTER_ROOT; positive modes also require the pinned '
      'CLEAN_NOTES_BUNDLETOOL_JAR.',
    );
    return;
  }
  final buildPositiveReleaseArtifacts =
      mode == AndroidSigningVerificationMode.contractAndPositive ||
      mode == AndroidSigningVerificationMode.positiveOnly;
  final runContractChecks = mode != AndroidSigningVerificationMode.positiveOnly;
  final repository = Directory.current.absolute;
  if (!File(path.join(repository.path, 'pubspec.yaml')).existsSync()) {
    stderr.writeln('Run this verifier from the repository root.');
    exitCode = 64;
    return;
  }

  Directory? temporaryDirectory;
  var protectedRoots = const <String>[];
  var verificationChecksPassed = false;
  var cleanupSucceeded = false;
  var totalChecks = 0;
  _PositiveReleaseEvidence? positiveReleaseEvidence;
  final sensitiveValues = <String>{};
  final sensitivePaths = <String>{repository.path};
  for (final name in const <String>{
    'CLEAN_NOTES_GIT_EXECUTABLE',
    'JAVA_HOME',
    'CLEAN_NOTES_ANDROID_SDK_ROOT',
    'CLEAN_NOTES_FLUTTER_ROOT',
    'CLEAN_NOTES_BUNDLETOOL_JAR',
  }) {
    final value = Platform.environment[name]?.trim();
    if (value != null && value.isNotEmpty) sensitivePaths.add(value);
  }
  String sanitized(Object value) => redactSensitiveText(
    value.toString(),
    sensitiveValues,
    sensitivePaths: sensitivePaths,
  );
  try {
    final systemTemporaryDirectory = resolveSystemTemporaryDirectory();
    sensitivePaths.add(systemTemporaryDirectory.path);
    late File gitExecutable;
    try {
      gitExecutable = resolveTrustedGitExecutable(
        repository,
        Platform.environment,
      );
    } on Object {
      throw StateError('Unable to resolve a trusted Git executable.');
    }
    sensitivePaths.add(gitExecutable.path);
    try {
      protectedRoots = await protectedRepositoryRoots(
        repository,
        gitExecutable: gitExecutable,
      );
    } on Object {
      throw StateError('Unable to resolve protected Git roots safely.');
    }
    sensitivePaths.addAll(protectedRoots);
    try {
      temporaryDirectory = await systemTemporaryDirectory.createTemp(
        'clean-notes-signing-contract-',
      );
    } on Object {
      throw StateError('Unable to create an isolated verifier workspace.');
    }
    sensitivePaths.add(temporaryDirectory.path);
    _assertSafeTemporaryDirectory(temporaryDirectory, protectedRoots);
    final toolchain = _resolveTrustedToolchain(
      repository,
      protectedRoots,
      gitExecutable,
      requireBundletool: buildPositiveReleaseArtifacts,
    );
    final candidateCommit = await _candidateCommit(repository, gitExecutable);
    final buildRepository = await _cloneExactCandidate(
      source: repository,
      destination: Directory(path.join(temporaryDirectory.path, 'source')),
      commit: candidateCommit,
      gitExecutable: gitExecutable,
    );
    sensitivePaths.add(buildRepository.path);
    _writeSnapshotLocalProperties(buildRepository, toolchain);
    final pubGet = await _runFlutterPubGet(buildRepository, toolchain);
    _expectSuccess(pubGet, 'snapshot flutter pub get --enforce-lockfile');
    final buildWrapper = await _materializeTrustedGradleWrapper(
      buildRepository,
      Directory(path.join(temporaryDirectory.path, 'trusted-wrapper')),
      gitExecutable,
    );
    final candidateProtectedRoots = await protectedRepositoryRoots(
      buildRepository,
      gitExecutable: gitExecutable,
    );
    final androidDirectory = Directory(
      path.join(buildRepository.path, 'android'),
    );
    final isolatedGradleUserHome = Directory(
      path.join(temporaryDirectory.path, 'gradle-user-home'),
    )..createSync();
    final buildRunner = _HermeticBuildRunner(
      repository: buildRepository,
      wrapper: buildWrapper,
      java: toolchain.java,
      gradleUserHome: isolatedGradleUserHome,
      inheritedEnvironment: toolchain.environment,
    );

    final password = 'contract-$pid-${DateTime.now().microsecondsSinceEpoch}';
    sensitiveValues.add(password);
    const uploadAlias = 'clean-notes-upload-contract';
    const debugAlias = 'androiddebugkey';
    final uploadStore = File(
      path.join(temporaryDirectory.path, 'upload-contract.p12'),
    );
    final debugStore = File(
      path.join(temporaryDirectory.path, 'contract-debug.p12'),
    );

    stdout.writeln(
      '[setup] Generating ephemeral certificates outside the repo',
    );
    await _generateKeyStore(
      toolchain.keytool,
      toolchain.environment,
      uploadStore,
      password: password,
      alias: uploadAlias,
      distinguishedName: 'CN=Clean Notes Contract Test,O=Local QA,C=VN',
    );
    await _generateKeyStore(
      toolchain.keytool,
      toolchain.environment,
      debugStore,
      password: password,
      alias: debugAlias,
      distinguishedName: 'CN=Android Debug,O=Android,C=US',
    );
    final uploadFingerprint = await _certificateFingerprint(
      toolchain.keytool,
      toolchain.environment,
      uploadStore,
      password: password,
      alias: uploadAlias,
    );
    final debugFingerprint = await _certificateFingerprint(
      toolchain.keytool,
      toolchain.environment,
      debugStore,
      password: password,
      alias: debugAlias,
    );

    final emptyProperties = File(
      path.join(temporaryDirectory.path, 'empty.properties'),
    )..writeAsStringSync('', flush: true);
    final validProperties =
        File(path.join(temporaryDirectory.path, 'valid.properties'))
          ..writeAsStringSync(
            _propertiesText(
              applicationId: _applicationId,
              storeFile: uploadStore.uri.pathSegments.last,
              password: password,
              alias: uploadAlias,
              fingerprint: uploadFingerprint,
            ),
            flush: true,
          );
    final invalidProperties =
        File(path.join(temporaryDirectory.path, 'invalid.properties'))
          ..writeAsStringSync(
            _propertiesText(
              applicationId: 'com.example.invalid',
              storeFile: 'missing-keystore.p12',
              password: 'invalid-password',
              alias: 'invalid-alias',
              fingerprint: ''.padLeft(64, '0'),
            ),
            flush: true,
          );
    final debugProperties =
        File(path.join(temporaryDirectory.path, 'debug-certificate.properties'))
          ..writeAsStringSync(
            _propertiesText(
              applicationId: _applicationId,
              storeFile: debugStore.uri.pathSegments.last,
              password: password,
              alias: debugAlias,
              fingerprint: debugFingerprint,
            ),
            flush: true,
          );
    final malformedProperties =
        File(path.join(temporaryDirectory.path, 'malformed.properties'))
          ..writeAsStringSync(
            r'applicationId=\uNOTHEX'
            '\n',
            flush: true,
          );
    final placeholderProperties =
        File(path.join(temporaryDirectory.path, 'placeholder.properties'))
          ..writeAsStringSync(
            File(
              path.join(androidDirectory.path, 'key.properties.example'),
            ).readAsStringSync(),
            flush: true,
          );
    final unreadableProperties = Directory(
      path.join(temporaryDirectory.path, 'not-a-properties-file'),
    )..createSync();
    final hostileGradleUserHome = Directory(
      path.join(temporaryDirectory.path, 'hostile-gradle-user-home'),
    )..createSync();
    final hostileReleaseProperties = _releaseProperties(
      storeFile: uploadStore.path.replaceAll('\\', '/'),
      password: password,
      alias: uploadAlias,
      fingerprint: uploadFingerprint,
    );
    File(
      path.join(hostileGradleUserHome.path, 'gradle.properties'),
    ).writeAsStringSync(
      _propertiesText(
        applicationId: _applicationId,
        storeFile: uploadStore.path.replaceAll('\\', '/'),
        password: password,
        alias: uploadAlias,
        fingerprint: uploadFingerprint,
      ),
      flush: true,
    );
    final hostileGradleUserHomeOption = hostileGradleUserHome.path.replaceAll(
      '\\',
      '/',
    );
    final hostileInheritedEnvironment = <String, String>{
      ...toolchain.environment,
      'GRADLE_USER_HOME': hostileGradleUserHome.path,
      'GRADLE_HOME': hostileGradleUserHome.path,
      'GRADLE_OPTS': '-Dgradle.user.home=$hostileGradleUserHomeOption',
      'JAVA_OPTS': '-Dgradle.user.home=$hostileGradleUserHomeOption',
      'JAVA_TOOL_OPTIONS': '-Dgradle.user.home=$hostileGradleUserHomeOption',
      '_JAVA_OPTIONS': '-Dgradle.user.home=$hostileGradleUserHomeOption',
      'JDK_JAVA_OPTIONS': '-Dgradle.user.home=$hostileGradleUserHomeOption',
      for (final entry in hostileReleaseProperties.entries)
        'ORG_GRADLE_PROJECT_${entry.key}': entry.value,
    };
    final missingCommonRepository = Directory(
      path.join(temporaryDirectory.path, 'missing-commondir-repository'),
    )..createSync();
    final missingCommonGitDirectory = Directory(
      path.join(temporaryDirectory.path, 'missing-commondir-gitdir'),
    )..createSync();
    File(path.join(missingCommonRepository.path, '.git')).writeAsStringSync(
      'gitdir: ${missingCommonGitDirectory.path.replaceAll('\\', '/')}\n',
      flush: true,
    );

    var check = 0;
    void progress(String label) {
      check += 1;
      stdout.writeln('[$check] $label');
    }

    if (runContractChecks) {
      progress('Debug assembles without usable release configuration');
      final blankProperties = {
        for (final name in _propertyNames) name: '',
        'CLEAN_NOTES_KEY_PROPERTIES_FILE': emptyProperties.path,
      };
      final defaultDebugStarted = DateTime.now().toUtc();
      final defaultDebug = await buildRunner.runGradle(
        ':app:assembleDebug',
        blankProperties,
      );
      _expectSuccess(defaultDebug, 'assembleDebug without release inputs');
      final defaultDebugEvidence = await _inspectApk(
        _variantApk(buildRepository, 'debug'),
        toolchain,
        notBefore: defaultDebugStarted,
      );
      _require(
        defaultDebugEvidence.applicationId == _templateApplicationId,
        'Unconfigured debug must keep the template application ID.',
        result: defaultDebug,
      );

      progress('Profile uses a distinct ID and the debug certificate');
      final defaultProfileStarted = DateTime.now().toUtc();
      final defaultProfile = await buildRunner.runGradle(
        ':app:assembleProfile',
        blankProperties,
      );
      _expectSuccess(defaultProfile, 'assembleProfile without release inputs');
      final defaultProfileEvidence = await _inspectApk(
        _variantApk(buildRepository, 'profile'),
        toolchain,
        notBefore: defaultProfileStarted,
      );
      _require(
        defaultProfileEvidence.applicationId ==
                '$_templateApplicationId.profile' &&
            defaultProfileEvidence.certificateSha256 ==
                defaultDebugEvidence.certificateSha256,
        'Unconfigured profile must use the template .profile ID and debug signer.',
        result: defaultProfile,
      );

      progress('Missing release inputs fail validation');
      final missing = await buildRunner.runGradle(
        ':app:validateReleaseConfiguration',
        {'CLEAN_NOTES_KEY_PROPERTIES_FILE': emptyProperties.path},
      );
      _expectValidationFailure(missing, _propertyNames);

      progress(
        'Inherited Gradle properties and JVM hooks cannot shadow inputs',
      );
      final hostileBuildRunner = _HermeticBuildRunner(
        repository: buildRepository,
        wrapper: buildWrapper,
        java: toolchain.java,
        gradleUserHome: isolatedGradleUserHome,
        inheritedEnvironment: hostileInheritedEnvironment,
      );
      final hermeticValidation = await hostileBuildRunner.runGradle(
        ':app:validateReleaseConfiguration',
        {'CLEAN_NOTES_KEY_PROPERTIES_FILE': emptyProperties.path},
      );
      _expectValidationFailure(hermeticValidation, _propertyNames);

      progress('Malformed or unreadable properties fail release, not debug');
      final malformedDebug = await buildRunner.runGradle(':app:assembleDebug', {
        'CLEAN_NOTES_KEY_PROPERTIES_FILE': malformedProperties.path,
      });
      _expectSuccess(malformedDebug, 'assembleDebug with malformed properties');
      _require(
        _packagedDebugApplicationId(buildRepository) == _templateApplicationId,
        'Malformed release properties must not prevent template-ID debug.',
        result: malformedDebug,
      );
      for (final unusableProperties in <FileSystemEntity>[
        malformedProperties,
        unreadableProperties,
      ]) {
        final unusableRelease = await buildRunner.runGradle(
          ':app:validateReleaseConfiguration',
          {'CLEAN_NOTES_KEY_PROPERTIES_FILE': unusableProperties.path},
        );
        _expectValidationFailure(unusableRelease, [
          'could not be read as UTF-8 Java properties',
        ]);
        _require(
          !unusableRelease.output.contains(unusableProperties.path),
          'Release validation must not expose a private properties path.',
          result: unusableRelease,
        );
      }

      progress('Shipped placeholders keep debug runnable and release redacted');
      final placeholderDebug = await buildRunner.runGradle(
        ':app:assembleDebug',
        {'CLEAN_NOTES_KEY_PROPERTIES_FILE': placeholderProperties.path},
      );
      _expectSuccess(placeholderDebug, 'assembleDebug with placeholder file');
      _require(
        _packagedDebugApplicationId(buildRepository) == _templateApplicationId,
        'Placeholder release properties must keep template-ID debug.',
        result: placeholderDebug,
      );
      final placeholderRelease = await buildRunner.runGradle(
        ':app:validateReleaseConfiguration',
        {'CLEAN_NOTES_KEY_PROPERTIES_FILE': placeholderProperties.path},
      );
      _expectValidationFailure(placeholderRelease, [
        'CLEAN_NOTES_STORE_FILE is required',
      ]);
      _require(
        !placeholderRelease.output.contains('InvalidPathException') &&
            !placeholderRelease.output.contains(placeholderProperties.path),
        'Placeholder validation must not expose internal paths or path errors.',
        result: placeholderRelease,
      );

      progress(
        'Blank direct environment value cannot fall back to a valid file value',
      );
      final blankOverride = await buildRunner
          .runGradle(':app:validateReleaseConfiguration', {
            'CLEAN_NOTES_KEY_PROPERTIES_FILE': validProperties.path,
            'CLEAN_NOTES_APPLICATION_ID': '',
          });
      _expectValidationFailure(blankOverride, ['CLEAN_NOTES_APPLICATION_ID']);
      _require(
        !blankOverride.output.contains('CLEAN_NOTES_STORE_FILE is required'),
        'A blank application-ID override must not hide valid file credentials.',
        result: blankOverride,
      );

      progress(
        'Relative file-based keystore path resolves from its properties file',
      );
      final relativeFilePath = await buildRunner.runGradle(
        ':app:validateReleaseConfiguration',
        {'CLEAN_NOTES_KEY_PROPERTIES_FILE': validProperties.path},
      );
      _expectSuccess(relativeFilePath, 'relative file-based keystore path');

      progress(
        'Direct environment overrides an invalid file and uses android/ as base',
      );
      final relativeProjectStorePath = path
          .relative(uploadStore.path, from: androidDirectory.path)
          .replaceAll('\\', '/');
      final precedence = await buildRunner
          .runGradle(':app:validateReleaseConfiguration', {
            'CLEAN_NOTES_KEY_PROPERTIES_FILE': invalidProperties.path,
            ..._releaseProperties(
              storeFile: relativeProjectStorePath,
              password: password,
              alias: uploadAlias,
              fingerprint: uploadFingerprint,
            ),
          });
      _expectSuccess(
        precedence,
        'project-property precedence and relative path',
      );

      progress('Wrong approved-certificate fingerprint is rejected');
      final wrongFingerprint = await buildRunner
          .runGradle(':app:validateReleaseConfiguration', {
            'CLEAN_NOTES_KEY_PROPERTIES_FILE': validProperties.path,
            'CLEAN_NOTES_UPLOAD_CERT_SHA256': ''.padLeft(64, '0'),
          });
      _expectValidationFailure(wrongFingerprint, [
        'does not match CLEAN_NOTES_UPLOAD_CERT_SHA256',
      ]);

      progress(
        'Android debug certificate is rejected even when fingerprint matches',
      );
      final debugCertificate = await buildRunner.runGradle(
        ':app:validateReleaseConfiguration',
        {'CLEAN_NOTES_KEY_PROPERTIES_FILE': debugProperties.path},
      );
      _expectValidationFailure(debugCertificate, [
        'Android debug certificate is forbidden',
      ]);

      progress('In-repository alternative properties file is rejected');
      final unsafeAlternative = await buildRunner.runGradle(
        ':app:validateReleaseConfiguration',
        {'CLEAN_NOTES_KEY_PROPERTIES_FILE': 'gradle.properties'},
      );
      _expectValidationFailure(unsafeAlternative, [
        'must be the ignored android/key.properties file or a file outside',
      ]);

      progress('Default key.properties symlink cannot target protected files');
      final defaultKeyPropertiesLink = Link(
        path.join(androidDirectory.path, 'key.properties'),
      );
      final defaultKeyPropertiesType = FileSystemEntity.typeSync(
        defaultKeyPropertiesLink.path,
        followLinks: false,
      );
      if (defaultKeyPropertiesType != FileSystemEntityType.notFound) {
        throw StateError(
          'The symlink contract requires an absent default key.properties file.',
        );
      }
      var linkCreated = false;
      try {
        try {
          await defaultKeyPropertiesLink.create(
            path.join(androidDirectory.path, 'key.properties.example'),
          );
          linkCreated = true;
        } on FileSystemException {
          throw StateError(
            'The host must support file symlinks for the signing contract.',
          );
        }
        final linkedDefault = await buildRunner.runGradle(
          ':app:validateReleaseConfiguration',
          const {},
        );
        _expectValidationFailure(linkedDefault, [
          'must be the ignored android/key.properties file or a file outside',
        ]);
        _require(
          !linkedDefault.output.contains(defaultKeyPropertiesLink.path),
          'Symlink rejection must not expose the protected path.',
          result: linkedDefault,
        );
      } finally {
        if (linkCreated &&
            FileSystemEntity.typeSync(
                  defaultKeyPropertiesLink.path,
                  followLinks: false,
                ) ==
                FileSystemEntityType.link) {
          await deleteFileSystemEntityWithRetries(defaultKeyPropertiesLink);
        }
      }

      progress('Common Git root and every linked worktree remain protected');
      for (final protectedRoot in _minimalProtectionRoots(
        candidateProtectedRoots,
      )) {
        final protectedRepositoryInputs = await buildRunner.runGradle(
          ':app:validateReleaseConfiguration',
          {
            'CLEAN_NOTES_KEY_PROPERTIES_FILE': protectedRoot,
            ..._releaseProperties(
              storeFile: protectedRoot.replaceAll('\\', '/'),
              password: password,
              alias: uploadAlias,
              fingerprint: uploadFingerprint,
            ),
            // Keep the direct configuration intentionally incomplete so the
            // lower-priority selector is exercised as well as the store path.
            'CLEAN_NOTES_UPLOAD_CERT_SHA256': '',
          },
        );
        _expectValidationFailure(protectedRepositoryInputs, [
          'must be the ignored android/key.properties file or a file outside',
          'CLEAN_NOTES_STORE_FILE must point outside the repository',
        ]);
      }

      progress('Linked worktrees require readable common Git metadata');
      final missingCommonMetadata = await buildRunner
          .runGradle(':app:verifyRepositoryProtectionFixture', {
            'CLEAN_NOTES_REPOSITORY_PROTECTION_FIXTURE':
                missingCommonRepository.path,
          });
      _expectFailureContaining(
        missingCommonMetadata,
        'Linked-worktree Git common-directory metadata is missing.',
      );

      progress('assembleRelease is guarded before signing');
      final assembleRelease = await buildRunner.runGradle(
        ':app:assembleRelease',
        blankProperties,
      );
      _expectValidationFailure(assembleRelease, [
        'CLEAN_NOTES_APPLICATION_ID',
      ], mustBeFirstReleaseTask: true);

      progress('bundleRelease is guarded before signing');
      final bundleRelease = await buildRunner.runGradle(
        ':app:bundleRelease',
        blankProperties,
      );
      _expectValidationFailure(bundleRelease, [
        'CLEAN_NOTES_APPLICATION_ID',
      ], mustBeFirstReleaseTask: true);

      progress('Configured production ID gives debug a distinct .debug suffix');
      final configuredDebugStarted = DateTime.now().toUtc();
      final configuredDebug = await buildRunner.runGradle(
        ':app:assembleDebug',
        {'CLEAN_NOTES_KEY_PROPERTIES_FILE': validProperties.path},
      );
      _expectSuccess(
        configuredDebug,
        'assembleDebug with configured release ID',
      );
      final configuredDebugEvidence = await _inspectApk(
        _variantApk(buildRepository, 'debug'),
        toolchain,
        notBefore: configuredDebugStarted,
      );
      _require(
        configuredDebugEvidence.applicationId == '$_applicationId.debug',
        'Configured debug must package $_applicationId.debug.',
        result: configuredDebug,
      );

      progress('Configured profile keeps .profile ID and the debug signer');
      final configuredProfileStarted = DateTime.now().toUtc();
      final configuredProfile = await buildRunner.runGradle(
        ':app:assembleProfile',
        {'CLEAN_NOTES_KEY_PROPERTIES_FILE': validProperties.path},
      );
      _expectSuccess(
        configuredProfile,
        'assembleProfile with configured release ID',
      );
      final configuredProfileEvidence = await _inspectApk(
        _variantApk(buildRepository, 'profile'),
        toolchain,
        notBefore: configuredProfileStarted,
      );
      _require(
        configuredProfileEvidence.applicationId == '$_applicationId.profile' &&
            configuredProfileEvidence.certificateSha256 ==
                configuredDebugEvidence.certificateSha256 &&
            configuredProfileEvidence.certificateSha256 !=
                uploadFingerprint.toLowerCase(),
        'Configured profile must use .profile and never the upload signer.',
        result: configuredProfile,
      );

      progress('Windows Properties path escaping is unambiguous');
      if (Platform.isWindows) {
        final windowsProperties =
            File(path.join(temporaryDirectory.path, 'windows-path.properties'))
              ..writeAsStringSync(
                _propertiesText(
                  applicationId: _applicationId,
                  storeFile: uploadStore.path.replaceAll('\\', r'\\'),
                  password: password,
                  alias: uploadAlias,
                  fingerprint: uploadFingerprint,
                ),
                flush: true,
              );
        final windowsPath = await buildRunner.runGradle(
          ':app:validateReleaseConfiguration',
          {'CLEAN_NOTES_KEY_PROPERTIES_FILE': windowsProperties.path},
        );
        _expectSuccess(
          windowsPath,
          'doubled-backslash Windows properties path',
        );
      } else {
        throw UnsupportedError(
          'The full signing contract requires a Windows host for '
          'Java-properties path verification.',
        );
      }
    }

    if (buildPositiveReleaseArtifacts) {
      final positiveReleaseProperties = {
        'CLEAN_NOTES_KEY_PROPERTIES_FILE': validProperties.path,
      };
      progress(
        'Positive release APK builds through trusted Flutter and Gradle',
      );
      final positiveApkStarted = DateTime.now().toUtc();
      final positiveApk = await _runFlutterReleaseBuild(
        repository: buildRepository,
        toolchain: toolchain,
        gradleUserHome: isolatedGradleUserHome,
        trustedWrapper: buildWrapper,
        properties: positiveReleaseProperties,
        artifact: 'apk',
      );
      _expectSuccess(positiveApk, 'positive release APK build');
      await _requireTrackedCandidateUnchanged(buildRepository, gitExecutable);
      _requireReleaseRegistrantExcludesDevPlugins(buildRepository);
      final apkEvidence = await _inspectApk(
        _variantApk(buildRepository, 'release'),
        toolchain,
        notBefore: positiveApkStarted,
      );
      _require(
        apkEvidence.applicationId == _applicationId &&
            apkEvidence.certificateSha256 == uploadFingerprint.toLowerCase(),
        'The release APK identity or signer does not match the approved proof.',
        result: positiveApk,
      );

      progress(
        'Positive release AAB builds through trusted Flutter and Gradle',
      );
      final positiveAabStarted = DateTime.now().toUtc();
      final positiveAab = await _runFlutterReleaseBuild(
        repository: buildRepository,
        toolchain: toolchain,
        gradleUserHome: isolatedGradleUserHome,
        trustedWrapper: buildWrapper,
        properties: positiveReleaseProperties,
        artifact: 'appbundle',
      );
      _expectSuccess(positiveAab, 'positive release AAB build');
      await _requireTrackedCandidateUnchanged(buildRepository, gitExecutable);
      _requireReleaseRegistrantExcludesDevPlugins(buildRepository);
      final aabEvidence = await _inspectAab(
        _releaseAab(buildRepository),
        toolchain,
        notBefore: positiveAabStarted,
      );
      _require(
        aabEvidence.applicationId == _applicationId &&
            aabEvidence.certificateSha256 == uploadFingerprint.toLowerCase(),
        'The release AAB identity or signer does not match the approved proof.',
        result: positiveAab,
      );
      positiveReleaseEvidence = _PositiveReleaseEvidence(
        commit: candidateCommit,
        apk: apkEvidence,
        aab: aabEvidence,
      );
    }

    totalChecks = check;
    verificationChecksPassed = true;
    stdout.writeln(
      'CHECKS PASSED: $totalChecks Android signing contract checks completed; '
      'cleaning ephemeral credentials.',
    );
  } on Object catch (error) {
    stderr.writeln(
      'Android release-signing verification failed: ${sanitized(error)}',
    );
    exitCode = 1;
  } finally {
    final directoryToDelete = temporaryDirectory;
    if (directoryToDelete != null && directoryToDelete.existsSync()) {
      var safeToDelete = false;
      try {
        _assertSafeTemporaryDirectory(directoryToDelete, protectedRoots);
        safeToDelete = true;
      } on Object {
        stderr.writeln(
          'Android release-signing cleanup refused an unsafe location.',
        );
        exitCode = 1;
      }
      if (safeToDelete) {
        try {
          await deleteTemporaryDirectoryWithRetries(directoryToDelete);
          cleanupSucceeded = true;
        } on FileSystemException catch (error) {
          stderr.writeln(
            'Android release-signing credential cleanup failed: '
            '${sanitized(error)}',
          );
          exitCode = 1;
        }
      }
    } else {
      cleanupSucceeded = true;
    }
  }

  if (verificationChecksPassed && cleanupSucceeded) {
    final evidence = positiveReleaseEvidence;
    if (evidence != null) {
      stdout.writeln('PROOF_COMMIT=${evidence.commit}');
      stdout.writeln('PROOF_APK_APPLICATION_ID=${evidence.apk.applicationId}');
      stdout.writeln('PROOF_APK_CERT_SHA256=${evidence.apk.certificateSha256}');
      stdout.writeln('PROOF_APK_SHA256=${evidence.apk.artifactSha256}');
      stdout.writeln('PROOF_AAB_APPLICATION_ID=${evidence.aab.applicationId}');
      stdout.writeln('PROOF_AAB_CERT_SHA256=${evidence.aab.certificateSha256}');
      stdout.writeln('PROOF_AAB_SHA256=${evidence.aab.artifactSha256}');
      stdout.writeln('ARTIFACTS_RETAINED=false');
    }
    stdout.writeln(
      'PASS: $totalChecks Android signing contract checks completed and '
      'ephemeral credentials were deleted.',
    );
  }
}

Map<String, String> _releaseProperties({
  required String storeFile,
  required String password,
  required String alias,
  required String fingerprint,
}) => {
  'CLEAN_NOTES_APPLICATION_ID': _applicationId,
  'CLEAN_NOTES_STORE_FILE': storeFile,
  'CLEAN_NOTES_STORE_PASSWORD': password,
  'CLEAN_NOTES_KEY_ALIAS': alias,
  'CLEAN_NOTES_KEY_PASSWORD': password,
  'CLEAN_NOTES_UPLOAD_CERT_SHA256': fingerprint,
};

String _propertiesText({
  required String applicationId,
  required String storeFile,
  required String password,
  required String alias,
  required String fingerprint,
}) =>
    '''applicationId=$applicationId
storeFile=$storeFile
storePassword=$password
keyAlias=$alias
keyPassword=$password
uploadCertificateSha256=$fingerprint
''';

_TrustedToolchain _resolveTrustedToolchain(
  Directory repository,
  Iterable<String> protectedRoots,
  File gitExecutable, {
  required bool requireBundletool,
}) {
  final javaHome = _requiredExternalDirectory(
    repository,
    protectedRoots,
    Platform.environment['JAVA_HOME'],
    'JAVA_HOME',
  );
  final androidSdk = _requiredExternalDirectory(
    repository,
    protectedRoots,
    Platform.environment['CLEAN_NOTES_ANDROID_SDK_ROOT'],
    'CLEAN_NOTES_ANDROID_SDK_ROOT',
  );
  final flutterRoot = _requiredExternalDirectory(
    repository,
    protectedRoots,
    Platform.environment['CLEAN_NOTES_FLUTTER_ROOT'],
    'CLEAN_NOTES_FLUTTER_ROOT',
  );
  final executableSuffix = Platform.isWindows ? '.exe' : '';
  final scriptSuffix = Platform.isWindows ? '.bat' : '';
  final java = _requiredExternalFile(
    repository,
    protectedRoots,
    path.join(javaHome.path, 'bin', 'java$executableSuffix'),
    'Java executable',
  );
  final keytool = _requiredExternalFile(
    repository,
    protectedRoots,
    path.join(javaHome.path, 'bin', 'keytool$executableSuffix'),
    'keytool executable',
  );
  final jarsigner = _requiredExternalFile(
    repository,
    protectedRoots,
    path.join(javaHome.path, 'bin', 'jarsigner$executableSuffix'),
    'jarsigner executable',
  );
  final flutter = _requiredExternalFile(
    repository,
    protectedRoots,
    path.join(flutterRoot.path, 'bin', 'flutter$scriptSuffix'),
    'Flutter executable',
  );
  final apkanalyzer = _requiredExternalFile(
    repository,
    protectedRoots,
    path.join(
      androidSdk.path,
      'cmdline-tools',
      'latest',
      'bin',
      'apkanalyzer$scriptSuffix',
    ),
    'apkanalyzer executable',
  );
  final apksigner = _requiredExternalFile(
    repository,
    protectedRoots,
    path.join(
      androidSdk.path,
      'build-tools',
      '36.1.0',
      'apksigner$scriptSuffix',
    ),
    'apksigner executable',
  );
  File? bundletool;
  if (requireBundletool) {
    bundletool = _requiredExternalFile(
      repository,
      protectedRoots,
      Platform.environment['CLEAN_NOTES_BUNDLETOOL_JAR'],
      'CLEAN_NOTES_BUNDLETOOL_JAR',
    );
    _require(
      sha256Hex(bundletool.readAsBytesSync()) == _bundletoolSha256,
      'bundletool must be the pinned 1.18.3 release.',
    );
  }

  final environment = sanitizedGitEnvironment(
    sanitizedJavaEnvironment(Platform.environment),
  );
  environment['JAVA_HOME'] = javaHome.path;
  environment['ANDROID_HOME'] = androidSdk.path;
  environment['ANDROID_SDK_ROOT'] = androidSdk.path;
  environment['FLUTTER_ROOT'] = flutterRoot.path;
  final trustedPathEntries = <String>[
    path.dirname(gitExecutable.path),
    path.join(flutterRoot.path, 'bin'),
    path.join(javaHome.path, 'bin'),
    if (Platform.isWindows) ...[
      path.join(environment['SystemRoot'] ?? r'C:\Windows', 'System32'),
      path.join(
        environment['SystemRoot'] ?? r'C:\Windows',
        'System32',
        'WindowsPowerShell',
        'v1.0',
      ),
    ] else ...[
      '/usr/bin',
      '/bin',
    ],
  ];
  environment['PATH'] = trustedPathEntries.join(Platform.isWindows ? ';' : ':');

  return _TrustedToolchain(
    flutter: flutter,
    java: java,
    keytool: keytool,
    jarsigner: jarsigner,
    apkanalyzer: apkanalyzer,
    apksigner: apksigner,
    androidSdk: androidSdk,
    flutterRoot: flutterRoot,
    environment: environment,
    bundletool: bundletool,
  );
}

Directory _requiredExternalDirectory(
  Directory repository,
  Iterable<String> protectedRoots,
  String? configuredPath,
  String label,
) {
  final value = configuredPath?.trim();
  _require(
    value != null && value.isNotEmpty && path.isAbsolute(value),
    '$label must be an absolute external directory.',
  );
  final directory = Directory(value!);
  _require(directory.existsSync(), '$label directory is unavailable.');
  final canonical = directory.resolveSymbolicLinksSync();
  _requireExternalPath(repository, protectedRoots, canonical, label);
  return Directory(canonical);
}

File _requiredExternalFile(
  Directory repository,
  Iterable<String> protectedRoots,
  String? configuredPath,
  String label,
) {
  final value = configuredPath?.trim();
  _require(
    value != null && value.isNotEmpty && path.isAbsolute(value),
    '$label must be an absolute external file.',
  );
  final file = File(value!);
  _require(file.existsSync(), '$label file is unavailable.');
  final canonical = file.resolveSymbolicLinksSync();
  _requireExternalPath(repository, protectedRoots, canonical, label);
  return File(canonical);
}

void _requireExternalPath(
  Directory repository,
  Iterable<String> protectedRoots,
  String candidate,
  String label,
) {
  final roots = <String>{
    repository.resolveSymbolicLinksSync(),
    ...protectedRoots,
  };
  _require(
    roots.every(
      (root) =>
          !path.equals(root, candidate) && !path.isWithin(root, candidate),
    ),
    '$label must remain outside every protected repository root.',
  );
}

Future<String> _candidateCommit(
  Directory repository,
  File gitExecutable,
) async {
  final result = await Process.run(
    gitExecutable.path,
    ['-C', repository.path, 'rev-parse', '--verify', 'HEAD^{commit}'],
    environment: sanitizedGitEnvironment(Platform.environment),
    includeParentEnvironment: false,
    runInShell: false,
  );
  final commit = (result.stdout as String).trim().toLowerCase();
  _require(
    result.exitCode == 0 && RegExp(r'^[0-9a-f]{40,64}$').hasMatch(commit),
    'Unable to pin the candidate commit.',
  );
  return commit;
}

Future<Directory> _cloneExactCandidate({
  required Directory source,
  required Directory destination,
  required String commit,
  required File gitExecutable,
}) async {
  destination.parent.createSync(recursive: true);
  final environment = sanitizedGitEnvironment(Platform.environment);
  final clone = await Process.run(
    gitExecutable.path,
    [
      'clone',
      '--local',
      '--no-hardlinks',
      '--no-checkout',
      '--',
      source.path,
      destination.path,
    ],
    environment: environment,
    includeParentEnvironment: false,
    runInShell: false,
  );
  _expectSuccess(
    _CommandResult(clone.exitCode, '${clone.stdout}\n${clone.stderr}'),
    'exact-candidate clone',
  );
  final checkout = await Process.run(
    gitExecutable.path,
    ['-C', destination.path, 'checkout', '--detach', commit],
    environment: environment,
    includeParentEnvironment: false,
    runInShell: false,
  );
  _expectSuccess(
    _CommandResult(checkout.exitCode, '${checkout.stdout}\n${checkout.stderr}'),
    'exact-candidate checkout',
  );
  final actual = await _candidateCommit(destination, gitExecutable);
  _require(actual == commit, 'The isolated source snapshot changed commit.');
  return destination;
}

void _writeSnapshotLocalProperties(
  Directory repository,
  _TrustedToolchain toolchain,
) {
  String escaped(String value) => value.replaceAll('\\', r'\\');
  File(
    path.join(repository.path, 'android', 'local.properties'),
  ).writeAsStringSync(
    'sdk.dir=${escaped(toolchain.androidSdk.path)}\n'
    'flutter.sdk=${escaped(toolchain.flutterRoot.path)}\n',
    flush: true,
  );
}

Future<_CommandResult> _runFlutterPubGet(
  Directory repository,
  _TrustedToolchain toolchain,
) async {
  final result = await Process.run(
    toolchain.flutter.path,
    ['pub', 'get', '--enforce-lockfile'],
    workingDirectory: repository.path,
    environment: toolchain.environment,
    includeParentEnvironment: false,
    runInShell: Platform.isWindows,
  );
  return _CommandResult(result.exitCode, '${result.stdout}\n${result.stderr}');
}

Future<_CommandResult> _runFlutterReleaseBuild({
  required Directory repository,
  required _TrustedToolchain toolchain,
  required Directory gradleUserHome,
  required File trustedWrapper,
  required Map<String, String> properties,
  required String artifact,
}) async {
  _require(
    artifact == 'apk' || artifact == 'appbundle',
    'Unsupported Flutter release artifact.',
  );
  await _validateTrustedGradleWrapperSnapshot(trustedWrapper);

  final candidateLauncher = File(
    path.join(
      repository.path,
      'android',
      Platform.isWindows ? 'gradlew.bat' : 'gradlew',
    ),
  );
  _require(
    FileSystemEntity.typeSync(candidateLauncher.path, followLinks: false) ==
        FileSystemEntityType.file,
    'The isolated candidate Gradle launcher is not a regular file.',
  );
  final trustedBytes = await trustedWrapper.readAsBytes();
  final wrapperJar = File(
    path.join(
      trustedWrapper.parent.path,
      'gradle',
      'wrapper',
      'gradle-wrapper.jar',
    ),
  );
  final shimBytes = utf8.encode(
    trustedGradleLauncherShim(
      javaExecutablePath: toolchain.java.path,
      wrapperJarPath: wrapperJar.path,
      windows: Platform.isWindows,
    ),
  );
  final result = await runWithTrustedGradleLauncherShim<ProcessResult>(
    candidateLauncher: candidateLauncher,
    trustedLauncherBytes: trustedBytes,
    shimBytes: shimBytes,
    makeExecutable: Platform.isWindows ? null : _makeExecutable,
    operation: () => Process.run(
      toolchain.flutter.path,
      ['build', artifact, '--release', '--no-android-gradle-daemon'],
      workingDirectory: repository.path,
      environment: hermeticGradleEnvironment(
        inheritedEnvironment: toolchain.environment,
        projectProperties: properties,
        gradleUserHome: gradleUserHome,
      ),
      includeParentEnvironment: false,
      runInShell: Platform.isWindows,
    ),
  );
  await _validateTrustedGradleWrapperSnapshot(trustedWrapper);
  return _CommandResult(result.exitCode, '${result.stdout}\n${result.stderr}');
}

Future<void> _makeExecutable(File file) async {
  final result = await Process.run('/bin/chmod', ['700', file.path]);
  _require(result.exitCode == 0, 'Unable to secure a Gradle launcher.');
}

Future<void> _validateTrustedGradleWrapperSnapshot(File trustedWrapper) async {
  final androidDirectory = trustedWrapper.parent;
  final files = <String, File>{
    'unix': File(path.join(androidDirectory.path, 'gradlew')),
    'windows': File(path.join(androidDirectory.path, 'gradlew.bat')),
    'jar': File(
      path.join(
        androidDirectory.path,
        'gradle',
        'wrapper',
        'gradle-wrapper.jar',
      ),
    ),
    'properties': File(
      path.join(
        androidDirectory.path,
        'gradle',
        'wrapper',
        'gradle-wrapper.properties',
      ),
    ),
  };
  _require(
    files.values.every(
      (file) =>
          FileSystemEntity.typeSync(file.path, followLinks: false) ==
          FileSystemEntityType.file,
    ),
    'The trusted Gradle wrapper snapshot is incomplete.',
  );
  final bytes = <String, List<int>>{
    for (final entry in files.entries)
      entry.key: await entry.value.readAsBytes(),
  };
  validateGradleWrapperLauncherDigests(
    unixSha256: sha256Hex(bytes['unix']!),
    windowsSha256: sha256Hex(bytes['windows']!),
  );
  _require(
    sha256Hex(bytes['jar']!) == _gradleWrapperJarSha256,
    'The trusted Gradle wrapper JAR changed.',
  );
  validateGradleWrapperProperties(
    utf8.decode(bytes['properties']!, allowMalformed: false),
    expectedDistributionUrl:
        r'https\://services.gradle.org/distributions/gradle-8.14-all.zip',
    expectedDistributionSha256: _gradleDistributionSha256,
  );
}

Future<void> _requireTrackedCandidateUnchanged(
  Directory repository,
  File gitExecutable,
) async {
  final environment = sanitizedGitEnvironment(Platform.environment);
  for (final arguments in <List<String>>[
    ['-C', repository.path, 'diff', '--no-ext-diff', '--quiet', 'HEAD', '--'],
    [
      '-C',
      repository.path,
      'diff',
      '--cached',
      '--no-ext-diff',
      '--quiet',
      'HEAD',
      '--',
    ],
  ]) {
    final result = await Process.run(
      gitExecutable.path,
      arguments,
      environment: environment,
      includeParentEnvironment: false,
      runInShell: false,
    );
    _require(
      result.exitCode == 0,
      'Flutter release tooling must not mutate tracked candidate files.',
    );
  }
}

void _requireReleaseRegistrantExcludesDevPlugins(Directory repository) {
  final registrant = File(
    path.join(
      repository.path,
      'android',
      'app',
      'src',
      'main',
      'java',
      'io',
      'flutter',
      'plugins',
      'GeneratedPluginRegistrant.java',
    ),
  );
  final isRegularFile =
      FileSystemEntity.typeSync(registrant.path, followLinks: false) ==
      FileSystemEntityType.file;
  final contents = isRegularFile ? registrant.readAsStringSync() : '';
  _require(
    isRegularFile &&
        !contents.contains('integration_test') &&
        !contents.contains('IntegrationTestPlugin'),
    'Flutter release tooling retained a development-only Android plugin.',
  );
}

Future<File> _materializeTrustedGradleWrapper(
  Directory repository,
  Directory destination,
  File gitExecutable,
) async {
  const wrapperPaths = <String>[
    '.gitattributes',
    'android/gradlew',
    'android/gradlew.bat',
    'android/gradle/wrapper/gradle-wrapper.jar',
    'android/gradle/wrapper/gradle-wrapper.properties',
  ];
  final tracked = await Process.run(
    gitExecutable.path,
    [
      '-C',
      repository.path,
      'ls-files',
      '--error-unmatch',
      '--',
      ...wrapperPaths,
    ],
    environment: sanitizedGitEnvironment(Platform.environment),
    includeParentEnvironment: false,
    runInShell: false,
  );
  _require(
    tracked.exitCode == 0,
    'Every Gradle wrapper launcher and executable must be versioned.',
  );
  final unchanged = await Process.run(
    gitExecutable.path,
    [
      '-C',
      repository.path,
      'diff',
      '--no-ext-diff',
      '--quiet',
      'HEAD',
      '--',
      ...wrapperPaths,
    ],
    environment: sanitizedGitEnvironment(Platform.environment),
    includeParentEnvironment: false,
    runInShell: false,
  );
  _require(
    unchanged.exitCode == 0,
    'Gradle wrapper files must match the committed release candidate.',
  );

  final sources = <String, File>{
    for (final relativePath in wrapperPaths)
      relativePath: File(path.join(repository.path, relativePath)),
  };
  _require(
    sources.values.every(
      (file) =>
          FileSystemEntity.typeSync(file.path, followLinks: false) ==
          FileSystemEntityType.file,
    ),
    'The committed Gradle wrapper is incomplete.',
  );
  final bytes = <String, List<int>>{
    for (final entry in sources.entries)
      entry.key: await entry.value.readAsBytes(),
  };
  validateGradleWrapperLauncherDigests(
    unixSha256: sha256Hex(bytes['android/gradlew']!),
    windowsSha256: sha256Hex(bytes['android/gradlew.bat']!),
  );
  _require(
    sha256Hex(bytes['android/gradle/wrapper/gradle-wrapper.jar']!) ==
        _gradleWrapperJarSha256,
    'The Gradle wrapper JAR does not match Gradle 8.14.',
  );
  validateGradleWrapperProperties(
    utf8.decode(
      bytes['android/gradle/wrapper/gradle-wrapper.properties']!,
      allowMalformed: false,
    ),
    expectedDistributionUrl:
        r'https\://services.gradle.org/distributions/gradle-8.14-all.zip',
    expectedDistributionSha256: _gradleDistributionSha256,
  );
  final attributes = utf8
      .decode(bytes['.gitattributes']!, allowMalformed: false)
      .replaceAll('\r\n', '\n')
      .split('\n')
      .where((line) => line.isNotEmpty)
      .toSet();
  _require(
    attributes.containsAll(const {
          'android/gradlew text eol=lf',
          'android/gradlew.bat text eol=crlf',
          'android/gradle/wrapper/gradle-wrapper.properties text eol=lf',
        }) &&
        attributes.length == 3,
    'The Gradle wrapper line-ending contract is not pinned exactly.',
  );

  for (final relativePath in wrapperPaths.where(
    (relativePath) => relativePath != '.gitattributes',
  )) {
    final target = File(path.join(destination.path, relativePath));
    target.parent.createSync(recursive: true);
    await target.writeAsBytes(bytes[relativePath]!, flush: true);
  }
  final trustedLauncher = File(
    path.join(
      destination.path,
      'android',
      Platform.isWindows ? 'gradlew.bat' : 'gradlew',
    ),
  );
  if (!Platform.isWindows) {
    final chmod = await Process.run('/bin/chmod', [
      '700',
      trustedLauncher.path,
    ]);
    _require(
      chmod.exitCode == 0,
      'Unable to secure the trusted Gradle launcher.',
    );
  }
  return trustedLauncher;
}

Future<String> _fileSha256(File file) async =>
    sha256Hex(await file.readAsBytes());

Future<_CommandResult> _runGradle(
  Directory repository,
  File wrapper,
  File java,
  Directory gradleUserHome,
  Map<String, String> inheritedEnvironment,
  String task,
  Map<String, String> properties,
) async {
  final wrapperJar = File(
    path.join(wrapper.parent.path, 'gradle', 'wrapper', 'gradle-wrapper.jar'),
  );
  late ProcessResult result;
  for (var attempt = 0; ; attempt += 1) {
    await _validateTrustedGradleWrapperSnapshot(wrapper);
    try {
      try {
        result = await Process.run(
          java.path,
          [
            '-Dorg.gradle.appname=gradlew',
            '-jar',
            wrapperJar.path,
            '-p',
            path.join(repository.path, 'android'),
            '--no-daemon',
            '--console=plain',
            task,
          ],
          workingDirectory: repository.path,
          environment: hermeticGradleEnvironment(
            inheritedEnvironment: inheritedEnvironment,
            projectProperties: properties,
            gradleUserHome: gradleUserHome,
          ),
          includeParentEnvironment: false,
          runInShell: false,
        );
        break;
      } on ProcessException {
        if (!Platform.isWindows || attempt > 0) rethrow;
        _require(
          repository.existsSync() && wrapper.existsSync() && java.existsSync(),
          'The worktree or trusted toolchain disappeared while starting $task.',
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
    } finally {
      await _validateTrustedGradleWrapperSnapshot(wrapper);
    }
  }
  return _CommandResult(result.exitCode, '${result.stdout}\n${result.stderr}');
}

File _variantApk(Directory repository, String variant) => File(
  path.join(
    repository.path,
    'build',
    'app',
    'outputs',
    'flutter-apk',
    'app-$variant.apk',
  ),
);

File _releaseAab(Directory repository) => File(
  path.join(
    repository.path,
    'build',
    'app',
    'outputs',
    'bundle',
    'release',
    'app-release.aab',
  ),
);

Future<_ArtifactEvidence> _inspectApk(
  File artifact,
  _TrustedToolchain toolchain, {
  required DateTime notBefore,
}) async {
  _requireFreshArtifact(artifact, notBefore);
  final applicationId = await Process.run(
    toolchain.apkanalyzer.path,
    ['manifest', 'application-id', artifact.path],
    environment: toolchain.environment,
    includeParentEnvironment: false,
    runInShell: Platform.isWindows,
  );
  final signer = await Process.run(
    toolchain.apksigner.path,
    ['verify', '--print-certs', artifact.path],
    environment: toolchain.environment,
    includeParentEnvironment: false,
    runInShell: Platform.isWindows,
  );
  return _ArtifactEvidence(
    applicationId: parseSingleApplicationId(
      applicationId.stdout as String,
      exitCode: applicationId.exitCode,
    ),
    certificateSha256: parseApksignerSha256(
      signer.stdout as String,
      exitCode: signer.exitCode,
    ),
    artifactSha256: await _fileSha256(artifact),
  );
}

Future<_ArtifactEvidence> _inspectAab(
  File artifact,
  _TrustedToolchain toolchain, {
  required DateTime notBefore,
}) async {
  _requireFreshArtifact(artifact, notBefore);
  final bundletool = toolchain.bundletool;
  if (bundletool == null) {
    throw StateError('Pinned bundletool is required for AAB proof.');
  }
  final validate = await Process.run(
    toolchain.java.path,
    ['-jar', bundletool.path, 'validate', '--bundle=${artifact.path}'],
    environment: sanitizedJavaEnvironment(toolchain.environment),
    includeParentEnvironment: false,
    runInShell: false,
  );
  _expectSuccess(
    _CommandResult(validate.exitCode, '${validate.stdout}\n${validate.stderr}'),
    'bundletool AAB validation',
  );
  final applicationId = await Process.run(
    toolchain.java.path,
    [
      '-jar',
      bundletool.path,
      'dump',
      'manifest',
      '--bundle=${artifact.path}',
      '--xpath=/manifest/@package',
    ],
    environment: sanitizedJavaEnvironment(toolchain.environment),
    includeParentEnvironment: false,
    runInShell: false,
  );
  final signature = await Process.run(
    toolchain.jarsigner.path,
    [
      '-J-Duser.language=en',
      '-J-Duser.country=US',
      '-verify',
      '-certs',
      artifact.path,
    ],
    environment: sanitizedJavaEnvironment(toolchain.environment),
    includeParentEnvironment: false,
    runInShell: false,
  );
  _expectSuccess(
    _CommandResult(
      signature.exitCode,
      '${signature.stdout}\n${signature.stderr}',
    ),
    'AAB JAR-signature verification',
  );
  final certificate = await Process.run(
    toolchain.keytool.path,
    [
      '-J-Duser.language=en',
      '-J-Duser.country=US',
      '-printcert',
      '-jarfile',
      artifact.path,
    ],
    environment: sanitizedJavaEnvironment(toolchain.environment),
    includeParentEnvironment: false,
    runInShell: false,
  );
  return _ArtifactEvidence(
    applicationId: parseSingleApplicationId(
      applicationId.stdout as String,
      exitCode: applicationId.exitCode,
    ),
    certificateSha256: parseKeytoolSha256(
      certificate.stdout as String,
      exitCode: certificate.exitCode,
    ),
    artifactSha256: await _fileSha256(artifact),
  );
}

void _requireFreshArtifact(File artifact, DateTime notBefore) {
  _require(
    FileSystemEntity.typeSync(artifact.path, followLinks: false) ==
            FileSystemEntityType.file &&
        artifact.lengthSync() > 0 &&
        !artifact.lastModifiedSync().toUtc().isBefore(
          notBefore.subtract(const Duration(seconds: 2)),
        ),
    'The build did not produce a fresh regular artifact.',
  );
}

void _expectSuccess(_CommandResult result, String operation) {
  _require(result.exitCode == 0, '$operation should succeed.', result: result);
}

void _expectFailureContaining(_CommandResult result, String expectedMessage) {
  _require(result.exitCode != 0, 'The operation should fail closed.');
  _require(
    result.output.contains(expectedMessage),
    'Failure output must contain "$expectedMessage".',
    result: result,
  );
}

void _expectValidationFailure(
  _CommandResult result,
  Iterable<String> expectedMessages, {
  bool mustBeFirstReleaseTask = false,
}) {
  _require(
    result.exitCode != 0,
    'Release validation should fail closed.',
    result: result,
  );
  _require(
    result.output.contains(':app:validateReleaseConfiguration FAILED'),
    'Failure must come from validateReleaseConfiguration.',
    result: result,
  );
  for (final message in expectedMessages) {
    _require(
      result.output.contains(message),
      'Validation output must contain "$message".',
      result: result,
    );
  }
  if (mustBeFirstReleaseTask) {
    final validationIndex = result.output.indexOf(
      '> Task :app:validateReleaseConfiguration',
    );
    final priorOutput = result.output.substring(0, validationIndex);
    _require(
      !RegExp(r'> Task :app:\S*Release\S*').hasMatch(priorOutput),
      'Release build work ran before release configuration validation.',
      result: result,
    );
  }
}

Iterable<String> _minimalProtectionRoots(Iterable<String> roots) {
  final allRoots = roots.toList(growable: false);
  return allRoots.where(
    (candidate) => !allRoots.any(
      (other) =>
          !path.equals(other, candidate) && path.isWithin(other, candidate),
    ),
  );
}

void _assertSafeTemporaryDirectory(
  Directory directory,
  Iterable<String> protectedRepositoryRoots,
) {
  final candidate = directory.resolveSymbolicLinksSync();
  final systemTemporaryRoot = resolveSystemTemporaryDirectory().path;
  _require(
    path.basename(candidate).startsWith('clean-notes-signing-contract-') &&
        path.equals(path.dirname(candidate), systemTemporaryRoot),
    'Synthetic credential directory is not a direct, named child of system temp.',
  );
  for (final repositoryRoot in protectedRepositoryRoots) {
    _require(
      !path.equals(repositoryRoot, candidate) &&
          !path.isWithin(repositoryRoot, candidate),
      'Synthetic credential directory must remain outside every repository root.',
    );
  }
}

void _require(bool condition, String message, {_CommandResult? result}) {
  if (condition) return;
  final output = result?.output.trim();
  throw StateError(
    output == null || output.isEmpty ? message : '$message\n$output',
  );
}

String _packagedDebugApplicationId(Directory repository) {
  final manifestsDirectory = Directory(
    path.join(
      repository.path,
      'build',
      'app',
      'intermediates',
      'packaged_manifests',
      'debug',
    ),
  );
  final manifests =
      manifestsDirectory
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => path.basename(file.path) == 'AndroidManifest.xml')
          .toList()
        ..sort(
          (left, right) =>
              right.lastModifiedSync().compareTo(left.lastModifiedSync()),
        );
  _require(manifests.isNotEmpty, 'No packaged debug manifest was produced.');
  final match = RegExp(
    r'<manifest\b[^>]*\bpackage="([^"]+)"',
  ).firstMatch(manifests.first.readAsStringSync());
  _require(match != null, 'Packaged debug manifest has no application ID.');
  return match!.group(1)!;
}

Future<void> _generateKeyStore(
  File keytool,
  Map<String, String> environment,
  File file, {
  required String password,
  required String alias,
  required String distinguishedName,
}) async {
  final result = await Process.run(
    keytool.path,
    [
      '-J-Duser.language=en',
      '-J-Duser.country=US',
      '-genkeypair',
      '-noprompt',
      '-keystore',
      file.path,
      '-storetype',
      'PKCS12',
      '-storepass',
      password,
      '-keypass',
      password,
      '-alias',
      alias,
      '-keyalg',
      'RSA',
      '-keysize',
      '2048',
      '-validity',
      '2',
      '-dname',
      distinguishedName,
    ],
    environment: sanitizedJavaEnvironment(environment),
    includeParentEnvironment: false,
    runInShell: false,
  );
  _require(
    result.exitCode == 0,
    'keytool could not generate an ephemeral keystore.\n'
    '${result.stdout}\n${result.stderr}',
  );
}

Future<String> _certificateFingerprint(
  File keytool,
  Map<String, String> environment,
  File file, {
  required String password,
  required String alias,
}) async {
  final result = await Process.run(
    keytool.path,
    [
      '-J-Duser.language=en',
      '-J-Duser.country=US',
      '-list',
      '-v',
      '-keystore',
      file.path,
      '-storepass',
      password,
      '-alias',
      alias,
    ],
    environment: sanitizedJavaEnvironment(environment),
    includeParentEnvironment: false,
    runInShell: false,
  );
  final output = '${result.stdout}\n${result.stderr}';
  _require(
    result.exitCode == 0,
    'keytool could not inspect an ephemeral keystore.\n$output',
  );
  return parseKeytoolSha256(
    result.stdout as String,
    exitCode: result.exitCode,
  ).toUpperCase();
}
