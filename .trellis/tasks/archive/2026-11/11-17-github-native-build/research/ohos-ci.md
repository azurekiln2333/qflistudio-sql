# Standalone native CI feasibility

Research date: 2026-11-17. This is planning evidence. No Actions build ran in this research.

## Recommended first scope

| Job | Runner | Output | Reason |
| --- | --- | --- | --- |
| SQLite Windows x64 | `windows-2022` | `qfli_sqlite.dll` and bridge header | `native/runtime/CMakeLists.txt` is standalone and has no Flutter or Oracle dependency. |
| SQLite Linux x64 | `ubuntu-24.04` | `libqfli_sqlite.so` and bridge header | Same standalone CMake project. The existing real-engine SQL validation suite can also run on Linux. |
| Oracle MySQL OHOS arm64 | `ubuntu-24.04` | Four real Oracle libraries, resources, licenses, manifest, hashes and build log | Production arm64 scripts exist. SDK acquisition can use the verified upstream setup action and public SDK mirror. |

Defer Android, OHOS x86_64, Apple and full Flutter/HAP/APK packaging from this first run. This keeps the experiment focused on the large native source build. Root Flutter packaging is a separate concern: `pubspec.yaml` requires sibling `qfli_studio_core`, and Windows/Linux plugin CMake unconditionally includes Oracle desktop packaging. A Linux Flutter build without Oracle staging is not supported by the current code.

## SDK acquisition and provenance

Local `D:/ProgramFiles/Huawei/OpenHarmony/Sdk/23/native/oh-uni-package.json` reports:

- API: `23`.
- Version: `6.1.0.32`.
- Release: `Release`.
- LLVM resource directory: `llvm/lib/clang/15.0.4`.
- Required C++ headers: `llvm/include/libcxx-ohos/include/c++/v1`.
- Required architecture directories include `aarch64-linux-ohos` and `x86_64-linux-ohos`.

The separate DevEco bundled SDK currently reports API `26`, version `26.0.0.105`. It must not be silently substituted for the native port's API23 input.

Inspected upstream setup action:

- Repository: `https://github.com/openharmony-rs/setup-ohos-sdk`.
- Observed HEAD: `cfd996a9cff9e72a7e59827cb5424fcfae4ada3e`.
- Tag `v1.0.0`: `eb82b94ef522b07269679195c2512f22e922ef3b`.
- Inspecting `action.yml` and `install_ohos_sdk.sh` at HEAD confirms support for version `6.1`, native-only extraction, mirror downloads, archive checksum verification, and the `ohos_sdk_native` output.
- The action's current script explicitly handles the 6.1 archive layout. Pin the inspected commit rather than assume an older tag has that branch.
- `components: native` reduces installed components, but it still downloads the complete Windows/Linux source archive before extracting the Linux native component.

Observed mirror release `https://github.com/openharmony-rs/ohos-sdk/releases/tag/v6.1` exists. The release API reported publication on 2026-03-23 and these Windows/Linux inputs:

| File | Bytes |
| --- | ---: |
| `ohos-sdk-windows_linux-public.tar.gz.aa` | 2,000,000,000 |
| `ohos-sdk-windows_linux-public.tar.gz.ab` | 499,936,800 |
| `ohos-sdk-windows_linux-public.tar.gz.sha256` | 65 |

The fetched checksum file contains `b833b75a64ee46bbd7880921abbb49b733ec5c8171b6684c9b524d57f624cee0`.

The action downloads mirror split files, joins them, checks the whole archive, then extracts components. Its fallback URL is `https://repo.huaweicloud.com/openharmony/os/6.1-Release/ohos-sdk-windows_linux-public.tar.gz`. A direct request for the Huawei checksum returned HTTP 403 on this machine. The GitHub mirror checksum was accessible.

The mirror is maintained by the setup action upstream, not the official OpenHarmony project. Preserve that distinction in build provenance. Before compiling, require metadata `apiVersion == 23` and `version == 6.1.0.32`, record the metadata and expected archive checksum, and verify the resource/header/static-library paths used by the toolchain. This research did not download or inspect the complete remote native SDK, so metadata parity is still a CI gate.

## Clean build entrypoints

Use a fresh Linux work directory under `RUNNER_TEMP`, and set:

```bash
QFLI_MYSQL_PORT_ROOT="$RUNNER_TEMP/mysql-ohos-arm64"
QFLI_OHOS_SDK="<setup action ohos_sdk_native output>"
QFLI_MYSQL_ARCHIVE="<verified mysql-8.4.6.tar.gz>"
QFLI_OPENSSL_ARCHIVE="<verified openssl-3.5.3.tar.gz>"
QFLI_CLANG=/usr/bin/clang-18
QFLI_CLANGXX=/usr/bin/clang++-18
QFLI_HOST_CLANG=/usr/bin/clang-18
QFLI_HOST_CLANGXX=/usr/bin/clang++-18
```

Then run `native/mysql/build-openssl-ohos.sh` followed by `native/mysql/build-mysql-ohos.sh`.

Install Clang/LLVM18, LLD, CMake3.28+, Make, Perl, Git, Bison, `libssl-dev`, `libicu-dev`, `libtirpc-dev`, `pkg-config`, and `rpcsvc-proto`. The MySQL script builds host generators before cross-compilation. Its eight host outputs are `comp_err`, `comp_client_err`, `comp_sql`, `uca9dump`, `gen_lex_token`, `gen_keyword_list`, `gen_lex_hash`, and `protoc`.

Pinned source inputs already enforced by repository scripts:

- MySQL8.4.6: SHA256 `a1e523dc8be96d18a5ade106998661285ca01b6f5b46c08b2654110e40df2fb7`.
- OpenSSL3.5.3: SHA256 `c9489d2abcf943cdc8329a57092331c598a402938054dc3a22218aea8a8ec3bf`.

## Clean-build hazards and limits

1. Default SDK paths point to a local Windows drive through WSL. CI must override `QFLI_OHOS_SDK`.
2. Target compiler paths and LLVM archive tools assume version18. Install that version explicitly.
3. The production scripts and packager are arm64-specific. The research x86 variant uses fixed `/root/qfli-mysql-ohos-x64-1022` and `/root/qfli-mysql-port` roots, reuses a local source tree and host tools, and rewrites CMake text. It cannot be placed unchanged in hosted CI.
4. `native/mysql/README.md` explicitly says that the consolidated OHOS build script has not completed a clean end-to-end run. Historical incremental link evidence is not CI success evidence.
5. Existing source extraction is presence-based. A fresh work directory avoids reuse of partially extracted or differently patched source trees. Do not cache whole build/source trees in the initial experiment.
6. Every current OpenSSL/Oracle build command uses one compiler job. This limits compiler concurrency, but does not guarantee a hosted job completes within its time limit.
7. GitHub-hosted jobs have a six-hour execution limit. Public standard Linux runners document four CPUs, 16GB RAM and 14GB SSD. Private standard Linux runners document two CPUs, 8GB RAM and 14GB SSD. Repository visibility determines which applies.
8. No clean-build peak RAM, peak disk or elapsed-time measurement exists in the inspected records. The 2.5GB SDK archive, MySQL/OpenSSL source, host generator build, target object tree and two server link variants make disk the first concern. The documented 14GB SSD does not establish sufficient headroom.
9. Record `df -h` and memory at start, after SDK setup, and after each build stage. Fail early on missing inputs. Set a bounded job timeout and upload logs even on failure. A failed memory, disk or time run is useful feasibility evidence and must be reported as failed.

Resource references inspected:

- `https://docs.github.com/en/actions/reference/limits`.
- `https://docs.github.com/en/actions/reference/runners/github-hosted-runners`.

## Artifact contract

The existing OHOS packager produces `package/libs/arm64-v8a/` and `package/rawfile/mysql/` below `QFLI_MYSQL_PORT_ROOT`.

Required real libraries:

- `libqfli_mysql.so`: Oracle client and OHOS NAPI bridge.
- `libqfli_mysql_server.so`: Oracle server image.
- `libqfli_mysql_launcher.so`: packaged launcher executable.
- `libqfli_mysql_server_proto.so`: private server image.

The resources include `runtime.json`, English errors, charsets, ICU data and Oracle/OpenSSL licenses. The packager recursively copies non-platform shared dependencies and strips only packaged copies. It requires AArch64 ELF metadata and fails on missing non-platform dependencies.

Preserve this directory layout in a tar archive so it can be restored under local `build/mysql-port/package/`. Include source revision, input versions/hashes, SDK metadata, artifact SHA256 list and build log. Avoid publishing the whole intermediate build tree. A source/provenance archive should contain the corresponding sources, repository patches and build scripts required for distribution.

The OHOS native artifact is not an installable HAP. The SQLite DLL/SO artifacts are libraries, not complete desktop apps. The remote build validates compilation/package closure only; it does not validate device startup, SQL execution, persistence, signing or installability.

## Local storage observation

Read-only scan of root `build/` found 10.260GiB in 73,946 files. Largest groups were `mysql-port`3.214GiB, `ohos-audit`2.585GiB, `app`2.563GiB, and `ohos`0.689GiB. This excludes `native/build/`, platform build caches, SDKs and WSL storage. Moving future builds to GitHub does not remove these existing local files. Keep local runtime packages and needed diagnostic evidence until downloadable remote replacements exist.
