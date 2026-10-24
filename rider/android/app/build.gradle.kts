import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Read GOOGLE_MAPS_API_KEY from the Flutter project's .env (same file the
// Dart side reads via flutter_dotenv) so the key isn't duplicated/hardcoded
// in native Android config. Falls back to an empty string if .env or the
// key is missing — the Maps SDK simply fails to load tiles in that case
// rather than breaking the build, so the app still runs (see project.txt's
// "graceful fallback" rule for optional third-party services).
val envFile = File(rootProject.projectDir, "../.env")
val envProperties = Properties()
if (envFile.exists()) {
    envFile.forEachLine { line ->
        val trimmed = line.trim()
        val separatorIndex = trimmed.indexOf("=")
        if (trimmed.isNotEmpty() && !trimmed.startsWith("#") && separatorIndex > 0) {
            envProperties[trimmed.substring(0, separatorIndex).trim()] =
                trimmed.substring(separatorIndex + 1).trim()
        }
    }
}
val googleMapsApiKey: String = envProperties.getProperty("GOOGLE_MAPS_API_KEY", "")

// Real release signing, once you've followed the doc's "Android release
// build" step and created android/key.properties — falls back to the
// debug key when it's absent so `flutter build apk`/`--release` still work
// out of the box for quick test builds before you've set up a keystore.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.izmirimexpress.kurye"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Never change once riders have it installed: Android treats a new
        // id as a different app, so updates would stop installing over it.
        applicationId = "com.izmirimexpress.kurye"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["googleMapsApiKey"] = googleMapsApiKey
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Uses your own keystore once android/key.properties exists (see
            // the doc's "Android release build" step); until then, falls
            // back to the debug key so quick test builds still work.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // AGP 9's release default turned this on with no proguard-rules.pro
            // in the project to protect it — R8 was stripping code that
            // onesignal_flutter's bundled WorkManager/Room dependency reaches
            // only via reflection, crashing every release build on startup
            // with "Failed to create an instance of class
            // androidx.work.impl.WorkDatabase". Off explicitly until real
            // keep rules are written and verified against every plugin.
            isMinifyEnabled = false
            isShrinkResources = false
        }
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
    // FileProvider, for handing a downloaded update APK to the installer
    // (see MainActivity).
    implementation("androidx.core:core-ktx:1.13.1")
}
