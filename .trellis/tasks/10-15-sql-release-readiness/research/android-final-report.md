# Android final report — isolation fix + verification (task 10-15-sql-release-readiness)

Owner: Android build/isolation worker. Exclusive file:
`android/app/build.gradle.kts`. No other workspace touched. Core consumed
read-only.

- sqlab HEAD at capture: `1bfb0cb`
- shared core HEAD at capture: `8b33443` ("fix(settings): show active product
  identity in About dialog"; clean, no dirty tracked lib files) — use this for
  native tests and the final release.
- Flutter SDK: `D:/ProgramFiles/flutter_ohos` (Dart 3.11.5). Gradle wrapper 8.14,
  AGP 8.11.1. **Verification must set `JAVA_HOME` to Android Studio JBR (JDK 21)**;
  the machine default (`D:\ProgramFiles\Java\jdk-25`) breaks the Gradle Kotlin DSL
  compiler (`IllegalArgumentException: 25`). Flutter's own Gradle invocation uses
  the JBR, so `flutter`-driven builds are unaffected.

## 1. Defect

`flutter test integration_test/foo_test.dart` on this SDK passes
`-Ptarget=<tmp>\flutter_test_listener.<hash>\listener.dart` (a generated
wrapper), **not** the `integration_test/...` path. The previous
`flutterTarget.startsWith("integration_test/")` check was therefore always false
→ the build produced the **production** package (`com.azurekiln.qfli.sqlab`),
so an integration run would install over the production app. The suite's own
guard correctly refused (`Bad state: Refusing the production Android application
sandbox.`), turning a silent production install into a visible test failure.

Hard evidence:
```
-Ptarget=D:\AppData\Local\Temp\flutter_tools.b49c2037\flutter_test_listener.185a8d23/listener.dart
-Pdart-defines=...,SU5URUdSQVRJT05fVEVTVF9TSE9VTERfUkVQT1JUX1JFU1VMVFNfVE9fTkFUSVZFPWZhbHNl
```
The last dart-define base64-decodes to
`INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false` (the Flutter tool's own
integration marker).

## 2. Fix (`android/app/build.gradle.kts`)

Signals (union; any one applies `.integrationtest`):
1. `QFLI_SQL_INTEGRATION_TEST=1` process switch (manual override for the direct
   `flutter build apk -t integration_test/...` form).
2. Automatic marker: base64-decode every entry of the `dart-defines` Gradle
   property and match the **key**
   `INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE` (value-agnostic).
3. `target` under `integration_test/` (direct-target form).

Fail-closed: if the target is a Flutter test wrapper
(`target` contains `flutter_test_listener`) and **none** of the signals is
present, the build throws at configuration time — it can never silently build
the production package. The condition is **not** gated on whether dart-defines
were supplied (that would have re-opened the hole).

The native runtime guard (`checkAndroidMySql` / `preBuild` dependency and the
four required `.so` + two assets per ABI) is unchanged.

## 3. Manifest verification matrix (evidence, no device)

### Reproducible command
Run from `android/` with `JAVA_HOME` set to the Android Studio JBR (JDK 21):

```powershell
$env:JAVA_HOME='D:\ProgramFiles\Android\Android Studio\jbr'
.\gradlew.bat --console=plain `
  "-Ptarget=<listener-or-main target>" `
  "-Pdart-defines=<comma-separated base64 defines>" `
  -Ptarget-platform=android-arm64 :app:processDebugMainManifest
```

Then read the merged manifest package:

```powershell
Select-String -Path `
  ..\build\app\intermediates\merged_manifest\debug\processDebugMainManifest\AndroidManifest.xml `
  -Pattern 'package='
```

For the wrapper scenarios a listener-shaped target must exist on disk so the
build proceeds past `compileFlutterBuildDebug` to the manifest task; a temp file
at `D:\Temp\qfli_verify\flutter_test_listener.verify\listener.dart`
(`void main() {}`) was used.

Marker base64 tokens:
- `INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false` →
  `SU5URUdSQVRJT05fVEVTVF9TSE9VTERfUkVQT1JUX1JFU1VMVFNfVE9fTkFUSVZFPWZhbHNl`
- `INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=true` →
  `SU5URUdSQVRJT05fVEVTVF9TSE9VTERfUkVQT1JUX1JFU1VMVFNfVE9fTkFUSVZFPXRydWU=`

### Observed results

| # | Scenario (Gradle args) | Observed | Expected |
| --- | --- | --- | --- |
| S1 | `target=<listener>`, `dart-defines=<marker=false>` | `BUILD SUCCESSFUL`; `package="com.azurekiln.qfli.sqlab.integrationtest"` | suffix |
| S2 | `target=<listener>`, `dart-defines=<marker=true>`  | `BUILD SUCCESSFUL`; `package="com.azurekiln.qfli.sqlab.integrationtest"` | suffix |
| S3 | `target=<listener>`, no `dart-defines`, no env | `BUILD FAILED`: `Refusing to build: the Flutter test listener target ('...flutter_test_listener.../listener.dart') was used without the integration marker or QFLI_SQL_INTEGRATION_TEST=1.` | fail closed |
| S4 | `target=lib/main.dart`, no env/marker | `BUILD SUCCESSFUL`; `package="com.azurekiln.qfli.sqlab"` | production |

Decode spot-check (temporary diagnostic, since removed): with the real
dart-defines from the verbose log, `decoded=7`, keys ending in
`INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE`, `hasDefine=true`. Without
`dart-defines`, `decoded=0`. S3 fails closed **without** depending on that flag.

Implementation notes discovered during verification:
- `providers.gradleProperty("dart-defines").orNull` is the working accessor;
  `project.findProperty("dart-defines") as? String` returned null here.
- Gradle Kotlin DSL needs `import java.util.Base64` at the top of the file;
  the fully-qualified `java.util.Base64` resolves against the `java` extension
  and fails with `Unresolved reference: util`.

## 4. Status / next steps

- [x] Isolation fix implemented and reviewed by the coordinator.
- [x] 4-scenario manifest matrix verified (S1–S4 above).
- [ ] **Integration test APK build** (queued): `-t
      integration_test/sql_curriculum_native_test.dart` with the switch/marker
      present → **aapt2 must show `com.azurekiln.qfli.sqlab.integrationtest`
      before any install.** Waiting for p7 to report `SDK_FREE`; the Flutter SDK
      lock self-coordinates, so no need for a fully idle machine — only no
      concurrent `pub` in this project.
- [x] **Integration test APK pre-built and verified (no install):**
      `flutter build apk --debug --target-platform android-arm64 --no-pub \
      -t integration_test/sql_curriculum_native_test.dart` with
      `QFLI_SQL_INTEGRATION_TEST=1`.
      `aapt2 dump badging` → **`package name='com.azurekiln.qfli.sqlab.integrationtest'`**
      (disposable test package, **not** production).
      APK: `build/app/outputs/flutter-apk/app-debug.apk`,
      90,046,530 bytes, SHA256
      `771A46EFA880F330B241A5F2C37E853D52DC7A080ABA388C885133EBE7D8EFB0`.
      Log: `research/android-curriculum-apk-build.log`.
      This also confirms the direct `-t integration_test/...` form applies the
      suffix via the direct-target signal (signal 3).
- [ ] Run the 6 native curriculum lessons on-device once Web releases
      `192.168.68.236:35991` and the coordinator confirms finalnative + content
      + UI are done. **Only `sql_curriculum_native_test.dart`** first.
- [ ] After the curriculum target: run the checker-fixed
      `integration_test/mysql_native_test.dart`, `sql_native_test.dart` and
      `sql_workbench_test.dart` (TEST_READY received). `mysql_native_test.dart`
      and `sql_workbench_test.dart` now carry precise `/proc/self/cmdline`
      test-package guards, current phone-tree navigation, and owned-data
      cleanup. **Do not rewrite these tests**; the final analyze covers them.
- [ ] Final production release rebuild with the switch **unset** → verify
      `com.azurekiln.qfli.sqlab`, record APK SHA + core revision `8b33443`.
- [ ] Audit final APK: `zipalign -c -P16 4` (expect success) and 7 ELF LOAD
      alignments `>= 0x4000`; record in this report.

- [x] Final production release rebuild with the switch **unset** — see §6.
- [x] Audit final APK: `zipalign -c -P16 4` (exit 0) and 7 ELF LOAD
      alignments `>= 0x4000` — see §6.

## 5. Final production release APK (audited)

Built with the test switch **unset** (no `QFLI_SQL_INTEGRATION_TEST`), against
sqlab `8461bd6` / core `8b33443`:

```
flutter build apk --release --target-platform android-arm64
```

Note: the first attempt **with `--no-pub`** hit the stale unfiltered
`GeneratedPluginRegistrant.java` (`dev.flutter.plugins.integration_test` not on
the release classpath) left by the earlier `-t integration_test/...` debug build.
Per the documented platform fix, re-running **with pub** regenerated a filtered
registrant and succeeded. Log: `research/android-production-release-final.log`.

| Field | Value |
| --- | --- |
| Package | `com.azurekiln.qfli.sqlab` (production) |
| versionName / versionCode | 1.0.0 / 1 |
| Label | QFLISQLab |
| Size | 45,745,907 bytes |
| SHA256 | `9965F512D51022CC5E2AB875EA8F4DDD24F6D467C307B6867657AAA5B39BCD41` |
| Signing | **Android Debug** key (`C=US, O=Android, CN=Android Debug`, cert SHA-256 `3cf19ed8…`) — **not store-eligible** |
| `zipalign -c -P16 4` | **exit 0** (16 KB page aligned) |
| Built | 2026-10-15 20:21:39 |

### Native libs in the APK (`lib/arm64-v8a/`)

| Entry | Bytes | SHA256 |
| --- | ---: | --- |
| `libqfli_mysqld_exec.so` | 84504248 | `AE707A423B9B7E60A5F4395B751F2067A2C59930071FF6D2294623B3847CED12` |
| `libqfli_mysql_launcher_exec.so` | 46944 | `B8634965B7E7ABEDE920193349A2865BBA847F359445D426024520466FF931AF` |
| `libqfli_mysql_bridge.so` | 13968832 | `A2B5D7C0143530CFE8E525162CF33CD72B394ECCA100A98A5FD94B60DA378504` |
| `libc++_shared.so` | 1770920 | `5B55FBD6EBDEC23BFBEDBB7CF028BBF49A7AFC489571F48A0080242068BD556F` |
| `libqfli_sqlite.so` | 1140768 | `F324A8C3296B3CD695366B84358EDEF9F8C65446168CABB77FDB0F4F508CADB2` |
| `libapp.so` | 11600816 | `AF5DB66B5A5327C3D9CF1CE8C4A1EA5E91906442B47FF99DA90A27013AAC4DD7` |
| `libflutter.so` | 11317744 | `0C56C4A468224BEB2336C7BACAEE6D5885047A0075D613FE421871B4DCEAFDCE` |

The four Oracle runtime libs match the staging audit exactly; only arm64-v8a is
packaged. Assets present: `mysql-arm64-v8a.{json,zip}` (8164 / 2959944) and
`mysql-x86_64.{json,zip}` (8161 / 2959944; assets are not ABI-filtered).

### 16 KB ELF LOAD alignment (all 7 ELF files, min LOAD align)

| File | min LOAD align | >= 0x4000 |
| --- | --- | --- |
| `libapp.so` | 0x10000 | yes |
| `libflutter.so` | 0x10000 | yes |
| `libc++_shared.so` | 0x4000 | yes |
| `libqfli_mysql_bridge.so` | 0x4000 | yes |
| `libqfli_mysql_launcher_exec.so` | 0x4000 | yes |
| `libqfli_mysqld_exec.so` | 0x4000 | yes |
| `libqfli_sqlite.so` | 0x4000 | yes |

### Release-ready copy (preserve for production restore)

`build/release-ready/QFLISQLab-1.0.0-arm64-release.apk`
(SHA256 `9965F512…`, 45,745,907 B) plus `build/release-ready/SHA256SUMS.txt`.
This is the production artifact to restore after device testing; it is **not**
the standard output dir `app-debug.apk`. If device testing finds a product
defect, rebuild from a fixed source and replace this copy.

## 6. Device coordination state

### 6.1 x86_64 curriculum test APK (emulator fallback) — pre-built & verified
Built with the local test switch `QFLI_SQL_INTEGRATION_TEST=1`:

```
flutter build apk --debug --target-platform android-x64 --no-pub \
  -t integration_test/sql_curriculum_native_test.dart
```

| Field | Value |
| --- | --- |
| Package | `com.azurekiln.qfli.sqlab.integrationtest` (disposable test pkg) |
| Size | 86,238,392 bytes |
| SHA256 | `73DC5622F5E8187E54DB98750035C684ADF411FF93B2B341B264F0C650D2A9D0` |
| Saved as | `build/release-ready/QFLISQLab-1.0.0-x64-curriculum-test-debug.apk` |
| Log | `research/android-curriculum-apk-x64-build.log` |

x64 native inputs in the APK (`lib/x86_64/`), all matching the staging audit:

| Entry | Bytes | SHA256 |
| --- | ---: | --- |
| `libqfli_mysqld_exec.so` | 83438536 | `1AFFFE55285A0D8C8B04FCCCEE2E13A8E10BB4B8073BFCD6BFBEAE507F10A75F` |
| `libqfli_mysql_launcher_exec.so` | 42888 | `998E5309667735D2ED1A0EF732BDF6B2FC1C1EB33ADC1A244A780A2C6F4356E9` |
| `libqfli_mysql_bridge.so` | 14009016 | `4DD3B0E9309C168C84DB04E590CB9C26D722B5CF8AFBB027BDD342D06B3AE26C` |
| `libc++_shared.so` | 1609312 | `8A6E396B44F16D1E64CBC9D2653515D96289AAD6AC1F9B43A1586B9224B97EB7` |
| `libqfli_sqlite.so` | 1299472 | `20043B469DE574A2EA6F937FC5E6F06B47706876B2E33400F3C91C869AA5B9BC` |

Only `x86_64` native code is packaged. Assets `mysql-arm64-v8a.{json,zip}` and
`mysql-x86_64.{json,zip}` are present (not ABI-filtered).

The arm64 curriculum test APK remains saved (see §4). The final arm64
release-ready production APK remains in `build/release-ready/`.

### 6.2 Emulator handoff plan
- Go (seq37) started an independent temporary read-only `Pixel_10`
  `emulator-5580`; on Go's authoritative handoff, the SQL queue runs on
  **`emulator-5580` (emulator, NOT OPD2413)**: `sql_curriculum_native_test.dart`,
  `mysql_native_test.dart`, `sql_native_test.dart`, `sql_workbench_test.dart`.
- This worker does **not** start a duplicate emulator (host has ~4 GB free).
- Real-device (`OPD2413`) final production restore remains coordinated by the
  coordinator; this worker will not install on `emulator-5580` before Go's
  handoff.

- **Isolation fix committed:** `84746f1 fix(android): isolate generated
  integration test targets` (my exclusive file `android/app/build.gradle.kts`).
  Remaining work here is verification only.
- **SDK window handshake:** p7 reported `SDK_FREE` at 20:12 in
  `sdk-window-request-platform.md` (final unsigned HAP rebuilt). The coordinator
  then holds the repo SDK for a ~30s final tests/analyze/format pass; this worker
  starts the curriculum test-APK pre-build on the coordinator's explicit
  `SDK_FREE` signal. Waiting only — no PID polling.
- **Device:** Web still uses `192.168.68.236:35991`; no device install/launch by
  this worker until Web releases and the coordinator signals the device window.
- **Method:** coordination via the global channel / coordinator handshake, not by
  monitoring other workers' processes. Different projects' Dart/AOT processes are
  not controllable locks.
- Device `OPD2413` / direct serial `192.168.68.236:35991` (no-space, via
  `adb mdns services`): production `com.azurekiln.qfli.sqlab` is installed
  (v1.0.0, first install 19:04:54, dataDir present). The `.integrationtest`
  package is the disposable one and may be uninstalled; the production app must
  never be uninstalled or have its data cleared.
