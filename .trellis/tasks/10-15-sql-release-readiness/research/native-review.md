# Native release review

Review date: 2026-10-15. Scope: this repository only; shared core read-only.

## Repair boundary

The normal OHOS build must build and package the private server DSO selected by
the production phone runtime. The preload host must enforce its handshake
deadline and report failed starts with a negative PID while preserving reachable
ownership of any child whose termination is unconfirmed.

Changes are limited to `native/mysql/build-mysql-ohos.sh`,
`native/mysql/package-runtime.cmake`, the matching native CMake input check, the
native preload host and focused host regressions. The coordinator also authorized
repairs for the confirmed descriptor-reset and watchdog setup gaps discovered
during review. Existing native/runtime edits are preserved. The coordinator owns
Git commits, final HAP/APK builds, target binaries and device operations.

## Findings and verification

### Fixed: missing production phone library in clean build/package (P1)

`QfliMysqlRuntime.ets:659` selects `preloadStart` on phones, whose native
implementation loads `libqfli_mysql_server_proto.so`. The preexisting build
script only built the NAPI library, legacy server and launcher, and the package
dependency queue omitted the private server. Hvigor already required the fourth
library. An old manually staged library could mask this source/package drift.

`native/mysql/build-mysql-ohos.sh:83` now builds the private server target;
`native/mysql/package-runtime.cmake:13` requires it and line 34 includes it in
the architecture/dependency/strip packaging queue. `native/CMakeLists.txt:44`
checks the same four runtime inputs as Hvigor.

### Fixed: unbounded preload handshake and incorrect failed-start ownership (P1)

The supposed two-second handshake used blocking `read()` before checking its
deadline. A live child stalled before writing could block the native fork
thread and synchronous NAPI `preloadStart` indefinitely, including ArkTS UI
dispatch. Failure paths also retained an untracked PID and returned a positive
`childPid`, which NAPI interpreted as a successful start.

`ohos/entry/src/main/cpp/qfli_mysql_proto_probe.cpp:118` now waits with `poll()`
and a monotonic deadline. Every fork is adopted into the existing owned-child
table before waiting (line 237). Failed starts use bounded signal/poll/release
cleanup (line 144), keep a pending PID only when exit is unconfirmed, and return
`-1` when an error was recorded (line 410). The debug self-test uses this same
tracked lifecycle; the child also closes its unused handshake read descriptor.

### Fixed: incomplete preload descriptor reset (P2)

The preexisting `child_reset_signals_and_fds` method reset four handlers but its
FD body was only `(void)keep_stdio`. The production preloaded child therefore
retained app descriptors; the legacy exec-host test did not cover this path.

`ohos/entry/src/main/cpp/qfli_mysql_proto_probe.cpp:103` now uses the same portable
`close()` strategy as the exec host with its bound computed before fork. Exactly
stdin/stdout/stderr and the handshake writer survive. `close_range` remains
unused because it was observed to be sandbox filtered on the phone. An
actual-preload regression confirms a non-CLOEXEC fixture is closed in the child
and remains valid in the parent.

### Fixed: preload watchdog failure was ignored (P2)

The preload `watch_parent` function silently continued when `pthread_create`
failed, then sent its ready handshake. It also lacked the launcher's signal-mask
setup that keeps the extra watchdog thread from taking Oracle termination
signals. The legacy launcher already expresses the required behavior.

`ohos/entry/src/main/cpp/qfli_mysql_proto_probe.cpp:51` now makes watchdog setup
fallible, blocks TERM/INT/HUP/QUIT before thread creation, and restores the entry
thread's original mask. On mask/thread setup failure, the child sends a failure
byte (not the ready byte) and exits 125 before the Oracle entry. The parent
reports a specific watchdog error and applies the same owned-child cleanup.

The actual-host regression injects child-side `pthread_create` failure using a
test-only linker wrapper. Production code has no runtime fault switch. Tests
also verify the watchdog creation mask and restoration of an unrelated preexisting
SIGUSR1 mask in the entry thread. No resource-exhaustion phone run is claimed.

### Not fixed: Android store upload signing (existing configuration)

`android/app/build.gradle.kts` release explicitly uses the debug signing config.
An APK build/install can pass with this configuration; it is not evidence that
the artifact is ready for a production store upload. Signing credentials and
distribution setup are outside this code review and were not changed.

## Verified historical rationale and reviewed boundaries

- The phone preload host is intentionally a separate forked server process;
  using it is not a leftover stub. The recorded API26 phone capability is false
  for native/Ark child processes, and direct/interpreter exec failed with
  EACCES. Replacing preload with the legacy exec path would regress that device.
- Reviewed the private server's eager libc symbol resolution, local exit scope,
  `-Bsymbolic-functions`, local version map and static libc++/unwind linkage.
  The current build target expresses those requirements. Historical 12/12 phone
  probe acceptance is recorded in the OHOS spec, but is not a fresh result for
  this source snapshot or the newly enabled InnoDB fence build.
- `configureProbeRoot` and the Dart-facing `protoProbe` channel both reject
  release calls with `!BuildProfile.DEBUG`. The always-present NAPI
  `preloadStart` is required by production and must remain available. Its stale
  DEBUG/prototype comments do not describe actual runtime selection.
- ArkTS retains PID ownership during unconfirmed stop, serializes query work,
  prevents new work during disposal, and attempts graceful MySQL shutdown before
  escalation. No missing exported lifecycle method was found between its module
  interface and NAPI registration.
- Local Android/OHOS MySQL uses a private Unix socket and `skip-networking`;
  native client explicitly selects `MYSQL_PROTOCOL_SOCKET`. The newly added
  `MySqlWorkspaceRepository.openCloud` is a separate online code path and must
  be included in the offline UI/engine-preference review owned by the other
  agent. This native review does not certify cloud reachability.
- The `LocalMySqlRuntime` delta adds optional macOS helper/plugin layout and
  leaves Android layout injection intact. The macOS helper packaging change
  requires its untracked `native/mysql/macos` files to be delivered together.
  Portable bundle validation passed; no Apple build/signing/execution is claimed.

## Executed verification

All commands used this repository. No Flutter build, installation, SDK change,
device command, other product edit or Git staging/commit was performed.

- `wsl -d qfli-java-build -- bash .../native/tests/run-preload-host-test.sh`:
  PASS, 30 checks. Compiles actual production preload/ownership sources with
  `-Wall -Wextra -Werror`, replacing only the Oracle closure. Covers success,
  exact exit status/release, isolated exit self-test, a six-second pre-handshake
  stall failing within 1.8–4 seconds, early child death, negative failure result,
  confirmed cleanup without zombie or stale ownership, inherited descriptor
  removal with parent preservation, watchdog signal masks, and injected watchdog
  creation failure before the ready handshake.
- Existing `run-host-test.sh`: PASS, all lifecycle checks. The script was piped
  to Bash with only its log destination replaced by its fresh `/tmp` workdir;
  the historical build log was preserved. Includes malformed/partial error
  frames, live pending ownership, PID identity, native-child completion and
  inherited descriptor removal for the legacy exec host.
- Existing `run-preload-mechanism-test.sh`: PASS, constructor thread detection
  and child exit isolation.
- Existing `run-stdio-protocol-test.sh`: PASS, bounded lock acquisition,
  partial-lock release and repeated forks with concurrent stderr writes.
- Installed OHOS SDK23 `clang++ --target=aarch64-linux-ohos --sysroot=... -std=c++17
  -stdlib=libc++ -Wall -Wextra -Werror -fsyntax-only` on the changed preload host:
  PASS. This is target syntax/type checking, not a linked target build or run.
- `python native/mysql/macos/test_bundle.py`: PASS, 12 portable validation tests.
- Bash syntax checks on changed build/test scripts: PASS.
- `git diff --check` on modified tracked native files: PASS.
- Full native CMake/CTest was not configured: this WSL image lacks the required
  `mysqlclient` pkg-config/rapidjson prerequisite combination. Direct production
  host test compilation above passed without those optional client prerequisites.
- Default Ubuntu WSL could not mount its missing VHDX. The existing
  `qfli-java-build` distribution supplied the successful compiler host; nothing
  was installed or repaired in either distribution.
- Flutter analyze/full tests/APK/HAP and fresh phone acceptance are owned by the
  main/platform agents; no result is asserted here.

## Files changed by this reviewer

- `native/CMakeLists.txt`
- `native/mysql/build-mysql-ohos.sh`
- `native/mysql/package-runtime.cmake`
- `native/tests/CMakeLists.txt`
- `ohos/entry/src/main/cpp/qfli_mysql_proto_probe.cpp` (preexisting untracked file)
- `native/tests/qfli_mysql_preload_host_stub.cpp` (new)
- `native/tests/qfli_mysql_preload_host_test.cpp` (new)
- `native/tests/run-preload-host-test.sh` (new)
- `research/native-review.md` (this report)

## Coherent preexisting OHOS delivery dependencies

The coordinator must review/stage these source dependencies together with the
above files if committing the production OHOS preload delivery:

- `native/mysql/ohos-targets.cmake`
- `native/mysql/qfli_mysql_host.cpp`, `qfli_mysql_host.h`
- `native/mysql/qfli_mysql_launcher.cpp`
- `native/mysql/qfli_mysql_server.cpp`
- `native/mysql/qfli_mysql_server_proto.cpp`, `qfli_mysql_server_proto.map`
- `native/mysql/qfli_mysql_stdio_protocol.h`
- `ohos/entry/src/main/cpp/qfli_mysql_napi.cpp`, `qfli_mysql_proto_probe.h`
- `ohos/entry/src/main/ets/plugins/QfliMysqlRuntime.ets`, `QfliMysqlNative.ets`
- the MySQL runtime lifecycle delta in `ohos/entry/src/main/ets/entryability/EntryAbility.ets`
- `ohos/entry/hvigorfile.ts`
- `native/tests/qfli_mysql_child_stub.cpp`, `qfli_mysql_host_test.cpp` (referenced
  by the preexisting CMake delta); their run scripts and other focused test
  sources may be included with reviewed test coverage.

`native/mysql/qfli_mysql_server.map` is not referenced by the reviewed build
graph; do not add it merely because it is untracked. Experimental investigation
scripts, baseline artifacts, signing-profile changes, app icons and unrelated
pages are not required by this repair.

## Rebuild/commit gate and remaining unreviewed work

The staged `libqfli_mysql.so` must be rebuilt to pick up handshake changes.
The private server DSO must be rebuilt with the selected memory-fence flag, then
the normal package script must stage that fresh file and Hvigor must consume
that package. A successful HAP build using an old manually staged image cannot
verify these fixes. The coordinator was notified before final platform builds.

The four repaired defects are ready for a coherent source commit after the
coordinator reviews the complete preexisting dependency diff. Their actual-host
regressions and OHOS target syntax check pass; final target rebuild and phone
acceptance remain required.

Not reviewed for commit: all exploratory native shell/Python scripts except the
executed focused test scripts, their saved build/probe artifacts, local OHOS
signing-profile material, AgreementReader/icon changes, generated platform
registrants, full macOS packaging/signing execution, UI/content/terminal changes,
and the independent cloud repository delivery. Other agents own those scopes.
