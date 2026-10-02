# Oracle MySQL On Android

This port builds upstream Oracle MySQL 8.4.6 for Android/Bionic, using the
existing Oracle C client and JSON FFI. It requires a 64-bit ABI and API 28.
The source, bridge, launcher, resources and application lifecycle must all be
verified before claiming a delivered platform. ARM execution requires a device.

## Inputs

| Input | Version | SHA256 |
| --- | --- | --- |
| Oracle community source | 8.4.6 | `a1e523dc8be96d18a5ade106998661285ca01b6f5b46c08b2654110e40df2fb7` |
| OpenSSL source | 3.5.3 | `c9489d2abcf943cdc8329a57092331c598a402938054dc3a22218aea8a8ec3bf` |
| Android NDK | 27.0.12077973 | Installed NDK input; runtime provenance includes its notices |

Official downloads are listed in `../README.md`. Use Linux Clang/LLVM 18,
LLD, CMake 3.28+, Make and Perl. The toolchain also accepts the Windows NDK's
sysroot and compiler resources from WSL. It uses NDK libc++ headers/libraries
and its static unwind library, not the host C++ runtime. Emulated TLS allows
loading the Oracle client dynamically on API 28. Every LOAD uses at least
16 KiB alignment.

Supply the matching upstream host generators `comp_err`, `comp_client_err`,
`comp_sql`, `uca9dump`, `gen_lex_token`, `gen_keyword_list`, `gen_lex_hash` and
`protoc` (24.4). The host-build configuration in `../build-mysql-ohos.sh` shows
the upstream host targets. Reusing verified generators does not modify OHOS.

## Build And Stage

Use a fresh work directory on the Linux filesystem, separate from other ports.
Preparation fingerprints the verified archive and source patches. A changed
preparation fingerprint requires a fresh source tree; never reset user data.

```bash
export QFLI_MYSQL_ANDROID_WORK=/path/to/android-work
export QFLI_ANDROID_NDK=/path/to/ndk/27.0.12077973
export QFLI_ANDROID_ABI=x86_64 # or arm64-v8a
export QFLI_MYSQL_HOST_TOOLS=/path/to/matching-host-tools
export QFLI_MYSQL_ARCHIVE=/path/to/mysql-8.4.6.tar.gz
export QFLI_OPENSSL_ARCHIVE=/path/to/openssl-3.5.3.tar.gz
bash native/mysql/android/build-openssl.sh
bash native/mysql/android/configure.sh
cmake --build "$QFLI_MYSQL_ANDROID_WORK/android-build-$QFLI_ANDROID_ABI" \
  --target qfli_mysql_bridge qfli_mysql_launcher mysqld --parallel 1
export QFLI_MYSQL_ANDROID_OUTPUT=/path/to/new-runtime-export
bash native/mysql/android/export-runtime.sh
```

From PowerShell, stage that exported directory with the installed NDK's
`llvm-readelf.exe`:

```powershell
./native/mysql/android/stage.ps1 -Abi x86_64 -Runtime /path/to/export `
  -ReadElf /path/to/ndk/toolchains/llvm/prebuilt/windows-x86_64/bin/llvm-readelf.exe
flutter build apk --debug --target-platform android-x64
```

Stage each requested ABI. Ordinary builds accept `android-arm64,android-x64`;
missing inputs fail the Gradle gate. Staging verifies ELF64 ABI, PIE interpreters,
16 KiB LOAD congruence and public/package dependencies. It preserves licenses,
English messages, charsets and ICU data, and writes a content identity and
input hashes. Generated files under `native/build/mysql-android` are ignored.

## Installed Layout

- APK native code is extracted into `applicationInfo.nativeLibraryDir`:
  `libqfli_mysqld_exec.so`, `libqfli_mysql_launcher_exec.so`,
  `libqfli_mysql_bridge.so`, `libc++_shared.so`.
- Resources are atomically provisioned in `files/mysql-resources/<content-id>`.
  Existing resource generations and database data survive app updates.
- Database state is `files/mysql-runtime`; transient files and short private
  sockets use `cache/mysql`. The installer never deletes database state.
- `qfli_sql/mysql_runtime.layout` returns seven absolute paths, consumed by
  `AndroidMySqlRuntime.prepare`. Installation runs off the Android UI thread.
- `LocalMySqlRuntime` owns initialization, credential metadata, locks,
  readiness, serialized FFI and shutdown. It sets native library/TMPDIR/ICU_DATA
  paths. The launcher ties server lifetime to the app parent with PDEATHSIG.

Executable code must not be copied into writable app data. Local transport is
a private Unix socket with a generated credential, and TCP stays disabled.
Oracle version mismatches fail without upgrading or replacing user data.

## Verification

`integration_test/mysql_native_test.dart` uses the installed Android files and
actual engine for initialization/version, exact BIGINT, NULL/binary, prepared
values, ICU regex, rollback/partial scripts, authentication, persistence,
editor execution and real workbench selection/editing/shutdown. Existing
SQLite and desktop suites remain separate checks.
Integration-test entry points receive a separate `.integrationtest` application
ID, since the Flutter test tool uninstalls the test package when it exits.

On 2026-10-02, both integration cases passed on an x86_64 API 37 emulator with
16 KiB pages. Both 64-bit Oracle/OpenSSL builds and their staging audits passed.
ARM execution remains unverified because no ARM device is available.
Android client connections set the upstream `MYSQL_OPT_RETRY_COUNT` option to
handle interrupted Bionic I/O during handshake. This never replays a SQL script.

Release distributions must provide corresponding source archives, patches,
build inputs and application/native sources required by their licenses.
