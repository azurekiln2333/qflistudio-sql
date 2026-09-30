# Oracle MySQL port experiment

## Required engine

The user explicitly requires Oracle MySQL. MariaDB and SQLite do not satisfy
the final runtime requirement. The current workbench still uses SQLite.

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

These source trees and experiments are ignored build artifacts. There is no
bundled Oracle server artifact yet. Release packaging must include source
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
