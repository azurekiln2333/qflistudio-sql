# Phone debug progress

Device: hdc 192.168.68.207:46551, MRT-AL10, OpenHarmony-7.0.0.105,
HarmonyOS HongMeng Kernel 1.13.0, arm64, target API24, sdkApi 26.
App com.azurekiln.qfli.sqlab / EntryAbility. `install -r` only; app data kept.

## Evidence labeling correction

`build/mysql-port/run-1791527503013601/latest.json` is the current pointer and
actually contains runId `1791527638828183_5606e50c9450c6a0`; it is NOT the user's
`1791527503013601_296a6ac99d485e75` run. The module `initialize.log` is
cumulative across runs. When attributing a run, retrieve the owned nested report
at
`/data/storage/el2/base/files/mysql-ohos-probe/<runId>-<suffix>/report.json`
(e.g. `1791527503013601_296a6ac99d485e75-EHULDE/report.json`) or label the
current pointer by its true runId. Do not attribute the latest pointer to a
specific user run.

Owned report for the user's run, retrieved and correctly attributed:
`build/mysql-port/run-1791527503013601/owned-report.json`, runId
`1791527503013601_296a6ac99d485e75`, status fail:
- `oracle_identity_and_socket`: fail, `exitCode=127`, `error=Permission denied`.
- `final_stop`: pass.
This matches the module `initialize.log` EACCES result for the launch stage.

## Loop used

1. `flutter build hap --debug --no-pub --target-platform ohos-arm64
   --target integration_test/mysql_ohos_probe.dart`
2. `hdc ... install -r build/ohos/hap/entry-default-signed.hap`
3. `hdc ... shell aa start -a EntryAbility -b com.azurekiln.qfli.sqlab`
4. `hdc ... file recv -b com.azurekiln.qfli.sqlab
   /data/storage/el2/base/files/mysql-ohos-probe/latest.json <out>`
5. Module logs: `hdc ... file recv -b com.azurekiln.qfli.sqlab
   /data/storage/el2/base/haps/entry/files/mysql/<log> <out>`

## Attempt 20261009-1430 (capability query + rich diagnostics)

Source: parent-prepared interpreter argv (no post-fork allocation), separate
direct/interpreter errno, capability log, launcher-stage markers.

Results:
- Probe: `status: fail`, `oracle_identity_and_socket` -> `Permission denied`,
  `final_stop` pass. Report `attempt-1430-result.json`.
- `capability.log`:
  `deviceType=phone sdkApi=26 query=ok supported=false error= host=fork`.
  The API26 `childProcessManager.isNativeChildProcessSupported()` ran and
  returned **actual false**: native child processes are genuinely unsupported
  on this phone, not merely undocumented.
- `initialize.log` (module scope):
  `[host] direct errno=13 interp errno=13
   launcher=/data/storage/el1/bundle/libs/arm64/libqfli_mysql_launcher.so
   mode=0100644 uid=3060 size=11640
   interp=/lib/ld-musl-aarch64.so.1 mode=0100755`.
  - Direct `execve` of the installed launcher -> EACCES (mode 0644, no exec bit).
  - `execve` of the system interpreter -> **also EACCES** (interp mode 0755).
- `server.stderr.log`, `mysql.log`: not created (children never reached launch).

## Conclusion (exact device evidence)

On this phone, in the normal app domain:
1. The API26 native-child API reports supported = **false**.
2. The API26 **Ark** child process API also reports supported = **false**
   (`native query=ok supported=false ark query=ok supported=false`). So neither
   OS-supported child-process mechanism is available to this app on this phone.
3. Direct exec of the packaged launcher is denied (installed mode 0644).
4. Exec of the system musl interpreter is also denied (mode 0755 but app-domain
   policy denies) — so the direct-interpreter fallback is not a phone host.
5. Declaring `executableBinaryPaths` (the only mechanism that marks a packaged
   executable) is rejected at install on this phone (`9568449`).

Files: `attempt-ark/latest.json`, `attempt-ark/initialize.log`,
`attempt-ark-module-logs/capability.log`. Consolidated evidence bundle:
`build/mysql-port/phone-evidence-final/{latest.json,capability.log,initialize.log}`.
No SQL/data mutation; no app crash.

There is no currently-known supported phone host for spawning the Oracle 8.4.6
server process from this app under its present policy and bundle shape. Do not
use post-fork dlopen, chmod, private-code copy, root, or security changes. This
needs a considered host-redesign decision by the director (candidate directions:
run the server in-process, a supported packaging form, or a different on-device
capability).

## Parent-side host fixes (batch after 1430)

Code ready for targeted review, not yet re-installed:
1. `trace_fd` was closed twice (near the fork then again in the failure path);
   now closed exactly once and immediately set to -1, so no other thread can
   reuse the descriptor number.
2. `snprintf` clamped to `sizeof(line)-1` before the diagnostic write.
3. Error-pipe protocol: only a clean zero-byte EOF (no partial frame) means exec
   succeeded; a partial frame, one-int EOF, or a read error is an explicit
   `EPROTO` failure with reap + owned-child cleanup. Both errnos preserved.
All interpreter argv remains parent-prepared before fork. Host tests 49/49 pass;
native package rebuilt and staged.

## Parent-side host fixes (protocol/robustness batch)

Ready for review; native package rebuilt and staged:
1. `read_error_frame()` is now a separate, tested function: only a clean
   zero-byte EOF means "no error frame" (not proof of exec success); a complete
   two-int frame reports both errnos; a partial frame or read error returns -1
   (protocol failure) and is never success.
2. On a protocol failure or a reported exec failure, the owned child is
   **force-terminated (SIGKILL) before `waitpid`**, so a read error can never
   block the NAPI call on a child that did not exit.
3. Timeout/reap paths never discard a live owned PID.
Host tests now **55/55 pass**, including complete-frame, clean-EOF,
partial-frame, and read-error cases.

## Device acceptance progress (runId 1791541125739749_7a3c97bd6142f31b)

Via the **preloaded direct entry** host (fork + call the private server entry; no
`exec`), on the isolated probe root, real Oracle 8.4.6 PASSED:
`proto_closure_quiescent`, `oracle_identity_and_socket`, `create_owned_schema`,
`crud_exact_values`, `invalid_sql_is_available`,
`scripts_transactions_and_literals`, `workbench_repository_round_trip`,
`project_editor_and_saved_query`.

Remaining failures and fixes applied (retained files):
- `stop_runtime` exit 143 (SIGTERM raced Oracle's graceful shutdown) -> `stopChild`
  now waits for the exit record WITHOUT signalling after a successful
  `shutdown(socket)`, escalating only on timeout.
- `final_stop` PID file remains (consequence of the SIGKILL) -> same fix.
- Preload selection was AFTER the exec branch -> now selected INSIDE
  `host === 'fork'` before the exec host (`QfliMysqlRuntime.ets`).
- `preloadStart` now returns the same structured
  `{pid, failed, owned, pendingPid, errno, error}` and preserves a retained PID.
- Beginning-of-start cleanup reaps any pending owned child before file rewrites
  or a new spawn (no second child, no PID overwrite).

## FULL DEVICE ACCEPTANCE PASS (runId 1791542089201247_c1326982907f1eee)

All 12 checks PASS on the real phone:
proto_closure_quiescent, oracle_identity_and_socket, create_owned_schema,
crud_exact_values, invalid_sql_is_available, scripts_transactions_and_literals,
workbench_repository_round_trip, project_editor_and_saved_query, stop_runtime,
restart_persistence, cleanup_owned_fixture, final_stop.

- reportPath:
  `/data/storage/el2/base/files/mysql-ohos-probe/1791542089201247_c1326982907f1eee-CKOPHW/report.json`
  (saved: `build/mysql-port/preload-attempt4/{latest.json,owned-report.json,mysql.log}`)
- Server identity: version 8.4.6, "Source distribution", skipNetworking=1,
  port=0 (private Unix socket only), serverUuid
  `0e1a664c-c3cd-11f1-bc11-73948d057024`, serverPid 43853.
- Restart: same serverUuid, same socket/pid-file, different PID 43948 ->
  clean stop + fresh restart, persistence held.
- Cleanup: schemaDropped=true, projectRemoved=true, runtimeStopped=true.
- Device/ABI: MRT-AL10, API 26, arm64.
- Host: preloaded direct entry (fork + call the private server entry; no exec),
  isolated probe root. stopChild graceful-first fix resolved the exit-143 race.

Normal app (`lib/main.dart`) HAP rebuilt OK. Per coordinator sequencing, no
further Flutter HAP build until CORE_SNAPSHOT_READY / grant; then one Flutter
HAP build + CORE_RELEASE/SDK_FREE signal, then continue device probes.

## Current accepted state (hold for coordinated release)

- Latest accepted device run: **1791542089201247_c1326982907f1eee, status=pass,
  12/12 checks** (identity/socket, CRUD, invalid SQL, scripts, workbench, editor,
  stop_runtime, restart_persistence, cleanup, final_stop). The earlier 8-pass run
  1791541125739749 is superseded; shutdown-143 and final_stop are already fixed
  (graceful-first stopChild) and verified on device.
- Native artifacts staged at 18:33: `libqfli_mysql.so`, `libqfli_mysql_server_proto.so`.
- Held per coordinator: no further Flutter HAP build until CORE_SNAPSHOT_READY /
  coordinated SDK release; then one Flutter HAP build + CORE_RELEASE/SDK_FREE,
  then continue device probes.
- Re-taken by pi-mysql after helper non-progress: `qfli_mysql_proto_probe.cpp/.h`,
  `native/mysql/qfli_mysql_stdio_protocol.h` (already contain the shared checked
  fork protocol). Waiting for the explicit file handback before further native
  edits to avoid overlapping writers.

## Ownership split (freeze)

- Retained by pi-mysql: `qfli_mysql_napi.cpp`, `QfliMysqlRuntime.ets`,
  `QfliMysqlNative.ets`, `EntryAbility.ets`,
  `integration_test/mysql_ohos_probe.dart`, CMake/packaging, all builds and
  device operations.
- Handed off (FROZEN by pi-mysql): `ohos/entry/src/main/cpp/qfli_mysql_proto_probe.cpp`,
  `qfli_mysql_proto_probe.h`, `native/mysql/qfli_mysql_stdio_protocol.h`, and a
  focused native test, owned by a focused implementer. `qfli_mysql_server_proto.cpp`
  holds the verified private-binding/interposer work.

## Ownership release (helper non-progressing -> re-taken by pi-mysql)

The focused implementer did not produce a new proto_probe version or a focused
native test, and left no helper-ready signal. The frozen files already contain
pi-mysql's own shared checked-fork implementation (`ForkMode` ExitSelfTest /
ServerEntry, lock-abort-BEFORE-fork, bounded handshake, enter_scope before any
Oracle exit, signal/FD reset, parent watchdog). pi-mysql re-takes ownership of
those files to finish the work; no competing helper is started.

## Exact latest evidence (runId 1791541125739749_7a3c97bd6142f31b)

- reportPath:
  `/data/storage/el2/base/files/mysql-ohos-probe/1791541125739749_7a3c97bd6142f31b-PITTEM/report.json`
- Passed: proto_closure_quiescent, oracle_identity_and_socket,
  create_owned_schema, crud_exact_values, invalid_sql_is_available,
  scripts_transactions_and_literals, workbench_repository_round_trip,
  project_editor_and_saved_query.
- Failed: stop_runtime (MYSQL_SHUTDOWN_FAILED, exit 143) and final_stop (PID file
  remains). Shutdown evidence: mysql.log shows
  `Received SHUTDOWN from user root. Shutting down mysqld (Version: 8.4.6)` —
  Oracle shut down gracefully; exit 143 came from the host's SIGTERM escalation
  racing it. Fix applied: `stopChild` now waits for the exit record without
  signalling after a successful `shutdown(socket)`.

See `research/phone-host-options-2026-10-09.md`. Under the app's normal policy
no OS-supported fresh-process mechanism exists on this phone (native=false,
ark=false, direct/interpreter exec EACCES). Adopting a preload+fork design is
not established safe (`research/phone-parent-preload-fork-safety-2026-10-09.md`)
and is deferred to a director decision. No risky design adopted.

## Packaging hypothesis test (attempt 1456, runId ...941815679)

Hypothesis: a packaging/settings difference could give the launcher an execute
bit. Falsified by the on-device diagnostic:

```
launcher=.../libqfli_mysql_launcher.so mode=0100644
sibling =.../libqfli_mysql.so          mode=0100644
interp  =/lib/ld-musl-aarch64.so.1     mode=0100755
```

OHOS installs **all** packaged native libs (launcher and the NAPI client alike)
as mode 0644; the app loads them via `dlopen`, never exec. `executableBinaryPaths`
(the only exec-enabling declaration) is rejected at install on this phone. So no
packaging change makes a packaged binary executable here, and the interpreter is
also denied exec from the app domain.

Conclusion: with the current bundle/policy on this phone there is no supported
fresh-process host. Evidence: `attempt-1456/latest.json`,
`attempt-1456/initialize.log`. No app crash, no data mutation.

## Option B design + isolated prototype (authorized)

Design: `research/option-b-private-preload-design.md`. Measured prototype
evidence for the **binding half**: adding a version script
(`native/mysql/qfli_mysql_server.map`) + `-Bsymbolic-functions` to the already
built server objects drops defined dynamic symbols from 83,032 to **3** and
leaves **zero** undefined Oracle/OpenSSL/ICU/abseil imports (629 remain, all
libc/libc++/runtime). Script: `native/tests/experiment-private-binding.sh`.
Remaining: static private libc++ (`libc++_static.a`/`libc++abi.a` exist in the
SDK), the 870-entry constructor audit, and the fork/exit/watchdog lifecycle.
Production app is NOT changed to use option B; only isolated scripts + this
design exist so far.

## Option B prototype evidence (binding + static C++ + ctor audit)

- **Private binding:** version script + `-Bsymbolic-functions` -> defined dynamic
  symbols 83,032 -> **3**; zero Oracle/OpenSSL/ICU/abseil undefined imports.
- **Static libc++:** relink with `-nostdlib++` + `c++/libc++_static.a` +
  `libunwind.a` -> `NEEDED` **`libc.so` only** (no `libc++_shared.so`); ABI stays
  **`std::__n1`** (19,643 symbols); still 3 exports, 0 Oracle/OpenSSL/ICU
  imports. Script `native/tests/experiment-static-libcxx.sh`.
- **Constructor audit:** `.init_array` is zero on disk, filled by 93,050
  `R_AARCH64_RELATIVE` relocs. RELA-resolution (`resolve-ctors.py`) finds **869**
  constructors: 868 `_GLOBAL__sub_I_*.cc` static initializers + `__do_init`; no
  OpenSSL/ICU/thread constructors.
- **Open blocker (not a passed gate):** the client already calls
  `mysql_library_init` -> `my_init()` -> `my_thread_global_init()`, setting
  persistent `my_init_done`/`my_thread_global_init_done` + TLS + THR_LOCK mutexes.
  A preload parent that also loads the server is therefore NOT a pristine
  snapshot; private binding does not fix this. Must be resolved (reset or
  separate image) before any lifecycle prototype.

**CORRECTION (reviewer-confirmed, verified locally):** the above was a FALSE
blocker. With the version script `local:*` + `-Bsymbolic-functions`, the private
server image defines `my_init_done` and `_ZL26my_thread_global_init_done` as
**local BSS symbols** at distinct addresses (`llvm-nm` shows `b` entries); neither
is exported nor imported. The client's `mysql_library_init` cannot set the
private server's copy. Do NOT add manual global resets. See
`native/tests/verify-static-closure.sh` output.

## Gate evidence (reviewer-endorsed)

- **Gate 1 (static closure):** `verify-static-closure.sh` on the static image:
  `NEEDED libc.so` only; no `libc++_shared`; no external `__call_once`,
  `__cxa_guard*`, `__gxx_personality`, `_Unwind_*`, or STL imports (only
  libc-provided `__cxa_atexit`/`__cxa_thread_atexit_impl` remain); 3 exports.
- **Gate 2/4 (mechanism):** `run-preload-mechanism-test.sh` passes — an interposed
  `pthread_create` wrapper observes constructor-time thread spawn (count=1), and a
  forked child exiting via `_Exit` does not run the inherited parent `atexit`
  sentinel.
- **DATA protocol:** probe root is `<filesDir>/mysql-probe/<runKey>` (short
  prefix); an existing per-run dir is rejected; the Unix socket path length is
  validated (<=107); the probe asserts `@@socket`/`@@pid_file` are under the
  returned root. The Dart `runId` is 33 chars; with `mysql-probe` the socket path
  stays within `sun_path`.
- **STDIO protocol:** `run-stdio-protocol-test.sh` passes — bounded
  `ftrylockfile` acquisition, release-all-on-timeout (proven by stdin being
  usable after a timeout), and repeated forks with concurrent parent stderr all
  exit cleanly. No `fflush(NULL)`/exit finalization; child discards inherited
  buffers with the public SDK `__fpurge`.
- **Actual arm64 Oracle DSO prototype:** `qfli_mysql_server_proto` builds with
  `NEEDED libc.so` only, 7 exported entries, and **verified interposer binding**
  (`exit`/`pthread_create`/`pthread_atfork` are local definitions with zero
  external imports and zero PLT relocations for them). The real functions are
  resolved eagerly in the parent constructor at `dlopen(RTLD_NOW)`; the child
  never lazily `dlsym`s. (`-Wl,--wrap` did NOT bind for these archive members;
  the verified approach is image-local interposers + `-Bsymbolic-functions`.)
- **NAPI/ArkTS owned-pid contract:** `startChild` now returns a structured
  `{pid, failed, owned, pendingPid, errno, error}`; `startHostChild` adopts a
  `pendingPid` on failure so `stop()`/`dispose()` can clean it.

## Production-config revalidation (runId 1791543204596329_6d7175e0ff852321)

Status=**pass, 12/12 checks**. reportPath
`/data/storage/el2/base/files/mysql-ohos-probe/1791543204596329_6d7175e0ff852321-WGSWEO/report.json`
(saved under `build/mysql-port/prod-revalidation/`). Built with the production
host configuration (preload host unconditional; NAPI/CMake no longer gated by
QFLI_MYSQL_PRELOAD_PROTOTYPE).

**There is NO new CHECK_FAIL.** The clock (`CLOCK_MONOTONIC is unsupported`) and
InnoDB memory-barrier warnings are **pre-existing build-config gaps present in the
proven 12/12 binaries too**; they are **not** the `Permission denied` root cause
(that was exec EACCES on the launcher/interpreter, fixed by the preload host).

Native correctness deltas under review (NOT yet applied):
1. InnoDB memory barrier: `storage/innobase/innodb.cmake` wraps the
   HAVE_IB_GCC_ATOMIC_THREAD_FENCE / HAVE_IB_GCC_SYNC_SYNCHRONISE
   CHECK_C_SOURCE_RUNS probes in `IF(NOT CMAKE_CROSSCOMPILING)`, so cross builds
   define neither and `os0atomic.h` uses empty `os_rmb`/`os_wmb` ("Memory barrier
   is not used"). Must be proven on a real aarch64 compile probe before changing.
2. Monotonic clock fallback: HAVE_CLOCK_GETTIME=FALSE / HAVE_CLOCK_REALTIME=FALSE
   are forced, so `os0event.cc` skips pthread_condattr_setclock. The warning does
   not prove the phone lacks the clock; resolve or document on evidence.

Ownership/scheduling: pi-terminal owns Flutter/core writes; request a fresh saved
CORE_SNAPSHOT_READY + SDK RELEASED and hold it stable before any next HAP.
pi-mysql remains sole MySQL writer/operator; helper handback complete.

## Atomic-fence native delta (fence enabled, tested)

- Proven defect (source+preprocess): `innodb.cmake` gates the fence probes behind
  `IF(NOT CMAKE_CROSSCOMPILING)`, so the OHOS cross build defined neither macro
  and `os0atomic.h` used empty `os_rmb`/`os_wmb`. Real preprocessing of
  `os0atomic.h` with the actual innobase flags now yields
  `os_rmb -> __atomic_thread_fence(2)` (ACQUIRE) and
  `os_wmb -> __atomic_thread_fence(3)` (RELEASE).
- Target support proven: Clang 18 `--target=aarch64-linux-ohos` compiled AND
  linked a shared object using both fences; disassembly shows real `dmb ishld` /
  `dmb ish` barriers (native/tests/probe-atomic-fence.sh).
- Compile recipe proof: `storage/innobase/CMakeFiles/innobase.dir/flags.make`
  now contains `-DHAVE_IB_GCC_ATOMIC_THREAD_FENCE=1`; `srv0start.cc.o` was
  recompiled and its only barrier message is
  "GCC builtin __atomic_thread_fence() is used for memory barrier".
- Object->archive->DSO trace: `srv0start.cc.o` and `libinnobase.a` contain only
  the fence message. The DSOs still contain the "not used" text, but that text is
  **catalog data** from `share/messages_to_error_log.txt` (an error-log message
  catalog), not the executed branch. No source TU emits it.
- Delta: production server .so 89004056 -> 89004736 (+680 B, fence codegen in
  InnoDB). Baseline 12/12 PASS HAP: hap-prod-20261009-185223.log
  (run 1791543204596329_6d7175e0ff852321). Revalidation of this native delta is
  pending; it uses the same checked preload/ownership/cleanup contract.

## Monotonic-clock fallback

- `HAVE_CLOCK_GETTIME=FALSE` / `HAVE_CLOCK_REALTIME=FALSE` are forced in the
  cross configure, so `os0event.cc` skips `pthread_condattr_setclock`. This is a
  behavior fallback (uses a different wait mechanism), not a proven phone
  limitation; it is present in the 12/12-passing binaries and did not cause a
  failure. Documented as a known, non-blocking fallback; not changed to avoid
  unproven flag churn.

## Cold production backup (complete, verified)

- Source: `/data/storage/el2/base/haps/entry/files/mysql` (app-visible) /
  `/data/app/el2/100/base/<bundle>/haps/entry/files/mysql` (shell physical view).
- **259 / 259 regular files fetched and size-verified** via `hdc file recv -b`,
  total 168.2 MB. Located at
  `build/mysql-port/prod-cold-backup-20261009/mysql/`, with
  `prod-file-sizes.txt` (source manifest) and `backup-manifest.sha256.txt`
  (path size sha256). No chmod, no skips; failures would abort the script.
- Real user data preserved: `data/qfli_project_4fedf250.../notes.ibd`,
  `data/azurekiln/ttt.ibd`, plus all InnoDB files/logs/keys/config/system schemas.
- User stores: `sql_engine.json` = `{"engine":"localMysql"}`
  (sha256 05745d936c15f8e58396732bb49546e92c1454dfa9f502afc5c1b25282f671f8);
  `sql_queries.json` **absent** (confirmed). Preserved as-is.
- Observation: the production root contains a **stale `mysql.pid` (12899)** and
  `mysql.sock.lock`; the last production-root server did not cleanly remove them.
  MySQL is currently **stopped** (no mysqld process). Normal launch must handle
  the stale pid/socket lock as the runtime already does (remove-if-exists).

## Accepted native artifact manifest

`build/mysql-port/native-artifact-manifest.txt`:
- libqfli_mysql.so 15004600 e812c680f5cdb172d92b2cf78c31eddda8bce48d5c1d5be85d3a0bab1a8355d2
- libqfli_mysql_server.so 89004736 05fbfbb0dc55da94d56c11f995e8d95426cc19511aa3e193797c9e41cff0d6a2
- libqfli_mysql_server_proto.so 81011056 f216e6def30a0c761af6c13dd5a1c6dcd2dc90280605db8d0ebd342b668a2446
- libqfli_mysql_launcher.so 22560 ef54810dfeff3260e8563dd1c19cccc7c09ecd1e0ea569de09ca700d6f9ed76c
(The server 89004736 / proto 81011056 include the fence delta; source/ELF
identity recorded. Baseline 12/12 HAP build log: hap-prod-20261009-185223.log —
a BUILD LOG, distinct from the signed .hap artifact.)

## Production-root stopped-state evidence (not just pidof)

- Stale `mysql.pid` = 12899; `/proc/12899/status`: Name `kiln.qfli.sqlab`,
  **State S (sleeping)**, PPid 12476, Uid 20020371 (the app uid). So a **live
  forked server child** from a prior production-root run is still present — the
  exact "fork children inherit the app name" case. `kill -0 12899` from shell is
  denied (different domain).
- `initialize.exit` = `0` (clean init); **`server.exit` absent** -> the prior
  server did not record a clean exit.
- MySQL runtime is therefore treated as **not authoritatively stopped** for the
  old child; an app reinstall replaces the app process tree (killing the old
  child). After install, re-verify no live app-uid child holds the production
  datadir before normal launch.
- Stale `mysql.sock` (s?-type) and `mysql.sock.lock` present; the runtime's
  remove-if-exists startup handles these.

## Verified cold backup + HAP artifacts (2026-10-09)

Cold backup (VERIFIED, from a stopped state):
- `build/mysql-port/prod-cold-backup-20261009/mysql/` — **259/259 files,
  168.2 MB**, size-verified via `hdc file recv -b`; manifest
  `prod-file-sizes.txt` (source) and `backup-manifest.sha256.txt` (path size
  sha256). `ibdata1` re-hash after copy was **stable** (no writer), so the copy
  is consistent (not a live InnoDB snapshot).
- Earlier live copy preserved separately as **UNVERIFIED**:
  `build/mysql-port/prod-backup-UNVERIFIED-live-20261009/`.
- Stopped-state proof: stale PID 12899 (`/proc/12899` gone; parent 12476 gone),
  app force-stopped, no `com.azurekiln.qfli.sqlab` process.
- User stores: `sql_engine.json` = `{"engine":"localMysql"}`
  (sha256 05745d93…); `sql_queries.json` absent.

HAP artifacts (`build/mysql-port/artifacts/`):
- `entry-fence-probe-20261009.hap` 263008835 sha256 e19c319d79df50e731e561e45baad18ac7f98167e657e809f3a0a79820047bc7
  (fence-delta probe, installed on device at 19:59).
- `entry-normal-main-20261009.hap` 274055738 sha256 5f70e8f3a2ead1b34d3b0e1f680aa38cad771409ee303494d8b4f17158236480
  (normal main.dart from the held core checkpoint; retained, NOT installed yet).

Stale `latest.json` on device (runId 1791543204596329...) is the prior run; the
19:59 `aa start` failed with 10106102 (screen locked), so it is NOT a new run.
Fence revalidation requires a fresh START/runId after unlock.

## Fresh launch attempt (fence probe installed)

- 2026-10-09 20:13:06 — `aa start -a EntryAbility -b com.azurekiln.qfli.sqlab`
  returned `10106102` ("device screen is locked during the application launch,
  unlock screen failed"; developer mode blocks auto-unlock). No new runId; the
  device `latest.json` remains the prior run 1791543204596329_6d7175e0ff852321.
- Waiting on the existing user unlock request; no repeated prompts, no unlock
  bypass, no new build.
