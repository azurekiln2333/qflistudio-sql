# Phone native host for Oracle MySQL

## Problem

HarmonyOS gates `childProcessManager.startNativeChildProcess` and
`OH_Ability_*NativeChildProcess` to PC/2-in-1 (API13+) and tablets (API14+).
The acceptance target is a phone, so the current host cannot start Oracle.

## Options assessed

1. `startNativeChildProcess` / `OH_Ability_*` — API gated; the current SDK24
   `@ohos.app.ability.childProcessManager.d.ts` and `native_child_process.h`
   still restrict it. Kept for tablet/2in1.
2. `startChildProcess` / `StartMode` — starts an ArkTS module or a fork; cannot
   load the native server entry, and `SELF_FORK` forbids Binder IPC. Rejected.
3. `fork()` then `dlopen` the server in the child — rejected: from a
   multithreaded Flutter process the child would inherit loader/allocator locks
   and C++ runtime state before loading MySQL. This is not fork-safe.
4. `fork()` + `execve()` of a packaged PIE launcher — selected. The child
   performs only descriptor/signal/exec operations; a fresh process image loads
   the server. `mysqld_main`'s `exit()` only terminates the launcher process.

## Implemented design

### Fork + exec (not post-fork dlopen)

`native/mysql/qfli_mysql_host.cpp` `start_child()`:

- Builds argv and environment before fork; allocates nothing in the child.
- Creates an exec-error pipe, both ends `FD_CLOEXEC`. The child writes its exec
  errno as raw bytes if `execve` fails, then `_exit(127)`. The parent reads the
  pipe: EOF means exec succeeded; 4 bytes mean startup failed with that errno.
  No stdio/`strerror`/allocation happens in the child.
- Child only: `prctl(PR_SET_PDEATHSIG, SIGKILL)`, re-check `getppid()`, reset
  SIGTERM/SIGINT/SIGPIPE/SIGHUP to default, redirect stderr to an app-private
  log, close every inherited descriptor except stdio and the error pipe, then
  `execv`. The descriptor closing is explicit (`close_inherited_descriptors`),
  not merely relying on a CLOEXEC flag that inherited parent handles may not set.
- The parent reaps a child that failed to exec, so no zombie is left.

A regression test opens a non-CLOEXEC fixture descriptor in the parent and
asserts it is absent from the exec'd child's descriptor list, proving inherited
handles are closed rather than assumed CLOEXEC.

`native/mysql/qfli_mysql_launcher.cpp` is a PIE executable staged with a `.so`
name (`libqfli_mysql_launcher.so`). It resolves its own directory with `dladdr`,
`dlopen`s `libqfli_mysql_server.so` beside it, and calls the exported
`qfli_mysql_child_main(argv[1])`. The server entry lives in
`native/mysql/qfli_mysql_server.cpp`; both `QfliMysqlMain` (native-child API)
and `qfli_mysql_child_main` share one JSON parser, ICU env handling, and exit
record.

### Typed child status

`poll_child()` returns `{state, exitCode}` where state is `running`, `exited`,
or `unknown`. A successful exit 0 is therefore never confused with a running
child. Terminal status is retained until `release_child()` and repeated polls
are idempotent. `release_child()` rejects a still-running child.

### Two child kinds

- **Forked** (`start_child`): `waitpid(WNOHANG)` is the authoritative reaper.
- **Registered** (`register_child`): the HarmonyOS native-child API started the
  process and AppSpawn may be its parent, so `waitpid` is never used. A stable
  kernel identity is captured at registration (`pidfd_open` where available,
  plus the `/proc/<pid>/stat` start-time). Liveness and every `kill` re-verify
  that identity first, so a PID recycled after AppSpawn reaps the child is never
  signalled. Completion is explicit through
  `complete_registered_child(pid, exitCode)` after the exit record is observed.
  `waitpid` `ECHILD` is never treated as success and there is no arbitrary
  `kill(0)` fallback. Fork-owned unreaped children remain fine (waitpid reaps).

### Cancellation

`signal_child(pid, force)` is signal-only (SIGTERM, or SIGKILL when forced) and
never blocks. The ArkTS runtime polls `pollChild` with bounded async escalation
and only reports success after observing an `exited` status, not from a single
`WNOHANG` after `SIGKILL`.

## ArkTS lifecycle (`QfliMysqlRuntime.ets`)

- Host selection by `deviceInfo.deviceType`: phone → fork+exec; `2in1`/`tablet`
  → native-child API, with fork+exec as the fallback host.
- `Initialize-insecure` and normal service use separate fresh children.
- Bounded readiness/exit timeouts; every initialization/shutdown path terminates
  and awaits a terminal typed status before clearing the PID.
- `stop()` coalesces concurrent calls through one promise. `stopChild()` reports
  whether a terminal state was **confirmed** and any diagnostic error, without
  deciding ownership. `stopInternal()` clears `pid`/`host`/`closing` whenever the
  child is confirmed terminal — including when shutdown reports a nonzero exit
  or a release error — so a later stop/restart cannot fail `ECHILD` on an
  already-released PID. Ownership and `closing` are retained only while
  termination is unconfirmed (a timeout), so a later stop can retry.
- For registered native-child processes, `settleStatus()` reads and completes
  the exit record before the final status is reported, so the sentinel `125` is
  replaced by the real mysqld exit code.
- `diagnostic()` surfaces `initialize.log`, `server.stderr.log`, and `mysql.log`,
  so pre-mysqld exec/loader failures are visible, not just mysqld's own log.
- `dispose()` marks `disposed` before awaiting `stop()`.

## Phone probe results

**First probe (kernel HongMeng Kernel 1.13.0, app PID survives):**
`oracle_identity_and_socket` failed in ~852 ms with
`Oracle MySQL exited without an exit result (status exited, code 159)`. Code 159
= 128 + SIGSYS (31), i.e. the forked child died on a syscall filtered by the app
sandbox. `initialize.log` did **not** exist (`hdc file recv -b` ENOENT), so with
the previous build (child opened the log itself) the child died **before** its
first log write. Full report:
`build/mysql-port/phone-probe-first-result.json`. No shell crash-log access.

**Suspects and disposition (root cause still provisional):** the phone path used
`close_range` (now removed) and `prctl(PR_SET_PDEATHSIG)` (now removed), plus
standard `fork`/`signal`/`open`/`dup2`/`execv`. `pidfd_open` is only on the
native-child path, not the phone path. The exact failing syscall is **not yet
proven** and is not assumed to be `execve`.

**Narrow corrections shipped in this batch:**
1. The raw `close_range` optimization was replaced with the portable `close()`
   loop.
2. `prctl(PR_SET_PDEATHSIG)` was removed from the fork child. Parent-death
   cleanup now runs in the **launcher** as a `getppid()` watchdog thread
   (`pthread_create` + `nanosleep` + `_exit`), using only standard supported
   calls. The host passes the **original app pid** (captured before fork) as
   `argv[2]`; the launcher validates it (`> 1`) and requires
   `getppid() == passed pid` before starting the watchdog or the server. There is
   no `kill(parent, 0)` probe (EPERM is not parent death). If `pthread_create` or
   the signal mask fails the launcher reports the error and exits 125 rather
   than starting the server unprotected. The launcher main blocks
   SIGTERM/SIGINT/SIGHUP/SIGQUIT **before** creating the watchdog so the watcher
   inherits them blocked from creation, then restores the original mask in the
   main thread.
3. The launch log is now opened by the **parent before fork**, and the child
   writes async-signal-safe stage markers (`[launch] fork`, `parent-ok`,
   `signals`, `fds-closed`, `exec-failed`, `exec-interp`). The failed-exec errno
   is captured immediately after `execv` before any marker write. The launcher
   adds its own stage markers (`launcher-main`, `dlopen-before`, `watchdog-ready`,
   `dlopen-after`, `entry-before`, `parent-gone`).

**Second probe (app PID survives, no SIGSYS):** the log now reached
`[launch] fork -> parent-ok -> signals -> fds-closed -> exec-failed`, so direct
`execv` of the packaged launcher failed **before** launcher main. The error was
`Permission denied` (EACCES) — the installed launcher in the module libs has no
execute bit. Report: `build/mysql-port/phone-probe-stages-result.json`; stages:
`build/mysql-port/phone-initialize-stages.log`. No SQL/data mutation;
`final_stop` passed.

**Corrections for the EACCES finding (this batch):**
- The host now appends a rich diagnostic on exec failure with the launcher
  **path, errno, mode/uid/size** and the interpreter path/mode, so the next probe
  shows the exact permission state rather than a naked `Permission denied`.
- A **guarded API26 capability probe** was added:
  `childProcessManager.isNativeChildProcessSupported()` is queried at runtime
  (try/catch; API26 only). If it reports `true`, the runtime prefers the normal
  public native-child API on phone; the result is written to
  `<root>/capability.log` so the probe shows what the OS actually reported.
  Static docs (PC/tablet-only) are never the sole basis when the query exists.
- If direct exec fails with EACCES/ENOEXEC, the child retries through the
  on-device ELF interpreter (`/lib/ld-musl-aarch64.so.1`) of the same signed,
  installed launcher, with an `exec-interp` marker. This keeps all OS
  permission/code-signing checks in force; it does not chmod, copy, or bypass
  anything. Device note: `/lib/ld-musl-aarch64.so.1` and
  `/system/lib/ld-musl-aarch64.so.1` exist mode 0755 root:shell, but invoking it
  from hdc shell also returned `Permission denied` (shell-domain evidence only;
  app-domain remains unproven).



## Device gating and packaging (unproven on phone)

1. **`executableBinaryPaths` is API24 and declared to be effective only on
   PCs/2-in-1** (official module configuration reference,
   `build/mysql-port/module-configuration-reference.md`).
   **Observed device result (MRT-AL10 phone, OpenHarmony-7.0.0.105, target
   API24):** with the field declared for
   `libs/arm64-v8a/libqfli_mysql_launcher.so`, `hdc install -r` returned
   `code:9568449 error: check bin file failed` (`9568449 = 0x9200C1`, a BMS
   bin-file validation error).
   **Provisional root cause (NOT yet proven):** the phone BMS rejects the
   unsupported field. A pre-probe HAP
   (`build/mysql-port/entry-production-before-phone-probe-20261009.hap`) had no
   field and no launcher and had installed, but that is a different binary and
   is not a controlled A/B.
   **Controlled same-binary confirmation:** the same native binary with
   `executableBinaryPaths` removed built (`18.4 s`) and `hdc install -r` now
   reports **install bundle successfully** on this phone. This confirms the
   removed declaration caused the installation rejection (`9568449`) for this
   package on this phone.
   **Still not a runtime proof:** no Oracle startup/persistence result exists
   yet. `aa start` returned `10106102` only because the phone screen was locked.
   The exact field-vs-ELF breakdown also stays provisional until an actual
   runtime probe with the field removed is observed.
   **Current handling:** the field is removed from the phone module, because the
   reference states it takes effect only on PCs/2-in-1 and it therefore cannot
   be relied on to authorize an executable on a phone.
2. **The launched PIE requests interpreter `/lib/ld-musl-aarch64.so.1` and needs
   `libc++_shared.so` + `libc.so`.** The launcher ELF is a valid AArch64 `DYN`
   with `.note.ohos.ident`. Whether the app sandbox resolves that loader and
   permits `execve` of the packaged launcher is still unproven; it is testable
   only by a probe, and any failure is reported as a real loader/errno result.

Only a real device probe can decide point 2. If phone exec is denied, the design
needs a different supported/safe host; a post-fork `dlopen` (the pattern used by
`qfli_java`) is **not** an acceptable fallback here, because forking the
multithreaded Flutter process and then loading MySQL inherits loader/allocator
locks and C++ runtime state.

## Tests

`native/tests/qfli_mysql_host_test.cpp` exercises the **real production host**
and the **real production launcher** against a stub server entry
(`qfli_mysql_child_stub.cpp`). It covers: successful exit 0 distinguishable
from running; idempotent repeated polling; release of completed children and
rejection of running ones; bounded signal escalation; nonzero exit; failed exec
reported at start; rejection of non-owned PIDs; and explicit completion of a
registered framework child after the framework reaps it. All 22 checks pass on
Linux via `native/tests/run-host-test.sh`.

## Remaining device work

On the target phone: confirm whether `execve` of
`libqfli_mysql_launcher.so` is authorised, capture the launcher/loader errno and
app-private log, and only then claim phone Oracle startup. If phone exec is
denied, this needs a different supported/safe host; a post-fork `dlopen` is not
an acceptable fallback.
