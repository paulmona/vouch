import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing. The release workflow passes the upload keystore
// through environment variables (decoded into the runner's temp directory);
// a developer can use android/key.properties instead (never committed). With
// neither, a release build stops: a debug-signed release cannot update a
// properly signed install, and anyone has the debug key.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
fun signingValue(env: String, prop: String): String? =
    System.getenv(env)?.takeIf { it.isNotBlank() } ?: keyProps.getProperty(prop)?.takeIf { it.isNotBlank() }
val uploadStore = signingValue("ANDROID_KEYSTORE_PATH", "storeFile")
val uploadStorePassword = signingValue("ANDROID_KEYSTORE_PASSWORD", "storePassword")
val uploadKeyAlias = signingValue("ANDROID_KEY_ALIAS", "keyAlias")
val uploadKeyPassword = signingValue("ANDROID_KEY_PASSWORD", "keyPassword")
val hasUploadKey = listOf(uploadStore, uploadStorePassword, uploadKeyAlias, uploadKeyPassword).all { it != null }

// App identity. The upstream (Viewbridge) values unless android/vouch.properties
// (gitignored) sets your own; see docs/building-the-app.md.
val vouchProps = Properties().apply {
    val f = rootProject.file("vouch.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}
val vouchApplicationId = vouchProps.getProperty("applicationId") ?: "ai.viewbridge.vouch"
val vouchAppName = vouchProps.getProperty("appName") ?: "Vouch"

android {
    namespace = "ai.viewbridge.vouch"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time; desugar it for the Android runtime.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = vouchApplicationId
        manifestPlaceholders["appName"] = vouchAppName
        // Android 11+: BiometricPrompt with a CryptoObject, StrongBox, and
        // setUserAuthenticationParameters(0, AUTH_BIOMETRIC_STRONG) so the
        // Keystore key needs a fingerprint for every single use.
        minSdk = 30
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Instrumented security tests: ./gradlew connectedDebugAndroidTest
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    signingConfigs {
        if (hasUploadKey) {
            create("release") {
                storeFile = file(uploadStore!!)
                storePassword = uploadStorePassword
                keyAlias = uploadKeyAlias
                keyPassword = uploadKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (hasUploadKey) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// Checked when the task graph is known, so debug builds and IDE syncs work
// without the keystore; only packaging a release needs it.
gradle.taskGraph.whenReady {
    val releasePackaging = allTasks.any {
        it.project == project && it.name in setOf("packageRelease", "signReleaseBundle")
    }
    if (releasePackaging && !hasUploadKey) {
        throw GradleException(
            "No upload keystore (ANDROID_KEYSTORE_* or android/key.properties): " +
                "refusing to build a release signed with anything else."
        )
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // System fingerprint sheet with a Keystore CryptoObject (DeviceKeyChannel).
    implementation("androidx.biometric:biometric:1.1.0")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test:runner:1.6.2")
}

// google-services.json is never committed (it comes from the Firebase console
// locally and from the GOOGLE_SERVICES_JSON_B64 secret in CI). The plugin
// fails the build when the file is missing, so apply it only when present:
// the app still builds and runs without Firebase until pairing needs a push
// token.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
} else {
    logger.warn("Vouch: android/app/google-services.json not found; building without Firebase config.")
}
