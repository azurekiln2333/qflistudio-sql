# Option B design: private-bound, parent-preloaded Oracle server (evidence prototype)

Status: design + isolated prototype only. NOT enabled in the production app until
the binding and lifecycle plan is reviewed. No unsafe fallback shipped.

## Goal

On a phone with no supported fresh-process mechanism (native-child=false,
ark-child=false, exec EACCES), enter the Oracle 8.4.6 server in a child created
by `fork()` from a parent that has **already loaded a private, quiescent server
image**, without any post-fork `dlopen`/`dlsym`.

## Measured facts (staged ELFs, this repo)

| Fact | Value |
| --- | --- |
| `libqfli_mysql.so` NEEDED | `libace_napi.z.so`, `libc++_shared.so`, `libc.so` |
| `libqfli_mysql_server.so` NEEDED | `libc++_shared.so`, `libc.so` |
| Server exported defined symbols | ~83,032 (all GLOBAL DEFAULT) |
| Client exported defined symbols | ~10,647 |
| Overlapping exported symbols | **10,515** (OpenSSL `CRYPTO_*`/`EVP_*`/`OpenSSL_*`, `my_once_*`, `my_thread_create`, `Per_thread_connection_handler` globals, ICU static state) |
| Server `.init_array` | 6960 bytes = **870 entries** |
| Client `.init_array` | 56 bytes = 7 entries |
| Dynamic flags | BIND_NOW on both; no `-Bsymbolic`; no version script |

Consequence: loaded together in the default global namespace, the two images can
interpose each other's OpenSSL/MySQL/ICU symbols. The server is not a pristine,
privately bound instance today.

## Design

### 1. Private binding via version script + symbolic binding
- Give the server its own `SONAME` and a **version script** exporting only the
  three entry symbols (`QfliMysqlMain`, `qfli_mysql_child_main`,
  `qfli_mysql_record_exit`) and marking everything else `local:`. This removes
  ~83k preemptible definitions from the dynamic symbol table.
- Link the server with `-Wl,-Bsymbolic-functions` (and `-Bsymbolic` for data
  where safe) so intra-image references bind to the image's own definitions and
  cannot be preempted by the client.
- Load the server with `dlopen(..., RTLD_NOW | RTLD_LOCAL)` in the parent. **Note:**
  `RTLD_LOCAL` only prevents the image's symbols from being *exported* to later
  loads; it does **not** prevent the image from *importing* definitions already
  in the global scope. Only private definitions (version script) plus
  relocation-level proof eliminate that risk.
- Verify with `llvm-readelf --dyn-symbols` that only the three entries remain
  GLOBAL, and with a **relocation audit** that no server relocation references an
  external definition of an Oracle/OpenSSL/ICU symbol (private definition proof,
  not just visibility).

**Prototype evidence (relinked the already-built server objects, no source or
CMake change):** with `qfli_mysql_server.map` + `-Bsymbolic-functions`:

| Metric | Before | After |
| --- | ---: | ---: |
| Defined dynamic symbols | 83,032 | **3** |
| Undefined dynamic imports | (many Oracle/OpenSSL/ICU) | 629, **zero** Oracle/OpenSSL/ICU/abseil |
| `.init_array` | 6960 B (870) | 6960 B (870, unchanged) |
| `NEEDED` | `libc++_shared.so`, `libc.so` | `libc++_shared.so`, `libc.so` |

Script: `native/tests/experiment-private-binding.sh`; version script:
`native/mysql/qfli_mysql_server.map`. So the binding half is proven feasible;
static libc++, the constructor audit, and lifecycle remain.

### 2. Static/private libc++ and ABI
- The server currently needs `libc++_shared.so`; the client shares it. Shared
  C++ runtime locks (iostreams, locale, exception tables) are inherited across
  fork.
- Prototype: link the server against a **static libc++** so the server has no
  shared C++ runtime to share locks with the parent.
- Confirm the server then `NEEDED` only `libc.so` and keeps `std::__n1`.

**Prototype evidence:** relinking with `-nostdlib++` + the SDK's
`llvm/lib/aarch64-linux-ohos/c++/libc++_static.a` (+ `libunwind.a`) and the
version script:

| Metric | Value |
| --- | --- |
| `NEEDED` | **`libc.so` only** (no `libc++_shared.so`) |
| Defined dynamic symbols | **3** |
| Undefined Oracle/OpenSSL/ICU/abseil imports | **0** (434 remain: libc/libc++abi/zstd weak) |
| ABI namespace | **`std::__n1`** (19,643 symbols) — ABI-consistent |

Note: `libc++_static.a` from `c++/` is self-contained; adding the separate
`libc++abi.a` duplicates symbols (link error), so only the self-contained archive
is used. Script: `native/tests/experiment-static-libcxx.sh`.

### 3. Constructor audit (870 entries)
- Resolve `.init_array` entries through the ELF **RELA** relocations and the
  symbol table (the array is zero on disk and filled by `R_AARCH64_RELATIVE` at
  load). `dl_iterate_phdr` does **not** report which constructors ran, and musl
  `LD_AUDIT` support is unestablished, so neither is used as evidence.
- Classify each constructor and audit the reachable **thread / atfork / env /
  signal / FD / exit** startup calls (imports: `pthread_create`, `pthread_once`,
  `__cxa_atexit`, `atexit`, `setenv`, `sigaction`, `socket`, `timer_create`,
  `fork`). Instrument owned wrapper calls for before/after-load where useful.
- Gate: no constructor creates threads or mutates server state that must differ
  per child, **or** those are explicitly reset in the child before `mysqld_main`.

**Measured audit (this repo):** `.init_array` is zero on disk and filled by
`R_AARCH64_RELATIVE` relocations in `.rela.dyn` (93,050 relative relocs). For each
relocation whose `r_offset` lies in `.init_array`, the addend names the
constructor. Resolver: `native/tests/resolve-ctors.py` (uses RELA + `llvm-nm` of
the **unstripped** build artifact). Result: **869 constructors**, 868
`_GLOBAL__sub_I_*.cc` per-TU static initializers + `__do_init`.

**The filename list does NOT prove absence of threading/OpenSSL work.** Many
constructors call functions that mutate process-wide state. The finite evidence
is the **wrapper instrumentation**: wrap `pthread_create` and `pthread_atfork` in
the isolated static closure and count/log any calls that occur during
constructor-time, from the `dlopen(RTLD_LOCAL)` of the private image until it
returns. No full enumeration of all 870 ordinary container constructors is
attempted.

**Resolved (was recorded as a blocker, now disproven):** `my_init_done` and
`my_thread_global_init_done` appeared to be shared between client and server
because both images export MySQL symbols today. With the version script
(`local: *`) plus `-Bsymbolic-functions`, the private server image defines them
as **local BSS symbols** at distinct addresses and neither exports nor imports
them:

```
$ llvm-nm libqfli_mysql_server_static.so | grep my_init
0000000003977150 b _ZL26my_thread_global_init_done
0000000003976b00 b my_init_done
```

So the client's `mysql_library_init` cannot set the private server's copy; there
are separate BSS definitions. The binding fixes the interposition. Do **not** add
manual global resets based on the earlier false premise.

### 4. Platform fork wrapper + libc repair
- Use `fork()` (OHOS musl runs registered `pthread_atfork` handlers and repairs
  loader/pthread-key/AIO/allocator locks per the researched `src/process/fork.c`
  and `mallocng/glue.h`). Do **not** use `posix_spawn`/`exec`.

**Finalized stdio protocol (agreed finite spec).** musl fork resets the stdio
open-list lock but not each `FILE.lock`; a child `freopen(stderr)` takes the
inherited lock and can deadlock if the parent logger held it. Protocol:
1. Fork from a **dedicated fresh native fork thread** that holds no preowned
   recursive stdio locks.
2. Before fork, take bounded `ftrylockfile(stdin|stdout|stderr)` — max total
   500 ms. If an acquisition times out, **release every acquired lock** and
   retry; do not hold a partial set.
3. Hold the acquired locks **across the fork**.
4. Parent and child each `funlockfile` **their own copies** of the 1/2/3 file
   streams (OHOS musl does not compare old TIDs).
5. In the child, signals stay blocked; after unlocking, use the public SDK
   `__fpurge` to **discard** inherited stdio buffers (not flush), then redirect
   and reset handlers, then unmask the child's signals.
6. **No `fflush(NULL)`** and no `exit()` finalization in the child.
7. Existing `pthread_atfork` callbacks must not log via stdio before the fork
   returns.
8. The actual app handshake must be **bounded**: if the child's after-fork
   raw-write marker never arrives, the parent times out and terminates the known
   owned PID. Never an unbounded error-pipe read.
9. Validate repeated forks with concurrent parent stderr, lock-acquire timeout,
   and a parent-exit sentinel.
- The child immediately:
  - resets signal handlers/mask to a known state,
  - closes all inherited FDs except the error pipe, the private socket path (as a
    path, not an inherited FD), and the child's own exit-record channel,
  - sets parent-death ownership (getppid watchdog in the child, since prctl is
    not proven),
  - does **no** allocation-heavy work until it owns a fresh copy of the parent's
    server snapshot.
- Enter the preloaded server entry by a **direct function pointer** captured in
  the parent (`dlsym` in the parent before fork), never `dlsym` in the child.

### 5. Both init and service from the untouched parent snapshot
- The parent loads the private server image once and never runs `mysqld_main`
  (the image stays quiescent). Each child is a `fork` of that same pristine
  parent, so the initialization child and the service child each start from the
  same snapshot.
- A child is never reused for a second `mysqld_main`.

### 6. Child-local exit; never inherited parent finalizers
- The server entry must, after Oracle's own cleanup, call `_exit(code)` directly
  (not `exit()`), so inherited Flutter/NAPI `atexit`/`__cxa_atexit` finalizers
  and stdio flushing from the parent do not run in the child.
- Patching only `mysqld_exit` is insufficient: Oracle and its dependencies call
  `exit()` from many other places. Use **link-time exit interception scoped to
  this DSO only** (define a local `exit`/`_exit`-shim that the private, symbolic
  server image resolves internally), gated by a child flag so it only affects the
  preloaded child. Combine with a source audit so every child exit path routes
  through the child-local exit and the exit record, and reset/disable inherited
  callbacks rather than relying on a single patched function.
- The exit record writer uses raw `open`/`write`/`fsync`/`rename` only.

### 7. Parent-death ownership
- Child runs a `getppid()` watchdog (standard calls) that `_exit`s when the
  parent app dies. Parent tracks the child PID + start-time identity to avoid
  PID reuse.

### 8. Data isolation (required before any phone prototype)
- The production runtime root is `<filesDir>/mysql`; an experimental
  InnoDB init/start/stop must never touch it.
- `QfliMysqlRuntime.configureProbeRoot(runKey)` (debug-only) points the runtime
  at `<filesDir>/mysql-ohos-probe-runtime/<runKey>` **before** any server/init
  is owned, with strict validation (single safe segment, no traversal).
  `runtimeRoot()` returns the actual native root used, for PID/log evidence.
  The normal `lib/main.dart` path never calls it and keeps `<filesDir>/mysql`.
  The probe channel method is gated by `BuildProfile.DEBUG`. No existing data is
  copied, deleted, or adopted.

## Prototype / test plan (isolated, no production enablement)

- `native/mysql/ohos-targets.cmake` (prototype target, gated by a CMake option
  `QFLI_MYSQL_PRELOAD_PROTOTYPE=ON`): a `qfli_mysql_preload.so` that links the
  server objects privately with the version script and `-Bsymbolic`, static
  libc++, and exports only the entry + a `qfli_mysql_preload_main(json)`.
- `native/tests/qfli_mysql_binding_test.sh`: statically asserts the server
  exports only the three entries, `NEEDED` excludes `libc++_shared.so`, and no
  relocation references an external Oracle/OpenSSL/ICU symbol.
- `native/tests/qfli_mysql_ctor_audit.sh` / `native/tests/resolve-ctors.py`:
  resolve and classify `.init_array` constructors through RELA (869 found; 868
  per-TU static initializers + `__do_init`).
- `native/tests/qfli_mysql_preload_test.cpp`: on Linux, `dlopen(RTLD_LOCAL)` the
  private image, `fork`, have the child enter the entry on a simple no-oracle
  payload, assert clean `_exit`, exit-record, watchdog, and that the parent
  survives.
- `native/tests/run-preload-mechanism-test.sh` +
  `qfli_mysql_preload_mechanism_test.cpp` + `qfli_mysql_preload_closure_stub.cpp`
  — Linux-runnable mechanism proof: an interposed `pthread_create` wrapper
  observes a constructor-time thread spawn (count=1), and a forked child exiting
  via `_Exit` does **not** run an inherited parent `atexit` sentinel. All checks
  pass.
- Device prototype: a **separate probe HAP** (probe target only) that exercises
  `dlopen(RTLD_LOCAL)` + fork + entry in the app, recording stage markers, until
  reviewed. Production `lib/main.dart` keeps the current safe behavior.

## Open risks (must be resolved before any production use)

- OHOS musl/public sources are not proof of the exact phone runtime; the
  allocator/libc C++ static-link availability must be confirmed.
- The 870-constructor audit may find thread creation or per-child server state
  that cannot be reset cheaply.
- Static libc++ ABI availability on the OHOS SDK for `std::__n1`.
- Whether OHOS BMS/policy permits a forked child to run a long-lived server
  (no evidence yet).
