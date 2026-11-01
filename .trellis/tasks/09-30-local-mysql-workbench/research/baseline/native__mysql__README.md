# Oracle MySQL HarmonyOS Port

This directory contains the Oracle MySQL source patches, cross-build inputs,
HarmonyOS child entry, and runtime packaging scripts. Building the libraries
does not prove initialization or persistence on a HarmonyOS device.

## Pinned Inputs

| Input | Version | SHA256 |
| --- | --- | --- |
| Oracle MySQL community source | 8.4.6 | `a1e523dc8be96d18a5ade106998661285ca01b6f5b46c08b2654110e40df2fb7` |
| OpenSSL source | 3.5.3 | `c9489d2abcf943cdc8329a57092331c598a402938054dc3a22218aea8a8ec3bf` |

Official source URLs:

- `https://cdn.mysql.com/archives/mysql-8.4/mysql-8.4.6.tar.gz`
- `https://www.openssl.org/source/openssl-3.5.3.tar.gz`

Build prerequisites in the working WSL distribution `qfli-java-build`:

- LLVM/Clang 18, LLD, CMake 3.28, GNU Make, Perl, Git, Bison 3.8.2.
- Host generator dependencies: `libssl-dev`, `libicu-dev`, `libtirpc-dev`,
  `pkg-config`, and `rpcsvc-proto`.
- The HarmonyOS SDK23 native sysroot and SDK Clang 15.0.4 resource headers.

## Target OpenSSL

Place the verified OpenSSL archive at
`build/mysql-port/openssl-3.5.3.tar.gz`, then run from the repository root:

```powershell
wsl.exe -d qfli-java-build -- bash /mnt/d/MyNewProjects/qfli_sql/native/mysql/build-openssl-ohos.sh
```

The script uses one compiler job, builds static PIC libraries for
`aarch64-linux-ohos`, installs headers and archives under
`build/mysql-port/openssl-ohos`, and links a shared-library smoke artifact with
`--no-undefined`. It does not execute target code.

Environment overrides:

- `QFLI_MYSQL_PORT_ROOT`: source and build artifact directory.
- `QFLI_OHOS_SDK`: native SDK root, using a WSL path.
- `QFLI_CLANG`: Linux Clang executable, default `/usr/bin/clang-18`.
- `QFLI_OPENSSL_ARCHIVE`: path to the pinned archive.

The previously linked OpenSSL smoke artifact is an AArch64 ELF shared object
whose only system dependency is `libc.so`. The organized OpenSSL script has not
yet been run end to end; its build and link commands were executed separately.

## Oracle MySQL Build

Place the pinned MySQL archive at `build/mysql-port/mysql-8.4.6.tar.gz` and
install the target OpenSSL prerequisite, then run:

```powershell
wsl.exe -d qfli-java-build -- bash /mnt/d/MyNewProjects/qfli_sql/native/mysql/build-mysql-ohos.sh
```

`QFLI_MYSQL_ARCHIVE` can name a different location for the same pinned archive.
The script checks its hash, extracts the source, and applies
`patches/0001-ohos-platform.patch`. Already applied patches are accepted only
when their reverse applicability check succeeds. It builds eight host
generators before configuring the ARM64 target, and builds with one job to
limit memory use. Do not run Flutter/HAP builds concurrently on the current
host. `QFLI_CLANGXX`, `QFLI_HOST_CLANG`, and `QFLI_HOST_CLANGXX` override the
target C++, host C, and host C++ compilers respectively.
`QFLI_MYSQL_HOST_TOOLS` can point to the eight generators already built from
the same pinned source, allowing another target build to reuse them.
This includes the bundled host `protoc 24.4`, supplied through Oracle's
`WITH_PROTOC` option instead of trying to execute a target-architecture tool.

For large native builds, set `QFLI_MYSQL_PORT_ROOT` to a directory on the WSL
filesystem and copy the required SDK headers/libraries there before setting
`QFLI_OHOS_SDK`. This avoids repeated Windows filesystem metadata overhead.
The toolchain deliberately uses `llvm/include/libcxx-ohos/include/c++/v1`,
whose `std::__n1` ABI matches the SDK target `libc++_shared`. The generic
`llvm/include/c++/v1` headers use `std::__1` and cannot link to that runtime.

The target configuration disables the Router, X Protocol, NDB plugin, group
replication, optional enterprise authentication integrations, CLI line editing,
and the unused Zstd dictionary trainer. Ordinary Zstd compression/decompression
is retained. It selects Oracle's existing fallbacks for the unexecuted setns,
clock, hole-punching, and builtin-ffs runtime probes. The OHOS thread-cancellation
API returns `ENOTSUP`, because the SDK provides no `pthread_cancel`; custom
plugins that require forced thread cancellation are unsupported by this port.
Boost's nanosleep path also skips cancellation-state toggling on OHOS, matching
its existing Android behavior; the timed wait itself is unchanged.
InnoDB skips Linux-specific CPU affinity and thread-priority tuning on OHOS;
buffer-pool statistics initialization and page-flushing operations are retained.
The zero-range file-allocation path includes its Linux flag header independently
of hole-punch support and retains Oracle's write-zero fallback on runtime failure.
InnoDB uses Oracle's software CRC32-C implementation on OHOS to avoid ARM
intrinsic target-feature incompatibilities; the page-checksum format is unchanged.
DNS SRV uses the SDK's non-reentrant resolver API, as Oracle already does on
Alpine. Protobuf and Abseil are linked statically into the server library.

Two targets are added to Oracle's CMake build:

- `qfli_mysql`: the async HarmonyOS NAPI channel and Oracle socket client.
- `qfli_mysql_server`: the child entry, using the complete Oracle server link
  graph, including InnoDB and the built-in storage engines.

Both shared libraries link with `--no-undefined` and are written to
`build/mysql-port/ohos-build/qfli-runtime/lib/`. The build then runs
`package-runtime.cmake` to stage `package/libs/arm64-v8a/` and
`package/rawfile/mysql/` under the port root. The rawfile directory contains
`runtime.json`, generated English error messages, character-set and ICU data, and the
upstream MySQL and OpenSSL license notices.
The packager reads each library's ELF metadata as JSON with LLVM readobj and
recursively copies non-system shared dependencies from the Oracle build.
Platform `libc`, NAPI, and the Flutter-provided `libc++_shared` are excluded.
Missing dependencies or a non-ARM64 artifact abort packaging.
Only the packaged copies are stripped with LLVM `--strip-unneeded`; original
build artifacts and the dynamic exports needed for NAPI and native child entry
are preserved.

Release distributions must also
provide the corresponding Oracle/OpenSSL source archives, these patches and
build scripts, and the app/native sources required by their licenses.

## Child Entry Contract

HarmonyOS native-child APIs support PC/2-in-1 devices and, from API14, tablets.
Phones are unsupported by both the ArkTS and native C entry APIs. The app
currently targets phone and rejects startup there; compiling this library does
not establish a supported Oracle host on that target. See the upstream
[native child API reference](https://github.com/openharmony/docs/blob/master/en/application-dev/reference/apis-ability-kit/capi-native-child-process-h.md).

The API13 entry is `libqfli_mysql_server.so:QfliMysqlMain`. Its
`NativeChildProcess_Args.entryParams` is a JSON object:

```json
{
  "arguments": ["mysqld", "--defaults-file=/absolute/app/path/my.cnf", "--initialize-insecure"],
  "exitFile": "/absolute/app/path/initialize.exit",
  "icuDataDirectory": "/absolute/app/path/share/icu"
}
```

Use a fresh native child process for initialization and another for normal
server operation. Omit `--initialize-insecure` when starting the server.
Arguments are passed directly to Oracle's `mysqld_main`, with no shell parsing.
The parent owns app-private directory creation, configuration, resource
extraction, stale exit-file removal, readiness queries, and shutdown.
The optional `icuDataDirectory` sets `ICU_DATA` in the child before Oracle
initializes its bundled ICU library.

Oracle initialization and server shutdown call `exit()` internally. The OHOS
patch therefore invokes an optional weak `qfli_mysql_record_exit` hook after
server cleanup and before process exit. The wrapper writes the numeric exit
code and a newline using a temporary file, full writes, `fsync`, and `rename`.
Malformed arguments report failure when a valid exit path is available. A
missing exit record is never evidence of initialization success.

## Build Result

The Oracle MySQL 8.4.6 ARM64 server and async client successfully linked with
`--no-undefined`. The runtime packager completed its architecture and dependency
checks, stripped the staged libraries, and copied the resulting package to
`build/mysql-port/package/`.

| Packaged output | Bytes |
| --- | ---: |
| `libs/arm64-v8a/libqfli_mysql_server.so` | 71,584,424 |
| `libs/arm64-v8a/libqfli_mysql.so` | 13,627,424 |
| `rawfile/mysql/` (73 files) | 5,139,034 |

The successful build log is
`build/mysql-port/ohos-build-ext4-server-link.log`. This result was obtained
incrementally from the prepared WSL ext4 source/build tree. A clean invocation
of the consolidated build script has not been performed.

No further tests or device probes were run, as requested. HarmonyOS startup,
initialization, persistence, and shutdown still require on-device acceptance;
successful compilation and packaging do not establish those runtime results.
