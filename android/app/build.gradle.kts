import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.inputStream().use { load(it) }
    }
}

val releaseStoreFile = file("keystore.jks")
val releaseStorePassword = localProperties.getProperty("storePassword")
val releaseKeyAlias = localProperties.getProperty("keyAlias")
val releaseKeyPassword = localProperties.getProperty("keyPassword")
val hasReleaseSigning = releaseStoreFile.exists() &&
    releaseStorePassword != null &&
    releaseKeyAlias != null &&
    releaseKeyPassword != null

// setup.dart's `--env` reaches Gradle only through Flutter's base64 dart-defines,
// where a later define wins and an absent APP_ENV means pre, as in Dart.
val dartDefines = (findProperty("dart-defines") as String?)
    .orEmpty()
    .split(",")
    .filter { it.isNotEmpty() }
    .map { String(Base64.getDecoder().decode(it)) }
    .associate { it.substringBefore("=") to it.substringAfter("=", "") }
val isPreChannel = (dartDefines["APP_ENV"] ?: "pre") == "pre"

android {
    namespace = "com.follow.clashx"
    compileSdk = libs.versions.compileSdk.get().toInt()
    ndkVersion = libs.versions.ndkVersion.get()

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "io.portal.xfc"
        // The floor is written once, in the catalog: core, service and common already read it
        // from there, and flutter.minSdkVersion trails whatever Flutter happens to ship.
        minSdk = libs.versions.minSdk.get().toInt()
        targetSdk = libs.versions.targetSdk.get().toInt()
        // Releases up to 0.5.0-pre.8 gave split APKs Flutter's ABI offset of up to +4000, so the
        // code every variant now shares sits above it and any earlier APK upgrades to any variant.
        versionCode = flutter.versionCode + 5000
        // Flutter rewrites local.properties from pubspec.yaml on every build, and pubspec only
        // accepts a semver core, so the shop-facing name is set here where nothing overwrites
        // it. PORTAL_VERSION_NAME lets a build override it without touching this file.
        // The shop-facing name is the pubspec's base version plus the release suffix. Flutter
        // writes `flutter.versionName` into local.properties from pubspec.yaml on every build,
        // so the two cannot drift: bumping pubspec alone bumps what the phone reports.
        val baseVersion = localProperties.getProperty("flutter.versionName") ?: "0.0.0"
        // The owner's name for this line is `0.5.6_1a-portal-duo`: an underscore, which a
        // semver core does not accept, so the base comes from pubspec and the suffix is added
        // here. An explicit PORTAL_VERSION_NAME still wins for a one-off build.
        versionName =
            System.getenv("PORTAL_VERSION_NAME") ?: "${baseVersion}_3a-portal-duo"
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildFeatures {
        resValues = true
    }

    packaging {
        jniLibs {
            // libxray.so is a real shared library, loaded in-process with System.loadLibrary.
            // Legacy packaging keeps it uncompressed in the APK and extracts it to
            // nativeLibraryDir at install: that is where the loader looks, the only
            // directory an app targeting API 29+ may map an executable from, and the layout
            // Flutter's own ABI lookup expects for every .so it ships.
            useLegacyPackaging = true
            // Unstripped on purpose. The library is Go, built -buildmode=c-shared, and its
            // symbol table is what turns a core panic into a stack that names a function
            // instead of an address.
            keepDebugSymbols += "**/libxray.so"
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
            applicationIdSuffix = ".dev"
        }

        release {
            isMinifyEnabled = true
            isShrinkResources = true
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
                if (isPreChannel) {
                    applicationIdSuffix = ".pre"
                    resValue("string", "app_name", "FlClashX Pre")
                }
            } else {
                // A release build without a keystore is a build that must not be shipped: it
                // was silently signed with the debug key and given the .dev id, so an APK that
                // looked like a release installed as a different app on top of nothing and
                // could never be updated by a properly signed one. `flutter run --release`
                // still needs a signing config, so it keeps the debug key; everything else
                // stops here with the reason.
                val forTooling = gradle.startParameter.taskNames.any {
                    it.contains("assembleRelease", ignoreCase = true)
                } && System.getenv("PORTAL_ALLOW_UNSIGNED_RELEASE") == "1"
                if (forTooling) {
                    signingConfig = signingConfigs.getByName("debug")
                    applicationIdSuffix = ".dev"
                } else {
                    throw GradleException(
                        "release build without android/app/keystore.jks and the storePassword/" +
                            "keyAlias/keyPassword entries in local.properties. " +
                            "Set PORTAL_ALLOW_UNSIGNED_RELEASE=1 for a debug-signed test build.",
                    )
                }
            }

            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    sourceSets {
        // Unit tests live under android/tests/ instead of each module's src/test.
        getByName("test").java.setSrcDirs(listOf("../tests/app"))
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(project(":service"))
    implementation(project(":common"))
    implementation(project(":core"))
    implementation(libs.core.splashscreen)
    implementation(libs.gson)
    coreLibraryDesugaring(libs.desugar.jdk.libs)
    testImplementation(libs.junit)
    testImplementation(libs.kotlinx.coroutines.test)
}
