# SQLite FFI Contract

## 1. Scope / Trigger

This contract applies to `sqlite_ffi.dart`, `invokeSqliteNative`, the local
Flutter plugin under `native`, and SQLite runner/workspace calls.

## 2. Signatures

```dart
SqliteFfi.invoke(String method, Map<String, Object?> arguments,
    {String? libraryPath});
invokeSqliteNative(String method, Map<String, Object?> arguments,
    {MethodChannel? channel});
NativeSqliteDatabase({MethodChannel? channel});
NativeSqliteEngine({MethodChannel? channel});
NativeLocalSqlEngine();
SqlWorkspaceRepository({required Directory root, SqlDatabase database,
    SqlScriptDatabase? scriptDatabase});
```

## 3. Contracts

- Methods are `query`, `execute` and `executeScript`. They receive `source: String` and
  `databasePath: String`; query also receives `params: List<String?>`.
- Default Android/Windows/Linux/iOS/macOS calls execute the actual packaged C
  library on an isolate. OHOS uses `qfli_sql/native`. An explicitly supplied
  channel is always used, including on desktop tests.
- Source and database paths reject embedded NUL; bound values preserve NUL
  using SQLite's explicit UTF-8 byte length and SQLITE_TRANSIENT ownership.
- Grid query prepares one statement; non-whitespace trailing SQL is rejected
  before execution. Parameter count must match. SQL NULL remains Dart null.
- Grid results contain available/exitCode/error/columns/rows/affectedRows/
  truncated and preserve the existing decoder shape. Values use native SQLite
  text conversion. At most 500 complete rows and 1 MiB cell bytes are returned.
- Every statement is finalized and every database closed before native buffers
  are freed. Database lock waits are bounded to 3000 ms for structured queries.
- Script execution reuses `qfli_sql_execute` and `qfli_sql_result_free`; output
  remains tab-separated lines and retains errors and truncation diagnostics.
- Structured scripts use SQLite prepare/tail boundaries in one connection,
  preserving transactions, string literals and all statement results. The
  shared display budget is 500 rows / 1 MiB; scripts stop after 512 statements.
  Errors and limits retain completed results and fail the summary.
- `openDefault()` supplies the native script adapter explicitly. Custom
  repositories without one keep their existing overridden `runQuery` contract.
  OHOS SQLite scripts retain their existing single-query channel behavior.
- The committed editor and workbench select SQLite on supported FFI platforms;
  the existing OHOS native MySQL default remains in the platform dispatcher.
  Pre-existing cloud preference work remains in the working tree separately.
- `QFLI_SQLITE_LIBRARY` is a desktop test/development override, not a fallback
  engine. Missing native symbols/library fail and never report successful SQL.

## 4. Validation & Error Matrix

| Condition | Outcome |
| --- | --- |
| Invalid SQL / parameter count | available true, exitCode 1, SQLite/binding error |
| Second grid statement | Rejected before either statement executes |
| Missing native library | Platform error converted to unavailable by the caller |
| Row/cell limit | truncated true; no partial row |
| Explicit test channel | Use that channel and existing response validation |
| Source/path NUL | Invocation fails before native parsing |

## 5. Good / Base / Bad Cases

Good: a script creates rows and the grid reads/updates the same on-disk database.
Base: a single SELECT returns the engine's columns and nullable strings.
Bad: loading a desktop host DLL on Android, treating a mock as engine evidence,
or labeling SQLite as MySQL.

## 6. Tests Required

`test/sqlite_ffi_test.dart` requires a built native library and runs real SQL.
`integration_test/sql_native_test.dart` exercises the Android application bridge.
`integration_test/sql_workbench_test.dart` opens the actual default workbench,
edits rows, executes SQL and reopens saved queries; it does not inject a repository.
Retain the existing injected-channel tests for query and runner response errors.
Platform build skips and runtime evidence belong in SQLITE_PLATFORMS.md.

## 7. Wrong vs Correct

Wrong: append bound text to SQL, silently choose a cloud evaluator, or copy a C
library into writable app data and assume it can be loaded everywhere.

Correct: bind UTF-8 bytes with native parameter APIs, package the upstream C
library through the platform build, and close native resources in finally.

Wrong: change base `runScript` to invoke its default database directly even when
a custom repository overrides `runQuery`.

Correct: explicitly supply a script adapter in `openDefault`; otherwise preserve
the custom query boundary. Widget regressions must cover both routes.
