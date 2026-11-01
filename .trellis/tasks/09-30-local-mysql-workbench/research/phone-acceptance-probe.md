# HarmonyOS phone Oracle acceptance probe

## Boundary

`integration_test/mysql_ohos_probe.dart` is a normal Flutter application entrypoint
for manual HAP installation. It uses the existing OHOS plugin registration,
`qfli_sql/mysql`, `NativeMySqlDatabase`, the workbench repository and the project
SQL engine. It adds no runtime implementation and changes no engine preference.
Only this entrypoint and this note belong to the probe implementation subtask.
Pi owns the native host/runtime; main owns native/HAP builds and the device.

## Build and run

Run from `D:/MyNewProjects/qfli_sql` using the installed OHOS Flutter fork. Do not
run a native build concurrently with a HAP build.

```powershell
flutter build hap --debug --no-pub --target integration_test/mysql_ohos_probe.dart --target-platform ohos-arm64
```

Main installs the signed HAP as an update, preserving the app's existing data:

```powershell
hdc -t 192.168.68.207:46551 install -r ohos/entry/build/default/outputs/default/entry-default-signed.hap
hdc -t 192.168.68.207:46551 shell aa start -a EntryAbility -b com.azurekiln.qfli.sqlab
```

Use the current connected target if the wireless debug address changes. The
connected phone is MRT-AL10 / OpenHarmony 7.0.0.105 (reported by main). Do not
uninstall the bundle, clear application storage, remove MySQL data/version
markers, or use `flutter test`/`flutter drive` automatic device installation.
If update installation reports a signature conflict, preserve the installed
application and resolve signing; uninstalling is not an acceptance workaround.
Keep the phone foregrounded and capture hilog during the run. The entrypoint
starts once automatically and leaves a selectable progress log on screen.

## Evidence and pass condition

Hilog/Flutter console lines start with `QFLI_MYSQL_OHOS_PROBE` followed by
`START`, `REPORT`, `CHECK_START`, `CHECK_PASS`, `CHECK_FAIL`, `PASS`, or `FAIL`
and a JSON object containing `runId`. Only a final `PASS` for the current run
means the harness completed; isolated successful checks are not acceptance.
Large payloads emit numbered `DETAIL` lines: concatenate each event's `jsonChunk`
fields in `part` order to recover its JSON. This retains full initialization and
loader errors in hilog as well as the screen and report.

Reports are written and flushed after each check to:

```text
<AppPaths.storageDirectory()>/mysql-ohos-probe/<unique-run-directory>/report.json
<AppPaths.storageDirectory()>/mysql-ohos-probe/latest.json
```

The `REPORT` marker and the screen expose the actual paths. Reports contain
real server version/comment, UUID, PID, socket, TCP-disabled status, exact SQL
rows, Oracle error codes/SQLSTATE, check durations, and cleanup outcomes. A
report still marked `running` after an app crash/hang is incomplete, not a pass.
`latest.json` is a convenience snapshot; previous per-run reports remain intact.
The first failed startup query records the complete native error even if no
socket or server identity could be obtained.

Checks cover:

- OHOS only, Oracle **8.4.6**, no MariaDB, absolute Unix socket and
  `@@skip_networking = 1`; Oracle's PID must differ from the Flutter app's PID.
- Real schema/table creation and parameterized INSERT/SELECT/UPDATE/DELETE,
  BIGINT `9007199254740993`, exact DECIMAL, Unicode/quotes/semicolons, NULL,
  empty bytes and BLOB hexadecimal values; unchanged UPDATE matched-row count.
- Invalid SQL with `available = true`, error `1064`, SQLSTATE `42000`, and a
  successful subsequent query.
- One-connection multi-statement USE/transactions, ROLLBACK, COMMIT, comments,
  quoted semicolons and a partially committed script failure.
- Actual repository explorer/grid insertion, editing and deletion using returned
  opaque row identities; the actual `NativeMySqlEngine` and private saved SQL.
- `stop` on the registered channel, removal of the server PID file, then a fresh
  adapter/query: a different server PID, the same UUID/socket/datadir identity,
  all exact rows and reopened project/saved-query files retained.
- Cleanup of only the newly created fixture and a final runtime stop while the
  Flutter screen continues running.

The test uses a collision-resistant `qfli_project_ohosprobe_*` schema. CREATE
omits `IF NOT EXISTS`; ownership is recorded only after success. Its unique
temporary project is inside the report run directory. An existing user schema,
project, runtime directory or initialization marker is never deleted. Failures
before cleanup retain the owned fixture for diagnosis; the report records it,
and the harness still attempts a bounded channel stop. Successful runs drop
only their captured schema and delete only their captured project directory;
reports remain, including if a later final stop fails. An unknown CREATE result
after a timeout never grants cleanup ownership. Native calls have a four-minute
deadline and channel stop a 90-second deadline; timeouts report failure and do
not imply native cancellation.

The project engine is injected directly instead of changing `PreferredSqlEngine`
preferences. This verifies Oracle editor execution but does not claim engine
selection UI coverage. Same-process server restart is covered; full app/device
restart and production workbench visual acceptance still require separate runs.

For a later read-only report inspection, rebuild this entrypoint with
`--dart-define=QFLI_MYSQL_PROBE_READ_ONLY=true` added to the build command, update
the HAP in place and launch. It reads the saved report and emits `REPLAY`, never
`PASS`, and performs no MySQL queries, cleanup or report overwrites.

## Implementation verification

Executed with the installed OHOS Flutter fork's Dart SDK:

```powershell
& 'D:\ProgramFiles\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe' format integration_test/mysql_ohos_probe.dart
& 'D:\ProgramFiles\flutter_ohos\bin\cache\dart-sdk\bin\dart.exe' analyze integration_test/mysql_ohos_probe.dart
```

Formatting passed. Focused analysis passed with `No issues found!`. The first
analysis caught a missing explicit `flutter/foundation.dart` import for
`debugPrintSynchronously`; it was fixed before the successful rerun.
No device commands, native/HAP builds, broad tests, or commits were performed by
the probe sub-agent. Device execution is owned by main. Static analysis does not
establish runtime acceptance.

