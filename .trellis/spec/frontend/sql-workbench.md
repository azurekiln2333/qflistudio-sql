# SQL Workbench

## 1. Scope / Trigger

`SqlHomeShell` (`lib/sql_home_shell.dart`) is the SQL app home: it owns the
**top-level navigation** and exposes exactly **five swipeable PageView
destinations — 数据库、项目、功能、教程、示例**. The shell renders no `AppBar`; each page
owns its single toolbar, which is how a double home / stacked toolbar is avoided.
Phone (<900px) uses a bottom `NavigationBar`; desktop (>=900px) uses a
`NavigationRail` (extended at >=1200px). Pages are lazily built and retained
(`RetainedPage` + `TickerMode`).

The app-local `SqlWorkbenchPage` is the **数据库** destination: on a phone its body
IS the **expandable database→table tree**; on desktop the tree is a side panel
beside the workspace. `SqlProjectsPage` is the **项目** destination — a
self-contained single-toolbar page built from the shared public project APIs
(`ProjectStore`, `ProjectCard`, `ProjectDialogs`, `EditorPage`). Both accept an
`embedded` flag: embedded they drop the cross-page affordances (a back button and
the 项目/更多 push actions respectively) because the destinations are siblings;
standalone (pushed route, tests) they keep the previous behavior. Database UI
belongs in this package.

> Note: the prior "projects is a pushed route, home has no tabs" rule is
> superseded by PRD R3 of task 10-15-sql-release-readiness.

## 2. Signatures

`SqlWorkbenchPage` accepts `repositoryFactory`, `queryLibraryFactory`,
`contentRepository`, and `embedded` for boundary tests. Production loads
`SqlEnginePreference`
and opens local SQLite or local Oracle. An offline profile refuses cloud
repositories even when a former signed-in session persisted that selection.
The existing OHOS default remains native Oracle. Query-library
storage remains independent. `contentRepository` defaults to the app-local
`SqlContentRepository` (C2-owned) and is injected into the SQL `LocalTutorialsTab`
/ `ExampleCodeTab`. Compact view controls are located by their tooltips in device
tests.

## 3. Contracts

- Home is the database/table tree. Phone (<700px): the tree is the home **body**
  (never a launch drawer); tapping a table enters the workspace and a back
  affordance returns to the tree. Desktop (≥700px): tree side panel + workspace.
- Each database expands/collapses **independently** (`_expanded` /
  `_expandedTables`); the active database is expanded by default. The row tap
  selects; the leading chevron toggles expansion.
- Projects are the **项目** destination: a self-contained single-toolbar page
  (one `AppBar` titled "项目", search toggle, and a 更多 menu with
  添加现有项目/移除失效项目) hosting a real project list built from
  `ProjectStore`/`ProjectCard`/`ProjectDialogs`/`EditorPage`. Embedded it has no
  back button; it never adds a home tab bar, rail or PageView of its own.
- The 功能/教程/示例 destinations host the shared `FunctionsTab` /
  `LocalTutorialsTab` / `ExampleCodeTab` directly (each keeps its own toolbar).
  In embedded mode the workbench no longer offers the 更多 menu or the 项目 push,
  because those destinations are sibling tabs. Standalone mode keeps them.
- `sqlProfile.toolsTabBuilder` uses `buildSqlToolsTab` / `SqlToolsBody`: natural-height local
  rows reuse shared `commonTools` metadata/routes and the supplied terminal
  callback. Preserve every tool; do not use fixed-height cards that overflow
  at 2x text scale or merge SQL navigation into shared core.
- The database toolbar always exposes settings, including with zero projects;
  offline `SettingsPage` uses `showAi: false`. Standalone content routes push
  the shared page directly, without wrapping its Scaffold/AppBar again.
- Project visibility is recomputed inside the store ListenableBuilder so
  asynchronous load/create/remove notifications update the displayed list.
  Offline lists hide cloud registry entries, reject stale cloud opens, and
  omit task-activity network reporting while preserving the saved registry.
- Object names, columns, rows, and row identifiers come from the repository.
- Hybrid layout: phone (<700px) home body is the tree with a back affordance;
  desktop (≥700px) is the tree side panel + workspace.
- `_busy` serializes workspace commands. Disable mutation controls during work.
- The engine menu selects persisted SQLite/localMysql. Unsupported SQLite is
  omitted. Display the selected engine; both workbench and preferred editor
  consume `sql_engine.json` (`sqlite`, `localMysql`, or existing `cloud`). Loading
  callers await the same pending read. Save publishes memory state only after
  a successful atomic write. A selected native engine cannot silently fall back.
- Offline product: the engine menu never offers a cloud/online choice, and a
  stale persisted `cloud` value must not open a network repository. The
  workbench short-circuits a stale cloud choice and ignores a cloud
  `_selectEngine` request. `SqlEnginePreference`, the preferred runner,
  `CloudMySqlDatabase` and `openCloud` enforce the same offline policy before
  requesting a token or calling any API; see `sql-terminal-offline.md`.
- Engine changes clear previous object/row/schema/result/filter state before
  async work. Leaving local Oracle stops its prepared runtime, then reloads the
  selected repository. Query text and the independent saved-query library stay.
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
| Database row tap | Select the database; keep/expand it (chevron controls collapse) |
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

`test/sql_workbench_page_test.dart` covers cell edits, phone tree home (no
drawer), independent expand/collapse, standalone projects page without a second
home, offline engine exposure, injected tutorial/example content, 2× text scale
at 390px, empty tables, failed selection loads, query-library commands, and
storage errors.
`test/sql_home_shell_test.dart` covers the five PageView destinations, swiping to
项目/功能/教程/示例, desktop rail vs phone bottom bar, the absence of a second home
toolbar, embedded mode hiding the duplicate pushes, and 2× text scale.
`integration_test/sql_workbench_test.dart` uses the native SQLite repository in
the isolated Android test package and checks tree navigation, grid edits, SQL
results, and saved-query reopening. It refuses production/other platforms and
restores the test sandbox's prior engine preference.
`integration_test/mysql_native_test.dart` covers actual Oracle/SQLite selection,
persisted choice, row edits, old-data clearing, server stop, and preferred editor.

## 7. Wrong vs Correct

Wrong: await a new selection's load while leaving the old grid editable.

Correct: clear `_tablePage` when selection changes; on load failure, render
`_tableError` and offer retry instead of rendering stale rows.
