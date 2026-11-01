# Research: Parent-preloaded Oracle image followed by fork

- Query: Can the parent preload a quiescent, privately bound Oracle server image and later enter it in independent fork children without post-fork dlopen?
- Scope: mixed; current native wrapper/link rules, prepared Oracle 8.4.6 source, packaged ELF metadata, and official OpenHarmony musl source. Read-only except this note; no implementation, build, or device execution.
- Date: 2026-10-09

## Findings

**Not established safe for this application/platform; the current images and wrapper have concrete blockers.** Parent preloading removes one post-fork loader operation, but does not create a fresh runtime or establish safe arbitrary C++/Oracle execution in a child of multithreaded Flutter. This investigation does not replace the ongoing fresh-exec/native-child work.

### 1. OHOS musl repairs specific locks; that is not a blanket server guarantee

Official `src/process/fork.c:55–102` calls registered fork handlers, blocks application signals, and, when libc.need_locks is set, acquires loader, pthread-key, AIO, thread-creation, listed libc and allocator locks before `_Fork()`. It repairs/releases them afterward. `src/malloc/mallocng/glue.h:83–92` explicitly resets the mallocng lock in the child. `ldso/linux/dynlink.c:3796–3818` handles loader locks, including special child repair for dlclose/notifier locks.

Therefore, saying OHOS musl never repairs allocator/loader locks would be false. The unresolved requirement is stronger: the phone's exact libc build, selected/replaced allocator, shared libc++, TLS/once guards, registered atfork callbacks and all reachable dependencies must support the operations entered after fork. These sources do not repair arbitrary Oracle/application mutexes or prove the closed phone runtime has this exact implementation. The ordinary portable post-fork boundary remains async-signal-safe work until exec; no supported platform extension promising arbitrary preloaded C++ server startup was found.

The existing child entry immediately performs string mutation, RapidJSON parsing, setenv, vector allocation and mysqld_main (`qfli_mysql_server.cpp:66–110`). It does not stay inside that portable boundary.

### 2. Current server and NAPI client are not proven privately bound

`ohos-targets.cmake:8–18` reuses the full mysqld link graph and exports the three entry symbols; it does not define a private export/binding boundary. Line 32 links NAPI against mysqlclient. `native/src/qfli_mysql_client.cpp:12,85` initializes that client with std::call_once/mysql_library_init.

Read-only llvm-readelf inspection of **both** `build/mysql-port/package/libs/arm64-v8a/libqfli_mysql.so` and `libqfli_mysql_server.so` confirmed:

| Symbol | Both images export | Both images contain dynamic relocation |
| --- | --- | --- |
| my_init_done | GLOBAL DEFAULT data | R_AARCH64_GLOB_DAT |
| _Z7my_initv / my_init() | GLOBAL DEFAULT function | R_AARCH64_JUMP_SLOT |
| _Z21my_thread_global_initv | GLOBAL DEFAULT function | R_AARCH64_JUMP_SLOT |
| _Z6my_endi / my_end(int) | GLOBAL DEFAULT function | R_AARCH64_JUMP_SLOT |

Both also export OpenSSL functions/state and share libc++_shared.so/libc.so dependencies. Dynamic flags show BIND_NOW/NOW, not a demonstrated private binding boundary. Eager binding is not symbol isolation. Exact interposition depends on runtime namespace/load scope, but the actual overlapping preemptible symbols make the risk concrete. RTLD_LOCAL alone prevents outgoing global exposure; it does not guarantee that incoming references ignore already-visible definitions.

Prepared Oracle source: `mysys/my_init.cc:97,136–159` owns my_init_done and returns early when it is already true; `libmysql/libmysql.cc:153–160` initializes that same mysys facility. `mysys/my_thr_init.cc:59–79,158–195` has persistent init flags, TLS and THR_LOCK_* mutexes. A NAPI-initialized client instance cannot be assumed to be a pristine server instance. `my_thread_global_reinit()` is expressly an instrumentation setup step before threads exist, **not** a generic post-fork repair routine (prepared source `:110–120`).

### 3. Preloading has substantial constructor and finalizer work

The inspected server ELF contains INIT_ARRAYSZ=6960 bytes (**870 arm64 pointer entries**), imports __cxa_atexit/__cxa_thread_atexit/atexit and has a FINI_ARRAY. Thus 'mysqld_main has not run' is not evidence of a quiescent image. Its complete constructor/dependency graph, TLS registration, allocations, callback registration, any thread creation and parent-side destructor behavior have not been audited.

A safe design would have to show that the server's private state stays unchanged in the parent between forks, cannot be touched through NAPI/client symbol aliases, and is safe on normal parent disposal. Each initialization child and service child would have to start independently from that same verified pristine snapshot; re-entering mysqld_main in an already-used child is not equivalent.

### 4. Existing exit handling runs inherited parent cleanup

The OHOS patch only calls qfli_mysql_record_exit and then ordinary exit (`native/mysql/patches/0001-ohos-platform.patch:141–154`; prepared `sql/mysqld.cc:2603–2636`). It does not intercept child termination.

Official musl `src/exit/exit.c:47–77` performs thread-local finalization, registered exit functions, ELF finalizers and stdio cleanup before _Exit. The forked child inherits those registrations and open-stream state from Flutter/NAPI and other parent libraries. Repairing the atexit list lock does not discard the callbacks.

A safe private-child contract must preserve required Oracle cleanup while preventing unrelated inherited parent callbacks/streams from running, covering every normal/error return and dependency termination path without interposing termination into the parent. The current callback only records a result; no such comprehensive contract is implemented or verified.

### Remaining required guarantees

- **Runtime:** exact phone libc/allocator/C++/TLS/atfork behavior for the entire reachable child call graph, beyond the specific musl locks observed.
- **Binding and quiescence:** private server functions/data/dependencies, proven symbol resolution, completed and audited parent constructors, no parent server entry or later mutation, safe parent disposal.
- **Signals/FDs:** child-owned signal dispositions and mask; no inherited Flutter/NAPI/Binder handler activity; only explicitly retained descriptors. No-exec children keep inherited streams and handlers that fresh exec would otherwise replace. Thread/watchdog creation itself requires the runtime guarantee above.
- **Termination:** child-specific completion/cleanup with reliable status records, no inherited parent finalizers, no stale PID signalling.
- **Lifecycle:** separate fresh init and service children from a verified parent snapshot; parent-death cleanup, bounded stop/reap, repeated stop/restart and no parent-side effects.

These are acceptance requirements, not an implementation proposal. Successful startup in a few probes would not demonstrate freedom from concurrent-fork races or inherited-state corruption.

### Files found / related specs

- `native/mysql/qfli_mysql_server.cpp`: allocating/parser/environment entry and ordinary exit-record writer.
- `native/mysql/ohos-targets.cmake`: server and NAPI link boundaries.
- `native/mysql/patches/0001-ohos-platform.patch`: exit-record hook, without exit interception.
- `native/src/qfli_mysql_client.cpp`: parent client initialization and thread context.
- WSL `qfli-java-build:/root/qfli-mysql-port/mysql-8.4.6/{sql/mysqld.cc,mysys/my_init.cc,mysys/my_thr_init.cc,libmysql/libmysql.cc}`: actual prepared Oracle state/exit source.
- `build/mysql-port/package/libs/arm64-v8a/{libqfli_mysql.so,libqfli_mysql_server.so}`: inspected ELF symbols/relocations/dependencies/initializer metadata; these are staging artifacts, not claimed byte-identical to the latest phone HAP.
- `.trellis/spec/backend/mysql-workspace.md` and `research/ohos-resume-2026-10-09.md`: real Oracle, separate safe children, private socket, no unsafe inherited-runtime shortcut.

### External references

Official OpenHarmony musl master, retrieved 2026-10-09:

- [fork wrapper](https://github.com/openharmony/third_party_musl/blob/master/src/process/fork.c#L55), also independently fetched from [Gitee](https://gitee.com/openharmony/third_party_musl/blob/master/src/process/fork.c).
- [mallocng child lock repair](https://github.com/openharmony/third_party_musl/blob/master/src/malloc/mallocng/glue.h#L83).
- [OHOS loader atfork handling](https://github.com/openharmony/third_party_musl/blob/master/ldso/linux/dynlink.c#L3796).
- [Registered pthread_atfork handlers](https://github.com/openharmony/third_party_musl/blob/master/src/thread/pthread_atfork.c).
- [exit finalization sequence](https://github.com/openharmony/third_party_musl/blob/master/src/exit/exit.c#L47).

## Caveats / Not Found

- No exact-phone allocator/libc guarantee, complete constructor audit, or private relocation proof was established. These are blockers to endorsing the contingency as safe, not proof that every deliberately designed prefork architecture is impossible.
- No pthread_atfork/register_atfork hook was found in the prepared Oracle `mysys`, `libmysql` or `sql` directories. This scoped search does not rule out hooks in external dependencies, and such hooks would not by themselves cover the complete application.
- OpenHarmony's public master sources are not proof of exact binary identity with the HongMeng phone implementation. The allocator reset source is specifically mallocng; the device allocator/hook selection was not inspected.
- The POSIX web reference fetch timed out; no retrieved quotation from it is used. The official OHOS sources and project/binary observations above are the direct evidence.
- No post-fork dlopen, security change, root/device command, source edit or build was performed.
