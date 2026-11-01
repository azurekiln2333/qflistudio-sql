# Research: Direct invocation of the OHOS musl interpreter

- Query: Does official OHOS musl support `/lib/ld-musl-aarch64.so.1 <installed signed PIE> ...` as ordinary program startup, and what does this establish about current phone EACCES?
- Scope: mixed; official musl source/build selection, local SDK inspection, and project launcher code. No builds or device commands.
- Date: 2026-10-09

## Findings

**The official OpenHarmony musl implementation supports direct-interpreter command-line startup. This does not establish that this phone permits the app to execute that interpreter.** If execve were unavailable for every executable, this mechanism would not solve that: it still requires exec of the system interpreter. The latest parent evidence is an execv call returning EACCES, not proof of a globally unavailable syscall.

### Source and build evidence

All external paths below are in the official `openharmony/third_party_musl` repository, `master`, fetched on 2026-10-09.

- `ldso/linux/dynlink.c:4912–4944`: distinguishes an application already loaded by the kernel from the dynamic interpreter itself being the executed program, using AT_PHDR versus ldso.phdr.
- `ldso/linux/dynlink.c:4944–4981`: direct-interpreter branch consumes the loader argument and prints `Dynamic Program Loader` / `Usage: %s [options] [--] pathname [args]` when arguments are missing or invalid.
- `ldso/linux/dynlink.c:4983–4996`: opens the supplied pathname with O_RDONLY, calls map_library, and sets the target AT_ENTRY.
- `ldso/linux/dynlink.c:5058`: initializes loader namespaces for the application; successful initial exec is not the end of dependency/policy checks.
- `ldso/linux/dynlink.c:5217`: transfers control to the target entry with its adjusted argv.
- `BUILD.gn:137–146`: creates a ported source tree using scripts/porting.sh, including loader sources.
- `scripts/porting.sh:57`: overlays `ldso/linux/*` into the generated tree's `ldso/`.
- `musl_template.gni:481–486`: compiles loader sources from that generated tree. Thus the Linux-overlay source above matters; the repository's upstream-style root ldso/dynlink.c alone would be insufficient evidence.
- The older `porting/linux/user/ldso/dynlink.c:2936–2988` also contains normal direct-interpreter startup, but the build-overlay source above is the stronger current reference.

### What it does and does not prove

Starting the interpreter with an installed PIE as its argument is a source-supported loader interface, not the same syscall target as executing the PIE directly. The kernel initially checks execution of the **interpreter**. The loader then opens and maps the target and resolves its dependencies. Consequently, do not claim that every original target execve permission check is identical; the target is not passed through that same execve path.

No chmod, executable copy into writable data, namespace-policy modification, security-setting change, or post-fork dlopen was used or recommended by this research. A successful exec of the permitted system interpreter would give a fresh runtime rather than the inherited multithreaded Flutter runtime. Whether this exact phone binary and its app-domain policy allow it remains unverified.

| Evidence | Supported inference | Unsupported inference |
| --- | --- | --- |
| Direct exec returns EACCES | This attempted exec was denied. | The target definitely lacks an execute bit; all phone exec is impossible. |
| Target mode lacks execute bits | Ordinary execute access for that target is absent; this can explain direct EACCES. | No additional mount, directory, interpreter, or platform restrictions exist. |
| Interpreter is mode 0755 | Ordinary mode bits permit execution for common users. | Its mount, security label, app domain, or code policy necessarily permits exec. |
| hdc shell cannot execute interpreter | The shell-domain invocation failed. | The app domain must behave identically. |
| Interpreter exec succeeds but loader errors | Failure has moved beyond initial exec, into ELF/dependency/namespace/loading work. | MySQL entered main, initialized, or is ready. |

Parent owns the remaining device observations: actual capability-query result, target/interpreter path and modes, distinct direct-exec versus interpreter-exec errno, and whether loader/launcher stage markers appear. Preserve separate errors; one overwritten errno cannot distinguish both attempts.

### Files found and code patterns

- `native/mysql/qfli_mysql_host.cpp:216`: start_child; `:234`: system interpreter path; `:296`: direct execv; `:317`: interpreter execv in the snapshot inspected.
- `native/mysql/qfli_mysql_host.cpp:308–316`: snapshot contained std::vector/std::string construction and push_back **after fork** while building interpreter argv. This is not async-signal-safe in a multithreaded parent; reported immediately to parent so Pi can prepare all argument storage before fork. No researcher code edit.
- `native/mysql/qfli_mysql_host.cpp:320`: snapshot suppressed interpreter EACCES/ENOEXEC/ENOENT in favor of direct errno; reported to parent because it loses useful failure-stage evidence. Pi is actively changing this code; re-check before relying on those line numbers.
- `native/mysql/qfli_mysql_host.cpp:368`: new mode/path/UID/size diagnostics. A source comment claiming missing execute bits is not equivalent to an observed stat result.
- Installed SDK `native/sysroot/usr/lib/aarch64-linux-ohos/libc.so` exists. Targeted string search found no `Dynamic Program Loader`/related strings; therefore no claim is made that this SDK library independently confirms the phone loader implementation.
- `research/phone-native-host.md`: implementation-owner notes, including parent device reports; some earlier first-log/missing-execute-bit wording was identified as premature and reported to parent.

### External references

- [OHOS Linux-overlay dynamic loader](https://github.com/openharmony/third_party_musl/blob/master/ldso/linux/dynlink.c#L4912)
- [Build source staging](https://github.com/openharmony/third_party_musl/blob/master/BUILD.gn#L137)
- [Linux source overlay](https://github.com/openharmony/third_party_musl/blob/master/scripts/porting.sh#L57)
- [Loader compilation template](https://github.com/openharmony/third_party_musl/blob/master/musl_template.gni#L481)
- [Older ported loader implementation](https://github.com/openharmony/third_party_musl/blob/master/porting/linux/user/ldso/dynlink.c#L2936)

### Related specs

- `.trellis/spec/backend/mysql-workspace.md`: Oracle/private-socket and real device requirements.
- `research/ohos-resume-2026-10-09.md`: separate fresh child, safe pre-exec boundary, truthful startup/lifecycle diagnostics.
- `research/phone-process-host-capabilities-sdk26-2026-10-09.md`: SDK 26 APIs and their documented phone limits.

## Caveats / Not Found

- Public OpenHarmony musl master is source evidence, not proof of byte-for-byte identity with the closed HongMeng phone runtime.
- No official statement was found granting normal third-party phone apps direct execution of the system interpreter or arbitrary long-running services through this interface.
- The first missing-log observation used the wrong app-global directory; the correct module path is `/data/storage/el2/base/haps/entry/files/mysql`. It cannot establish which earlier syscall caused SIGSYS.
- The parent reports current direct-exec EACCES and shell-domain interpreter EACCES. This researcher did not run or reproduce either.
- No runtime fallback is marked successful by this research; Oracle initialization, SQL correctness, persistence, stop/restart and process isolation still need real phone evidence.
