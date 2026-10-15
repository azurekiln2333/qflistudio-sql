# Final Content & Contract Review (read-only)

- Task: `.trellis/tasks/10-15-sql-release-readiness`
- Date: 2026-10-15
- Reviewer workspace: `D:/MyNewProjects/qfli_sql` (verified cwd)
- Scope: read-only final review of curriculum, MySQL host fixtures/expectations,
  five-page home contract, offline entries, and terminal report accuracy.
- Constraint respected: **no Flutter/pub/platform build/device operations**, only
  Python validators. No other source was edited; the coordinator commits.
- Review basis (HEAD): `1bfb0cb`, with the curriculum committed in `6457be4` and
  the native acceptance/exercise-expectation work in `d9ff3a7`.

## Verdict

All four areas **match the final implementation**. No blocking defects found.
One **non-blocking** observation is recorded at the end (lesson 118 label).

## 1. Curriculum count and source↔asset consistency — PASS

Commands (Python only):

```powershell
python tool\sql_curriculum\coverage.py
python tool\sql_curriculum\validate_content.py     # authoring source modules
python tool\sql_curriculum\validate_assets.py      # packaged JSON assets
```

- `coverage.py`: **126 lessons total** (sqlite 120 / mysql 6). Every track meets
  its planned minimum; no duplicated `explain`/`code`; "coverage checks passed".
- `validate_content.py`: **120/120 SQLite examples**, **240/240 exercise
  answers** matched authored expectations from the source modules; 6 MySQL
  skipped as "requires MySQL".
- `validate_assets.py`: **120 packaged-JSON examples** matched; **240/240
  packaged-JSON exercise expectations matched** (the earlier "execute cleanly
  only" gap noted in my prior report was closed by `d9ff3a7`); 6 MySQL skipped.
- Source ↔ asset equality (in-memory render vs on-disk JSON):
  ```
  tutorials asset == source render: True
  examples  asset == source render: True
  ```
  The comparison uses `build_content.render_example()` (which adds
  `exerciseSetup`/`exerciseExpectedOutputs`), not bare `example_entry()`; both
  documents are identical to the shipped assets. Note: `schema.example_entry()`
  alone does **not** emit the exercise fixtures — they are added in
  `build_content.render_example()`. This is intentional, not drift.

Per-item structural audit (all 126 tutorials): complete non-empty fields, ≥1
exercise with prompt/hint/answer, dialect visible in display fields, no
placeholder tokens; every example has `CREATE` setup and ends in a query.

## 2. Six MySQL native targets: fixtures and expected outputs — PASS

The `engine == "mysql"` set is exactly **6**: `sql-example-121`…`126`
(`sql-tutorial-121`…`126`, Oracle MySQL 8.0).

For all 126 examples the packaged fixtures match the authored source with
**0 mismatches**:
- `inputFixtures.exerciseSetup == lesson.setup` for every example;
- `inputFixtures.exerciseExpectedOutputs == [ex.expected ...]` for every example;
- `expectedOutput == lesson.expected` for every example.

The 6 MySQL exercises previously had empty expectations with
`verify_query=False`; `track_13_mysql.py` now authors real expectations
(`1`, `6|2`, `4`, `REPEATABLE-READ`, `pen,book,bag`, `1`) and makes
`GROUP_CONCAT` deterministic with `ORDER BY id`. These are additive expectation
values — lesson prose/answers were not re-authored.

Consumer check: `integration_test/sql_curriculum_native_test.dart` iterates
`[121,122,123,124,125,126]`, asserts the shipped MySQL example set, requires a
real Oracle `VERSION() == 8.4.6`, `@@skip_networking == 1`, isolates each case in
a per-run schema, and compares native output against
`inputFixtures['exerciseSetup']` + each `exerciseExpectedOutputs[index]`.
It explicitly refuses non-Android/OHOS hosts, refuses the production sandbox, and
cleans up. This is a genuine device acceptance path (not executed here — device
operations are out of scope for this review).

## 3. Five-page home contract — PASS

`lib/sql_home_shell.dart`:
- `destinationLabels = ['数据库', '项目', '功能', '教程', '示例']` (exactly 5).
- `PageView.builder(itemCount: SqlHomeShell.destinationLabels.length, ...)` with
  `key: 'sql-home-page-view'`.
- The shell renders **no `AppBar`**; phone uses `NavigationBar` (`< 900px`),
  desktop uses `NavigationRail` (extended `>= 1200px`).
- Pages are lazily built and retained (`RetainedPage` + `TickerMode`), and one
  shared `SqlContentRepository` is injected into both 教程 and 示例.

`lib/sql_app.dart:47-48`: `home:` is `SqlHomeShell(store, auth, settings)` —
replacing the older workbench-as-home flow. `SqlWorkbenchPage` and
`SqlProjectsPage` are both embedded as destinations (`embedded: true`), so the
duplicate 项目 push and 更多 menu are gone. This satisfies PRD R3 / AC1.

Test coverage referenced by the UI report (`test/sql_home_shell_test.dart`) exists
and asserts the five destinations, swipe behavior, desktop rail, and no second
home toolbar. (Flutter test execution was not repeated here per scope.)

## 4. Offline entries and terminal report accuracy — PASS

Verified against the actual source:

- `lib/main.dart:27` `isOffline: true`; `lib/main.dart:37`
  `terminalCommandDelegate: SqlTerminalCommands.execute` — matches the terminal
  report's claim that the delegate is registered.
- `lib/sql_runner.dart` defines `SqlTerminalCommands.execute` (report cites line
  340; the class/delegate signature matches
  `Future<bool> Function(SandboxShellBackend, String)`).
- Offline cloud guards exist as reported:
  - `lib/sql_engine_preference.dart` centralizes
    `StudioProfile.offlineOnly` → cloud unavailable;
  - `lib/mysql_workspace_repository.dart:32` throws
    `UnsupportedError(SqlEnginePreference.cloudUnavailableMessage)` in the cloud
    open path;
  - `lib/cloud_mysql_database.dart` refuses offline calls;
  - `lib/sql_workbench_page.dart:131,176,182` short-circuits a stale persisted
    `cloud` choice and ignores `_selectEngine(cloud)` when offline; the engine
    menu offers only `SQLite` / `本机 MySQL`.
- The terminal report's withdrawal of the "shared editor Git page exposed
  offline" claim agrees with the UI report §4: the shared editor gates the Git
  menu item and dispatch on `offlineOnly != true`, and no other SQL route reaches
  `GitPage`. Both reports now state the same reachable-UI conclusion.

The terminal report's explicit non-claims (no device install, no MySQL device
execution, no Android/OHOS build success, desktop host-shell passthrough not
isolated) are accurate and consistent with the platform report.

## 5. Cross-report consistency

- `curriculum-report.md`, `ui-report.md`, `terminal-offline-report.md`,
  `platform-report.md`, and `native-integration-review.md` agree on: 126
  lessons/examples, 6 MySQL-only lessons, five-page home, offline-only profile,
  and the "MySQL device execution pending real runtime" limitation.
- Device/native execution of the 6 MySQL lessons remains the only
  curriculum-related unverified item, and it is correctly scoped to the native
  acceptance test / platform worker.

## Observations (non-blocking)

- `sql-tutorial-118` summary contains the word "MySQL" in prose but its
  `runtime.engine` is `SQLite 3.50` and it is not in the `engine=mysql` fixture
  set. This is a comparative reference inside a SQLite lesson, not a
  misclassification. No `coverage.py`/`validate_*` check flags it. No action
  needed; recorded only for completeness.

## Evidence commands run (read-only, Python only)

```
python tool\sql_curriculum\coverage.py
python tool\sql_curriculum\validate_content.py
python tool\sql_curriculum\validate_assets.py
# plus an in-memory render-vs-asset equality check via build_content.render_example
```

No files were modified except this review note. No Flutter/pub/platform build or
device operation was performed.
