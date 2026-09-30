# Oracle MySQL port experiment

## Required engine

The user explicitly requires Oracle MySQL. MariaDB and SQLite do not satisfy
the final runtime requirement. The workbench and runner now default to
Oracle; device acceptance remains pending.

## Source inputs

- Oracle MySQL 8.4.6:
  `https://cdn.mysql.com/archives/mysql-8.4/mysql-8.4.6.tar.gz`
- Downloaded size: 479211975 bytes.
- Computed SHA256:
  `a1e523dc8be96d18a5ade106998661285ca01b6f5b46c08b2654110e40df2fb7`.
- Extracted source: `build/mysql-port/mysql-8.4.6/`.
- OpenSSL 3.5.3 archive verified against its upstream checksum:
  `c9489d2abcf943cdc8329a57092331c598a402938054dc3a22218aea8a8ec3bf`.
- OpenSSL source and partial objects are in
  `build/mysql-port/openssl-3.5.3/` and `openssl-build/`.

These source trees and experiments are ignored build artifacts. The compiled
Oracle runtime is staged at `build/mysql-port/package`. Release packaging must include source
provenance, reproducible patches/build inputs, and the upstream license notices.

## Available toolchain

- WSL distro `qfli-java-build` works; the default `Ubuntu` distro has a missing VHD.
- Host tools: Clang 18.1.3, CMake 3.28.3, Make, Perl, Git, Bison 3.8.2,
  pkg-config, and host OpenSSL development files.
- Target SDK:
  `D:/ProgramFiles/Huawei/OpenHarmony/Sdk/23/native`.
- The exploratory `build/mysql-port/ohos-toolchain.cmake` uses Clang's
  `aarch64-linux-ohos` target, the SDK sysroot and libc++ headers, and SDK target
  runtime libraries. A C shared-library probe linked successfully and `file`
  identified it as ARM aarch64 ELF.

## Actual configure result

Oracle MySQL C and C++ compiler checks succeeded. CMake proceeded through POSIX
header/function checks and bundled Boost/zlib/zstd setup. It then reported:

1. `try_run` needs `HAVE_SETNS_EXITCODE`, `HAVE_CLOCK_GETTIME_EXITCODE`, and
   `HAVE_CLOCK_REALTIME_EXITCODE` because ARM programs cannot run on this host.
2. Target OpenSSL headers/libraries are absent from the stock SDK.

Do not fill these probe results with invented successful values. Optional
namespace/timing features can be disabled deliberately where source provides
fallbacks, or proved on the target. MySQL also builds host executable generators;
their host build and invocation must be handled before a full cross build can
complete.

## OpenSSL progress

`build/mysql-port/build-openssl.sh` configured a static PIC ARM OHOS OpenSSL
build and compiled part of its objects. The build was stopped when Windows
exhausted committed memory. No libssl/libcrypto installation was completed.
Logs and objects are preserved in `build/mysql-port/`.

Resume with enough free committed memory:

```powershell
wsl.exe -d qfli-java-build -- bash -lc 'cd /mnt/d/MyNewProjects/qfli_sql/build/mysql-port/openssl-build && make -j1 build_libs && make install_dev'
```

## Process entry and verification

SDK 23 declares `OH_Ability_StartNativeChildProcess` (API 13+) and ArkTS
`childProcessManager.startNativeChildProcess`. The entry is a packaged shared
library plus exported function, such as `libEntry.so:Main`, rather than a
desktop executable path. The server port must expose an entry that invokes
Oracle's server main in that child process, using private storage and a local
socket. Initialization, readiness, shutdown, and persistence remain unverified.

The connected HarmonyOS emulator was x86_64. It passed the SQLite native and
workbench integration suites, then disconnected. An arm64 target is still
needed for the final Oracle runtime acceptance checks.

## Host resource observation

Concurrent native compilation and HAP signing exhausted Windows committed
memory, causing Java `errno=1455`, Dart allocation failures, and even PowerShell
startup failures. Stopping the owned build and terminating its otherwise idle
WSL distro restored available memory. Keep these heavy builds sequential and
limit native compilation to one job until more host memory is available.

For HAP verification, process-scoped Java options used successfully were:

```text
-Xms32m -Xmx256m -XX:MaxMetaspaceSize=128m
-XX:ReservedCodeCacheSize=64m -XX:ActiveProcessorCount=2
```

## Reproducible Port Continuation

- Organized pinned-source preparation, OpenSSL build, Oracle build, native child
  entry and runtime staging now live under `native/mysql/`.
- Target OpenSSL and all eight host generators built. Oracle 8.4.6 target CMake
  configuration completed with explicit platform fallback selections.
- Oracle's DNS resolver, optional editline/dictionary trainer and unavailable
  pthread_cancel paths required small OHOS patches. Static Protobuf/Abseil
  avoid extra shared dependencies in the HAP.
- Generic SDK C++ headers emit std::__1, while target libc++_shared exports
  std::__n1. The target requires `llvm/include/libcxx-ohos/include/c++/v1`.
  With those headers, `libqfli_mysql.so` strictly linked for AArch64 with only
  ace_napi, libc++_shared and libc as runtime dependencies.
- The source and target build were moved to WSL ext4 at
  `/root/qfli-mysql-port` to reduce repeated header reads through `/mnt/d`.
  The final package was staged back into `build/mysql-port/package`.
- ICU data is bundled at `share/icu/icudt77l`; the child entry accepts an
  explicit `icuDataDirectory` and sets ICU_DATA before Oracle startup.
- Initialization writes an atomic numeric exit record after Oracle cleanup.
  The parent requires that record and a real `SELECT VERSION()` result.
- WSL restarts interrupted server and host-generator compilation; existing objects were
  retained and compilation resumed. Heavy builds remain single-job/sequential.
- Further tests and device probes were deferred by the user. These build
  findings do not establish initialization, shutdown or persistence on target.
- Bundled protoc 24.4 is an eighth required host generator. Oracle's supported
  WITH_PROTOC option points the cross-build to that host executable.

## Compiled Package and HAP

- Oracle MySQL 8.4.6 arm64 server and client linked with `--no-undefined`.
  Successful log: `build/mysql-port/ohos-build-ext4-server-link.log`.
- The package contains `libqfli_mysql_server.so` (71,584,424 bytes),
  `libqfli_mysql.so` (13,627,424 bytes), and 73 rawfiles (5,139,034 bytes).
  ELF architecture and dependency checks completed during packaging.
- The build was resumed incrementally in WSL ext4. The consolidated scripts
  have not been run from a clean build tree end to end.
- Full Hvigor `assembleHap` compiled and signed the normal application.
  The HAP contains both Oracle arm64 libraries, runtime.json, ICU/charset/error
  resources, and both upstream license notices.
- The first ArkTS build rejected a constructor parameter property; explicit
  class-field declaration and assignment fixed compilation.
- SDK declarations restrict ArkTS `startNativeChildProcess` to PC/2-in-1 and
  tablet devices. The upstream native API reference applies the same restriction
  to `OH_Ability_CreateNativeChildProcess` and `OH_Ability_StartNativeChildProcess`:
  PC/2-in-1 through API13, plus tablets from API14. Native C is not a phone
  workaround. Reference:
  `https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-ability-kit/capi-native-child-process-h.md`.
- The project declares phone, so its Oracle launch path remains blocked. The
  runtime explicitly rejects unsupported devices before asset extraction or
  initialization writes. A supported phone host has not been established.
- Further tests and device probes remain deferred at the user's request.
