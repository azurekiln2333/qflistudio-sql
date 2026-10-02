plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val flutterTarget = (project.findProperty("target") as? String)?.replace('\\', '/') ?: ""
val isIntegrationTest = flutterTarget.startsWith("integration_test/") ||
    flutterTarget.contains("/integration_test/")
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
