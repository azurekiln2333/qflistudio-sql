# Oracle MySQL OHOS Runtime (phone)

## Scope

The HarmonyOS/OpenHarmony phone backend for the bundled Oracle MySQL 8.4.6
server. Desktop/macOS/Android have their own contracts. Only results observed on
a real phone count as phone acceptance; compilation and packaging do not.

## Why the preloaded private host (root cause history)

On the target phone (MRT-AL10, API 26, arm64) the ordinary app sandbox denies
separate-process start of the server:

- API26 `childProcessManager.isNativeChildProcessSupported()` -> actual `false`.
- API26 `childProcessManager.isArkChildProcessSupported()` -> actual `false`.
- `execve` of the packaged launcher -> EACCES (installed mode 0644); `execve` of
  the system interpreter `/lib/ld-musl-aarch64.so.1` -> also EACCES.
- Declaring `executableBinaryPaths` (the only exec-enabling declaration) is
  rejected at install (`9568449`).

Consequently the server is started by **forking** the app process and calling the
server entry **directly** from a privately loaded image — no `exec`, no child
`dlopen`.

## Private server image

- `native/mysql/qfli_mysql_server_proto.cpp` + `qfli_mysql_server.cpp` link the
  full Oracle server graph with:
  - `--version-script=qfli_mysql_server_proto.map` exporting only the entries,
  - `-Bsymbolic-functions` so intra-image references bind to the image itself,
  - `-nostdlib++` + the SDK's `c++/libc++_static.a` and `libunwind.a` so the
    image `NEEDED`s only `libc.so` (no shared `libc++_shared` locks).
- Proven: defined dynamic symbols drop from ~83k to 3; zero external
  Oracle/OpenSSL/ICU imports; ABI stays `std::__n1`.
- The image defines its own `exit`/`pthread_create`/`pthread_atfork` interposers;
  the real libc functions are resolved EAGERLY in a library constructor at
  `dlopen(RTLD_NOW)` in the parent. The child never lazily `dlsym`s.
  (`-Wl,--wrap` did NOT bind for these archive members; image-local interposers
  with `-Bsymbolic-functions` do, verified by zero external imports/PLT.)
- Because the image binds symbolically, its `my_init_done` /
  `my_thread_global_init_done` are **local** definitions neither exported nor
  imported, so the client's `mysql_library_init` cannot set the server's copy.
  Do not add manual global resets for this.

## Fork / child contract

- `fork()` from a dedicated fresh pthread that holds no preowned recursive stdio
  locks.
- Bounded `ftrylockfile(stdin/stdout/stderr)` (max ~500 ms, abort BEFORE fork on
  failure; release a partial set and retry).
- Compute the descriptor limit before fork. Child: unlock its own stdio copies,
  discard inherited buffers with SDK `__fpurge`, enter the child exit scope
  BEFORE any Oracle exit, reset signal handlers and close inherited descriptors
  except stdio and the handshake writer. Start a `getppid()` parent watchdog
  with termination signals blocked in that thread and restore the entry-thread
  signal mask. Refuse startup before the handshake if watchdog setup fails.
- Parent: release locks, adopt the PID into waitpid-owned tracking BEFORE the
  handshake, then use `poll` and a monotonic deadline (~2 s). A blocking `read`
  inside a deadline loop does not enforce a timeout. Failure returns a negative
  PID, preserves its diagnostic and confirms cleanup or retains pending ownership.
- Child-local exit: the image's `exit` interposer records the numeric code and
  `_Exit`s in child scope, so inherited Flutter/NAPI finalizers never run. Only
  a clean zero-byte EOF with no frame means "no exec error"; a partial frame or
  read error is a protocol failure (`EPROTO`), never success.

## Runtime selection (ArkTS)

- `QfliMysqlRuntime.startHostChild` chooses the preload host whenever
  `preloadStart` is available (the production phone path), inside the
  `host === 'fork'` branch before the legacy exec host. The exec host is a
  fallback only.
- `configureProbeRoot(runKey)` and `protoProbe` are debug-only (guarded by
  `BuildProfile.DEBUG`); the normal app uses `<filesDir>/mysql` unchanged.
- `startChild`/`preloadStart` return the same structured result
  `{pid, failed, owned, pendingPid, errno, error}`; a failed start that could not
  confirm termination retains `pendingPid`, and beginning-of-start cleanup reaps
  a pending owned child before any file rewrite or new spawn.
- `stopChild` is graceful-first: after a successful `shutdown(socket)` it waits
  for the exit record WITHOUT signalling, escalating only on timeout. This fixed
  an exit-143 race that left the PID file behind.

## Build configuration

- InnoDB memory barrier: `storage/innobase/innodb.cmake` gates the
  `HAVE_IB_GCC_ATOMIC_THREAD_FENCE` / `HAVE_IB_GCC_SYNC_SYNCHRONISE` probes behind
  `IF(NOT CMAKE_CROSSCOMPILING)`, so cross builds define neither and `os0atomic.h`
  compiles `os_rmb`/`os_wmb` to nothing. The OHOS configure sets
  `-DHAVE_IB_GCC_ATOMIC_THREAD_FENCE=TRUE` (Clang 18 aarch64 supports
  `__atomic_thread_fence`; verified by a real compile+link+disassembly probe that
  emits `dmb ishld`/`dmb ish`). The error-log catalog text "memory barrier has
  not been used" is catalog data, not the executed branch.
- Monotonic clock: `HAVE_CLOCK_GETTIME=FALSE` / `HAVE_CLOCK_REALTIME=FALSE` are
  forced, so `os0event.cc` skips `pthread_condattr_setclock`. This is a behavior
  fallback, not a proven phone limitation; documented, non-blocking.

## Verification

- Clean OHOS build/package must include `qfli_mysql_server_proto` along with
  client/server/launcher. Rebuild the private image with the selected fence flag;
  an old manually staged image cannot validate current sources.
- `native/tests/run-preload-host-test.sh` compiles the production preload host
  with an Oracle closure stub and verifies 30 assertions: bounded stalled child,
  early exit, negative failure PID, cleanup/ownership, inherited descriptor
  isolation, watchdog creation refusal and thread signal masks.

- 12/12 on-device probe PASS (identity/socket, CRUD, invalid SQL, scripts,
  workbench, editor, stop/restart persistence, cleanup) under the preload host.
- Host-side Linux tests cover fork/stdout protocol, owned PID, and error frames.
- Never claim phone acceptance from compilation alone; require a live runId.


## Explicit same-device sharing (2026-10-26)

The OHOS Tools page exposes `sharingStatus`, `startSharing` and `stopSharing`
through `qfli_sql/mysql`. The returned map contains `supported`, `running`,
`host`, `port`, `database`, `username`, `password` and `error`. The only endpoint
is `127.0.0.1:3306`, schema `qfli_shared`, account `qfli_app@127.0.0.1`.
The password is returned only after an authenticated TCP readiness check.

Normal internal startup remains socket-only. Sharing first verifies
`@@skip_networking = 1` on an owned child, persists cryptographically generated
admin/shared credentials with mode 0600 and atomic replacement, provisions the
schema/account and verifies root authentication. It stops and reaps this child
before enabling TCP. Never use init-file as the sole authentication barrier.
Internal queries/scripts/shutdown retain Unix sockets and pass the admin
password through optional trailing NAPI arguments. Legacy isolated probes may
omit the password. Empty-password interruption recovery is restricted to a
newly owned private start and never runs on TCP startup.

Sharing sets `skip-networking=OFF`, `bind-address=127.0.0.1`, `port=3306`,
`skip-name-resolve` and `loose-mysqlx=OFF`. No LAN binding or alternate-port
fallback is allowed. Readiness authenticates as the dedicated account over TCP
and verifies version, port, bind address, networking, schema and account.
The dedicated account has privileges only on `qfli_shared`.*. Loopback identifies
a host, not an application: any local app holding these credentials can connect.
Do not export root credentials or embed generated passwords in source/logs.

Stopping sharing terminates the managed server and preserves its data. A later
internal query may restart privately. Unconfirmed termination retains ownership
and an error; it must not permit a second child. Disposal and the existing
parent-death watchdog remain the lifecycle boundary. There is no persistent
background-service guarantee. INTERNET and READ_PASTEBOARD are the exact
manifest permission set; declaration checks do not prove traffic scope.

Current-source analyze, native rebuild, HAP staging and real two-app OHOS
acceptance are open. Require first-install and existing-data recovery, wrong
password rejection, dedicated-schema privilege checks, port collision,
stop/restart, internal Unix access, background/disposal, IPv4 loopback-only
listeners and no MySQLX listener. Historical phone probes do not cover sharing.
