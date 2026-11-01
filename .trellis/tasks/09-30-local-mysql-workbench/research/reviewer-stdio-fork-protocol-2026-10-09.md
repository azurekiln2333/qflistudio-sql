# Reviewer note: bounded OHOS preload/fork stdio protocol

Scope: the isolated private Oracle 8.4.6 DSO prototype. Pi owns implementation,
builds and device execution. This is a finite experiment contract, not phone
runtime acceptance or a portable POSIX guarantee.

## Verified stdio boundary

The inspected OpenHarmony musl fork.c/_Fork.c repair the global open-FILE-list
lock and selected allocator/loader locks, but not each inherited FILE::lock.
__lockfile waits on the stored owner; freopen locks and flushes the existing
FILE first. Reopening alone therefore cannot repair an inherited locked stderr.

ftrylockfile/funlockfile can control the three standard streams. The inspected
funlockfile clears a single acquisition without requiring the old numeric TID.
Use a fresh dedicated pthread so there are no pre-owned recursive acquisitions.

Sources inspected:
- https://github.com/openharmony/third_party_musl/blob/master/src/process/fork.c
- https://github.com/openharmony/third_party_musl/blob/master/src/process/_Fork.c
- https://github.com/openharmony/third_party_musl/blob/master/src/stdio/__lockfile.c
- https://github.com/openharmony/third_party_musl/blob/master/src/stdio/ofl.c
- https://github.com/openharmony/third_party_musl/blob/master/src/stdio/freopen.c
- https://github.com/openharmony/third_party_musl/blob/master/src/stdio/ftrylockfile.c
- https://github.com/openharmony/third_party_musl/blob/master/src/stdio/funlockfile.c

These upstream implementations do not prove the proprietary phone libc is
identical. Actual bounded device behavior is a separate gate.

## Finite protocol

1. Parent prepares the private DSO, eager bindings, real libc wrapper targets,
   arguments, private descriptors and status pipe before fork. Missing pointers
   fail before fork. No child lazy-dlsym fallback.
2. On a fresh dedicated pthread, block application signals and acquire stdin,
   stdout and stderr with bounded ftrylockfile retries. On failure release all
   acquisitions and return without creating a child. Do not block in a parent
   fflush call.
3. Fork. Parent and child each funlockfile their copied acquisitions. Parent
   restores its signal mask. Child emits a raw-write after-fork marker.
4. Child discards copied stream buffers before redirecting/reopening private
   stdio, resets signal dispositions, then enables its intended signal mask.
   SDK stdio_ext.h declares __fpurge; verify target behavior in the focused
   probe before relying on it. Do not use fflush(NULL).
5. Enter Oracle only after preparation. Intercept Oracle's actual exit calls
   to record status and _exit/_Exit. Do not execute inherited finalizers,
   return into app code, or load another library after fork.
6. Parent uses a monotonic deadline, waitpid(WNOHANG), and EINTR handling.
   Timeout triggers bounded kill/reap; unconfirmed termination returns retained,
   reachable PID ownership for stop/dispose. No new start may overwrite it.

## Child atfork callback limitation

Child callbacks run before fork returns, before step 3 can unlock streams.
For this controlled prototype, pre-unlock callback diagnostics use raw write.
Require the after-fork marker within the deadline, otherwise kill/reap and
report an unsupported callback case. This is not an unlimited callback audit.

Focused mechanism cases: raw-write child callback succeeds; a stdio-logging
callback blocked by an inherited stream lock is detected and cleaned up within
the deadline; concurrent parent stdio either permits the child or times out
before fork while the parent stays responsive.

## Go/no-go gates for isolated phone execution

- Actual private-closure constructor thread/atfork counts are recorded. Zero
  passes; inspect nonzero counts before allowing that case to fork.
- Readiness and counters gate fork; real host uses the bounded stdio and child
  handshake/reap protocol, rather than only testing an unused helper.
- Rebuilt ELF, source map and CMake inputs agree. Verify actual Oracle exit
  binding; directly invoking a wrapper alone is not binding evidence.
- A successful load/exit probe does not establish Oracle identity, initialization,
  CRUD, persistence, shutdown or parent survival across those operations.

No tests, builds or device operations were performed by this reviewer.
