# Final SQL release quality review

Reviewer scope: `D:/MyNewProjects/qfli_sql` only. Shared
`../qfli_studio_core` was read-only. Review covered committed SQL release work
`41b710d..1bfb0cb`, the current SQL frontend/runtime specs, the Android isolation
delivery `84746f1` owned by Pi p5, and the two Android native UI targets explicitly delegated
by the coordinator. Existing platform/native/UI/terminal review evidence was
reused rather than repeating independent owners' work.

## Findings fixed

### High: native tests could access the production application sandbox

Files: `integration_test/mysql_native_test.dart`,
`integration_test/sql_workbench_test.dart`.

These targets previously opened default application repositories and wrote the
engine preference without checking the actual app process. The old Gradle
target-path detector had already demonstrated that Flutter's listener wrapper
could build the production package. Both tests now read `/proc/self/cmdline`
and require the exact `com.azurekiln.qfli.sqlab.integrationtest` process before
runtime preparation, preference writes, temporary fixtures or database opens.
The MySQL target additionally requires its native runtime data path to contain
that exact application-id segment. Unsupported platforms fail explicitly.
The read-only process check also avoids installing native resources in the
production sandbox before refusing it.

### Medium: native UI tests still assumed the former phone layout

Files: `integration_test/mysql_native_test.dart`,
`integration_test/sql_workbench_test.dart`.

The phone home is a database tree; opening a table replaces it with the
workspace. The MySQL helper still checked for the removed drawer and then
tried to select invisible database rows after switching engines. It now uses
the real `返回数据库` toolbar action before selecting the database/table. The
SQLite target now selects its own database/table instead of expecting its row
grid on the initial phone home. Both scroll their target tree rows into view.
The SQLite target explicitly selects SQLite and restores the prior preference,
so a previous local-MySQL choice cannot change what it tests.

### Medium: native fixture cleanup did not consistently prove ownership

File: `integration_test/mysql_native_test.dart`.

The lifecycle test registered `DROP DATABASE IF EXISTS` before successful
creation, and its editor schema was removed only on the success path. The
engine-switch test registered cleanup after both creates, leaving the first
database behind if the second create failed. Cleanup now tracks each successful
create; a fresh owned project's published MySQL marker establishes ownership
of its generated editor schema. Cleanup checks real drop results. Independent
teardown callbacks ensure a failed schema assertion does not prevent the
remaining callbacks, runtime stop, preference restoration or store disposal.

## Integration review

- `SqlLabApp` opens the app-local `SqlHomeShell`, whose PageView has exactly
  five retained destinations. Database/project widgets receive embedded mode;
  shared tools/tutorial/example pages receive their required stores and local
  content repository. No home-navigation merge was added to shared core.
- `sqlProfile` supplies the same SQL terminal delegate to the shared standalone
  and editor terminal consumers. It uses the preferred local engine and project
  metadata, preserving editor/database identity. No missing production terminal
  method or placeholder implementation was found in the release-owned files.
- Cloud policy is enforced at preference, repository-open and query/script
  boundaries before token/API access. The app-local project list recomputes
  after store notifications and filters stale cloud entries without deleting
  their registry data.
- Content goes through the shared catalog parser. The fixture outputs remain
  strings, including the JSON-encoded exercise-output array required by that
  parser. Source and shipped JSON both execute against authored expectations.
- Read-only review of the Android Gradle patch found no additional defect.
  Standard Base64 Dart defines recognize the integration marker by key for both
  values, direct targets and explicit process switches form a union, and an
  unmarked listener wrapper fails closed. Pi p5 reports four actual manifest
  cases: marker false/true both use `.integrationtest`, no-signal wrapper fails,
  and ordinary main uses the production package. Device installation still
  requires inspecting the actual APK package, as the coordinator specified.
- The coordinator synchronized the frontend Quality Check, current tools-body
  name, OHOS local-engine distinction and Android wrapper-isolation contract
  after the review reported their drift.
- At frozen shared core `8b33443`, both generic terminal help and unsupported
  toolchain text describe the host application's tools. The older report's
  Java-specific copy finding has been resolved; this reviewer verified the
  current source directly.

## Verification

Executed directly by this reviewer, without Flutter/pub/build/device activity:

| Check | Result |
| --- | --- |
| `get_context.py --mode packages` | Single repository; frontend/backend layers reviewed |
| `coverage.py` | PASS: 126 lessons, required tracks, 120 SQLite + 6 MySQL |
| `validate_content.py` | PASS: 120/120 SQLite examples; 240/240 exercise answers |
| `validate_assets.py` | PASS: 120 shipped SQLite examples; 240/240 shipped exercise expectations |
| Exact generated-text comparison without writing assets | PASS: both assets exactly match current authoring; 126 entries each |
| Authored exercise metadata | PASS: all 246 have nonempty expectations and query verification |
| `git diff --check` for edited tracked native UI target | PASS |

The Python validators explicitly do **not** execute the six MySQL-only lessons.

The coordinator completed the final gate against source-clean shared core
`8b33443` (only two untracked Trellis context manifests remain). This reviewer
read the saved output directly:

| Final source check | Result / evidence |
| --- | --- |
| `flutter analyze --no-pub lib test integration_test` | PASS: no issues, 2.5 s; `final-core8b33443-analyze.log` |
| Repository-root `dart analyze` | PASS: no issues; `final-core8b33443-repository-analyze.log` |
| `flutter test --no-pub --reporter expanded` | PASS: 92 passed, 2 explicit desktop-Oracle skips; `final-core8b33443-tests.log` |

The analysis includes both newly repaired integration targets. The coordinator
ran Dart formatting on exactly those two targets before this gate. Lint and
type checking are green. Native Android device execution of those targets is
still owned by Pi p5 and is not established by the host suite.

Additional existing evidence reviewed: `terminal-offline-tests.log` (75 combined
checks), the native host regressions and the platform artifact audit reports.
Their independent execution/platform limits retain their original meaning;
final platform builds must record the actual source/core revision.

## Findings not fixed / release limits

1. **Release blocker — OHOS signing and phone acceptance:** SQL-specific signing
   files referenced by the local build profile are missing. The unsigned HAP
   compiles/packages and its four fresh native libraries were audited, but
   signing, installation and this release's real-phone acceptance remain open.
   Reusing another product's profile or clearing the installed user's database
   is outside this task and was not done.
2. **Release blocker — Android distribution signing:** the existing release
   configuration uses the Android Debug certificate. Successful local builds
   and test installations do not establish store-ready signing. The owner must
   supply the SQL release keystore/configuration.
3. **Pending acceptance:** Pi p5 owns final native curriculum/lifecycle/UI runs,
   final production APK restoration and artifact hashes. Final analysis and the
   host suite against core `8b33443` are green; they do not replace these device
   and artifact checks.
4. **Explicit coverage limit:** the two desktop Oracle skips need
   `QFLI_MYSQL_TEST_BUNDLE`; they do not establish desktop runtime acceptance.
   OHOS debug probe/signed-device tests cannot be replaced by host stub tests.
5. **Documented terminal limits:** full interactive `mysql`/`sqlite3` clients are
   not bundled, and native SQL exposes no cancellation/rollback handle. Desktop
   host-shell fallback can execute manually typed host network tools; mobile
   lacks that fallback. No broader desktop network-isolation claim is made.
6. **Evidence formatting only:** the committed raw analyzer progress line in
   `research/flutter-analyze-final.log:1` has trailing spaces. This is unrelated
   to source correctness; the coordinator owns retained evidence files and was
   informed. No unrelated baseline/macOS/privacy changes were included here.

No further product source change was identified by this final integration
review. Do not archive release readiness or mark all platforms accepted until
the pending execution and signing requirements above have concrete evidence.
