# Android final report — isolation fix + verification (task 10-15-sql-release-readiness)

Owner: Android build/isolation worker. Exclusive file:
`android/app/build.gradle.kts`. No other workspace touched. Core consumed
read-only.

- sqlab HEAD at start of this work: `1bfb0cb`; isolation fix committed as
  `84746f1`; final production build at `8461bd6`; final device runs and
  production restore at `30ee9cb`.
- shared core HEAD at capture: `8b33443` ("fix(settings): show active product
  identity in About dialog"; clean, no dirty tracked lib files) — used for
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

- [x] Isolation fix implemented and reviewed by the coordinator (`84746f1`).
- [x] 4-scenario manifest matrix verified (S1–S4 above).
- [x] Integration test APK pre-built and verified (no install): `aapt2 dump
      badging` → `com.azurekiln.qfli.sqlab.integrationtest` (see §3).
- [x] Four native targets run on the physical device (`30ee9cb`):
      curriculum 6/6, mysql 2/2, sql_native 6/6, sql_workbench 1/1 — see §6.1.
      The checker-fixed `mysql_native_test.dart` / `sql_workbench_test.dart` were
      run as-is (not rewritten).
- [x] Final production release rebuild with the switch **unset** — see §5.
- [x] Audit final APK: `zipalign -c -P16 4` (exit 0) and 7 ELF LOAD
      alignments `>= 0x4000` — see §5.
- [x] Production restore on the physical device (in-place, data preserved) —
      see §6.2.
- [x] Root 5-page visual + PID/error check **PASS**; device explicitly released
      (global seq53) — see §6.4.

Remaining (out of this worker's scope): real signing material (store
eligibility); the production APK here is debug-key signed.

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

## 6. Device results (final)

**Device:** physical `OPD2413`, serial **`192.168.68.236:35991`** (arm64-v8a,
API 36). No emulator used; my temporary port-5582 emulator was stopped and Go's
`emulator-5580` was never touched. Runs used `flutter test -d
192.168.68.236:35991 <target>` with the local `QFLI_SQL_INTEGRATION_TEST=1`
switch, so only the disposable `.integrationtest` package was installed (the
production package is never the target of that switch). The Oplus Install Guide
UI was handled by the root coordinator; no concurrent UI input from this worker.

### 6.1 Four native targets on the physical device (TEST_READY `30ee9cb`)

| Target | Result | Log |
| --- | --- | --- |
| `integration_test/sql_curriculum_native_test.dart` | **6/6 passed** | `research/device-curriculum-run.log` |
| `integration_test/mysql_native_test.dart` | **2/2 passed** | `research/device-mysql-native-run.log` |
| `integration_test/sql_native_test.dart` | **6/6 passed** | `research/device-sql-native-run.log` |
| `integration_test/sql_workbench_test.dart` | **1/1 passed** | `research/device-sql-workbench-run.log` |

Curriculum evidence (real Oracle engine, isolated sandbox):
`VERSION()=8.4.6`, `@@version_comment=Source distribution`, `@@skip_networking=1`,
socket and pid file under
`/data/user/0/com.azurekiln.qfli.sqlab.integrationtest/cache/...`, final
`CLEANUP {schemas: removed, runtimeStopped: true}`. 12 PASS markers (6 lessons +
6 exercises), authored outputs matched exactly (`a|3`, `1|Alice@example.com|5`,
`REPEATABLE-READ`, `north|book,pen` / `south|bag`, ...). The earlier abort
(Unix socket >108 bytes) was fixed by the root coordinator shortening only the
test fixture path (`30ee9cb`); **no product code changed**.

Each run rebuilt/installed `app-debug.apk` into the `.integrationtest` package
(~90–170 s install); the Oplus Install Guide was confirmed by root.

### 6.2 Production restore (final)

Restored the saved production APK in place, **no uninstall / no data clear**:

```
adb -s 192.168.68.236:35991 install -r \
  build/release-ready/QFLISQLab-1.0.0-arm64-release.apk
  → Success
```

| Field | Value |
| --- | --- |
| APK | `build/release-ready/QFLISQLab-1.0.0-arm64-release.apk` |
| SHA256 | `9965F512D51022CC5E2AB875EA8F4DDD24F6D467C307B6867657AAA5B39BCD41` |
| Package | `com.azurekiln.qfli.sqlab` (production), `primaryCpuAbi=arm64-v8a` |
| versionName / code | 1.0.0 / 1 |
| firstInstallTime | 2026-10-15 19:04:54 (unchanged; restore used install -r, no uninstall/data clear) |
| lastUpdateTime | 2026-10-15 21:11:26 |
| Launch | `am start -n com.azurekiln.qfli.sqlab/.MainActivity` → started; `pidof` = 28316; `MainActivity` topResumed |
| Crash check | PID 28316 survived all five home destinations; zero matching fatal/unhandled/RenderFlex-overflow lines in available PID logcat; `device-production-final-check.log` |

The disposable `.integrationtest` package was uninstalled by the Flutter test
tooling; only the production package remains. Store-eligibility is still
**blocked** on real signing (debug key only, see §5).

### 6.3 Cleanup / artifacts

- My port-5582 read-only emulator (`Pixel_10`, 2048 MB, `-no-snapshot`,
  `-skip-adb-auth`) was stopped with `adb -s emulator-5582 emu kill`; Go's
  `emulator-5580` was not touched. Logs: `research/emulator-5582.log*`.
- The x86_64 curriculum test APK (emulator fallback) was pre-built and verified
  earlier: package `com.azurekiln.qfli.sqlab.integrationtest`, SHA256
  `73DC5622F5E8187E54DB98750035C684ADF411FF93B2B341B264F0C650D2A9D0`, saved as
  `build/release-ready/QFLISQLab-1.0.0-x64-curriculum-test-debug.apk`; its x64
  native inputs matched the staging audit.
- `build/release-ready/` holds the audited arm64 production APK, the arm64
  curriculum test APK, and the x64 curriculum test APK.

### 6.4 Device release (final)

- Root ran the final 5-page visual check and PID/error check: **PASS**, logged at
  `research/device-production-final-check.log`.
- SQL app force-stopped; the physical device `192.168.68.236:35991` is
  **explicitly RELEASED** (global **seq53**). No further SQL device actions.
- Net device state: production `com.azurekiln.qfli.sqlab` installed (v1.0.0)
  with data preserved; disposable `.integrationtest` package removed.
