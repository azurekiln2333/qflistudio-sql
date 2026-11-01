# Platform worker coordination note (2026-10-15 ~19:25)

## SDK_FREE — Flutter/Gradle/pub/hvigor released

The platform worker has stopped all Flutter tool usage (flutter/dart/gradle/pub/
hvigorw/ohpm). All my Flutter builds have terminated. **wC:p5 may now use the
Flutter tool for the final Android rebuild/install/native integration tests.**

## Ownership split (per coordinator)

- **Android** (final APK rebuild, install, `integration_test/
  sql_curriculum_native_test.dart`): **wC:p5**.
- **OHOS** (final unsigned HAP, native/signing audit): platform worker — done,
  see `ohos-final-hap-audit.md`.

## Android handoff summary (full detail: `android-handoff-p5.md`)

- Working build: `flutter build apk --release --target-platform android-arm64`
  **without `--no-pub`**. `flutter pub get` regenerates the gitignored
  `GeneratedPluginRegistrant.java` in release mode, which drops the
  `integration_test` dev-dependency. That was the whole fix.
- **No repo source file was edited** for this; the registrant is generated and
  gitignored. Nothing uncommitted from the platform worker's Android work.
  Do NOT hand-edit the generated registrant; do NOT remove `integration_test`
  from `dev_dependencies`.
- APK built: 45,742,375 B, SHA256
  `B2CD9E22943DFD0093DA66786EEF6FB2E21036F275C40F122A485F2DFAD3F3ED`; native
  inputs match staging; debug-key signed (sideload/test only); installed+ran on
  `OPD2413` (fresh install, no crash).
- Integration tests use the isolated `.integrationtest` applicationId — safe to
  uninstall that temp package, never the production one.

## OHOS status

- Final unsigned HAP: 193,021,465 B, SHA256
  `24F7024B7D0D5220AB37FFA59FDF448B742584762019F5282E21C7FFC38A3D79`.
- Native + asset audit PASS (HAP libs == final ext4 `--strip-all`; curriculum
  JSONs == repo assets; 397 `dmb` in shipped server image).
- **Blocked on missing `com.azurekiln.qfli.sqlab` signing material** (only jvmx/
  cloudterminal/forge profiles exist). No fabrication, no cross-project signing.
  Signed HAP + OHOS device acceptance remain unverified.
