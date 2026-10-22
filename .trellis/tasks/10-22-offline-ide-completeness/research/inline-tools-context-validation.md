# Inline SQL tools and engine context validation

Date: 2026-10-22. Owner: inline_sql_tools implementer. This is host evidence;
it does not establish OHOS device acceptance or close the umbrella task.

## Delivered behavior

- `SqlEnginePreference` publishes successful disk changes through one revisioned
  Listenable. A failed save leaves the current selection/revision unchanged.
  Offline persisted cloud selections resolve locally without overwriting disk.
- `SqlExecutionContext` opens exactly the selected SQLite or local MySQL engine,
  never substitutes another local engine, and rejects stale/ABA contexts before
  further query/script dispatch. SQLite remains available through its native
  channel path on OHOS. Already submitted native work cannot be cancelled.
- Workbench responds to external preference changes, clears engine-specific
  results/metadata, preserves drafts/library, and waits for submitted work before
  reconnecting.
- Tools exposes the worksheet, ordered results/errors/SQLSTATE/truncation,
  non-executing plain plans, columns/indexes, reviewed MySQL index SQL, lexical
  formatting, identifier/value helpers, CSV and history directly under the
  existing single toolbar. Terminal and all shared common tools retain routes.
- SQLite indexes are inspected inside the app-local service through captured
  context `PRAGMA main.index_list(...)` and per-index `index_info(...)`. String
  arguments are escaped, native errors/truncation/malformed results stay visible,
  and every await is followed by a context/epoch guard before another dispatch
  or publication. Real names, ordered columns, uniqueness, constraint origin,
  primary flags and partial flags are retained. Expression entries are honestly
  displayed as expressions; the service does not invent the expression SQL.
- SQLite index mutation generation stays unavailable with an explicit UI note;
  the worksheet remains available for reviewed SQL. Primary keys do not offer a
  misleading DROP INDEX action. Generated schema previews clear when selection
  changes, and stale schema columns cannot be used for generation.
- The shared lexical scanner's `statement-boundary-unsupported` and scan limit
  are respected. Ambiguous counts show an unavailable explanation while full
  scripts can still reach the engine. Plan requests reject incomplete/error
  scans, executable MySQL comments, file-writing SELECT forms, multiple
  statements, mutations and EXPLAIN ANALYZE.

## Owned files

`lib/sql_engine_preference.dart`, `lib/sql_execution_context.dart`,
`lib/sql_workbench_page.dart`, `lib/sql_tools_service.dart`,
`lib/sql_tools_tab.dart`, `test/sql_engine_context_test.dart`,
`test/sql_tools_service_test.dart`, `test/sql_tools_tab_test.dart`,
`test/sql_home_shell_test.dart`, `test/sql_workbench_page_test.dart`.

`SqlToolsScope` supplies app-local test dependencies through the real profile
builder and home/workbench routes, avoiding filesystem/native work under fake
widget time. Production continues using its ordinary engine/library factories.

## Exact local checks

Authoritative SDK: `D:/ProgramFiles/flutter_ohos/bin/flutter.bat`.
Metadata: Flutter `3.27.5-ohos-1.0.1`, framework
`12587c79e88aacf3172a84e536f226457d037594`, Dart `3.11.5`, engine
`42d3d75a56efe1a2e9902f52dc8006099c45d937`.

Final command (exit 0; no issues):

```text
flutter analyze --no-pub lib/sql_engine_preference.dart lib/sql_execution_context.dart lib/sql_workbench_page.dart lib/sql_tools_service.dart lib/sql_tools_tab.dart test/sql_engine_context_test.dart test/sql_tools_service_test.dart test/sql_tools_tab_test.dart test/sql_home_shell_test.dart test/sql_workbench_page_test.dart
```

Final focused gate (exit 0; **104 passed**, no skipped native regression):

```text
flutter test --no-pub --reporter expanded test/sql_tools_service_test.dart test/sql_tools_tab_test.dart test/sql_engine_context_test.dart test/sql_home_shell_test.dart test/sql_workbench_page_test.dart test/sql_offline_policy_test.dart
```

Covered delayed engine changes during database/table/column/index-list/index
detail awaits, script/plan awaits, late library/history errors, no-notification
staleness, initialization races and ABA changes. UI coverage includes retained
worksheet/results across distant destinations, all common routes, single
toolbar, narrow phone and desktop layouts, and 2x text.

Bundled SQLite regression used
`native/build/windows/qfli_sqlite.dll`, SHA256
`12BB8326B9AB400472D4B95596CB343512A10AB2AC6E40620E09DF2DA2C59F93`.
It created an isolated temporary database with a table containing an apostrophe
and an index name containing an apostrophe, semicolon and comment marker; checked
five indexes (composite, partial, expression, primary automatic, unique automatic)
and their actual metadata; verified plain plan rows, unchanged persisted data,
and `PRAGMA integrity_check = ok`. Only the owned temporary directory was removed.
Missing native libraries produce an explicit skipped test rather than a pass.

`git diff --check` for owned tracked sources/tests returned exit 0. Git emitted
only the repository's LF/CRLF normalization advisories. No stage/commit/push,
core/main/native/packaging/device operation was performed by this implementer.

## Remaining review and platform limits

- Full app analysis/tests, current MySQL semantics and OHOS package/device
  acceptance remain coordinator-owned. Host/native-channel tests do not claim an
  OHOS run. No debugger stepping backend or standalone transaction connection
  was fabricated.
- Review follow-up sent to coordinator: the inherited keyword-case formatter
  does not parse identifier grammar. A MySQL unquoted table/alias named after a
  nonreserved keyword could change case on a case-sensitive server. Production
  sources are frozen for the coordinator's serialized audit build; this remains
  an explicit follow-up before claiming formatting semantics are fully safe.
- SQLite index details are collected by multiple read-only calls. Concurrent
  external DDL can require refresh; failed/incomplete metadata stays visible and
  no partial index list is presented as complete.
