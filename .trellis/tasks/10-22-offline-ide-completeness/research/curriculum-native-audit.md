# Exhaustive native curriculum audit

Date: 2026-10-22. Status: implementation and host verification passed;
current OHOS execution remains unproven.

## Boundary

The original integration target selected only MySQL lessons 121–126. The new
runner derives its denominator from the actual shipped `SqlContentRepository`
catalog through `curriculumCases`, shared with the existing bundled-engine host
coverage test. It rejects lesson/example mapping, source/output or exercise
expectation drift before invoking a native session.

The current shipped denominator is **126 examples / 372 scripts** (246 exercises):

| Engine | Examples | Main/exercise scripts |
| --- | ---: | ---: |
| SQLite | 120 | 360 |
| Oracle MySQL | 6 | 12 |

Correction after independent package/collector checks: the six MySQL entries
each contain one exercise, while every SQLite entry contains two. Earlier
handoffs incorrectly assumed two exercises for all126 and reported378. The
runtime has always derived its denominator from the actual catalog; no shipped
exercise was removed and no execution coverage was reduced by this correction.

The 180 new paired topics remain task-local drafts and are excluded. Product
curriculum assets and authoring modules were not changed by this implementation.

## Files

- `integration_test/sql_curriculum_ohos_audit.dart`: manually installed debug
  application using `WidgetsFlutterBinding`, with status and report-path UI.
- `integration_test/sql_curriculum_native_test.dart`: integration-test adapter
  using the same catalog denominator, comparator, runner and real sessions.
- `integration_test/support/sql_curriculum_audit.dart`: complete immutable
  denominator, per-script pass/fail/notExecuted outcomes, engine/platform
  identity checks, coverage reconciliation and all-engine gates.
- `integration_test/support/sql_curriculum_runtime.dart`: actual native SQLite
  and independently owned private Oracle runtime sessions.
- `integration_test/support/sql_curriculum_store.dart`: unique app-private run
  directory, flushed checkpoints/events and numbered JSON log chunks.
- `test/sql_curriculum_audit_test.dart`: orchestration/persistence regressions
  plus an actual bundled SQLite session smoke and isolation test.

The existing shared comparator/support and
`test/sql_curriculum_native_coverage_test.dart` were reused without modification.
No test binding, mock messenger or native plugin replacement is imported by the
standalone application. No production preference/source writes, uninstall,
staging, commit or device operations were performed by this implementer.

## Runtime and failure contracts

- Every expected script is present before engine identification or execution.
  An explicit engine filter changes execution only. Missing engine identity,
  skipped engines, failed output, any notExecuted record, timeout, missing
  cleanup confirmation or lost checkpoint prevents the full device gate.
- `deviceGatePassed` also requires actual `Platform.operatingSystem == 'ohos'`
  and a nonempty platform version. Host engine success cannot satisfy it.
- Ordinary SQL/output failures continue to later scripts and the next engine.
  A four-minute identity/script/cleanup deadline is a Dart deadline, not native
  cancellation. A timed-out engine receives no later script invocation, and
  its owned roots are retained. Pending denominator entries stay notExecuted.
- SQLite scripts each use a new `:memory:` connection. Actual version identity
  must be bundled SQLite 3.50.*, followed by `SELECT 1; SELECT 2;` with exactly
  two independent dense 1×1 result sets; the observed smoke is in the identity.
- Oracle requires the actual pinned 8.4.6 identity, no MariaDB marker, networking
  disabled and socket/PID/datadir within newly owned roots. OHOS uses the
  debug-only `configureProbeRoot` method before any runtime activity; Android
  additionally requires the integration-test application sandbox. Each script
  gets a separate validated schema. Only successful CREATE establishes schema
  cleanup ownership. Cleanup validates canonical ownership and confirmed stop
  before deleting owned roots; timeout retains them.

## Report and build integration

The standalone app writes only its audit report/events and owned runtime fixture:

```text
<app-private storage>/sql-curriculum-audit/<unique-run>/report.json
<app-private storage>/sql-curriculum-audit/<unique-run>/events.jsonl
```

OHOS storage must resolve under `/data/storage/el2/base/` with a `files` segment;
the generic AppPaths writable-directory fallback cannot silently become report
storage outside the app sandbox. Each run creates a new directory. The report
is atomically replaced using a flushed temporary file. Its event is flushed
first, so a failed final event append cannot publish a PASS report on disk.

Reports include platform/version, engine identities, complete per-engine counts,
source, authored expected output, actual native result metadata/rows, outcomes,
timing, cleanup and fatal failures. Checkpoints precede/follow every script.

Log prefix: `QFLI_SQL_CURRICULUM_AUDIT`. The final `REPORT` event either contains
the JSON or announces `chunked:true`. Reassemble `DETAIL` records for the same
`runId` and `sequence` in `part` order from 1 through `parts`, concatenate
`jsonChunk`, then JSON-decode the result. The decoded event's `details` is the
report. Chunks preserve Unicode surrogate pairs and stay below 3000 UTF-8 bytes
per log line. An unavailable filesystem still emits a chunked `REPORT` with
`logOnly:true` and `persistError`; a lost checkpoint keeps its gate false. The
persistent report is authoritative when the device log ring has wrapped.

Optional build stamps:

```text
QFLI_SQL_CURRICULUM_BUILD_ID
QFLI_SQL_CURRICULUM_REVISION
QFLI_SQL_CURRICULUM_TOOLCHAIN
```

`QFLI_SQL_CURRICULUM_ENGINES` defaults to `sqlite,mysql`. A SQLite-only run is
diagnostic evidence and leaves the 12 Oracle scripts notExecuted; it cannot
pass the full OHOS device gate. The coordinator owns target selection, unique
audit bundle configuration, signing, artifact hashes, installation and device
log/report capture. This implementer did not build/install a HAP.

## Verification

SDK: `D:/ProgramFiles/flutter_ohos`, cached Flutter version
`3.27.5-ohos-1.0.1`, framework revision
`12587c79e88aacf3172a84e536f226457d037594`, Dart **3.11.5** on Windows x64.

```powershell
dart format integration_test/sql_curriculum_native_test.dart integration_test/sql_curriculum_ohos_audit.dart integration_test/support/sql_curriculum_audit.dart integration_test/support/sql_curriculum_runtime.dart integration_test/support/sql_curriculum_store.dart test/sql_curriculum_audit_test.dart

dart analyze integration_test/sql_curriculum_native_test.dart integration_test/sql_curriculum_ohos_audit.dart integration_test/support/sql_curriculum_audit.dart integration_test/support/sql_curriculum_runtime.dart integration_test/support/sql_curriculum_store.dart integration_test/support/sql_curriculum_support.dart test/sql_curriculum_audit_test.dart

D:/ProgramFiles/flutter_ohos/bin/flutter.bat test --no-pub --reporter expanded test/sql_curriculum_audit_test.dart test/sql_curriculum_native_coverage_test.dart

git diff --check -- integration_test/sql_curriculum_native_test.dart
```

Results: analyzer **no issues**, focused tests **26 passed**, diff whitespace
check passed. Tests cover omitted/empty engine selections, count preservation,
output/SQL failure continuation, script/identity/cleanup timeouts, late native
completion, missing/mismatched engine/platform identity, failed construction,
unconfirmed/throwing cleanup, failed checkpoints, immutable denominators, unique
persistent runs, exact Unicode chunk reassembly, and final-event filesystem
failure without a stale PASS report.

Actual bundled SQLite smoke passed dense multiple-result validation and verified
that a table created by one script is absent in the next `:memory:` database.
Existing native catalog test emitted:

```text
QFLI_SQL_CURRICULUM_HOST sqliteExamples=120 sqliteScripts=360 mysqlNotExecuted=6
```

Actual library: `native/build/windows/qfli_sqlite.dll`, SQLite **3.50.0**, SHA256
`12bb8326b9ab400472d4b95596cb343512a10ab2ac6e40620e09df2da2c59f93`.
This is real host native evidence; it does not prove an OHOS bridge or runtime.

Unchanged product asset SHA256 after the audit work:

- tutorials: `0ea1071c1aa9a6611ebceba7c4b4a832f6f635f4b57e052406f6455c99e5a2e0`
- examples: `cacfbf628a56fc42635764e3767981da14325eb9c8802cda94f5be0270276049`

## Open authoritative acceptance

The full current-catalog OHOS run, real 12 Oracle scripts, native stop/root
cleanup, HAP signing/install and current artifact identity remain coordinator
acceptance work. Draft promotion remains blocked by the user's required order
until the existing shipped catalog passes the current OHOS gate. No device PASS
is claimed by this host verification.
