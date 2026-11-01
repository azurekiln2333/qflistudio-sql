# HarmonyOS phone runtime continuation

The user resumed this task on 2026-10-09, stopped terminal UI work, and explicitly
requested Pi in the right Herdr pane. The acceptance target is a real HarmonyOS
phone. Prior requests to defer runtime tests and device probes are superseded.

## Confirmed state

Oracle 8.4.6 OHOS libraries and assets are packaged, but phone hosting remains
unimplemented. QfliMysqlRuntime.module rejects devices except 2in1 and tablet;
current SDK 24 still documents native-child APIs as PC/tablet-only. The Java
sibling provides a fork-based native host reference, not MySQL runtime proof.
The initial hdc list returned Empty; phone execution is pending.

## Ownership and implementation

Pi (pi-mysql, Herdr wC:p2) owns OHOS host/launcher/lifecycle/packaging and focused
native/device tests. Main owns coordination, SDK/device evidence, review,
overall verification and task/spec records. Preserve all pre-existing edits.
Keep heavy native builds single-job and sequential with HAP builds.

Implement separate fresh children for initialization and normal service. Prefer
fork/exec of a packaged PIE launcher to avoid inherited multithreaded Flutter
state. A direct fork/entry design must address inherited loader/allocator locks,
file descriptors and signals. Code comes from installed native libraries, not
writable data. Do not run mysqld_main in Flutter or substitute SQLite/cloud.

Retain private Unix sockets, exact SQL results, data/version markers and real
startup/exit diagnostics. Use bounded waits, owned child identities, reaping
and parent-death cleanup. Stop/restart must work within the same app process;
final disposal rejects new work. Never signal arbitrary stale PIDs or treat a
missing exit record as success.

## Acceptance

A packaged phone build must initialize Oracle, answer SELECT VERSION(), pass
CRUD/error cases, preserve exact values across stop/restart, and shut down
without terminating the app. Tests use owned fixtures and preserve user data.
Native tests, HAP compilation and package audits are separate evidence from the
required real phone run. All prior deferred device work is now in scope.
