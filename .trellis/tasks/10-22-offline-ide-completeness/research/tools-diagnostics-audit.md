# Research: SQL tools, diagnostics, and offline IDE capabilities

- Query: Which SQL-specific tools can be exposed directly in the Tools tab, which existing execution/schema/transaction/output APIs can be reused, and how should SQL provide safe unsaved-buffer diagnostics to the shared editor?
- Scope: mixed; product and shared-core source inspection, read-only cross-product contract inspection, and official vendor documentation.
- Date: 2026-10-22
- Ownership: this report only. No application, shared-core, sibling-product, native, task-lifecycle, or Git changes were made. No runtime/test pass is claimed by this research.

## Findings

### Requirements and source of authority

The attachment `C:/Users/lichengyu/.codex/attachments/2cf53127-89fb-437c-ba48-f4d09a4f8791/pasted-text-1.txt` requests useful language tools **directly on the Tools tab**, offline-only standalone products, editor syntax errors with wave underlines and Problems-style feedback, honest debug/log/output capabilities, all examples verified on current OHOS, shared-core coordination, and standardized commits/push where possible. This audit covers the SQL tool/diagnostic slice; it does not close the broader multi-product or OHOS acceptance goal.

Loaded `.agents/skills/trellis-start/SKILL.md`, `.trellis/workflow.md`, frontend/backend/guides indexes, and relevant SQL specs. Research-role isolation takes precedence over the start skill's general lifecycle commands: the supplied active task was used; no other session's active task was resolved, and implement/check manifests were not read.

### Files found and current code patterns

| File and location | Current behavior and implication |
| --- | --- |
| `pubspec.yaml:14` | Product depends on `../qfli_studio_core`; core source remains C coordinator-owned. |
| `lib/main.dart:25` | `sqlProfile` registers `SqlProgramRunner`, `SqlTerminalCommands.execute`, `buildSqlToolsTab`, offline mode, and SQL extensions. `runtimeStatus` remains `unavailable`; do not promote it from source inspection or host tests. |
| `lib/sql_tools_tab.dart:12` | Existing product-owned Tools body, with a natural-height ListView, retained scroll key, terminal callback, and every shared `commonTools` entry. This is the correct edit boundary. |
| `lib/sql_tools_tab.dart:42` | Still renders a generic “专用” group and one SQL entry that pushes `ContentToolsPage`. It violates the requested direct presentation of language features. |
| `lib/sql_home_shell.dart:203` | Five retained destinations; Tools hosts shared `FunctionsTab`. Keep this shell and its single toolbar. |
| `../qfli_studio_core/lib/pages/quick_tools_page.dart:32` | `FunctionsTab` prefers explicit/product `toolsTabBuilder` and embeds its body within the existing Scaffold/AppBar. No shared-core navigation edit is needed. |
| `../qfli_studio_core/lib/pages/quick_tools_page.dart:95` | `ContentToolsPage` routes SQL to shared `SqlToolPage`; `_projectPath` picks the first non-cloud project rather than the user's explicit SQL context. |
| `../qfli_studio_core/lib/pages/content_tools_pages.dart:323` | Shared `SqlToolPage` is a text area plus run button. It is a secondary page, not a direct useful tools collection. |
| `../qfli_studio_core/lib/services/structured_content_service.dart:60` | `SqlQueryService.execute(source, projectPath)` invokes fixed `qfli_sql/native` / `execute` against SQLite `:memory:` or `<project>/.qfli/data.sqlite`. It bypasses the product's preferred MySQL/SQLite execution selection and should not power new SQL tools. |
| `lib/sql_engine_preference.dart:20` | Offline guards convert stale cloud selection to local and refuse saving cloud. Reuse these boundaries; never add network adapters to Tools. |
| `lib/sql_workbench_page.dart:116` | Repository selection already maps unsupported FFI SQLite platforms to local MySQL. Tool labels must describe the actual selected local engine, especially OHOS. |
| `lib/sql_workspace_repository.dart:72` | Existing repository boundary; `listDatabases`, `listTables`, `tableColumns`, `runQuery`, and `runScript` are reusable. |
| `lib/sql_workspace_repository.dart:348` | `runQuery(databaseName, source)` is a structured **executing** query; `runScript` delegates to supplied `SqlScriptDatabase` or preserves custom `runQuery` fallback. It is not a parser API. |
| `lib/mysql_workspace_repository.dart:48` | `openLocal()` opens the app-private runtime with `NativeMySqlDatabase`. `supportsSchemaTools` / `supportsSqlExport` are true. |
| `lib/mysql_workspace_repository.dart:131` | Columns come from `information_schema`, preserving generated/auto-increment/real primary-key metadata. |
| `lib/mysql_workspace_repository.dart:333` | `tableIndexes(database, table)` uses `information_schema.STATISTICS`, ordered by `SEQ_IN_INDEX`; existing `createIndex`/`deleteIndex` handle validated names and current metadata. |
| `lib/sql_workspace_repository.dart:88` | SQLite currently advertises neither schema-tools nor export capabilities, and `tableIndexes`, index creation/deletion and schema-edit methods throw. Do not display an enabled action that calls these stubs. Read-only `tableColumns` still works. |
| `lib/sql_database.dart:21` | `SqlQueryResult` preserves availability, engine exit/error code, SQLSTATE, error text, columns, nullable string cells, affected rows, truncation, and binary column metadata. No source offset is present. |
| `lib/sql_database.dart:128` | `SqlScriptResult` preserves summary plus ordered statement results and failure after partial success. |
| `lib/sql_workbench_page.dart:748` | `_executeScript` retains the SQL result even if independent query-history persistence fails; then refreshes real metadata because earlier statements may have committed. Reuse this behavior. |
| `lib/sql_workbench_page.dart:2139` | Workbench displays ordered results, affected rows and truncation; its result rendering is private today. Extract a small product-owned result widget if both surfaces need it; do not duplicate a second engine. |
| `lib/sql_query_library.dart:64` | `SqlQueryLibrary.openDefault`, `history`, `saved`, `recordExecution`, `saveQuery`, and deletion/clear APIs; history capped at 100 and saved independently of engine. |
| `lib/sql_document_service.dart:8` | Existing UTF-8/picker/URI read/write adapter with a 1 MiB cap; reuse for local SQL import/export rather than network upload. |
| `lib/sql_runner.dart:27` | Project execution identity is `<project>/.qfli/data.sqlite`; MySQL uses the validated `.qfli/mysql.json` schema marker. These differ from the workbench's app-level database list. Context must be explicit. |
| `lib/sql_runner.dart:131` | `scriptProgramResult` provides real ordered stdout and stderr, including truncation; it currently does not format SQLSTATE explicitly. |
| `lib/sql_runner.dart:288` | `SqlProgramRunner` reads the saved entry file; it is a run API, not an unsaved analysis API. |
| `lib/sql_runner.dart:342` | `SqlTerminalCommands` already supplies local `sql file.sql`, `sql -e`, help, sandbox checks, project discovery and correct failure exits to both terminal surfaces. Keep one delegate. |

### Useful tools directly inside the existing Tools tab

Use stateful, natural-height product sections inside `SqlToolsBody`, with retained controllers. Each SQL tool's actual fields and action buttons should be present on the tab; do not replace the old generic landing card with several cards that still all open another SQL landing page. Existing common-tool routes and full-screen terminal callback can remain.

| Visible SQL section | Concrete behavior | Reuse / bounded addition |
| --- | --- | --- |
| SQL worksheet | Explicit local engine/database context, SQL text, Run, ordered result tables and errors. Serialize commands and disable context/mutation controls while busy. | `SqlWorkspaceRepository.runScript`, `SqlScriptResult`, extracted result view. Use repository factories for tests. |
| Query plan | Explain one statement, show real returned plan columns/rows; retain engine name and original source. | `runQuery` with SQLite `EXPLAIN QUERY PLAN` or MySQL `EXPLAIN`. No current dedicated explain API. Restrict supported input and report unsupported forms; never silently run `EXPLAIN ANALYZE`. |
| Table structure | Local database/table selectors, column name/type/nullability/key/generated flags, Refresh. | `listDatabases`, `listTables`, `tableColumns`. Does not require a successful data-grid load. |
| Index inspector and builder | Actual ordered index columns/uniqueness/primary status; choose existing columns and preview quoted CREATE INDEX SQL. Execute an index change only after an explicit action. | MySQL `tableIndexes`, `createIndex`, `deleteIndex`; add tested SQLite readers/create/delete support if offering the same action there. A mere disabled SQLite stub is not completion of that capability. |
| SQL text analysis | Exact unterminated literal/comment, mismatched delimiters and source locations, with precise limits advertised. | New pure product scanner shared with analyzer. It is lexical analysis, not a full MySQL grammar validator. |
| SQL text formatting | Format only tokens known to be SQL keywords/whitespace, preserving literals, quoted identifiers and comments; return original text for unsupported syntax. | No SQL-specific formatter exists. Shared `CodeFormatter.format` only cleans whitespace for `.sql`; add a product service, not a generic core formatter patch. |
| Literal / identifier helper | NULL versus empty string, dialect-specific identifier quoting and quote escaping; show parameter placeholders as the preferred execution representation. | Reuse validated repository quoting for operations. Do not splice helper output into bound grid values. Test apostrophes, backticks, double quotes and Unicode. |
| Transaction script helper | Produce explicit BEGIN/START TRANSACTION, DML, COMMIT or ROLLBACK **within one script**; user reviews/runs the complete script. | Current `runScript` preserves a single connection during a script. Do not describe DDL wrapping as rollback-safe on MySQL. |
| Saved queries / execution history | Load selected SQL into the same text field, save query, retain success/error and timestamp, clear explicitly. | `SqlQueryLibrary`; persistence failure must not erase valid results. |
| Result copy / CSV export | Copy/export only captured complete rows; keep NULL distinct in display, quote CSV fields correctly, and visibly state truncation. | Captured `SqlQueryResult` plus local picker/write adapter. Never imply a truncated result is a full table backup. |

Avoid selecting the first project implicitly as the shared tool currently does. Either target the app database collection explicitly or expose a clear project choice; a project database is not the same identity as an arbitrary workbench database. If Tools can change the global engine, app-local state must notify/reload the retained workbench; otherwise it can retain a repository for the previous engine. A bounded app-local context/controller is preferable to another global shared-core field.

### Query plans and transactions: supported versus absent

`native/src/qfli_mysql_client.cpp:101` allocates an RAII connection, and `:350` creates a new connection for each `execute_script`; the connection closer calls `mysql_close` at `:21`. `lib/sqlite_ffi.dart:267` and `:280` close the SQLite connection after individual queries/scripts. Therefore:

- A script's BEGIN/START TRANSACTION through COMMIT/ROLLBACK is real and is already tested.
- Standalone “Begin”, “Commit” and “Rollback” buttons across separate repository calls would address different connections and are misleading. A real manual transaction console would require an explicit long-lived session backend and lifecycle/cancellation contract; no such API exists today.
- MySQL can implicitly commit DDL; do not promise arbitrary-script rollback or use wrapping as a diagnostic safety mechanism.
- Plain EXPLAIN is the useful offline analogue of DataGrip's plan viewer. Raw plan output is an acceptable first renderer. SQLite explicitly warns that EQP display format may change; avoid a brittle parser of the free-text `detail` column.

### Shared unsaved-buffer diagnostic contract: live update during audit

Read-only global `trellis channel messages qfli-core-release-sync --scope global --raw` confirms C as sole common-core owner in sequences 77–81. Sequence 82 acknowledges a frozen CodeAnalyzer contract. The initially absent public module **was created during this audit** and was re-read before this report was written:

- `../qfli_studio_core/lib/services/code_analysis.dart:3`: `CodeAnalyzer.analyze(CodeAnalysisRequest)`.
- `CodeDocumentSnapshot(path, text, revision)` contains exact unsaved UTF-16 text, including CRLF.
- `CodeAnalysisRequest(projectPath, activeFilePath, language, revision, documents)` has an immutable documents list.
- `CodeDiagnostic(filePath, startOffset, endOffset, message, severity, source, code)` uses zero-based UTF-16 half-open offsets. Severity is error/warning/information/hint.
- `CodeAnalysisResult(diagnostics, unavailableReason)` distinguishes actual empty success from unavailable analysis.
- `../qfli_studio_core/lib/services/studio_profile.dart:99` accepts `codeAnalyzer`; `:135` stores it and the module is re-exported.
- Frozen design: `../qfli_studio_core/.trellis/tasks/10-22-offline-editor-analysis/design.md`. Core owns bounds/debounce, revision/generation invalidation, wave spans preserving syntax colors, Problems navigation and lifetime handling. Hook presence is not evidence those UI behaviors have passed.
- `../qfli_dart/lib/dart_code_analyzer.dart` is a read-only consumption example. It filters owner-root snapshots, works on exact unsaved text and maps offsets without executing source.

Add SQL-only `lib/sql_code_analyzer.dart`, register `const SqlCodeAnalyzer()` in SQL's profile, and consume this API; do not edit core. `EditorFileTool.run(file, projectPath)` is unsuitable: `../qfli_studio_core/lib/editor/editor_page.dart:874` saves the current file before invoking it. `OpenFile` already tracks `controller.text`, `revision`, dirty state and owner root, so the new snapshot API is the correct boundary.

### Safe SQL diagnostics and explicit limitations

1. Analyze captured `.sql` documents inside `request.projectPath`; require a matching active snapshot. Never reread the active saved file in place of `document.text`, never create `.qfli/mysql.json`, and never call `SqlProgramRunner` or `NativeMySqlEngine.execute` merely to validate text.
2. A pure, bounded token scanner can safely and precisely report unterminated quoted strings/identifiers, block comments and mismatched parentheses, and locate obvious malformed statement tokens. Preserve SQL dialect rules: MySQL `--` comments require following whitespace, SQL strings can double quotes, backslash escapes depend on SQL mode, and semicolons inside strings/comments/routines do not define generic executable boundaries. Do not call this a full grammar/type/schema checker.
3. Full native syntax checking is an additional backend deliverable. Existing `SqlDatabase.query` **executes** after preparation. Current FFI accepts only `query`, `execute`, `executeScript` (`lib/sqlite_ffi.dart:45–64`); `NativeMySqlDatabase` exposes only query/script. There is no validate/explain-offset/debug API to call today.
4. For MySQL, a new bounded `validate` operation can use `mysql_stmt_init` / `mysql_stmt_prepare` / `mysql_stmt_close` without `mysql_stmt_execute`. Existing query code at `native/src/qfli_mysql_client.cpp:215` is the concrete preparation pattern, followed by actual execute at `:234`. Treat “unsupported prepared statement”, missing schema/table or backend unavailable separately from grammar failure. Official C API does not provide a universal precise source offset; preserve message/SQLSTATE and use only reliably mapped ranges, such as a whole failing statement. Do not invent token positions by globally searching a quoted error substring. Compound routines/multi-statement scripts need a documented coverage strategy; naïve `split(';')` is forbidden.
5. For SQLite, bundled header is 3.50.0 (`native/third_party/sqlite/sqlite3.h:149`). `sqlite3_error_offset` exists in the bundled header, but the Dart wrapper does not bind it. It returns UTF-8 **byte** offsets; convert the UTF-8 prefix to Dart UTF-16 code-unit length before emitting a CodeDiagnostic. Missing-table errors in an empty schema do not prove invalid syntax.
6. Critical safety fact: SQLite documents that some PRAGMAs act during `sqlite3_prepare`, and EXPLAIN does not suppress those effects. Preparing arbitrary user SQL against a writable user database is therefore not a safe universal analysis strategy. Use an isolated/read-only validation connection with a defined supported statement set, prohibit side-effecting PRAGMA/ATTACH paths, and never step the user statement. A throwaway database avoids user-data changes but lacks live schema; surface that limitation rather than reporting a false clean result.
7. A lexer-only result is useful incremental R5 progress but does not satisfy broad engine grammar coverage. Keep full parser/native validation scope open until the selected dialect, multi-statement behavior and non-mutating proof are implemented and tested. Empty success must mean the advertised checker actually ran; unsupported forms or absent engines need `unavailableReason` or an accurately scoped information diagnostic.

### Output, logging, debugger and ports

- SQL run stdout/stderr and engine failures already flow through `ProgramRunResult` / the shared terminal. Preserve exit 127 for a backend that never ran, actual engine codes for SQL failures, prior successful result sets, SQLSTATE, affected rows and truncation. Add structured SQL execution summaries instead of parsing terminal text back into a model.
- A bounded local execution log can record engine, target database, timing, outcome, engine code/SQLSTATE and result counts. Keep original errors and independent log-storage failures; no network telemetry.
- `lib/local_mysql_runtime.dart:233` already places the private server error log at `<dataDirectory>/mysqld.log`; `:263` reads it on readiness failure. There is no general streaming log-reader API. If adding a viewer, implement bounded tail reads of the app-owned path, not arbitrary file browsing or unbounded `readAsString` of a growing log. OHOS log plumbing must be inspected/implemented independently rather than assuming a desktop path.
- No breakpoint, pause/continue, step, stack/variables, debug protocol, or SQL debugger backend was found in product/native sources. Native `sqlite3_step` is database execution, not a source debugger. Do not add decorative debug controls or claim DataGrip-style stored-procedure debugging exists.
- The MySQL client uses a private pipe/socket and disables TCP fallback. A VS Code-style forwarded Ports UI has no backend to manage here and would conflict with the offline-only scope. Retain useful Problems/output/terminal behavior without fabricating this capability.

### Narrow implementation ownership and execution order

Recommended SQL-owned batch boundaries, coordinated by the SQL main session:

1. **Text tooling and adapter:** new `lib/sql_tools_service.dart` (tokenizer, text transformations, literal/identifier helpers, bounded diagnostics model), `lib/sql_code_analyzer.dart`, focused unit tests, and the small `lib/main.dart` analyzer registration. No shared-core edits. Exact native grammar checking is a separate explicit sub-batch, not an implied property of the lexer.
2. **Direct Tools UI:** `lib/sql_tools_tab.dart`, optional small SQL-owned controller/result widget, `test/sql_home_shell_test.dart`, and new focused tools widget tests. Reuse app repositories and existing common routes. Do not push `ContentToolsPage` for SQL-specific operations or nest another Scaffold/AppBar.
3. **Native validation / missing SQLite capabilities:** explicitly allocate `lib/sqlite_ffi.dart`, native SQL adapters/bridge/client files, `lib/sql_database.dart` if needed, base-repository index APIs and native tests to one owner. This batch has stronger platform regression requirements. Do not let two workers concurrently change runner/database/core contracts.
4. **App-local integration review:** SQL main session confirms canonical engine/database identity, retained-tab refresh, offline refusal, history/result lifetime and OHOS acceptance. C coordinator independently owns core Problems/waves/highlighting. At initial inspection SQL was absent from core `HighlightThemes._languages`/extension mapping; the C-owned highlighting change must be consumed and verified, not patched concurrently by SQL.

### Meaningful regression validation plan

No tests were executed as part of this report. These are validation requirements, not results:

- Existing UI coverage: `test/sql_home_shell_test.dart:300` verifies all shared offline tools remain reachable and return to destination 2; existing width/2x-text tests cover 390/900/1280. Update its old single “SQL 查询” expectation to prove the actual SQL-specific controls are in the tab, no generic “专用”/“SQL专用功能” landing remains, no route is pushed by those inline actions, and there is only one AppBar. Preserve terminal/common routes and retained text/results across distant page switches.
- Tools unit/widget tests: inject a repository and query library; assert the exact selected engine/database and source reach `runScript`/`runQuery`; verify busy serialization, visible engine error/SQLSTATE, multi-results, partial failure, unavailable 127, output cap, and independent history-storage failure. A mock success alone cannot prove native execution.
- Lexical tests: CRLF, emoji/surrogate pairs, Chinese source, multiline comments, escaped/doubled quotes, backtick/double-quoted identifiers, MySQL comment rules, nested parentheses, empty text, source bounds, and semicolons inside literals/routine bodies. Transformations must preserve literal/comment content byte-for-byte; compare meaningful query results before/after supported formatting on a real engine.
- Adapter tests: use the new exact snapshot API with saved disk text deliberately different from unsaved text; expect ranges from the unsaved buffer, no source/marker/database writes, foreign-root rejection, all open owned SQL buffers, no network/runner calls, and honest unavailable reasons. Core's tests must separately prove debounce, stale response rejection, tab/root changes, close/dispose, wave spans and Problems navigation; SQL profile integration should exercise a real SQL diagnostic once the shared UI is ready.
- Query-plan tests: with isolated real databases, obtain SQLite/MySQL plan results for a SELECT and prove table contents remain unchanged; show a real index access plan where stable, without hardcoding the entire engine-specific text. Reject malformed/multiple/unsupported statements and ANALYZE execution forms. A formatter/scanner acceptance test cannot substitute for this.
- Native validate tests: prove INSERT/UPDATE/DELETE/DDL/PRAGMA/ATTACH input cannot alter the user's DB or file system during analysis; check unsupported forms distinctly; test SQLite UTF-8-to-UTF-16 conversion and MySQL missing-schema versus syntax errors. Avoid a false safety test that only passes because the engine is unavailable.
- Existing real execution suites to retain: `test/sqlite_ffi_test.dart:46` shared editor/script/grid persistence, `:151` one-connection transaction and literal boundaries, limits and malformed SQL; `test/sql_terminal_commands_test.dart:143` real terminal-to-editor persistence; `test/sql_runner_test.dart` native-channel failures; `test/sql_database_test.dart` strict response validation; `test/mysql_workspace_repository_test.dart` primary keys/metadata/parameters/truncation; `native/tests/mysql_client_test.cpp` real native C API; `native/tests/mysql_workspace_test.dart` real Oracle repository.
- OHOS acceptance: extend/run the current application path, not host-only SQLite or a mock. `integration_test/mysql_ohos_probe.dart:270` already checks transactions/literals and `:495` covers rollback/commit/partial failure; add direct-tools/plan/diagnostic cases with ownership-safe fixtures. Existing probe source is not fresh runtime evidence. Record current HAP/native hashes, exact device/toolchain, per-case result and actual normal-app behavior; compilation/packaging is not a device pass.
- Required package gate after implementation: compatible project SDK `flutter analyze --no-pub lib test integration_test` and `flutter test --no-pub`; native/runtime targets separately. Explicitly record unavailable-engine skips, including absent OHOS device, instead of converting them to passes. Source inspection here did not establish current device availability.

### External references and applicable ideas

Only official primary sources were consulted. URLs are included for durable handoff; checked 2026-10-22. Product implementation should not depend on opening any of them at runtime.

| Official reference | Relevant fact / offline adaptation |
| --- | --- |
| JetBrains DataGrip, Explain Plan: https://www.jetbrains.com/help/datagrip/query-execution-plan.html | Plan output is a useful SQL-specific tool; keep plain EXPLAIN separate from executing analysis and show the actual local engine output. |
| JetBrains DataGrip 2026.2, SQL inspections: https://www.jetbrains.com/help/datagrip/code-inspection.html | Syntax/semantic inspections provide editor feedback, locations and Problems-like navigation. Copy the interaction principle; do not claim unavailable schema/type inference. |
| JetBrains DataGrip 2026.2, transaction control: https://www.jetbrains.com/help/datagrip/configuring-database-connections.html#transaction-mode | Manual transaction actions apply to an actual session; current per-call connections cannot emulate them. The initially tried `commit-and-rollback.html` URL returned 404; this is the verified official replacement. |
| VS Code, programmatic language features: https://code.visualstudio.com/api/language-extensions/programmatic-language-features | Diagnostics are distinct from execution; editor Problems and underlines use a document diagnostic collection. The new typed core snapshot adapter is the analogous local boundary. |
| SQLite, EXPLAIN QUERY PLAN: https://www.sqlite.org/eqp.html | Plan display is for interactive use and the output format may change. Render current rows rather than promise a stable textual parser. |
| SQLite, preparing statements: https://www.sqlite.org/c3ref/prepare.html | Preparation is distinct from stepping; tail identifies remaining input. This alone does not make arbitrary analysis side-effect-free. |
| SQLite, PRAGMA: https://www.sqlite.org/pragma.html | Some PRAGMAs act during prepare; EXPLAIN does not prevent prepare-time effects. The validation connection must be isolated and constrained. |
| SQLite, error offsets: https://www.sqlite.org/c3ref/errcode.html | `sqlite3_error_offset` is a UTF-8 byte offset, or -1 when unavailable. Convert precisely to the shared UTF-16 contract. |
| Oracle MySQL 8.4 C API, prepare: https://dev.mysql.com/doc/c-api/8.4/en/mysql-stmt-prepare.html | Native prepare-only checking is distinct from `mysql_stmt_execute`; prepared-statement support has limits. A new product backend operation is required. |
| Oracle MySQL 8.4, EXPLAIN: https://dev.mysql.com/doc/refman/8.4/en/explain.html | Plain EXPLAIN describes an execution plan; ANALYZE can execute the statement. Keep different behavior explicit. |
| Oracle MySQL 8.4, implicit commits: https://dev.mysql.com/doc/refman/8.4/en/implicit-commit.html | Many DDL statements commit implicitly and are not generally undone by a transaction wrapper. |

Sources are ideas/contracts, not proof that this app implements those features. The bundled SQLite version is 3.50.0; the native test README records Oracle host verification at 8.0.46 and target port 8.4.6. Verify the actually running engine's version before relying on version-specific syntax.

### Related specs

- `.trellis/spec/frontend/sql-workbench.md`: five-page shell, app-local tools/body, retained state, engine/offline/context and result/history contracts.
- `.trellis/spec/frontend/sql-terminal-offline.md`: one local delegate, project database identity, cloud refusal and correct terminal failures.
- `.trellis/spec/frontend/index.md`: full analysis/tests, responsive/large-text review, shared-core ownership, separate native/OHOS gates.
- `.trellis/spec/backend/sql-workspace.md`: stable row identity, bound values and truncation handling.
- `.trellis/spec/backend/sqlite-native-runtime.md`: FFI/channel split, actual bundled engine, statement boundaries, limits and honest platform evidence.
- `.trellis/spec/backend/mysql-workspace.md`: actual metadata, SQLSTATE, binary/numeric precision, one-connection scripts, native limits. Its phone-hosting status text is older than the more detailed OHOS spec; read current implementation and `mysql-ohos-runtime.md` before repeating the older platform conclusion.
- `.trellis/spec/backend/mysql-ohos-runtime.md`: platform-specific current host and acceptance limits; not replaced by desktop results.
- `.trellis/spec/backend/sql-query-library.md`: independent persistence failures must preserve successful SQL output.
- `.trellis/spec/guides/cross-layer-thinking-guide.md` and `code-reuse-thinking-guide.md`: follow selection/source/result/availability end-to-end; search before duplicating existing boundaries.

## Caveats / Not Found

- No existing native validate operation, precise SQL source-location result, persistent manual transaction session, SQL debugger, or managed-port backend was found. These cannot be represented as already-supported controls.
- Core changed concurrently: `code_analysis.dart` and `StudioProfile.codeAnalyzer` appeared during the audit. Their current existence was verified; shared scheduler/Problems/wavy rendering and SQL highlighting still require integration evidence from the core owner.
- Pure lexical diagnostics alone do not meet all SQL grammar expectations. Native preparation is not automatically safe or complete, especially SQLite PRAGMAs and MySQL compound/unsupported statements. Keep those explicit deliverables open.
- No new tests, analysis, native runs, HAP builds or device sessions were run. Existing test/probe files identify useful validation coverage but do not establish fresh passes.
- No sibling code was modified. Read-only references to Dart/C/core establish agreed contracts and ownership, not authority to edit those workspaces.
