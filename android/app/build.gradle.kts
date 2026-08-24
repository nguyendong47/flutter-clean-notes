import java.io.File
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.cert.X509Certificate
import java.util.Properties
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val templateApplicationId = "com.example.flutter_clean_notes"
val androidApplicationIdPattern =
    Regex("^[A-Za-z][A-Za-z0-9_]*(\\.[A-Za-z][A-Za-z0-9_]*)+$")

fun directEnvironmentValue(name: String): String? = System.getenv(name)

fun canonicalFile(file: File): File =
    try {
        file.canonicalFile
    } catch (_: Exception) {
        throw GradleException(
            "Unable to resolve a protected filesystem path safely.",
        )
    }

fun normalizedFile(file: File): File =
    file.absoluteFile.toPath().normalize().toFile()

fun normalizedUserFile(file: File): File? =
    try {
        normalizedFile(file)
    } catch (_: Exception) {
        null
    }

fun canonicalUserFile(file: File?): File? =
    if (file == null) {
        null
    } else {
        try {
            file.canonicalFile
        } catch (_: Exception) {
            null
        }
    }

fun File.readFirstLineUtf8(): String? =
    try {
        if (isFile) bufferedReader(Charsets.UTF_8).use { it.readLine()?.trim() } else null
    } catch (_: Exception) {
        null
    }

fun resolvePath(baseDirectory: File, configuredPath: String): File {
    val candidate = File(configuredPath)
    return canonicalFile(
        if (candidate.isAbsolute) candidate else File(baseDirectory, configuredPath),
    )
}

data class GitDirectoryLayout(
    val directory: File,
    val isLinkedWorktree: Boolean,
)

fun gitDirectory(repositoryRoot: File): GitDirectoryLayout? {
    val dotGit = File(repositoryRoot, ".git")
    if (dotGit.isDirectory) {
        return GitDirectoryLayout(
            directory = canonicalFile(dotGit),
            isLinkedWorktree = false,
        )
    }
    if (!dotGit.exists()) return null

    val marker = dotGit.readFirstLineUtf8()
    if (marker == null || !marker.startsWith("gitdir:")) {
        throw GradleException("Unable to resolve linked-worktree Git metadata safely.")
    }
    val configuredPath = marker.substringAfter("gitdir:").trim()
    if (configuredPath.isEmpty()) {
        throw GradleException("Linked-worktree Git metadata has an empty gitdir path.")
    }
    return GitDirectoryLayout(
        directory = resolvePath(repositoryRoot, configuredPath),
        isLinkedWorktree = true,
    )
}

fun repositoryProtectionRoots(repositoryRoot: File): List<File> {
    val roots = linkedSetOf(canonicalFile(repositoryRoot))
    val gitLayout = gitDirectory(repositoryRoot) ?: return roots.toList()
    val gitDirectory = gitLayout.directory
    val commonDirectoryMarker = File(gitDirectory, "commondir")
    val commonGitDirectory =
        if (gitLayout.isLinkedWorktree) {
            if (!commonDirectoryMarker.isFile) {
                throw GradleException(
                    "Linked-worktree Git common-directory metadata is missing.",
                )
            }
            val configuredPath = commonDirectoryMarker.readFirstLineUtf8()
            if (configuredPath.isNullOrEmpty()) {
                throw GradleException("Git common-directory metadata is unreadable.")
            }
            resolvePath(gitDirectory, configuredPath)
        } else {
            gitDirectory
        }

    commonGitDirectory.parentFile?.let { roots.add(canonicalFile(it)) }
    val worktreeMetadataRoot = File(commonGitDirectory, "worktrees")
    if (worktreeMetadataRoot.exists()) {
        val worktreeMetadataEntries =
            worktreeMetadataRoot.listFiles()
                ?: throw GradleException("Git linked-worktree metadata is unreadable.")
        worktreeMetadataEntries.forEach { worktreeMetadata ->
            if (!worktreeMetadata.isDirectory) {
                throw GradleException("Git linked-worktree metadata is malformed.")
            }
            val configuredGitFile =
                File(worktreeMetadata, "gitdir").readFirstLineUtf8()
            if (configuredGitFile.isNullOrEmpty()) {
                throw GradleException("Git linked-worktree metadata is unreadable.")
            }
            val linkedGitFile = resolvePath(worktreeMetadata, configuredGitFile)
            val linkedWorktree = linkedGitFile.parentFile
            if (!linkedGitFile.isFile || linkedWorktree == null || !linkedWorktree.isDirectory) {
                throw GradleException("A registered linked worktree is unavailable.")
            }
            roots.add(canonicalFile(linkedWorktree))
        }
    }
    return roots.toList()
}

val currentRepositoryRoot = canonicalFile(rootProject.projectDir.parentFile)
data class RepositoryProtectionState(
    val roots: List<File>,
    val resolutionFailed: Boolean,
)

val repositoryProtectionState =
    try {
        RepositoryProtectionState(
            roots = repositoryProtectionRoots(currentRepositoryRoot),
            resolutionFailed = false,
        )
    } catch (_: Exception) {
        // Debug/profile/IDE configuration stays usable. Release validation
        // receives the failure below and refuses to sign.
        RepositoryProtectionState(
            roots = listOf(currentRepositoryRoot),
            resolutionFailed = true,
        )
    }
val protectedRepositoryRoots = repositoryProtectionState.roots

tasks.register("verifyRepositoryProtectionFixture") {
    doLast {
        val fixturePath =
            directEnvironmentValue("CLEAN_NOTES_REPOSITORY_PROTECTION_FIXTURE")
                ?: throw GradleException("Repository-protection fixture path is required.")
        repositoryProtectionRoots(canonicalFile(File(fixturePath)))
    }
}

fun isRepositoryLocal(file: File): Boolean =
    protectedRepositoryRoots.any { repositoryRoot ->
        file.toPath().startsWith(repositoryRoot.toPath())
    }

val directReleaseInputNames =
    listOf(
        "CLEAN_NOTES_APPLICATION_ID",
        "CLEAN_NOTES_STORE_FILE",
        "CLEAN_NOTES_STORE_PASSWORD",
        "CLEAN_NOTES_KEY_ALIAS",
        "CLEAN_NOTES_KEY_PASSWORD",
        "CLEAN_NOTES_UPLOAD_CERT_SHA256",
    )
val hasCompleteDirectReleaseConfiguration =
    directReleaseInputNames.all { name ->
        directEnvironmentValue(name)?.isNotBlank() == true
    }
val configuredKeyPropertiesPath =
    if (hasCompleteDirectReleaseConfiguration) {
        null
    } else {
        directEnvironmentValue("CLEAN_NOTES_KEY_PROPERTIES_FILE")
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
    }
val defaultKeyPropertiesSelector = normalizedFile(rootProject.file("key.properties"))
val configuredKeyPropertiesSelector =
    configuredKeyPropertiesPath?.let { normalizedUserFile(rootProject.file(it)) }
val hasInvalidConfiguredKeyPropertiesSelector =
    configuredKeyPropertiesPath != null && configuredKeyPropertiesSelector == null
val selectsExactDefaultKeyPropertiesFile =
    configuredKeyPropertiesSelector == null ||
        configuredKeyPropertiesSelector.toPath() == defaultKeyPropertiesSelector.toPath()
val selectedKeyPropertiesSelector =
    if (hasCompleteDirectReleaseConfiguration) {
        null
    } else if (configuredKeyPropertiesPath == null) {
        defaultKeyPropertiesSelector
    } else {
        configuredKeyPropertiesSelector
    }
val keyPropertiesFile = canonicalUserFile(selectedKeyPropertiesSelector)
val hasUnsafeDefaultKeyPropertiesLink =
    selectsExactDefaultKeyPropertiesFile &&
        selectedKeyPropertiesSelector != null &&
        keyPropertiesFile != null &&
        selectedKeyPropertiesSelector.toPath() != keyPropertiesFile.toPath() &&
        isRepositoryLocal(keyPropertiesFile)
val hasUnsafeAlternativeKeyPropertiesFile =
    hasUnsafeDefaultKeyPropertiesLink ||
        (configuredKeyPropertiesPath != null &&
            !selectsExactDefaultKeyPropertiesFile &&
            selectedKeyPropertiesSelector != null &&
            keyPropertiesFile != null &&
            (isRepositoryLocal(selectedKeyPropertiesSelector) ||
                isRepositoryLocal(keyPropertiesFile)))
val keyProperties = Properties()
val keyPropertiesLoadFailed =
    if (hasCompleteDirectReleaseConfiguration) {
        false
    } else if (hasUnsafeAlternativeKeyPropertiesFile) {
        false
    } else if (hasInvalidConfiguredKeyPropertiesSelector || keyPropertiesFile == null) {
        true
    } else if (!keyPropertiesFile.exists()) {
        configuredKeyPropertiesPath != null
    } else if (!keyPropertiesFile.isFile) {
        true
    } else {
        try {
            keyPropertiesFile.reader(Charsets.UTF_8).use(keyProperties::load)
            false
        } catch (_: Exception) {
            keyProperties.clear()
            true
        }
    }

fun externalValue(projectPropertyName: String, keyName: String): String? {
    val configuredValue = directEnvironmentValue(projectPropertyName)
    return configuredValue ?: keyProperties.getProperty(keyName)
}

data class ResolvedStoreFile(
    val file: File,
    val isRepositoryLocal: Boolean,
)

fun isPlaceholder(value: String?): Boolean =
    value == null ||
        value.isBlank() ||
        (value.startsWith('<') && value.endsWith('>'))

fun resolveStoreFile(): ResolvedStoreFile? {
    val configuredStorePath = directEnvironmentValue("CLEAN_NOTES_STORE_FILE")
    val selectedPath = configuredStorePath ?: keyProperties.getProperty("storeFile")
    val path = selectedPath?.trim()?.takeIf { it.isNotEmpty() } ?: return null
    if (isPlaceholder(path)) return null
    val baseDirectory =
        if (configuredStorePath != null) {
            rootProject.projectDir
        } else {
            keyPropertiesFile?.parentFile ?: rootProject.projectDir
        }
    val candidate =
        try {
            File(path)
        } catch (_: Exception) {
            return null
        }
    val selectedFile =
        normalizedUserFile(
            if (candidate.isAbsolute) candidate else File(baseDirectory, path),
        ) ?: return null
    val canonicalStoreFile = canonicalUserFile(selectedFile) ?: return null
    return ResolvedStoreFile(
        file = canonicalStoreFile,
        isRepositoryLocal =
            isRepositoryLocal(selectedFile) || isRepositoryLocal(canonicalStoreFile),
    )
}

fun isPlaceholderApplicationId(value: String?): Boolean {
    if (value == null || !androidApplicationIdPattern.matches(value)) return true
    return value
        .split('.')
        .any { segment ->
            segment.startsWith("example", ignoreCase = true) ||
                segment.startsWith("yourcompany", ignoreCase = true)
        }
}

fun normalizedSha256(value: String?): String? =
    value
        ?.replace(":", "")
        ?.filterNot(Char::isWhitespace)
        ?.uppercase()
        ?.takeIf { it.matches(Regex("^[0-9A-F]{64}$")) }

fun certificateSha256(certificate: X509Certificate): String =
    MessageDigest
        .getInstance("SHA-256")
        .digest(certificate.encoded)
        .joinToString("") { byte -> "%02X".format(byte) }

fun isDebugCertificate(
    certificate: X509Certificate,
    storeFile: File,
    keyAlias: String,
): Boolean {
    val subject = certificate.subjectX500Principal.name
    return storeFile.name.equals("debug.keystore", ignoreCase = true) ||
        keyAlias.equals("androiddebugkey", ignoreCase = true) ||
        subject
            .split(',')
            .any { it.trim().equals("CN=Android Debug", ignoreCase = true) }
}

data class ReleaseConfiguration(
    val applicationId: String?,
    val storeFile: File?,
    val hasRepositoryLocalStoreFile: Boolean,
    val storePassword: String?,
    val keyAlias: String?,
    val keyPassword: String?,
    val uploadCertificateSha256: String?,
    val hasUnsafeAlternativeKeyPropertiesFile: Boolean,
    val keyPropertiesLoadFailed: Boolean,
    val repositoryProtectionResolutionFailed: Boolean,
) {
    fun validationErrors(): List<String> {
        val errors =
            buildList {
                if (hasUnsafeAlternativeKeyPropertiesFile) {
                    add(
                        "CLEAN_NOTES_KEY_PROPERTIES_FILE must be the ignored " +
                            "android/key.properties file or a file outside the repository.",
                    )
                }
                if (keyPropertiesLoadFailed) {
                    add(
                        "The selected release properties file could not be read " +
                            "as UTF-8 Java properties.",
                    )
                }
                if (repositoryProtectionResolutionFailed) {
                    add(
                        "Git repository/worktree protection metadata could not be resolved safely.",
                    )
                }
                if (isPlaceholderApplicationId(applicationId)) {
                    add(
                        "CLEAN_NOTES_APPLICATION_ID must be an owner-approved, " +
                            "non-example Android application ID.",
                    )
                }
                if (storeFile == null) {
                    add("CLEAN_NOTES_STORE_FILE is required.")
                } else if (hasRepositoryLocalStoreFile) {
                    add("CLEAN_NOTES_STORE_FILE must point outside the repository.")
                } else if (!storeFile.isFile || !storeFile.canRead()) {
                    add("CLEAN_NOTES_STORE_FILE must point to a readable keystore file.")
                }
                if (isPlaceholder(storePassword)) {
                    add("CLEAN_NOTES_STORE_PASSWORD is required.")
                }
                if (isPlaceholder(keyAlias)) {
                    add("CLEAN_NOTES_KEY_ALIAS is required.")
                }
                if (isPlaceholder(keyPassword)) {
                    add("CLEAN_NOTES_KEY_PASSWORD is required.")
                }
                val expectedCertificateSha256 =
                    normalizedSha256(uploadCertificateSha256)
                if (isPlaceholder(uploadCertificateSha256) || expectedCertificateSha256 == null) {
                    add(
                        "CLEAN_NOTES_UPLOAD_CERT_SHA256 must be the 64-digit SHA-256 " +
                            "fingerprint of the approved upload certificate.",
                    )
                }
            }

        if (errors.isNotEmpty()) return errors

        val expectedCertificateSha256 = normalizedSha256(uploadCertificateSha256)!!
        return try {
            val keyStore =
                KeyStore.getInstance(storeFile!!, storePassword!!.toCharArray())
            val resolvedKeyAlias = keyAlias!!
            val certificate =
                keyStore.getCertificate(resolvedKeyAlias) as? X509Certificate
            val privateKey =
                keyStore.getKey(resolvedKeyAlias, keyPassword!!.toCharArray())
            buildList {
                if (certificate == null || privateKey !is PrivateKey) {
                    add(
                        "CLEAN_NOTES_KEY_ALIAS and CLEAN_NOTES_KEY_PASSWORD must " +
                            "identify a private-key entry in the upload keystore.",
                    )
                } else {
                    if (isDebugCertificate(certificate, storeFile, resolvedKeyAlias)) {
                        add(
                            "The Android debug certificate is forbidden for release signing.",
                        )
                    }
                    if (certificateSha256(certificate) != expectedCertificateSha256) {
                        add(
                            "The upload certificate does not match " +
                                "CLEAN_NOTES_UPLOAD_CERT_SHA256.",
                        )
                    }
                }
            }
        } catch (_: Exception) {
            listOf(
                "The upload keystore could not be opened with the supplied " +
                    "store password, alias, and key password.",
            )
        }
    }
}

val resolvedStoreFile = resolveStoreFile()
val releaseConfiguration =
    ReleaseConfiguration(
        applicationId =
            externalValue("CLEAN_NOTES_APPLICATION_ID", "applicationId")
                ?.trim(),
        storeFile = resolvedStoreFile?.file,
        hasRepositoryLocalStoreFile =
            resolvedStoreFile?.isRepositoryLocal == true,
        storePassword =
            externalValue("CLEAN_NOTES_STORE_PASSWORD", "storePassword"),
        keyAlias = externalValue("CLEAN_NOTES_KEY_ALIAS", "keyAlias")?.trim(),
        keyPassword = externalValue("CLEAN_NOTES_KEY_PASSWORD", "keyPassword"),
        uploadCertificateSha256 =
            externalValue(
                "CLEAN_NOTES_UPLOAD_CERT_SHA256",
                "uploadCertificateSha256",
            )?.trim(),
        hasUnsafeAlternativeKeyPropertiesFile =
            hasUnsafeAlternativeKeyPropertiesFile,
        keyPropertiesLoadFailed = keyPropertiesLoadFailed,
        repositoryProtectionResolutionFailed =
            repositoryProtectionState.resolutionFailed,
    )

val configuredReleaseApplicationId =
    releaseConfiguration.applicationId
        ?.takeUnless(::isPlaceholderApplicationId)

kotlin {
    compilerOptions {
        jvmTarget = JvmTarget.JVM_17
    }
}

android {
    namespace = "com.example.flutter_clean_notes"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Debug stays runnable with the template ID. Release validation below
        // requires an external, owner-approved ID before an artifact can build.
        applicationId = configuredReleaseApplicationId ?: templateApplicationId
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseConfiguration.storeFile
            storePassword = releaseConfiguration.storePassword
            keyAlias = releaseConfiguration.keyAlias
            keyPassword = releaseConfiguration.keyPassword
        }
    }

    buildTypes {
        debug {
            // A configured production identity must never be shared by a debug build.
            if (configuredReleaseApplicationId != null) {
                applicationIdSuffix = ".debug"
            }
        }
        getByName("profile") {
            // Flutter initializes profile from debug before this script applies
            // debug's suffix, so profile needs its own explicit isolation.
            applicationIdSuffix = ".profile"
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

val validateReleaseConfiguration =
    tasks.register("validateReleaseConfiguration") {
        group = "verification"
        description = "Fails unless Android release identity and upload signing are configured."
        doLast {
            val errors = releaseConfiguration.validationErrors()
            if (errors.isNotEmpty()) {
                throw GradleException(
                    buildString {
                        appendLine("Clean Notes Android release configuration is incomplete:")
                        errors.forEach { appendLine("- $it") }
                        appendLine()
                        appendLine(
                            "Copy android/key.properties.example to the ignored " +
                                "android/key.properties file, or supply the matching " +
                                "direct CLEAN_NOTES_* environment variables.",
                        )
                        appendLine(
                            "For CI, use direct CLEAN_NOTES_* environment variables. " +
                                "Release signing never falls back " +
                                "to the debug key.",
                        )
                    }.trim(),
                )
            }
        }
    }

tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(validateReleaseConfiguration)
}

tasks
    .matching {
        it.name != "validateReleaseConfiguration" &&
            it.name.contains("Release")
    }.configureEach {
        mustRunAfter(validateReleaseConfiguration)
    }

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
