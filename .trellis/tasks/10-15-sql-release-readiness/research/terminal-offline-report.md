# SQL terminal and offline audit — 2026-10-15

## Workspace and ownership

All commands ran with `D:/MyNewProjects/qfli_sql` as cwd. This worker changed only
the SQL repository; `../qfli_studio_core` was inspected read-only. The coordinator
owns commits. Existing cloud/preference/runner work was preserved: the baseline
already had modified `sql_runner.dart` and `mysql_workspace_repository.dart`, and
untracked `cloud_mysql_database.dart` / `sql_engine_preference.dart`.

Shared-core HEAD moved during the audit from
`ad17f35ac728e19670de1df305bc3e55c3b5172c` to
`8731df838432d24ba9b5f2b73689d26b97693ba7`. Other product owners are concurrently
changing that repository. The coordinator reports shared offline editor gating
is coordinated through `qfli-core-release-sync`; final integration must record
the exact shared-core commit/dirty state used by release builds.

## Implemented corrections

1. SQL's `StudioProfile.runner` was wired, but its terminal command delegate was
   absent. Both mobile terminal surfaces therefore rejected SQL commands.
   `lib/sql_runner.dart:340` now defines `SqlTerminalCommands.execute`, registered
   by the UI owner at `lib/main.dart:36`. Supported commands are
   `sql <file.sql>`, `sql -e "SQL"`, `sql --execute "SQL"`, and `sql -h/--help`.
   Both direct SQL and scripts use `PreferredSqlEngine`, preserving the same
   persisted engine selection as the editor/workbench. Non-SQL commands remain
   owned by the shared shell. Unquoted shell compounds are refused as one
   command, never partially executed. File reads use the sandbox resolver plus a
   canonical-path check. Walking to the nearest `.qfli/project.json` ensures
   scripts under `src/` use the project database instead of creating a second
   database inside `src/`. Engine-unavailable results use exit 127, and actual SQL
   errors preserve preceding output and nonzero exit status.
2. `lib/sql_engine_preference.dart:22` centralizes effective cloud availability
   from `StudioProfile.offlineOnly`. A legacy `sql_engine.json` with `cloud`
   loads as the local default without changing the user's file. Saving a cloud
   selection while offline throws before any write. Explicit local MySQL remains
   local MySQL; the existing native platform default is preserved.
3. `CloudMySqlDatabase.query/executeScript`
   (`lib/cloud_mysql_database.dart:23,48`) refuse offline calls before reading
   credentials or invoking APIs. `MySqlWorkspaceRepository.openCloud`
   (`lib/mysql_workspace_repository.dart:31`) also checks before its initial
   account-info request, which otherwise bypasses the database adapter.

## Terminal parity and method completeness

| Capability | Standalone terminal | Embedded editor terminal | Evidence |
| --- | --- | --- | --- |
| Backend/toolchain hook | `TerminaxTerminalPage._createSession` → `TerminalManager.create` → `createSandboxShell` | `TerminalPaneState._backendFor` → `createSandboxShell` | Both read `StudioProfile.terminalCommandDelegate`; registration regression passed |
| Initial directory | App storage root | Current project; sandbox root is app storage when available | Intentional surface-specific directory; nested-script parity regression passed |
| Local SQL file/direct execution | `SqlTerminalCommands` | Same delegate | Actual SQLite script created a table/row, then the editor runner read the same `.qfli/data.sqlite`; no `src/.qfli` database |
| Common file commands | Real sandbox file I/O | Same implementation | Shared sandbox and editor-pane tests passed, including real `ls`, directory/error handling, clear and cwd retention |
| Sessions, input and history | Shared terminal manager/session model; independent editors | Retained pane sessions | Standalone delegate test and editor-pane tests passed for new sessions, keyboard Return, focus, tabs, history, source-session output, scroll retention and bounded transcript |
| stdout/stderr/exit | `runStreams` and session output | Same backend output contract | Successful SQL, partial output/SQL errors, unavailable engine and invalid UTF-8 covered |
| Process-backed interrupt | Shared shell forwards cancellation | Stop/interrupt forwards cancellation | Shared pane/sandbox regression suites passed |
| Already submitted native SQL interrupt | No cancellation handle exposed | Same native API limitation | Not claimed as supported; native SQL can finish/commit after Ctrl+C |
| Full `mysql`/`sqlite3` interactive CLI | Not bundled | Not bundled | Product exposes the documented local `sql` command; full external-client flags, stdin sessions and host connections are not emulated |
| Shell pipes/redirection/chaining on mobile | Unsupported | Unsupported | Shared shell reports explicit limitations; SQL delegate rejects compound input |

The method paths used by SQL are implemented. `NativeSqliteEngine` calls
`execute`; the SQLite FFI dispatcher implements `execute`, `query`, and
`executeScript`. Native MySQL adapters call `query` and `executeScript`; OHOS
`QfliMysqlNative.ets:12,18` forwards both to `QfliMysqlRuntime` and the NAPI exports
(`qfli_mysql_napi.cpp:513,514`). The OHOS channel's default `notImplemented()` is
for unknown method names, not a missing production SQL method. The OHOS SQLite
channel deliberately has only `execute/query`; production OHOS selects local
MySQL, and unsupported SQLite is omitted from its engine menu. Android's native
adapter uses the local runtime/FFI path. Compilation/device acceptance belongs
to the platform worker, not this source/host test audit.

## Offline surfaces and coordinated core findings

`lib/main.dart` sets `isOffline: true`, which also sets `offlineOnly: true`.
The shared editor already disables cloud synchronization, AI/online-terminal
entries and cloud SQL fallback when offline. Its `TerminalPane` receives
`onlineEnabled: false`; `showOnline`, `runOnlineProject`, and `runCloudSql` all
refuse requests. `AppBootstrap`/`AuthStore.load` restore only local data and do
not refresh accounts over the network. Shared FunctionsTab/ToolsGrid expose the
local terminal and local tools; their URL tool is encoding/decoding, not HTTP.
The SQL workbench engine picker includes only local engines.

An initial shared-core defect exposed the editor Git menu, then GitPage's remote,
push and pull buttons, regardless of the offline profile. The coordinator
contacted the shared-core owners. The live shared editor now gates both the menu
items and dispatch handlers for Git/cloud-pull on `offlineOnly != true`
(`editor_page.dart` around 1432 and 1595). Searching both SQL and shared sources
finds only this editor route to `GitPage`; therefore no Git remote page remains
reachable through the normal SQL UI after that coordinated gate. There is no
existing `EditorPage` constructor option or profile menu override that could
have hidden it locally.

Residual shared API behavior is separate from reachable mobile release UI:

- Direct construction of public `GitPage` or calls to `GitService` still expose
  remote functionality. They are unreachable from SQL's normal UI after gating;
  adding service-level guards would be shared-core defense in depth.
- On desktop, `createSandboxShell` forwards unrecognized commands to the real
  host shell. That permits manually entered host commands such as Git/curl;
  mobile has no such fallback. No strict desktop network isolation is claimed.
- Shared `SandboxShellBackend.helpText` and unsupported-command copy still name
  Java even for other language products. `sql --help` documents SQL correctly,
  but the profile delegate cannot override the shared `help` builtin. Generic
  language-toolchain wording is a shared copy follow-up.

## Executed validation

`dart analyze lib/sql_runner.dart lib/sql_engine_preference.dart
lib/cloud_mysql_database.dart lib/mysql_workspace_repository.dart
test/sql_terminal_commands_test.dart test/sql_offline_policy_test.dart`
passed with **No issues found**. Saved log: `terminal-offline-analyze.log`.

The following command completed with **75 tests passed, no skips**:

```powershell
flutter test --no-pub test/sql_terminal_commands_test.dart test/sql_offline_policy_test.dart test/sql_runner_test.dart test/sqlite_ffi_test.dart ../qfli_studio_core/test/terminal_manager_delegate_test.dart ../qfli_studio_core/test/terminal_pane_test.dart ../qfli_studio_core/test/sandbox_terminal_test.dart --reporter expanded
```

Saved complete output: `terminal-offline-tests.log`. This ran from the SQL
workspace, using `D:/ProgramFiles/flutter_ohos/bin/flutter.bat`, and included the
actual `native/build/windows/qfli_sqlite.dll`; the native SQL test did not skip.
The new regressions also prove cloud query/script/account-info APIs and token
providers receive **zero calls** while offline, and that a stale cloud preference
remains local while explicit local selections persist successfully.

These are host/native/widget results. This worker did not install an app, mutate
user databases, claim MySQL device execution, or claim Android/OHOS build success.
The coordinator/platform worker owns those independent release checks.

## Delivery

Owned source/tests ready for coordinator-scoped staging:

- `lib/sql_runner.dart`
- `lib/sql_engine_preference.dart`
- `lib/cloud_mysql_database.dart`
- `lib/mysql_workspace_repository.dart`
- `test/sql_terminal_commands_test.dart`
- `test/sql_offline_policy_test.dart`

Also include this report and its two validation logs; coordinate the companion
`lib/main.dart` delegate registration with the UI owner's delivery. Suggested
conventional commit: `fix(sql): enable local terminal SQL and block offline cloud access`.
Review the preserved pre-existing cloud integration in those files before
committing whole files. This worker did not stage or commit anything.
