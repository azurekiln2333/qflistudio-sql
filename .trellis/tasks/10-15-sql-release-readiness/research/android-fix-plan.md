# Android release build — root cause & fix plan (task 10-15-sql-release-readiness)

Owner: Android repo-level build-fix worker. Exclusive scope:
`android/settings.gradle.kts`, `android/app/build.gradle.kts`, and build scripts
only when strictly required. **No** edits to UI, curriculum, `native/`, or
`../qfli_studio_core`. This is a plan report; no source has been changed yet.

Repository: `D:/MyNewProjects/qfli_sql` (verified cwd). Prior UI work already
committed as `0eb72c7`.

## 1. Symptom

```
flutter build apk --release --target-platform android-arm64 --no-pub
  → :app:compileReleaseJavaWithJavac FAILED
  GeneratedPluginRegistrant.java:24: 程序包 dev.flutter.plugins.integration_test 不存在
    flutterEngine.getPlugins().add(new dev.flutter.plugins.integration_test.IntegrationTestPlugin());
```
Log: `research/build-android-release.log`. The wrapper's later
`research/build-android-release-2.log` shows **BUILD SUCCESS** when the build is
run **with pub** (`flutter pub get` first).

## 2. Investigation (read-only; no repo file changed)

### 2.1 Current on-disk state is already correct
`android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java`
(untracked; `android/.gitignore:7` ignores it) currently registers **only**
`file_selector_android` and `path_provider_android` — the dev-only
`integration_test` plugin is **absent**. So the file shown in the failing log is
a **stale** version that has since been regenerated.

### 2.2 The plugin metadata marks integration_test as a dev dependency
`.flutter-plugins-dependencies` (generated) records, for `android`:
`{"name":"integration_test", ... "dev_dependency":true}` alongside the real
plugins with `"dev_dependency":false`. `pubspec.yaml` declares
`integration_test` under **`dev_dependencies`** (`sdk: flutter`).

### 2.3 SDK behavior that produces the bug (authoritative source read)
`D:/ProgramFiles/flutter_ohos/packages/flutter_tools` (Dart 3.11.5, the only
usable SDK; the stock Flutter 3.9/Dart 3.9 SDKs cannot satisfy
`environment: sdk: ^3.11.5`):

- `runner/flutter_command.dart`
  - `bool get shouldRunPub => _usesPubOption && boolArg('pub');`
  - `verifyThenRunCommand` only runs `pub.get` **and**
    `regeneratePlatformSpecificToolingIfApplicable` when `shouldRunPub` is true.
  - `regeneratePlatformSpecificToolingIfApplicable` **returns early when
    `!shouldRunPub`** (`if (!shouldRunPub) { return; }`), with an explicit code
    comment referencing flutter/flutter#162649.
- `flutter_plugins.dart`
  - `injectPlugins(..., required bool releaseMode, ...)`:
    ```dart
    final List<Plugin> filteredPlugins;
    if (releaseMode) {
      filteredPlugins = plugins.where((p) => !p.isDevDependency).toList();
    } else {
      filteredPlugins = plugins;
    }
    ...
    if (androidPlatform) {
      await _writeAndroidPluginRegistrant(filteredPluginsByPlatform[AndroidPlugin.kConfigKey]!);
    }
    ```
  - So the Android registrant is filtered **only** when `injectPlugins` is called
    with `releaseMode: true`, which only happens through the
    `regeneratePlatformSpecificTooling` path.

### 2.4 Root cause (definitive)
`--no-pub` sets `boolArg('pub') = false` → `shouldRunPub = false` → **both**
`pub get` and `regeneratePlatformSpecificTooling`(=`injectPlugins`) are skipped.
Therefore, under `--no-pub`, the Flutter tool **never rewrites
`GeneratedPluginRegistrant.java`**. It compiles whatever is on disk.

The stale on-disk registrant was written by a **non-release** invocation
(e.g. `flutter test integration_test/...` or `flutter run`, which call
`injectPlugins(releaseMode: false)` and therefore *include* the dev-only
`IntegrationTestPlugin`). The next `--no-pub` **release** build then compiles that
unfiltered registrant, whose `dev.flutter.plugins.integration_test` class is not
on the release compile classpath, and `javac` fails.

This exactly matches the observed evidence: with pub the registrant is
regenerated filtered → success; without pub the stale unfiltered registrant →
failure.

### 2.5 What is NOT the cause (ruled out)
- `android/settings.gradle.kts` is **not** misconfigured: it matches the SDK
  template verbatim (`include(":app")` only
  `templates/app/android.tmpl/settings.gradle.kts.tmpl`). There is intentionally
  no `:integration_test` Gradle subproject; the registrant is expected to omit it
  in release.
- The plugin loader/dev-dependency filtering is **not** inconsistent for Android:
  Android uses the filtered list. (A genuine SDK defect exists for **OHOS**:
  `injectPlugins` calls `_writeOhosPluginRegistrant(project, plugins)` with the
  **unfiltered** `plugins`, i.e. OHOS never strips dev deps. That is out of this
  Android scope and belongs to the OHOS worker / an SDK note.)
- The `GeneratedPluginRegistrant.java` must **not** be hand-edited, and the
  `integration_test` dev dependency must **not** be removed.

## 3. Fix options

### Option A (recommended) — repo-level pre-build guard that regenerates the
registrant in release mode, so `--no-pub` builds are self-consistent.
Provide a small Gradle task in `android/app/build.gradle.kts` wired to run
before `preBuild`/`compileReleaseJavaWithJavac`, which invokes the Flutter tool's
plugin injection with `releaseMode = true`. The public, stable surface for this
is the `flutter` CLI itself:

```
flutter pub get          # or: flutter build apk --release ... (without --no-pub)
```

But a Gradle task cannot call "inject plugins with releaseMode" directly; the
`--no-pub` skip is inside the tool. The robust, minimal and maintainable repo
fix is therefore to make the **build invocation** correctness part of the repo:

- Add a documented wrapper build script (e.g. `tool/build_android_release.ps1`)
  that runs `flutter pub get` and then `flutter build apk --release
  --target-platform android-arm64` **without `--no-pub`**, and have it assert the
  registrant contains no `IntegrationTestPlugin` before Gradle runs.
- Optionally also add a Gradle `check` that fails fast with a clear message if
  `GeneratedPluginRegistrant.java` contains `integration_test` while building a
  release variant — turning a cryptic `javac` error into an actionable one.
  This guard is release-only and does not remove the test dependency.

This keeps the fix repo-level, avoids editing generated files, keeps the dev
dependency, and does not depend on SDK internals.

### Option B (rejected) — exclude the registration in `android/app/build.gradle.kts`
Add a release-only ExcludePattern / filter so a stale line is tolerated.
Rejected: it would silently mask any future dev-plugin leak, is fragile against
the template, and does not address the real cause (skipped regeneration).

### Option C (rejected) — remove `integration_test` from dev_dependencies
Rejected by instruction: it fakes a fix and destroys the test target.

### Option D (rejected) — hand-edit `GeneratedPluginRegistrant.java`
Rejected: generated file; `android/.gitignore` ignores it; will be overwritten.

## 4. Planned minimal changes (Option A)

1. `android/app/build.gradle.kts` — add a **release-only** verification task
   (e.g. `verifyReleasePluginRegistrant`) that runs before
   `compileReleaseJavaWithJavac` and fails with a clear message if the on-disk
   registrant references `dev.flutter.plugins.integration_test`. Release-scoped,
   no behavior change for debug/test builds, no generated-file edit.
2. `tool/build_android_release.ps1` — documented, reproducible release build
   that runs `pub get` then `flutter build apk --release
   --target-platform android-arm64` (no `--no-pub`), then performs the native
   dependency/hash + signing audit and writes logs under `research/`.
3. No change to `android/settings.gradle.kts` (already correct). No change to
   UI/curriculum/native/core.

I will only adopt change (1) if it is genuinely needed after reproducing with the
recommended invocation; the guard must be real and correct, not cosmetic.

## 5. Environment facts (captured)

- cwd: `D:/MyNewProjects/qfli_sql` (verified).
- Flutter SDK: `D:/ProgramFiles/flutter_ohos`, `Flutter 3.27.5-ohos-1.0.1`,
  **Dart 3.11.5** (satisfies `environment.sdk: ^3.11.5`; stock Dart 3.9 SDKs are
  unusable and must not be upgraded).
- Gradle wrapper: `gradle-8.14-all`; AGP `8.11.1`; Kotlin `2.2.20`.
- `android/local.properties`: `sdk.dir=D:\ProgramData\Android\Sdk`,
  `flutter.sdk=D:\ProgramFiles\flutter_ohos`, release mode.
- Android namespace/applicationId: `com.azurekiln.qfli.sqlab`; integration
  target suffix `.integrationtest`.
- Device (explicit serial): `adb-d361e7a0-gqqQSM (2)._adb-tls-connect._tcp`
  (OPD2413, arm64-v8a, API 36). `com.azurekiln.qfli.sqlab` **not installed** →
  fresh install, no production app uninstall/clear.
- `android/` currently has **no** dirty tracked files (baseline preserved).

## 6. Coordination gate before building

`wC:p7` is doing OHOS work. At investigation time a live debug integration run
was observed holding the tool:

```
dart.exe ... flutter_tools.snapshot test -d 192.168.68.236:35991 \
  integration_test/nginx_runtime_test.dart --reporter expanded
(pid 51832, started 2026-10-15 19:15:39; Gradle daemon 8.14 also live)
```

This is direct live confirmation of §2.4: a **debug** `flutter test` invocation
runs `injectPlugins(releaseMode: false)` and therefore rewrites
`GeneratedPluginRegistrant.java` **unfiltered** (including the dev-only
`IntegrationTestPlugin`). The very next `--no-pub` release build then compiles
that unfiltered registrant and fails.

I will **not** run `pub get`/builds while this run holds the tool. Before building
I will re-confirm the lock is free and that nobody else is running `pub get` or
editing plugin metadata. I will not edit shared plugin metadata in
`../qfli_studio_core` or the SDK.

## 7. Acceptance / deliverables for the implementation phase

- Final **arm64-v8a release APK** produced with the recommended invocation, path
  and SHA-256 recorded.
- Native-dependency audit of the APK (`libqfli_mysql*.so`, `libc++_shared.so`,
  `assets/mysql-*.json/zip`), matched against `native/build/mysql-android`
  staging, plus explicit **debug-key signing** finding.
- Install attempt on the explicit ADB serial (fresh install, no uninstall of
  production apps / no data clear), launch check, logcat.
- All results and logs written to
  `research/android-final-report.md` (+ raw logs under `research/`).
- Clear statement of environment vs. source-code issues.

## 8. Status — CORRECTED after re-reading current state

The original blocker log (`build-android-release.log`) is **stale**. p7 already
built and installed the Android release APK at **18:50** (`android-release-result.md`,
`platform-report.md` §6). No builds or source changes are being made now.

### 8.1 What p7 actually did — NOT a hack, but not repo-level either

`android-release-result.md` states the fix was: run the build **with pub**
(drop `--no-pub`) so the Flutter tool regenerates `GeneratedPluginRegistrant.java`
in release mode, which filters out the dev-only `integration_test` plugin.

Verified independently in the repo:
- `git status --short -- android/` is **empty** and `git diff HEAD --stat -- android/`
is **empty** → **p7 made no repo-level Gradle change**; the fix was purely the
build invocation.
- The registrant is untracked/ignored (`android/.gitignore:7`), its header says
"Generated file. Do not edit.", and it currently contains **only**
`file_selector_android` + `path_provider_android` (no `IntegrationTestPlugin`)
→ it is tool-generated, **not hand-edited**. There is no hand-edit to clean up.

Verdict on maintainability: the current method is *correct* but **not
repeatable-by-construction**. Correctness depends on the operator remembering to
run with pub / omit `--no-pub`. The failure mode was already observed live: a
**debug** `flutter test integration_test/...` (running at investigation time, pid
51832) rewrites the registrant **unfiltered**, and a subsequent `--no-pub`
release build would compile it and fail. To make this durable, the repo-level
Option A fix (a documented release build script + a release-only fast-fail guard
in `android/app/build.gradle.kts`) is still the right *incremental* hardening —
but it is **not required to unblock** since the correct invocation already works
and no source hack exists.

### 8.2 p7's artifact is real but NOT the final ASSETS_STABLE build

- `build/app/outputs/flutter-apk/app-release.apk`, 45,742,375 B,
  SHA256 `B2CD9E22…`, built 18:50:58 — matches the report exactly.
- **But** `assets/content/sql_tutorials.json` + `sql_examples.json` were modified
  at **19:09:04**, i.e. **after** the 18:50 build, and are still dirty in git
  (`sql_examples.json` +504 lines). The curriculum worker is not done.
- The live `dart.exe` (pid 51832, started 19:15:39) is still running an
  integration test and holds the Flutter tool lock.

⇒ The 18:50 APK is **superseded**; re-verifying it now would certify stale
assets. Per instruction, I will **not** rebuild. The correct next step is to
wait for **ASSETS_STABLE**, then re-verify (build with pub, audit native hashes,
install on the explicit serial). No such step is started here.

### 8.3 Not repeated / not re-investigated

Per instruction, the already-resolved plugin issue is **not** re-investigated.
The root-cause analysis in §2 remains valid as background and directly explains
*why* the with-pub invocation works and why `--no-pub` is unsafe here.

## 8. Integration-test isolation fix (Android) — implemented, pending build verification

### 8.1 Hard evidence of the defect
- Built `app-debug.apk` manifest package via `aapt2 dump badging`:
  **`com.azurekiln.qfli.sqlab`** — the `.integrationtest` suffix was **not**
  applied, so the suite ran in the production sandbox. The suite's own guard
  correctly refused: `Bad state: Refusing the production Android application
  sandbox.` (protection worked; isolation did not).
- Actual Gradle invocation captured with `--verbose`:
  ```
  -Ptarget=D:\AppData\Local\Temp\flutter_tools.b49c2037\flutter_test_listener.185a8d23/listener.dart
  -Pdart-defines=...,SU5URUdSQVRJT05fVEVTVF9TSE9VTERfUkVQT1JUX1JFU1VMVFNfVE9fTkFUSVZFPWZhbHNl
  ```
  i.e. `flutter test integration_test/foo_test.dart` **rewrites `target` to a
  generated wrapper** (`flutter_test_listener.<hash>/listener.dart`), not the
  `integration_test/...` path. The previous
  `flutterTarget.startsWith("integration_test/")` check was therefore always
  false for `flutter test`-driven builds.
- The 7th dart-define base64-decodes to
  `INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE=false` (confirmed by decode),
  but `target`/dart-define path-shape guessing is not a stable contract.

### 8.2 Fix applied (repo-level, `android/app/build.gradle.kts`)
Primary signal is an explicit process-level env switch set **only** by the
integration build/test invocation; the direct-target check is retained:

```kotlin
val flutterTarget = (project.findProperty("target") as? String)?.replace('\\', '/') ?: ""
val hasIntegrationTestSwitch =
    providers.environmentVariable("QFLI_SQL_INTEGRATION_TEST").orNull == "1"
val isIntegrationTest = hasIntegrationTestSwitch ||
    flutterTarget.startsWith("integration_test/") ||
    flutterTarget.contains("/integration_test/")
```

- Production `flutter build apk --release` never sets the env var → production
  package unaffected.
- No generated-file edits, no removal of the suite's own guard, no global
  env/SDK change.
- Build/test wrappers will set `QFLI_SQL_INTEGRATION_TEST=1` for the process only
  and clear it in `finally`.

### 8.3 Verification plan (not yet run)
1. `flutter build apk --debug --target-platform android-arm64
   -t integration_test/sql_curriculum_native_test.dart` (with the env switch set)
   → then `aapt2 dump badging` must show
   `com.azurekiln.qfli.sqlab.integrationtest` **before** any install.
2. Then `flutter test` with the same switch.
3. Finally rebuild/serve the production release with the switch **unset** and
   re-verify the production package id, preserving production data.

### 8.4 Device coordination (cross-team, no SQL code/task change)
- wA:p1 (Python coordinator) requested a ~3 min device window for wA:p8 on
  OPD2413 / `192.168.68.236:35991`.
- This worker was **not** using the device and had **no** install/run in
  progress → reported the device **free**; no logcat cleared, no app uninstalled,
  no SQL data touched. This worker stays off the device until the isolation fix
  is verified with a build + aapt2 package check.

## 9. Status summary

- Investigation of the (now-resolved) blocker: complete; log was stale.
- p7 compatibility method: confirmed = correct build invocation, no hand-edit,
  no repo change. Not a hack; optionally hardened by Option A.
- Re-verification target: **blocked on ASSETS_STABLE** (assets changed 19:09:04,
  tool lock still held by pid 51832). No build/source action taken.
