# Android release APK — verification result (platform worker)

Date: 2026-10-15. Source: SOURCE_STABLE / UI-stable tree.

## Build

Command:
```
flutter build apk --release --target-platform android-arm64
```
(with `pub get`, so the plugin registrant regenerated correctly)
log: `research/build-android-release-2.log`

**Result: BUILD SUCCESS** — `√ Built build\app\outputs\flutter-apk\app-release.apk (43.6MB)`.

### Artifact

| Field | Value |
| --- | --- |
| Path | `build/app/outputs/flutter-apk/app-release.apk` |
| Size | **45,742,375 bytes** (43.6 MB) |
| SHA256 | `B2CD9E22943DFD0093DA66786EEF6FB2E21036F275C40F122A485F2DFAD3F3ED` |
| Built | 2026-10-15 18:50:58 |

`aapt2 dump badging`: `package name='com.azurekiln.qfli.sqlab' versionCode='1'
versionName='1.0.0' minSdkVersion:'28' targetSdkVersion:'36'
application-label:'QFLISQLab'`.

### Gradle / plugin issue RESOLVED

The earlier failure (`GeneratedPluginRegistrant.java` referenced
`dev.flutter.plugins.integration_test` which wasn't on the release classpath)
was fixed by running the build **with pub** (`flutter pub get` regenerates the
plugin registrant in release mode, which correctly excludes dev-dependency
plugins). Not hand-edited. The regenerated registrant now lists only
`file_selector_android` and `path_provider_android`.

The earlier netty `4.1.72.Final` download failure was transient; those jars are
now cached and resolution succeeds.

### Native inputs audited in the final APK

Extracted from the APK and hashed — **all match the staging audit**:

| APK entry | Size | SHA256 |
| --- | ---: | --- |
| `lib/arm64-v8a/libqfli_mysqld_exec.so` | 84504248 | `AE707A423B9B7E60A5F4395B751F2067A2C59930071FF6D2294623B3847CED12` |
| `lib/arm64-v8a/libqfli_mysql_launcher_exec.so` | 46944 | `B8634965B7E7ABEDE920193349A2865BBA847F359445D426024520466FF931AF` |
| `lib/arm64-v8a/libqfli_mysql_bridge.so` | 13968832 | `A2B5D7C0143530CFE8E525162CF33CD72B394ECCA100A98A5FD94B60DA378504` |
| `lib/arm64-v8a/libc++_shared.so` | 1770920 | (staged) |
| `assets/mysql-arm64-v8a.{json,zip}` | 8164 / 2959944 | present |
| `assets/mysql-x86_64.{json,zip}` | 8161 / 2959944 | present (assets are not ABI-filtered) |

Only `arm64-v8a` native code is packaged (build used `--target-platform
android-arm64`).

### Signing (store-eligibility)

`apksigner verify --print-certs`: **`C=US, O=Android, CN=Android Debug`**,
v2 scheme, RSA 2048, cert SHA-256
`3cf19ed8102760001b3d92f3e4f42a6e322a89ba987d93247b5f9d6afebc0b51`.

⇒ This release APK is **debug-key signed → sideload/test only, NOT
store-eligible** (the `add your own signing config` TODO in
`android/app/build.gradle.kts:70` remains an open release blocker).

## Device install + launch — PASS

Device (explicit serial): `adb-d361e7a0-gqqQSM (2)._adb-tls-connect._tcp`
(OPD2413 / OP615EL1, arm64-v8a, API 36). `com.azurekiln.qfli.sqlab` was **not
installed** anywhere → fresh install, no user data at risk.

- `adb -s <serial> install -r app-release.apk` → **Success**.
- `dumpsys package`: `primaryCpuAbi=arm64-v8a`, `versionCode=1 versionName=1.0.0`,
  firstInstallTime = lastUpdateTime = 2026-10-15 19:04:54.
- Launched `com.azurekiln.qfli.sqlab/.MainActivity`; process alive (`pidof` →
  7531); activity entered resumed state; **no FATAL / AndroidRuntime crash** in
  logcat (only normal `FlutterJNI` frame logs).
- Screenshot captured: `research/android-release-run.png`.

Note: the phone is a shared device (also hosts `com.azurekiln.qfli.goshift` and
other QFLI products, plus unrelated games). The sqlab activity is alive but was
backgrounded by other foreground apps during the check — expected. No other app
was uninstalled/cleared.

## Summary

| Check | Result |
| --- | --- |
| Android release APK compile/package | **PASS** (compiled, not just configured) |
| APK native input audit | **PASS** (hashes match staging) |
| APK install on real arm64 phone | **PASS** |
| APK launch/run on real arm64 phone | **PASS** (process alive, no crash) |
| Store-eligible signing | **FAIL / blocked** (debug key) |
| MySQL engine integration test | NOT RUN (see notes) |

## Not run / limitations

- `integration_test/mysql_native_test.dart` was intentionally **not** run: the
  Flutter integration-test tool uninstalls its `.integrationtest` application
  after execution, and the instruction forbids running tests that uninstall
  production apps on this shared device. The APK-level install/launch above is
  the device evidence collected.
- The MySQL engine end-to-end (init/CRUD/persistence) on Android ARM remains
  **unverified** in this session; it requires the integration harness, which is
  out of scope per the device-preservation constraint.
