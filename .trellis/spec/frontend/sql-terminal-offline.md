# SQL Terminal and Offline Contracts

## 1. Scope / Trigger

Read when editing the SQL runner, terminal command hook, engine preference or
offline database entry points. The standalone and editor terminals use the same
shared backend and product-owned delegate.

## 2. Signatures

- `sqlProfile.terminalCommandDelegate = SqlTerminalCommands.execute`.
- `execute(SandboxShellBackend backend, String command, {SqlProgramEngine engine = const PreferredSqlEngine()}) -> Future<bool>`.
- Commands: `sql <file.sql>`, `sql -e "SQL"`, `sql --execute "SQL"`, `sql --help`.
- `SqlEnginePreference.cloudEnabled` reads `StudioProfile.current.offlineOnly`.

## 3. Contracts

Unknown commands return false so shared file commands keep working. SQL uses
the selected native engine, the same request/result adapter as the editor, and
the nearest `.qfli/project.json` ancestor for a nested script's project database.
Paths must stay within the terminal sandbox, including resolved symlinks.
The hook reports engine stderr/exit status and unavailable-engine status honestly.
It does not claim a complete interactive mysql/sqlite3 client or a SQL cancellation
API; Ctrl+C cannot promise rollback of an already submitted native transaction.

An offline product maps a persisted cloud preference to the local `sqlite`
selection without opening a cloud connection. `NativeLocalSqlEngine` always
uses SQLite: FFI on supported targets and the SQLite native channel on OHOS.
The absence of FFI never changes the selected engine to Oracle.
Saving cloud is refused. `openCloud` checks policy before metadata
requests; both cloud query/script methods check policy before token/API access.
Local SQLite and Oracle remain independently selected; unavailable selected
native engines must not silently connect to another service.

OHOS `EntryAbility` refuses `openAgreement`, `openUrl` and Huawei `login`
with exactly one `OFFLINE_ONLY` error before reading arguments. Keep the account
channel registered for callers that still carry a persisted login action, but
do not import AccountKit or dispatch browser/router/authentication operations.
The module requests only `READ_PASTEBOARD`, with no `client_id` metadata.
Oracle uses its private Unix socket and `skip-networking`; it does not require
the INTERNET permission. Preserve local picker/share, native registrations,
runtime disposal and startup behavior when applying this policy.

## 4. Validation & Error Matrix

| Input/state | Observable behavior |
| --- | --- |
| Non-SQL command | Delegate returns false |
| Empty arguments/help | SQL-specific help, success |
| Unsupported flags, pipe/redirection/command chain | Usage error, no execution |
| Sandbox traversal/resolved symlink outside root | Refused, no execution |
| Missing/non-UTF8/empty source | Diagnostic with failure status |
| Offline persisted cloud setting | Local effective engine; no API request |
| Offline direct cloud repository/query/script call | Refused before token or API |

## 5. Good / Base / Bad Cases

Good: terminal runs a nested project SQL file and the editor reads its committed
SQLite data. Base: `sql -e "SELECT 1"` returns the actual native result. Bad:
passing an engine error as success or treating a stale cloud token as permission
to bypass offline policy.

## 6. Tests Required

`test/sql_terminal_commands_test.dart` verifies parser/path/error handling,
profile registration, project discovery and real SQLite terminal-to-editor
persistence. `test/sql_offline_policy_test.dart` verifies stale engine policy and
API/token refusal. Shared terminal delegate/editor-pane/sandbox tests verify the
same hook at both terminal surfaces; record the core revision used.

`node tool/test_sql_offline_platform.cjs` transpiles and executes the actual
EntryAbility with explicit SDK/native-interface doubles. It checks refused URI
schemes/missing values, a throwing argument accessor, exact-once replies and
preserved local dispatch/lifecycle. Default checks must work without unrelated
startup WIP; `--workspace-startup` additionally checks its progress contract.
This host gate does not establish ArkTS typing, actual picker/share IO, normal
startup networking or installed execution. Rebuild and inspect the HAP after
native changes; an earlier package containing INTERNET is historical evidence.

## 7. Wrong vs Correct

Wrong: implementing a second terminal engine, exposing unsupported mysql flags,
or guarding only the visible engine menu. Correct: inject one SQL delegate into
the shared backend and guard both selection and execution boundaries locally.
