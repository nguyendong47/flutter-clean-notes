pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.12.3" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

val injectedSigningPropertyPrefix = "android.injected.signing."
val gradleProjectSystemPropertyPrefix = "org.gradle.project."
val gradleProjectEnvironmentPrefix = "ORG_GRADLE_PROJECT_"

fun isInjectedSigningPropertyName(propertyName: String): Boolean {
    val unwrappedPropertyName =
        if (propertyName.startsWith(gradleProjectSystemPropertyPrefix, ignoreCase = true)) {
            propertyName.substring(gradleProjectSystemPropertyPrefix.length)
        } else {
            propertyName
        }
    return unwrappedPropertyName.startsWith(injectedSigningPropertyPrefix, ignoreCase = true)
}

val hasInjectedSigningOverride =
    providers
        .gradlePropertiesPrefixedBy(injectedSigningPropertyPrefix)
        .get()
        .isNotEmpty() ||
        gradle.startParameter.projectProperties.keys.any(::isInjectedSigningPropertyName) ||
        System.getProperties().stringPropertyNames().any(::isInjectedSigningPropertyName) ||
        System.getenv().keys.any { environmentName ->
            environmentName.startsWith(gradleProjectEnvironmentPrefix, ignoreCase = true) &&
                isInjectedSigningPropertyName(
                    environmentName.substring(gradleProjectEnvironmentPrefix.length),
                )
        }

if (hasInjectedSigningOverride) {
    throw GradleException("Android injected signing overrides are forbidden.")
}

include(":app")
