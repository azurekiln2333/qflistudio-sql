import java.util.Base64

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Detects an integration-test build so the app installs as a separate
// `.integrationtest` package instead of the production one. Any install built
// from an integration target MUST NOT land on the production package id.
//
// The Flutter tool identifies an integration build with the Dart-define
// `INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE` (value `false` for
// `flutter test integration_test/...`). Dart-defines arrive on the Gradle
// command line base64-encoded, one per comma-separated entry, so we decode
// them and look for the **key** (value-agnostic) — this is the tool's own
// integration semantics, not a guess about the generated wrapper path.
//
// Signals, in order of reliability:
//  1. explicit process switch `QFLI_SQL_INTEGRATION_TEST=1` (manual override for
//     the direct `flutter build apk -t integration_test/...` form);
//  2. the integration Dart-define marker above (automatic, covers
//     `flutter test integration_test/...`);
//  3. `target` under `integration_test/` (direct target form).
//
// Fail-closed: a `flutter test` listener wrapper target ("flutter_test_listener")
// with none of the signals above is refused at configuration time, so it can
// never silently build the production package. Signals are a union: any one of
// them applies the `.integrationtest` suffix.
val flutterTarget = (project.findProperty("target") as? String)?.replace('\\', '/') ?: ""
val integrationDefineKey = "INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE"
val dartDefinesProperty = providers.gradleProperty("dart-defines").orNull
val decodedDartDefines = dartDefinesProperty
    ?.split(',')
    ?.filter { it.isNotBlank() }
    ?.mapNotNull { encoded ->
        runCatching {
            String(Base64.getDecoder().decode(encoded), Charsets.UTF_8)
        }.getOrNull()
    }
    ?: emptyList<String>()
val hasIntegrationTestDefine = decodedDartDefines.any {
    it.substringBefore('=') == integrationDefineKey
}
val hasIntegrationTestSwitch =
    providers.environmentVariable("QFLI_SQL_INTEGRATION_TEST").orNull == "1"
val hasIntegrationTarget = flutterTarget.startsWith("integration_test/") ||
    flutterTarget.contains("/integration_test/")
if (!hasIntegrationTestDefine && !hasIntegrationTestSwitch &&
    !hasIntegrationTarget && flutterTarget.contains("flutter_test_listener")
) {
    // A `flutter test` wrapper was used without any integration marker: this is
    // the dangerous case that must never silently build the production package.
    // Fail closed regardless of whether any dart-defines were supplied.
    throw GradleException(
        "Refusing to build: the Flutter test listener target " +
            "('$flutterTarget') was used without the integration marker or " +
            "QFLI_SQL_INTEGRATION_TEST=1. Run integration tests through " +
            "'flutter test integration_test/...' or set QFLI_SQL_INTEGRATION_TEST=1.",
    )
}
val isIntegrationTest = hasIntegrationTestSwitch ||
    hasIntegrationTestDefine ||
    hasIntegrationTarget
val mysqlAbiMapping = mapOf("android-arm64" to "arm64-v8a", "android-x64" to "x86_64")
val mysqlPlatforms = (project.findProperty("target-platform") as? String)
    ?.split(",") ?: mysqlAbiMapping.keys.toList()
val mysqlAbis = mysqlPlatforms.map { target ->
    mysqlAbiMapping[target] ?: throw GradleException("Oracle Android supports only android-arm64 and android-x64")
}

android {
    namespace = "com.azurekiln.qfli.sqlab"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.azurekiln.qfli.sqlab"
        if (isIntegrationTest) applicationIdSuffix = ".integrationtest"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(28, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters.clear()
            abiFilters += mysqlAbis
        }
    }

    sourceSets.getByName("main") {
        jniLibs.srcDir("../../native/build/mysql-android/jniLibs")
        assets.srcDir("../../native/build/mysql-android/assets")
    }

    packaging {
        jniLibs.useLegacyPackaging = true
        jniLibs.keepDebugSymbols += "**/libqfli_mysql*.so"
        jniLibs.keepDebugSymbols += "**/libc++_shared.so"
        jniLibs.pickFirsts += "**/libc++_shared.so"
    }

    buildTypes {
        configureEach {
            ndk {
                abiFilters.clear()
                abiFilters += mysqlAbis
            }
        }
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

val checkAndroidMySql by tasks.registering {
    doLast {
        check(mysqlPlatforms.isNotEmpty()) {
            "Oracle Android supports only android-arm64 and android-x64"
        }
        val base = rootProject.file("../native/build/mysql-android")
        for (abi in mysqlAbis) {
            for (name in listOf("libqfli_mysqld_exec.so", "libqfli_mysql_launcher_exec.so", "libqfli_mysql_bridge.so", "libc++_shared.so")) {
                check(file("$base/jniLibs/$abi/$name").isFile) {
                    "Stage Android Oracle $abi using native/mysql/android/stage.ps1: missing $name"
                }
            }
            check(file("$base/assets/mysql-$abi.json").isFile && file("$base/assets/mysql-$abi.zip").isFile) {
                "Stage Android Oracle resources for $abi"
            }
        }
    }
}
tasks.named("preBuild").configure { dependsOn(checkAndroidMySql) }

flutter {
    source = "../.."
}
