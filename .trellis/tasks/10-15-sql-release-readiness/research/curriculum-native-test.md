# Native MySQL curriculum verification target

## Scope and current result

`integration_test/sql_curriculum_native_test.dart` is ready for the platform
worker to execute. This worker ran static and host curriculum checks only;
**the six MySQL examples and six MySQL exercises have not yet been executed on
Android/OHOS by this worker**. Unsupported platforms/native engines fail the
target, rather than being skipped or replaced by SQLite/mocks.

The target reads both shipped JSON assets through
`SqlContentRepository(bundle: rootBundle)` and the shared `ContentCatalog`
parser. It requires exactly the six bundled MySQL example IDs 121–126, links
each example to its actual tutorial lesson, and checks code/lesson expectation
consistency. Every lesson script and each exercise setup+answer runs in a new
schema. It compares ordered query rows to the authored outputs; statement
affected-row messages and column headers are excluded. Native NULL becomes an
empty pipe-delimited field, matching the existing authored convention (e.g.
lesson 126 `1|x|`). `(no rows)` explicitly means an empty query result; errors,
missing query results, truncation or unavailable engines cannot pass as empty
output. Exercise setup and answer run in the same native script/connection.

Six separate tests are registered so a failed lesson cannot silently remove
coverage of the other lesson IDs. Test output uses structured
`QFLI_SQL_CURRICULUM_NATIVE IDENTITY/PASS/CLEANUP/RETAINED` markers. Successful
completion requires six lesson PASS markers, six exercise PASS markers, a
successful test-framework summary, and cleanup evidence.

## Authored fixture contract

The prior shipped assets omitted exercise setup and expected outputs; the six
MySQL exercise objects also had empty `expected` and `verify_query=False`.
The coordinator authorized the following narrow corrections:

- `build_content.render_example` adds `exerciseSetup` and
  `exerciseExpectedOutputs` under each example's `inputFixtures`.
  `exerciseExpectedOutputs` is a **JSON-encoded string array** because the shared
  parser preserves only string fixture values. The values are authored
  `Exercise.expected` fields, never captured database output.
- The generator now rejects exercises without an authored expectation. Use the
  explicit `(no rows)` sentinel when the expected query result is empty.
- `validate_assets.py` uses the exact packaged setup instead of splitting SQL
  on semicolons, and compares every packaged exercise's output with its authored
  expectation. It also checks tutorial/example pairing and code/output drift.
- Only six MySQL expectation fields and one ordering clause changed in lesson
  authoring. All use `verify_query=True` through the existing default.

| Lesson | Exercise output | Reason from authored setup/SQL |
| --- | --- | --- |
| 121 | `1` | Setup inserts counter 1; the exercise runs before the lesson's separate upsert mutation |
| 122 | `6\|2` | Two UTF-8 Chinese characters occupy six bytes and two characters |
| 123 | `4` | January 5 minus January 1 is four days |
| 124 | `REPEATABLE-READ` | The pinned isolated Oracle runtime's documented default isolation |
| 125 | `pen,book,bag` | Explicit `ORDER BY id` inside GROUP_CONCAT establishes deterministic insertion-ID order; separator remains its default comma |
| 126 | `1` | The shipped answer is `SELECT 1` |

The exercise fixture intentionally uses `Lesson.setup`, not the example's
complete script: lesson 121 therefore expects 1 for the exercise, while its
complete upsert example expects `a|3`.

## Native isolation and cleanup

Android uses the existing integration target package
`com.azurekiln.qfli.sqlab.integrationtest`; the test checks the native layout's
data path contains that exact package segment and refuses the production
sandbox. It reuses the shipped binary/resource layout but creates a separate
`LocalMySqlRuntime` with a newly created test datadir and temporary directory.
No production default server is started, no engine preferences are changed,
and no production project is opened.

OHOS requires a debug HAP and invokes the existing debug-only
`qfli_sql/mysql.configureProbeRoot` before the first database call. The native
API rejects existing roots or an already started/reconfigured runtime. Queries
then use the production native channel against this fresh root, not the normal
`<filesDir>/mysql` data. The installed Flutter OHOS SDK advertises/registers its
OHOS `IntegrationTestPlugin`; no new native method is required.

Identity checks require real Oracle **8.4.6**, reject MariaDB, require
`@@skip_networking = 1`, and verify actual socket/PID paths lie under the owned
runtime/test directories. Schema names include a fresh run ID. `CREATE DATABASE`
has no `IF NOT EXISTS`; only a successful creation establishes cleanup ownership.
Each schema is dropped after comparison, then the runtime is stopped and its
PID file must disappear before recursively deleting the newly owned roots.

Android fixtures now use a short, newly created private-cache `qcXXXXXX`
directory with a `t` temporary subdirectory. The previous descriptive
storage/run-ID hierarchy produced a roughly 137-byte Unix socket name, exceeding
the 108-byte limit including NUL; the new package-specific path requires about
100 bytes. Cleanup records the canonical project identity immediately after
creation and requires an exact match before deletion. Canonical runtime-root
containment also handles Android's `/data/user/0` and `/data/data` aliases;
external OHOS roots still require the `mysql-probe/<runId>` ownership guard.
Independent read-only review and focused Dart analysis pass
(`curriculum-short-socket-analyze.log`). Device execution remains separate.

Native requests have a four-minute deadline. A timeout is a failure, blocks
further mutations, and retains the fixture with a RETAINED log: Dart timeout
does not prove native SQL was cancelled, so the test never deletes an active
database directory. Missing API/runtime/isolation support fails visibly.

## Platform execution handoff

Use explicit live device serials from the platform worker. The following are
target templates, not execution evidence from this worker:

```powershell
# Android: keep the override local; inspect the built APK before installation.
$savedSqlIntegrationSwitch = $env:QFLI_SQL_INTEGRATION_TEST
try {
  $env:QFLI_SQL_INTEGRATION_TEST = '1'
  flutter build apk --debug --target-platform android-arm64 -t integration_test/sql_curriculum_native_test.dart
  if ($LASTEXITCODE -ne 0) { throw 'Integration APK build failed' }
  $sqlApkBadging = & <aapt2-path> dump badging build/app/outputs/flutter-apk/app-debug.apk
  if ($LASTEXITCODE -ne 0 -or
      ($sqlApkBadging -join [Environment]::NewLine) -notmatch "package: name='com\.azurekiln\.qfli\.sqlab\.integrationtest'") {
    throw 'Unexpected integration APK package'
  }
  flutter test --no-pub -d <android-serial> integration_test/sql_curriculum_native_test.dart --reporter expanded
  if ($LASTEXITCODE -ne 0) { throw 'Native curriculum failed' }
} finally {
  $env:QFLI_SQL_INTEGRATION_TEST = $savedSqlIntegrationSwitch
}

# OHOS: build debug target, then install/launch preserving existing app data.
flutter build hap --debug -t integration_test/sql_curriculum_native_test.dart
```

The Gradle target may be a generated `flutter_test_listener` wrapper. Isolation
therefore detects the standard Base64 Dart-define integration marker as well as
the explicit process switch/direct target; it rejects an unmarked listener.
The four actual manifest cases and the final APK/device evidence belong in
`android-final-report.md`. Never infer the installed package solely from the
original Dart target filename. The runtime guard remains independent.

For OHOS, the repository's bundle name remains
`com.azurekiln.qfli.sqlab`. Use the platform worker's existing explicit-device
manual HAP install/launch/log capture procedure; **do not use an automatic
test-tool uninstall against the production bundle**. The test root is isolated
even when installing over the normal app. Preserve user data and restore the
normal application after test execution. Require all test/cleanup markers and
save the full log; packaging alone is not native curriculum acceptance.

No full interactive terminal client, network service, UI or production runner
was changed for this target.

## Executed host checks

- `dart analyze integration_test/sql_curriculum_native_test.dart`: no issues.
  Log: `curriculum-native-analyze.log`.
- `flutter test --no-pub test/sql_curriculum_test.dart --reporter expanded`:
  **8 passed**. Log: `curriculum-native-host-tests.log`.
- `python tool/sql_curriculum/validate_content.py`: **120/120 SQLite examples,
  240/240 exercises** matched; six MySQL lessons explicitly not executed.
  Log: `curriculum-source-exercise-validation.log`.
- `python tool/sql_curriculum/validate_assets.py`: **120 packaged SQLite
  examples, 240/240 packaged exercise expectations** matched; six MySQL lessons
  explicitly not executed. Log: `curriculum-packaged-exercise-validation.log`.
- `python tool/sql_curriculum/coverage.py`: **126 lessons** with required track
  coverage; no placeholders/duplicate bodies. Log: `curriculum-native-coverage.log`.
- Exact UTF-8 file-text comparison of both JSON documents with current
  `schema.dumps` output: **126 tutorial entries and 126 example entries match**.
  All **246 authored exercises** now have nonempty expectations and query
  verification enabled.
- Negative checks against temporary copied assets (repository assets untouched):
  syntactically valid answer with wrong expected output is rejected; blank
  exercise expectation is rejected.
- `git diff --check` passed for generator, validator, lesson source and assets.

## Files for coordinator review/commit

- `integration_test/sql_curriculum_native_test.dart`
- `tool/sql_curriculum/build_content.py`
- `tool/sql_curriculum/validate_assets.py`
- `tool/sql_curriculum/lessons/track_13_mysql.py`
- `assets/content/sql_examples.json`
- `assets/content/sql_tutorials.json` (only deterministic lesson-125 answer change)
- This report and the five logs named above.

Suggested commit: `test(sql): verify bundled curriculum on native MySQL`.
The worker did not build, install, stage or commit. The coordinator/platform
worker must append actual Android/OHOS execution results before claiming those
platforms passed.
