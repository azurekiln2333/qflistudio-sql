# Phone host design options (post-evidence)

## Established device facts (MRT-AL10, sdkApi 26, app com.azurekiln.qfli.sqlab)

- API26 `childProcessManager.isNativeChildProcessSupported()` -> actual `false`.
- API26 `childProcessManager.isArkChildProcessSupported()` -> actual `false`.
  (Both queries ran: `capability.log` `query=ok supported=false`.)
- Direct `execve` of the packaged launcher -> EACCES; installed mode `0100644`.
- `execve` of `/lib/ld-musl-aarch64.so.1` (mode `0100755`) -> EACCES from the app
  domain.
- Declaring `executableBinaryPaths` (only mechanism that marks a packaged file
  executable) -> install rejected `9568449` on this phone.
- `extractNativeLibs`/`compressNativeLibs` control compression, not the execute
  bit; neither makes a packaged `.so` executable.
- On-device diagnostic (attempt 1456) shows the launcher **and** the NAPI client
  `libqfli_mysql.so` are both installed mode `0100644`; only the system
  interpreter is `0100755` (and still EACCES from the app domain). The
  "packaging/settings could add an execute bit" hypothesis is falsified.

So under the app's normal policy there is currently **no OS-supported way to
start a separate process** (native-child, Ark-child, or file exec).

## Options assessed

### A. Supported device target (tablet / 2-in-1)
On devices where `isNativeChildProcessSupported()` is true, the existing
native-child host works with no architecture change. Phones remain a documented
limitation. **Zero new risk; but does not satisfy "phone".**

### B. Parent-preload then fork (no exec)
Load the server image in the Flutter process, then `fork` children that enter
`mysqld_main` directly.
- `research/phone-parent-preload-fork-safety-2026-10-09.md` shows concrete
  blockers: 870-entry server `INIT_ARRAY`, inherited finalizers/`atexit` from
  Flutter/NAPI, and **overlapping preemptible symbols** (`my_init`,
  `my_thread_global_init`, OpenSSL state) between `libqfli_mysql.so` and
  `libqfli_mysql_server.so`. The server would not be a pristine instance.
- Requires audited private binding, quiescence guarantees, inherited-finalizer
  interception, and exact phone libc/allocator behaviour. **Not established
  safe; do not adopt without a director decision and a full safety design.**

### C. Same-process server, no fork
Call `mysqld_main` directly in the Flutter process.
- `mysqld_main`/`mysqld_exit` call `exit()`; Oracle globals, signal handlers and
  threads would corrupt or kill the UI. Explicitly excluded.

### D. Different engine or remote server
Not Oracle MySQL 8.4.6 on-device; violates the pinned requirement.

### E. Supported extension point (extension ability / service)
Investigate whether a service-type extension or another OS component can
legitimately run a long-lived native server and be reached over the private
socket. This would be a **product/architecture** change and needs director
approval; not assumed viable.

## Recommendation

- Keep the native-child host for tablet/2-in-1 (option A) as the supported path.
- Do **not** adopt B or C without a director decision; B needs a dedicated
  private-binding + quiescence + finalizer-safety design, not a probe.
- Root to decide whether the phone target requires a different architecture
  (E) or a scope change (A).

## Patch plan (if root chooses a direction)

- **A**: none required beyond the existing host; add a clear phone capability
  message and keep the runtime refusing unsupported devices.
- **B**: design a private server image with a hidden/renamed symbol boundary,
  an audited initializer set, intercepted/nonexecuted inherited finalizers, and
  a bounded child lifecycle; prove on device before any claim. Large, risky.
- **E**: identify the allowed OS component, its lifecycle and IPC, then map the
  existing client to it.

No risky design has been adopted; no security controls were changed.
