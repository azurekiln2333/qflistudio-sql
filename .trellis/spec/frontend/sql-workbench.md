# SQL Workbench

## 1. Scope / Trigger

The app-local `SqlWorkbenchPage` is the default SQL home. Shared project editing
remains reachable through `HomePage`; database UI belongs in this package.

## 2. Signatures

`SqlWorkbenchPage` accepts `repositoryFactory` and `queryLibraryFactory` for
boundary tests. Production opens `SqlWorkspaceRepository.openDefault()` on
Android/Windows/Linux/iOS/macOS and `MySqlWorkspaceRepository.openLocal()` on
the existing OHOS path, plus `SqlQueryLibrary.openDefault()`.
Compact view controls are located by their tooltips in device tests.

## 3. Contracts

- Object names, columns, rows, and row identifiers come from the repository.
- Use a drawer below 700 logical pixels; keep table data horizontally scrollable.
- `_busy` serializes workspace commands. Disable mutation controls during work.
- A selected database/table and `_tablePage` must refer to the same objects.
- Query-history failures must preserve a successful SQL result and display a
  separate storage error with retry.
- Dialog input controllers belong to the dialog widget's lifetime. Dispose them
  from `_DialogLifetime.dispose`, after route removal and animation.
- SQL execution uses `runScript`, shows ordered results and summary truncation,
  and refreshes object metadata after errors as preceding statements may commit.
- Schema and export controls depend on repository capability getters. Oracle
  generated columns are never directly writable. After changing structure,
  reload both columns and indexes before enabling row/schema operations.
  Schema view owns `_schemaColumns`, `_indexes`, and `_schemaError`; it never
  requires a successful row-page load. Returning to Data reloads the real page.
- SQL documents use PickerService selection and URI writes, local paths or
  capped native URI reads, UTF-8, and a 1 MiB
  cap. Single-table InnoDB export reads one connection's consistent snapshot,
  preserves NULL, uses HEX literals and UTC timestamps, and fails on truncation.
  SQL URI reads use `qflistudio/platform.readSqlUri({uri})`, which checks the
  file size before allocation. Generic `readUri` remains available for shared
  editor resources. Both native reads and writes loop to completion; premature
  EOF, zero writes, or file growth fail rather than returning a shortened file.
  URI export respects Uint8Array.byteOffset and fsyncs before reporting success.

## 4. Validation & Error Matrix

| Condition | Required state |
| --- | --- |
| Table selection changes | Clear old rows and selection-specific filters |
| New table load fails | Show error and retry; keep old rows inaccessible |
| Table has zero rows | Keep headers, paging counter, and insert command visible |
| Library write fails | Show storage error; retain query result |
| User cancels a dialog | Perform no database write |
| Row page exceeds the display cap | Data shows error; Schema remains independently available |
| SQL URI exceeds 1 MiB | Native bridge rejects before allocating its content buffer |

## 5. Good / Base / Bad Cases

- Good: edit a nullable cell, refresh native data, and show the committed value.
- Base: open an empty database, create a table, and add its first row.
- Bad: display the previous table's row identifiers after selecting another table.

## 6. Tests Required

`test/sql_workbench_page_test.dart` covers cell edits, 390px navigation, empty
tables, failed selection loads, query-library commands, and storage errors.
`integration_test/sql_workbench_test.dart` uses the native repository and checks
grid edits, SQL results, and saved-query reopening.

## 7. Wrong vs Correct

Wrong: await a new selection's load while leaving the old grid editable.

Correct: clear `_tablePage` when selection changes; on load failure, render
`_tableError` and offer retry instead of rendering stale rows.
