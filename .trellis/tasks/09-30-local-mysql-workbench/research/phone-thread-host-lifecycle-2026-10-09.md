# Research: Oracle MySQL 8.4.6 hosted by a native application thread

- Query: Can an ordinary HarmonyOS phone application run the packaged Oracle server in a dedicated native thread, with private symbols and cooperative initialization, start, stop, and restart?
- Scope: mixed; prepared Oracle 8.4.6 source, current project integration, local dependency headers, and previously inspected ELF bindings. Architecture research only.
- Date: 2026-10-09

## Findings

**This is a technically credible source-adaptation direction, but the current wrapper is unsuitable unchanged.** A normal application-native thread avoids the inherited-runtime hazards of fork and does not need a native-child or executable-launch capability merely to enter a packaged DSO. It does not, however, turn the standalone mysqld entry point into an embedded-library API. The concrete remaining work is controlled completion, process-wide effects, private Oracle/client state, and repeatable lifecycle teardown.

The parent's current phone evidence is MRT-AL10, OpenHarmony-7.0.0.105 / HongMeng kernel: native-child capability false, Ark-child capability false, direct packaged exec EACCES, and direct system-interpreter exec EACCES. Those findings motivate investigating threads; they do not prove that every syscall reached by the server is permitted in the app sandbox. This researcher performed no device commands.

### Source identity and current integration

All Oracle line references below refer to the prepared source in WSL distribution `qfli-java-build`, rooted at `/root/qfli-mysql-port/mysql-8.4.6`, unless another path is given.

- `sql/mysqld.cc:8886` is the Unix `mysqld_main`; the entry near line 10097 is Windows-specific.
- `native/mysql/qfli_mysql_server.cpp:66-114` parses a JSON payload, sets `ICU_DATA`, allocates argument storage, and calls `mysqld_main`. The exit hook records a code; it does not change termination semantics.
- `ohos/entry/src/main/ets/plugins/QfliMysqlRuntime.ets:475-482` passes the same config to initialization and service, adding `--initialize-insecure` for initialization. Lines 584-601 configure an absolute data directory, socket, PID and error-log paths, disable networking/binlog, and use a 32 MiB InnoDB buffer pool.
- `native/src/qfli_mysql_client.cpp:333-344` already sends a real Oracle `mysql_shutdown(..., SHUTDOWN_DEFAULT)` request. A thread design can preserve real SQL shutdown semantics; it must change what happens after shutdown completes.

### 1. Intentional process exits must become controlled server completion

| Prepared source | Reachable condition | Current effect |
| --- | --- | --- |
| `sql/mysqld.cc:2607-2636` | `mysqld_exit`: success, failure, or restart completion | Performs final cleanup, invokes the OHOS recording hook, then calls ordinary `exit(exit_code)`. |
| `sql/mysqld.cc:10266-10323` | Successful `--initialize` / `--initialize-insecure` | `process_bootstrap` calls `unireg_abort(MYSQLD_SUCCESS_EXIT)`, which reaches `mysqld_exit`. Success currently terminates the host process. |
| `sql/mysqld.cc:9976-9977` | Normal server shutdown | `clean_up(true)`, then `mysqld_exit(signal_hand_thr_exit_code)`. |
| `sql/mysqld.cc:3728` | Failure creating the signal-handler thread | Direct `exit(MYSQLD_ABORT_EXIT)`, bypassing the recording hook. |
| `sql/mysqld.cc:9206` | `init_ssl()` failure | Direct abort exit. |
| `sql/mysqld.cc:9290-9300` | Early command-line parsing error | Direct abort exit. The nearby comment mentions Windows, but this exit is in the inspected Unix entry path, not guarded as Windows-only. |
| `sql/mysqld.cc:11736,12136,13191` | Help charset lookup failure; version option; PID-directory inspection error | Three additional direct exits. Fixed internal options can exclude help/version, but PID and initialization errors remain production-relevant. |
| `storage/innobase/srv/srv0start.cc:3125-3135` | `srv_fatal_error()` | Explicit `std::_Exit(3)`. This is an unrecoverable engine-error path, distinct from routine lifecycle completion. |

The ordinary `exit` also invokes process termination/finalization; calling it from a worker does not restrict it to that worker.

Changing just the last exit to `pthread_exit`, or returning from `mysqld_exit` into callers that assume it never returns, is not a lifecycle implementation. Calls arrive from nested startup/abort paths, and worker threads/resources may already exist. The core needs a deliberate completion boundary and stage-aware unwind. `longjmp` across C++ frames or asynchronous thread cancellation is not a substitute for destructor/resource cleanup.

There are also ordinary early `return 1` paths after state has been initialized: examples include persisted-variable setup and component initialization, and authentication-policy failure after `start_signal_handler()` (`sql/mysqld.cc:9794-9804`). A wrapper receiving an integer is not evidence that all work has stopped or that the image can immediately be re-entered.

It is reasonable to retain process-fatal behavior for genuinely unrecoverable native corruption as an explicit embedding tradeoff. It is not reasonable for successful initialize, normal stop, or an expected configuration error to terminate the app. The acceptance condition is a finite audit of the configured release build's lifecycle/error paths, not proof that arbitrary C++ can never crash.

### 2. A thread shares process-wide operating-system state

| Effect | Evidence | Required adaptation |
| --- | --- | --- |
| Signal dispositions | `sql/mysqld.cc:3621-3691` installs fatal handlers, ignores SIGPIPE, installs an ALRM handler, and resets TERM/HUP/USR1 dispositions. | Integrate with the application runtime or replace server control signalling; a worker thread does not own these dispositions. |
| Signal mask | The same function calls `pthread_sigmask` only on the invoking thread; later MySQL threads inherit its mask. | Do not assume existing Flutter/Ark/native threads inherit the server mask. Restoring it later does not protect those threads while the engine runs. |
| Stop/listener wakeup | `kill_mysql` uses directed `pthread_kill(signal_thread_id, SIGTERM)` (`:2504`); the signal thread uses directed ALRM to wake the listener (`:3836`). | These calls are directed, not indiscriminate process kills. A cooperative control/wakeup implementation can replace their dependency on process-wide handlers. |
| Current directory | `sql/mysqld.cc:9476-9482` calls `my_setwd(mysql_real_data_home)` for ordinary service and initialization. | Absolute configured paths alone do not prevent this change. Remove the global cwd dependency or deliberately coordinate it. |
| File creation mask | `sql/mysqld.cc:9210` sets `umask`. | Use engine-owned creation permissions without racing concurrent host file creation. |
| stdout/stderr | `sql/log.cc:1889-1921` opens the configured error log with `my_freopen` on both streams. The application currently supplies `log-error`. | Use a dedicated log stream/sink instead of rebinding the application's standard streams. |
| ICU/environment | Wrapper `:89` sets `ICU_DATA`; `clean_up` calls `u_cleanup()` (`sql/mysqld.cc:2789`). | Keep ICU ownership and configuration explicit; avoid cleaning state used by another consumer. |

Optional daemonization, chroot, and core-limit changes also exist, but the current generated options do not request them. They can be excluded from the embedded configuration rather than treated as unavoidable runtime behavior. Saving/restoring cwd, umask, streams, or dispositions only at shutdown is insufficient if another host thread observes them during execution.

### 3. Some reset support exists; specific gaps still block blind re-entry

The source has substantial intentional teardown and reset:

- `mysql_init_variables()` (`sql/mysqld.cc:11803-11920`) clears `server_shutting_down`, resets the connection-loop abort flag, resets operational state to booting, and resets many counters, options and paths.
- `mysys/my_init.cc:258` resets `my_init_done` in `my_end`.
- `mysys/charset.cc:588` reconstructs `charsets_initialized`, so its use of `std::call_once` is not by itself a restart blocker.
- `clean_up()` (`sql/mysqld.cc:2711-2860`) shuts down storage/plugins/components, destroys connection/THD singletons, closes TLS contexts and frees many resources.
- InnoDB has an old comment warning about repeat startup (`srv0start.cc:1626-1635`), but normal shutdown **does** reset `srv_start_has_been_called=false` and `srv_start_state=NONE` at `:3104-3105`. Quoting only the old comment would overstate the case.

Concrete unresolved reset defects in the inspected source:

1. **InnoDB shutdown phase remains terminal.** `srv_shutdown_state` is initialized once to `SRV_SHUTDOWN_NONE` (`srv0start.cc:162`), advances through shutdown and reaches `SRV_SHUTDOWN_EXIT_THREADS` (`:1364,3047`). A bounded search of the InnoDB source found stores that advance shutdown but no subsequent store to NONE. `srv_pre_dd_shutdown()` explicitly requires NONE (`:2600`). Resetting only the separate startup guard does not establish a valid second lifecycle.
2. **SQL startup/completion latches are incomplete.** `mysqld_server_started` is initialized false (`mysqld.cc:1633`) and set true (`:1988`), but a search across `sql/` found no later reset. `mysqld_process_must_end_at_startup` is initialized false (`:1643`), set true for early stop (`:2488`), and later consumed (`:9830`) without a found reset. `signal_hand_thr_exit_code` can become the restart code (`:3794,8628`) without a found per-run reset.
3. **TLS pointers leave a partial-start cleanup hazard.** `end_ssl()` (`mysqld.cc:7102-7105`) passes global pointers to `TLS_channel::singleton_deinit`; that function deletes its by-value argument and does not clear the owning pointer (`sql/ssl_acceptor_context_operator.cc:94-97`). `singleton_init` resets its output before rebuilding (`:51-56`), which helps a fully successful next startup. It does not make an intervening startup failure before TLS initialization safe to clean up again. Owning pointers and initialized-stage tracking need explicit treatment.

These are source-level defects/risks, not phone crash observations, and are not claimed to be the complete set. First-run initialization followed by serving already exercises a second lifecycle in the same image; this is not only an optional later restart feature.

### 4. OpenSSL is not proven to be permanently shut down by existing cleanup

`end_ssl()` only releases server TLS contexts and RSA keys. `vio/viosslfactories.cc:293-323` pairs `vio_ssl_end()` with `ssl_start()`, resets `ssl_initialized=false`, and uses the legacy `ERR_free_strings`, `EVP_cleanup`, and `CRYPTO_cleanup_all_ex_data` calls.

The local OHOS OpenSSL headers identify **3.5.3** (`build/mysql-port/openssl-ohos/include/openssl/opensslv.h:30-32,91`). Those three cleanup calls are no-op macros in this version (`err.h:482`, `evp.h:1222`, `crypto.h:289`). No call to `OPENSSL_cleanup()` was found in the inspected server/VIO/mysys/libmysql lifecycle locations.

OpenSSL's bundled `doc/man3/OPENSSL_init_crypto.pod:191-205` does say explicit `OPENSSL_cleanup` cannot be followed by reinitialization. That rule must not be misapplied to the legacy no-op cleanup calls. FIPS/provider ownership, crypto allocator callbacks and sharing with the client still require deliberate ownership, especially if symbols interpose.

### 5. Private binding is necessary, but private libc/libc++ is not the goal

The existing ELF proof is in [the preload/binding note](phone-parent-preload-fork-safety-2026-10-09.md), section 2. Both staging DSOs export and dynamically relocate overlapping Oracle mysys function/data symbols including `my_init_done`, `my_init`, and `my_end`. `RTLD_LOCAL` alone does not establish private incoming binding.

An embedded build needs a narrow exported entry/status/control ABI and verified local binding for the duplicate Oracle/mysys/client/OpenSSL/ICU state that it owns. Common platform libc, allocator and libc++ use is normal for threaded embedding; unlike the fork proposal, it does not require proving a pristine inherited runtime or private copies of every system runtime.

Keep one live engine instance at a time unless the core is separately made instance-safe. Do not use repeated `dlclose/dlopen` as an assumed reset: unloading requires all engine threads, TLS destructors, callbacks and references to be gone, and dependent DSOs may remain loaded.

### Practical feasibility boundary and evidence needed

A useful implementation sequence would establish:

1. A packaged, privately bound engine entered asynchronously on an owned native thread, with process-wide startup behavior adapted for the host.
2. Successful initialization returning a result while the app stays alive, with a proven clean boundary before service startup.
3. Real SQL service, writes, cooperative stop, thread completion, socket closure and durable storage.
4. Repeated stop/start and initialize-to-serve, plus startup failures at several initialized stages and stop during startup. Verify the app remains usable and no old engine thread/handle services the new run.

A smaller single-lifetime demonstration against an already initialized directory can validate native-thread execution with less work. It does not complete fresh-install initialization or actual restart. Leaving the engine alive while the UI labels it stopped is not a genuine stop.

An embedded host loses independent crash containment and cannot safely force-kill just the server thread after a hung shutdown. That is an architectural tradeoff to report, not a reason to demand impossible guarantees. On a failed cooperative stop, ownership must remain truthful and a new instance must not start over uncertain old state.

### Files found / related specs

- `native/mysql/qfli_mysql_server.cpp`: current allocating entry wrapper and exit recorder.
- `native/mysql/ohos-targets.cmake`: server/client link graph; currently no proven private binding boundary.
- `native/mysql/patches/0001-ohos-platform.patch`: exit hook records but does not intercept process termination.
- `native/src/qfli_mysql_client.cpp`: real client and shutdown path.
- `ohos/entry/src/main/ets/plugins/QfliMysqlRuntime.ets`: two-phase child lifecycle and generated Oracle configuration.
- Prepared `sql/mysqld.cc`, `sql/log.cc`, `sql/ssl_acceptor_context_operator.cc`: startup, termination, process effects and TLS lifecycle.
- Prepared `mysys/my_init.cc`, `mysys/charset.cc`, `vio/viosslfactories.cc`: existing reset mechanisms.
- Prepared `storage/innobase/srv/srv0start.cc`: startup guard, shutdown phase and fatal exit.
- `build/mysql-port/openssl-ohos/include/openssl/`, `build/mysql-port/openssl-3.5.3/doc/man3/OPENSSL_init_crypto.pod`: version-specific OpenSSL evidence.
- `.trellis/workflow.md`: research persistence and phase boundaries.
- `.trellis/spec/backend/mysql-workspace.md`: real Oracle, private socket, lifecycle and real-device acceptance.
- `research/ohos-resume-2026-10-09.md`: earlier accepted design requires fresh children and prohibits entering mysqld in Flutter. This note evaluates a proposed alternative; it does not silently replace that implementation contract.

### External references / versions

- Oracle prepared source version **8.4.6**, read from the local authoritative WSL tree.
- OpenSSL **3.5.3**, local installed headers and bundled upstream manual cited above.
- [OpenSSL initialization manual](https://docs.openssl.org/3.5/man3/OPENSSL_init_crypto/): navigation equivalent of the bundled manual; the local manual was the verified text.
- [Phone extension/companion boundary assessment](phone-extension-companion-boundaries-2026-10-09.md): remaining supported process alternatives.

## Caveats / Not Found

- No code edits, builds, tests, device commands, or git operations were performed.
- The lifecycle inspection is bounded, not an exhaustive Oracle subsystem or fatal-path audit.
- No thread-host implementation or successful initialize/start/stop/restart sequence has been demonstrated on the phone.
- The older SIGSYS event cannot be assigned to a specific syscall from the earlier missing-log inference; that inference used the wrong runtime directory.
- Parent reports the correct runtime directory as `/data/storage/el2/base/haps/entry/files/mysql`.
- Oracle's official removed-libmysqld page was not successfully retrieved during this work; no freshly verified quotation from it is used.
- Pi is concurrently modifying implementation. Project line references describe the inspected snapshot; prepared Oracle references identify the WSL source used here.

