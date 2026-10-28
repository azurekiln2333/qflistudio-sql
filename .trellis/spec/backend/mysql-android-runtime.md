# Oracle Android Runtime

## 1. Scope / Trigger

Read this for Android Oracle build, staging, resource installation, FFI or
local server lifecycle changes. Compilation alone does not establish an
application pass. Apple and ARM execution require their own available hosts.

## 2. Signatures

- `qfli_sql/mysql_runtime.layout()` returns a map of absolute paths:
  `bundleDirectory`, `dataDirectory`, `temporaryDirectory`, `libraryDirectory`,
  `serverPath`, `launcherPath`, `libraryPath`.
- `AndroidMySqlRuntime.prepare()` caches only successful preparation.
  `stop()` stops a prepared server without triggering new installation.
- `LocalMySqlRuntime` adds optional `libraryDirectory`, `pluginDirectory` and
  `temporaryDirectory`. A supplied plugin directory must be used for both
  initialization and normal startup; isolated native tests can retain the
  packaged plugins while keeping their own private data directory.
  The query/script result and existing OHOS C++ signatures remain unchanged.
- `stage.ps1 -Abi <arm64-v8a|x86_64> -Runtime <export> -ReadElf <NDK tool>`
  audits native inputs and writes ignored Android jniLibs/assets.

## 3. Contracts

Build actual Oracle 8.4.6 and OpenSSL 3.5.3 from the pinned archive hashes in
the Android README. Use independent source/build directories and matching
host generators; never execute target generators or reuse OHOS binaries.
The WSL compiler uses NDK27 Bionic/libc++, compiler-rt and static libunwind.
Use emulated TLS for API28 dynamically loaded code and 16 KiB LOAD alignment.
Link the server with Android liblog. Configure the client's MYSQL_OPT_RETRY_COUNT
for interrupted Bionic I/O before connecting; never replay a SQL operation.

Native code lives in extracted nativeLibraryDir. Resources use a versioned,
atomically installed private generation. Message, charset and ICU inputs are
required. Preserve data and prior resource generations on upgrades. The Dart
child environment supplies native library, private temp and ICU data paths.
Initialization and queries reuse the desktop ownership/credentials contract.
Version mismatches fail with user data intact, and TCP cannot be a fallback.
Explicit injected channels retain their existing behavior.

## 4. Validation & Error Matrix

| Condition | Behavior |
| --- | --- |
| Unsupported/missing staged ABI | Packaging fails |
| Wrong ELF ABI/interpreter/alignment/dependency | Staging fails |
| Resource installation fails | Channel reports error; prepare can retry |
| Native files missing or not executable | No server startup |
| Malformed resource identity | Reject before installation |
| Existing data lacks valid initialization metadata | Fail, retain data |
| SQL error after connection | available true, real SQLSTATE/code/message |
| App dies | Parent-bound launcher signals its server |

## 5. Good / Base / Bad Cases

Good: a schema retains BIGINT `9007199254740993` and NULL after server restart.
Base: the installed x86_64 bundle returns Oracle 8.4.6 over its private socket.
Bad: chmod a writable data copy and claim it runs on modern Android, or test
the host Oracle server and report an Android application pass.

## 6. Tests Required

Use `integration_test/mysql_native_test.dart` on an available device for actual
engine, workspace, preferred editor, persistence, credentials and stop checks.
Retain existing SQL/SQLite/desktop tests. Audit every final APK native input,
not only build outputs. Restore the normal application and preserve its data.
An x86_64 pass does not establish ARM execution; missing Apple hosts are skips.
Flutter integration-test targets use the separate .integrationtest application
ID because the test tool uninstalls its application after execution.
Flutter may replace the target with a generated listener path. Decode the
standard Base64 `dart-defines` and detect the
`INTEGRATION_TEST_SHOULD_REPORT_RESULTS_TO_NATIVE` key regardless of its value.
Direct `integration_test/` targets and the process-local
`QFLI_SQL_INTEGRATION_TEST=1` override also select the suffix. A listener without
any integration signal must fail the build. Never make this switch global.
Verify actual merged manifests for marker=false, marker=true, absent signals
and ordinary main builds; inspect the actual APK package with `aapt2` before
any integration installation. Keep the Dart runtime sandbox guard as an
independent check. Never uninstall or clear the production application.
Isolated curriculum fixtures use a short app-private cache directory so the
complete Unix socket path fits in 108 bytes including NUL. Capture the canonical
created-directory identity before startup; verify it again before cleanup and
resolve runtime paths before containment checks because Android may alias
`/data/user/0` to `/data/data`. A timeout retains the active runtime directory;
successful cleanup requires stop completion and PID-file disappearance.
The API 37 x86_64 emulator with 16 KiB pages passed both actual-engine integration
tests on 2026-10-02. Both x86_64 and ARM64 Oracle/OpenSSL builds and four-file
staging audits passed. On 2026-10-15 the physical ARM64 OPD2413 (API 36) passed
both Oracle lifecycle/workbench tests and all six native curriculum tests
(six examples plus six exercises, Oracle 8.4.6, private socket, cleanup).
Evidence is under `10-15-sql-release-readiness/research/device-*-run.log`.
No Apple execution result is established.

## 7. Wrong Vs Correct

Wrong: load a desktop library, omit ICU data, silently fall back to SQLite,
delete a version-mismatched datadir, or include concurrent cloud work unnoticed.

Correct: build/inspect matching Bionic code, use the native installed layout,
preserve real errors and user data, and review narrow owning delivery patches.

## 8. Normal release packaging and installation

Use the standard Flutter pub/tooling path for a normal Android release build.
The current OHOS Flutter SDK skips platform tooling regeneration with `--no-pub`.
A stale debug registrant can then reference `integration_test` in a release APK.
Gradle excludes that development plugin from release dependencies.
The resulting Java compilation fails with a missing `IntegrationTestPlugin` class.

Correct: build with `--pub` so release tooling filters development plugins.
Wrong: manually remove generated Java registrations or alter SDK sources.
A standalone `flutter pub get --offline` generates non-release registration.
It does not establish the release registration correction.
Freeze `pubspec.lock` and require unchanged authored inputs after the build.

For memory-constrained builds, use one Gradle worker and Kotlin in-process.
The bundled snapshot generator accepts `--old_gen_heap_size=512` in MB.
Pass it through `--extra-gen-snapshot-options=--old_gen_heap_size=512`.
This limits the managed old-generation heap, not compiler zone allocations.
Refresh system commit headroom before retrying an actual allocation failure.
Retain each failed attempt and use a fresh runner directory for each retry.

Before installation, inspect the actual APK with `aapt2` and `apksigner`.
Require the intended package, version, ABI and `debuggable=false`.
Distinguish development signing from release compilation and the debug flag.
Reused staged Oracle binaries do not establish a current-source native rebuild.
Use `adb -s <exact-device> push <apk> <staging-path>` and verify its SHA256.
Use `adb -s <exact-device> shell pm install -r <staging-path>` to retain data.
Require installer Success and compare the installed base APK hash.
Check the installed version and exact launch activity before claiming delivery.
A successful launch does not establish Oracle lifecycle or workspace acceptance.
Never uninstall or clear the normal application to work around a signing error.
