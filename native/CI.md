# Mobile native builds on GitHub

`.github/workflows/native-build.yml` builds native inputs for OHOS, Android
and iOS. It uses hosted runners without Flutter or `qfli_studio_core`.
It does not compile Windows or Linux distributions.

## Run and download

The trial runs on pushes to `ci/native-build-20261117`. It also exposes
`workflow_dispatch`; its manual button requires the workflow on the default branch.
For a manual run, select `target`: `all` (default), `android`, `ohos`, or `ios`.
Selecting one platform retries that platform without rebuilding the others.
Every run includes the corresponding source inputs. Pushes build all platforms.

1. Open https://github.com/azurekiln2333/qflistudio-sql/actions.
2. Select **Mobile native builds**, then a run and its source commit.
3. Inspect each job result. Successful platforms remain downloadable if another fails.
4. Sign in and download the named item under **Artifacts**.
5. Extract the Actions ZIP. For OHOS/Android, verify the outer `SHA256SUMS`
   before extracting the `.tar.gz`. For iOS, extract the `.tar.gz` first.
6. Verify the inner `SHA256SUMS` from the extracted package directory.

Artifacts expire after **14 days**. Download accepted packages and their matching
source inputs for longer retention. This workflow does not publish GitHub Releases.
Every runtime archive contains per-file hashes and source/ABI provenance. Logs
upload separately even after a failure. Logs alone are not runtime packages.
Packages built with the license packaging step include the repository `LICENSE`
and upstream license notices. Check the run's source commit for older artifacts.

| Artifact | Native payload |
| --- | --- |
| `native-ohos-arm64` | SQLite NAPI, four Oracle libraries, dependency closure, resources and licenses |
| `native-android-arm64-v8a` | ARM64 Oracle export under `mysql/`, SQLite under `sqlite/arm64-v8a/` |
| `native-android-x86_64` | x86_64 Oracle export under `mysql/`, SQLite under `sqlite/x86_64/` |
| `native-ios-sqlite` | XCFramework with device arm64 and simulator arm64/x86_64 static libraries |
| `native-source-inputs` | Pinned MySQL/OpenSSL archives and exact repository revision with patches/scripts |
| `native-*-logs` | Build, audit and resource logs |

These are native dependencies, not APK, HAP, IPA or application installers.
Compilation and ABI/dependency checks do not establish device runtime acceptance.

## Local staging

Extract each download into a new directory first. Verify hashes before replacing
an accepted package. Preserve database backups before choosing replacement paths.

### OHOS

Extract `native-ohos-arm64.tar.gz` under `build/mysql-port/package/` after preserving
an existing package. Its layout is:

```text
libs/arm64-v8a/libqfli_sql.so
libs/arm64-v8a/libqfli_mysql.so
libs/arm64-v8a/libqfli_mysql_server.so
libs/arm64-v8a/libqfli_mysql_server_proto.so
libs/arm64-v8a/libqfli_mysql_launcher.so
rawfile/mysql/runtime.json
rawfile/mysql/share/...
rawfile/mysql/licenses/...
```

The current app build still compiles the small SQLite NAPI target. The downloaded
`libqfli_sql.so` also records an SDK compilation check. The large Oracle engine
does not need rebuilding locally. OHOS x86_64 is not built by this workflow.
Platform libc, NAPI and the app's compatible C++ runtime remain platform inputs.

### Android

Keep `mysql/` separate from SQLite. The production stager rejects unexpected
Oracle ELF files. Stage each ABI with the existing script:

```powershell
./native/mysql/android/stage.ps1 -Abi arm64-v8a `
  -Runtime C:/downloads/native-android-arm64-v8a/mysql `
  -ReadElf C:/Android/ndk/27.0.12077973/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-readelf.exe
```

Repeat with `-Abi x86_64` and that artifact's `mysql/` directory if required.
The stager validates architecture, interpreter, dependencies and 16 KiB alignment.
It writes `native/build/mysql-android/jniLibs` and `assets`. The SQLite plugin
still compiles its small C library from source. The separate SQLite binary is an
optional integration artifact; this task does not switch the plugin to prebuilts.

### iOS and macOS

`tool/ci/build-ios-sqlite.sh` uses Xcode to build retained SQLite 3.50.0 and the
project bridge. The current CocoaPods integration still compiles these sources.
The XCFramework is optional native input, not an automatically packaged Flutter app.
There is no iOS Oracle MySQL server host in this project. CI does not substitute
SQLite for MySQL or report an iOS MySQL result.

macOS uses official Oracle MySQL binaries. `native/mysql/macos/bundle.py` compiles
the project bridge/launcher, relocates dependencies and signs helpers. See
[macOS packaging](mysql/macos/README.md) for SDK directories and deployment checks.
Official binary availability does not establish helper/app sandbox acceptance.

The official MySQL 8.4.6 archives below returned HTTP 200 on 2026-11-17:

- ARM64: https://cdn.mysql.com/archives/mysql-8.4/mysql-8.4.6-macos15-arm64.tar.gz
- x86_64: https://cdn.mysql.com/archives/mysql-8.4/mysql-8.4.6-macos15-x86_64.tar.gz

This availability check did not download or verify the archives. Verify their
provenance before use. Inspect the encoded minimum OS before using the current
app's macOS 10.15 deployment setting; do not silently raise app compatibility.

## Inputs and limits

- MySQL 8.4.6 and OpenSSL 3.5.3 hashes match the existing native port scripts.
- Android uses NDK 27.0.12077973, API28, Clang18 and two compiler jobs.
- OHOS uses API23 SDK6.1.0.31 and Clang18. The SDK comes from the
  `openharmony-rs/ohos-sdk` mirror, not an official OpenHarmony GitHub mirror.
  CI checks its pinned archive checksum, installed metadata and required paths.
  The Linux release is 6.1.0.31; the local Windows SDK is 6.1.0.32. CI records
  this difference and does not claim the resulting binaries are byte-identical.
- Fresh runner trees and job timeouts bound builds. Disk, memory or time limits
  remain possible; actual logs determine the result.
- Keep corresponding source archives and licenses with redistributed runtimes.

## Local space

Remote builds avoid keeping local compiler object trees. They do not remove
existing files. `.dart_tool/flutter_build`, Gradle and Hvigor intermediates are
rebuildable caches. Old APK/HAP copies are historical outputs. `build/mysql-port`
also contains production database backups and accepted runtime packages. Never
remove that directory wholesale. The shared WSL disk also contains other projects.

## Workflow validation

Run `actionlint .github/workflows/native-build.yml`, `bash -n` on changed scripts,
and `python -m py_compile tool/ci/package_native.py`. Real runner builds and package
audits provide compilation evidence. A syntax pass alone is not a native build pass.
