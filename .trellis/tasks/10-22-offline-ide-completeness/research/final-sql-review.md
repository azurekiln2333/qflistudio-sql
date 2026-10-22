# Final SQL product review — 2026-10-22

## Decision and ownership

No unresolved P0/P1/P2 product defect remains in the reviewed scope. Two P2
defects found during this final pass were corrected after the coordinator
explicitly transferred narrow ownership. All reviewed product source is now
frozen. A host-reviewed **checkpoint** is appropriate after the coordinator's
isolated HEAD-plus-task analysis/test gate and scoped staged-diff review pass.
This review does not mark the task, OHOS acceptance, or the umbrella complete.

The reviewer did not stage, commit, push, operate a device, or build/sign a HAP.
The package reviewer owns CMake/Hvigor/ABI staging/signing/archive inspection and
report-collection tooling. Its independent result must accompany this report;
no package result is inferred from source review.

## Inputs and complete reviewed product scope

Loaded current `check.jsonl`, PRD, design and implementation plan, both spec
indexes, and the referenced `sqlite-native-runtime.md` and
`sql-terminal-offline.md`. Also checked `sql-diagnostics.md`, `sql-workbench.md`,
`sql-workspace.md`, the content contract and existing review evidence.

Included task-owned production changes:

- `lib/sql_engine_preference.dart`, `lib/sql_execution_context.dart`:
  persisted local engine identity, preference publication/revision, stale
  context rejection and repository selection without silent substitution.
- `lib/sql_runner.dart`, `lib/sql_database.dart`: SQLite selection stays SQLite
  on OHOS; structured scripts use `executeScript` on the platform bridge.
- `lib/sql_workbench_page.dart`: preference reconnection, command lock,
  selected-engine labels and clearing previous engine selection/results.
- `lib/sql_tools_service.dart`, `lib/sql_tools_tab.dart`: direct retained
  worksheet, context generation checks after asynchronous operations,
  ordered/partial/unavailable results and SQLSTATE, guarded plain plans,
  actual schema/index metadata, text/value helpers and command normalization.
- `lib/sql_code_analyzer.dart`, `lib/sql_syntax_validator.dart`,
  `lib/sqlite_ffi.dart`: exact snapshots/UTF-16 ranges, bounded lexical work,
  strict native decoding, isolated prepare-only validation and its explicit
  incomplete coverage. The new script-cap correction is included.
- `lib/main.dart`: **only** the SQL analyzer import and profile registration.
- `ohos/entry/src/main/cpp/qfli_sql_napi.cpp`,
  `qfli_sql_validation.{h,cpp}` and
  `ohos/entry/src/main/ets/plugins/QfliSqlNative.ets`: structured script
  preparation/stepping/result indices, async validation, response fields,
  UTF-8/UTF-16 conversion and refusal of user-database validation paths.

Included acceptance harness and tests:

- `integration_test/sql_curriculum_native_test.dart`,
  `integration_test/sql_curriculum_ohos_audit.dart` and all four
  `integration_test/support/sql_curriculum_{support,audit,runtime,store}.dart`
  files. Checked catalog mapping, the immutable full denominator, authored
  output checks, engine identity, owned runtime cleanup, timeout retention,
  durable checkpoints and final report gates. Filters/unavailable engines do
  not remove required scripts; timeout never claims native cancellation.
- Diagnostics/analyzer/response/scanner tests; engine-context, runner,
  OHOS-script-dispatch, shared-core-consumer, tools-service/widget,
  home-shell/workbench, SQLite FFI and curriculum-audit/coverage tests.
- Production native validation tests and the both-ABI SDK syntax harness;
  host-core runtime evidence is qualified separately below.

Explicit exclusions: existing startup changes in `main.dart`,
`test/startup_test.dart`, `lib/local_mysql_runtime.dart`, `pubspec.yaml/lock`,
macOS packaging, unrelated old task/research files, generated platform files,
icons/startup ArkUI/agreement changes and other baseline WIP. No shared-core
file was edited. Content draft quality/promotion and package/report tooling
remain with their assigned reviewers/coordinator.

## Findings fixed

### P2 — Script cap treated trailing trivia as statement 513

- Files: `lib/sqlite_ffi.dart`,
  `ohos/entry/src/main/cpp/qfli_sql_napi.cpp`,
  `test/sqlite_ffi_test.dart`,
  `integration_test/support/sql_curriculum_runtime.dart`.
- Evidence: both loops tested the completed count before preparing remaining
  text. Exactly 512 real statements followed by a comment or extra empty
  separator therefore failed the 512-statement limit.
- Fix: let SQLite distinguish an actual next statement from trivia. A real
  513th prepared handle is finalized before `sqlite3_step`, is not appended to
  the completed results, and returns the explicit limit failure. Trivia-only
  tails succeed and retain the last actual statement's summary.
- Actual bundled SQLite regression covers whitespace, line/block comments,
  empty separators, exactly 512 completed results and a forbidden 513th INSERT.
  A separate query of the on-disk fixture confirms count zero, followed by a
  successful DROP. The completed 512 results remain intact.
- The real SQLite audit identity now performs bounded 512-plus-trivia and
  513th-statement refusal smoke calls. Its host execution passed. Its actual
  OHOS execution is still required.

### P2 — Dropping the final table left deleted schema visible

- Files: `lib/sql_tools_service.dart`, `test/sql_tools_service_test.dart`,
  `test/sql_tools_tab_test.dart`.
- Evidence: `runScript` refreshed the table list but skipped `_loadSchema` when
  the selected table became null. Cached columns/indexes were still rendered
  beside the no-table message.
- Fix: always refresh schema after the table list, retaining the existing
  context/epoch guards. The no-table branch clears columns, indexes and stale
  schema errors/notes through the existing cache-reset helper.
- Actual bundled SQLite service regression drops the last inspected table.
  A real-engine widget regression uses the worksheet's Execute button and
  confirms its columns/index disappear and the empty table/index state renders.

Earlier reviewed corrections remain in the final scope: artificial scan
cutoffs do not invent EOF errors; trigger boundary ambiguity is explicit;
FFI validation uses authoritative prepare/tail instead of lexical slices; and
formatting preserves identifiers, expression spelling and exact SQLite headers
by normalizing only recognized statement-start commands. Detailed evidence is
in `diagnostics-review.md` and `tools-formatter-review.md`.

## Findings not fixed / explicit limitations

No additional demonstrated task-owned product defect is left unfixed.

- MySQL grammar validation remains explicitly lexical-only. No SQLite grammar
  substitution or fabricated MySQL runtime pass is accepted.
- Lexical trigger boundaries are conservative and do not cover every possible
  identifier context. Detected ambiguity is reported; native SQLite script and
  validation boundaries come from SQLite rather than that count.
- FFI's 250 ms between-call budget and Dart timeout cannot cancel a single
  ongoing native prepare. OHOS has additional limits/progress handling; its
  actual channel/editor timing still needs target evidence.
- No breakpoint/step/ports backend is introduced. Actual local query output,
  errors and plain execution plans are the SQL capabilities reviewed here.
- CMake/Hvigor/staging/signing/final archive binding and report-collection
  defects, if any, belong to the independent package review. The coordinator
  archived the pre-cap HAP and is rebuilding against the frozen audit inputs.

## HEAD dependency review

Read SQL HEAD versions, not just the dirty working tree:

- Every `LocalMySqlRuntime` constructor argument and `stop()` used by the new
  audit runtime is present at SQL HEAD. The excluded local-runtime delta only
  changes macOS discovery/helper layout; the task does not require that delta.
- `configureProbeRoot` and its debug-only/native-root safety contract already
  exist at SQL HEAD in `QfliMysqlNative.ets`/`QfliMysqlRuntime.ets`.
- New task imports use existing declared dependencies. The extra
  `path_provider_platform_interface` devdependency is referenced only by the
  excluded `startup_test.dart`; task-owned tests do not need that baseline edit.
- Analyzer registration uses the committed core `CodeAnalyzer` and
  `StudioProfile.codeAnalyzer` APIs. Task code does not call the excluded startup
  progress/deferred-frame implementation.

SQL HEAD is `42602e37e75dff348ed4d2a453f7c8af009a4fbb`. The previous complete
host gate used core HEAD `96e6833f46a791949cfa58d36e7ba7a25720d18d` plus its
recorded working-tree hashes. During this final review, core HEAD advanced to
`e13d50d1e2118c2cbc0d36200bef829607edc688`. A byte-hash comparison with the
273-pass manifest found core `lib/services/studio_profile.dart` and
`test/go_snippet_import_test.dart` changed since that gate. The coordinator was
notified; the final isolated checkpoint gate must bind its actual core snapshot.
No clean-HEAD-only or final checkpoint compilation pass is claimed here.

## Verification

Earlier full application gate, before the final two corrections:

- `flutter analyze --no-pub lib test integration_test`: PASS, zero issues.
- `flutter test --no-pub --reporter expanded`: PASS, **273 passed / 0 failed /
  2 skipped**. Both skips are the real desktop Oracle bundle tests, explicitly
  requiring `QFLI_MYSQL_TEST_BUNDLE`. They are not MySQL passes.
- Exact source manifests and complete logs: `full-application-check.md` and
  `build/offline-ide-check/`. The old whole-source gate has not been relabelled
  as verification of the subsequent changes.

After the script-cap correction:

- `flutter test --no-pub --reporter expanded test/sqlite_ffi_test.dart`:
  **8/8 PASS**, no skips, actual bundled SQLite.
- Real `SqliteCurriculumSession` identity/fresh-memory test selected from
  `test/sql_curriculum_audit_test.dart`: **1/1 PASS**, including the new cap smoke.
- Analyze the three changed Dart cap/test/audit files: PASS, zero issues.
- `native/tests/check-ohos-sql-napi-syntax.ps1`: **ARM64 and x86_64 PASS**,
  NAPI/validation core, `-Wall -Wextra -Werror`.

After the final-table schema correction:

- `flutter test --no-pub --reporter expanded test/sql_tools_service_test.dart
  test/sql_tools_tab_test.dart`: **67/67 PASS**, no skips. Both actual-engine
  DROP regressions executed.
- Analyze the three changed tools/service-test/widget-test files: PASS, zero
  issues. `git diff --check` on all seven corrective source files: PASS.
- An initial widget-test harness error (boolean-only `testWidgets.skip`) and
  fake-clock/lazy-scroll waiting issues were corrected locally before the green
  final run; no product fallback was introduced.

Unchanged native validation core's earlier actual bundled SQLite CTest result
remains **1/1 PASS**, with self-tested zero-step and zero-VFS-open interception.
See `native-validation-check.md`. This is production-core host evidence, not
proof of OHOS NAPI execution or HAP installation.

Final corrective input SHA-256 identities:

| File | SHA-256 |
| --- | --- |
| `lib/sqlite_ffi.dart` | `bf0cfc8270a1964065df95688ce4e92530de2cd13a23f9e490a83940e14f5c8b` |
| `test/sqlite_ffi_test.dart` | `9eb52b192555c56ce476ef1d7577f2007a3c0ebc53b06919cd640ffa60b8d1d2` |
| `integration_test/support/sql_curriculum_runtime.dart` | `941c077e14831e46bf2850d49568a280f2d7e246c7634e1b6007c6fc91c44dcb` |
| `ohos/entry/src/main/cpp/qfli_sql_napi.cpp` | `9c1852e50a9c7030997da004ae70162e4fd54b4af9c75b7bf611d5ca71de40d2` |
| `lib/sql_tools_service.dart` | `6d9235a74d142aa456c585525c5b98c96479715efc00ae37feeb3e7b42086784` |
| `test/sql_tools_service_test.dart` | `53cbc27d91b9b5e4f95e571c92614b46654fda6b963654e888468687d63d7353` |
| `test/sql_tools_tab_test.dart` | `d64b8a78e5afe321a3e534457ba13b022a0a67658836ac1ef8c7520ebfeedc28` |

## Meaningful gates still open

- **R2:** original shipped catalog is **126 paired examples, 246 exercise
  answers, 372 scripts**: SQLite 120 examples/360 scripts; MySQL 6 examples/12
  scripts. Host SQLite passes do not establish the current all-engine OHOS
  gate. Require actual full reports, authored-output checks, exact artifact and
  toolchain identity, trusted installation and exclusive device handoff.
- **R3:** 180 new paired topics and 540 scripts remain task-local drafts.
  Production remains 126. Promotion waits for the original OHOS gate; then
  source/asset identity and all expanded target execution must be checked.
- **R4/R6/R7/R8:** host SQL filtering/badge/import/editor/waves/Problems
  integration is evidenced against specific core sources. Current OHOS
  interaction, SQL restart/sidebar/multi-root acceptance, every-language
  highlighting and C native-header evidence remain distinct owner gates.
- **R5/R10/R11:** tools have meaningful host service/widget/native evidence;
  current OHOS UI/runtime/offline acceptance is still required. Runtime/debug
  capability limits remain explicit.
- **R9:** Python module/package behavior and other product deliveries require
  their owners' target evidence; this checkout cannot establish them.
- **R12:** final isolated HEAD-plus-scoped-task analysis/full tests, rebuilt HAP
  inspection, scoped staging/diff review, Conventional Commit and actual remote
  comparisons remain coordinator work. No commit or push is claimed by this
  review. A checkpoint can preserve host-reviewed progress while these target
  and umbrella requirements remain open.

Coordinator spec-sync recommendations: state that the 512-script cap counts
actual prepared statements, finalizes a refused handle before step and accepts
trailing trivia; state that Tools clears all schema caches when its last table
disappears. These are additions to the existing actual-runtime/state contracts.
