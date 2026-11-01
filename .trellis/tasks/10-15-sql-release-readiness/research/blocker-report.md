# Blocker report → coordinator (platform worker)

Reported: 2026-10-15. Requesting an owner assignment; **no source edited.**

## BLOCKER 1 (hard, blocks both APK and HAP): `SqlTerminalCommands` undefined

- File: `lib/main.dart` line 36:
  `terminalCommandDelegate: SqlTerminalCommands.execute,`
- `flutter analyze lib` output (only 2 errors, same site):
  ```
  error - Invalid constant value - lib/main.dart:36:28 - invalid_constant
  error - Undefined name 'SqlTerminalCommands' - lib/main.dart:36:28 - undefined_identifier
  ```
- `SqlTerminalCommands` is referenced in exactly one place in `lib/` and is
  **defined nowhere**. This is the terminal/offline worker's in-flight edit
  (they own runner + engine preference + terminal command delegate).
- Effect: `flutter build apk` fails at
  `:app:compileFlutterBuildRelease` → `Target kernel_snapshot_program failed`
  (`Error: Undefined name 'SqlTerminalCommands'`). The OHOS HAP build would fail
  identically at AOT compile.
- Tree is still actively changing (git modified count 122→126→127 during my
  session; `lib/sql_document_service.dart` written 18:14).

**Request:** Have the terminal worker land the `SqlTerminalCommands` definition
(or temporarily remove the `terminalCommandDelegate:` line if the feature is not
landing now), then tell me the tree is source-frozen. I will then immediately run
the Android release APK and OHOS release HAP builds. I will NOT edit `lib/` myself.

Context for the owner: `terminalCommandDelegate` is a shared-core contract
(`qfli_studio_core/lib/services/studio_profile.dart:157`
`final TerminalCommandDelegate? terminalCommandDelegate;`, consumed by
`editor/terminal_pane.dart:440` and `pages/terminax_terminal_page.dart:42,109`).
`SqlTerminalCommands` must be a new qfli_sql-local class exposing a static
`execute` matching `TerminalCommandDelegate`. It has no other reference in
`lib/`, `test/`, or `integration_test/`.

## BLOCKER 2 (soft, environment): Gradle `:integration_test` netty resolution

- First release attempt (3m37s) failed configuring project `:integration_test`:
  could not download `io.netty:netty-*-4.1.72.Final` and
  `org.checkerframework:checker-qual:3.12.0` — `Remote host terminated the
  handshake` (TLS) from `repo.maven.apache.org`.
- The Gradle cache has **empty** `4.1.72.Final` dirs (failed download); full
  `4.1.110.Final`/`4.1.93.Final` jars are cached.
- Direct HTTPS HEAD to Maven Central and Google Maven now returns **HTTP 200** →
  likely transient. I will retry automatically after Blocker 1 clears.
- `:integration_test` is the Flutter `integration_test` package's Android module
  (classpath pulls `androidx.test:runner:1.2+`); netty version is not controlled
  by this repo. **No source/Gradle edit made.**

## Findings already delivered (research/platform-report.md)

- Toolchain: build BOTH platforms with `flutter_ohos` (Dart 3.11.5). The standard
  Flutter 3.35.3 SDKs are unusable (broken/3.9.2 < pubspec `^3.11.5`); not touched.
- Native staging integrity **OK** (Android both ABIs 4 files+2 assets each; OHOS
  arm64 4 libs + 73 rawfile files / 5,139,034 B). Hashes recorded.
- Identity/signing: package/bundle `com.azurekiln.qfli.sqlab`, label `QFLISQLab`.
  **Android release is debug-key signed** (gradle TODO at
  `android/app/build.gradle.kts:70`). OHOS uses DevEco auto debug cert
  (`appProvisionType=debug`). ⇒ both release artifacts are **sideload/test-only,
  not store-eligible**; production signing material must NOT be fabricated here.
  Test-only package `com.azurekiln.qfli.sqlab.integrationtest` (uninstalled by
  flutter test tooling — must not be used on the shared device per instructions).
- Devices (explicit serials): Android `adb-d361e7a0-gqqQSM (2)._adb-tls-connect._tcp`
  (OPD2413, arm64-v8a, API 36) — app **not installed** (fresh install, no data risk);
  OHOS `192.168.68.207:46551` — app **installed** (v1.0.0, debug), data must be
  preserved via in-place upgrade.
