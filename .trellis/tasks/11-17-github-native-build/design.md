# Mobile Native CI Design

## Boundary
Add CI orchestration, standalone target packaging and documentation. Reuse existing
runtime implementations and pinned patches. Do not alter SQL behavior or invent an
iOS MySQL host. User explicitly corrected and approved scope on 2026-11-17.

## Jobs and Inputs
- GitHub-only trial branch ci/native-build-20261117 from current local HEAD.
- Linux hosted runners compile target OHOS/Android code, not desktop product binaries.
- OHOS arm64: pinned setup-ohos-sdk commit and verified API23/6.1.0.31 (Linux release; local Windows is 6.1.0.32) metadata;
  source-hash checks; existing OpenSSL/Oracle build/package scripts. Compile SQLite
  OHOS NAPI with the actual SDK and staged Oracle dependencies where needed.
- Android arm64-v8a and x86_64: NDK27.0.12077973, Clang18, pinned Oracle/OpenSSL,
  matching host generators, existing Android configure/export scripts and ELF audits.
  Compile project SQLite library with the NDK for each ABI.
- iOS: hosted macOS Xcode builds static project SQLite/bridge for arm64 devices
  and arm64/x86_64 simulators, then creates an XCFramework and validates slices.
  This is native packaging, not a signed Flutter app or a MySQL runtime.
- macOS official Oracle packages exist; verify fixed-version download URLs and
  record them. Do not build the engine from source merely to produce CI activity.
  App-specific bridge/helper compilation remains part of application packaging.
- Use read-only workflow permissions, immutable action revisions, manual triggers
  and branch push triggers. Isolate failures across platforms and always retain logs.
- Manual runs accept target all/android/ohos/ios. Platform selection permits a
  targeted retry while other platforms continue their original builds. Every
  selected run retains corresponding source inputs. Push runs keep all platforms.
- Shared host generator logic may be extracted from the existing OHOS build script
  if needed by Android; preserve default behavior and use environment overrides.
- Conservative configurable parallelism with resource snapshots and bounded timeouts.
  Keep temporary source/build trees on the hosted runner, not local disks.

## Artifact Contract
| Artifact | Contents / use |
| --- | --- |
| native-ohos-arm64 | libs/arm64-v8a, rawfile/mysql, SQLite NAPI, licenses, provenance; restore under build/mysql-port/package |
| native-android-arm64-v8a | Oracle bin/lib/share/licenses and SQLite library; consume via existing stage.ps1 |
| native-android-x86_64 | Matching x86_64 Oracle/SQLite and resources; same staging contract |
| native-ios-sqlite | Static XCFramework, bridge header, license, slices/provenance manifest |
| native-source-inputs | Corresponding pinned source inputs and checked-in build/patch provenance |
| native-build-logs-* | Job logs and resource/diagnostic reports; never advertised as runtimes |

Archive Unix outputs in tar files to preserve executable permissions/symlinks.
Include the repository LICENSE unchanged alongside upstream notices and hash it.
Record commit, input hashes, SDK/NDK/compiler versions, ABI and output hashes.
Retention is 14 days. Upload runtime artifacts only after completeness/ABI checks.
Current iOS CocoaPods builds from source; document XCFramework as an optional
native integration artifact rather than claiming automatic app consumption.

## Expected Changes
.github/workflows/native-build.yml, tool/ci helpers, a shared Oracle host-generator
entrypoint if required, narrow native build portability corrections, native/CI.md,
README pointer and task/spec evidence. No new dependencies on sibling repositories.

## Risks and Rollback
The consolidated OHOS clean build is unproven and hosted disk/time may limit it.
The mirrored SDK must match API/version/hash and retain its actual provenance.
Cross-compilation is not device execution. Existing build/mysql-port contains
production backups; no blanket deletion is allowed. Revert CI/helper changes on
the dedicated branch to roll back without changing existing application packages.
