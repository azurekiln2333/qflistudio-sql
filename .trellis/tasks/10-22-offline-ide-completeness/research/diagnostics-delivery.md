# SQL diagnostics delivery — contracts for coordinator and tools worker

Owner: diagnostics worker (this brief's recipient).
Allocated files only: `lib/sql_syntax_validator.dart` (new),
`lib/sql_code_analyzer.dart` (new), `lib/sqlite_ffi.dart` (one isolated
prepare-only operation), `test/sql_syntax_validator_test.dart` (new),
`test/sql_code_analyzer_test.dart` (new).
No edits to `main.dart`, tools/content/core/native/acceptance. No git actions.

## 1. Reusable pure scanner (for tools worker p2)

`lib/sql_syntax_validator.dart` is pure Dart (no Flutter, no IO, no isolate) and
is the shared contract. Tools worker p2 should delete its duplicate
`SqlDialect` enum and `splitSqlStatements` and import this file instead.

```dart
enum SqlDialect { sqlite, mysql }

enum SqlTokenKind { whitespace, lineComment, blockComment, string,
  identifier, number, word, parameter, operator, punctuation }

class SqlToken { SqlTokenKind kind; int start, end; String text;
  bool get isTrivia; bool get isWord; String get keyword; /* uppercase */ }

class SqlStatement { int start, end; List<String> leadingKeywords;
  String get leading; }

enum SqlIssueSeverity { error, warning, information }
class SqlLexicalIssue { int start, end; String message, code; SqlIssueSeverity severity; }

class SqlLexicalAnalysis { List<SqlToken> tokens; List<SqlLexicalIssue> issues;
  List<SqlStatement> statements; bool truncated; }

abstract final class SqlSyntaxValidator {
  static const int maxScanUnits = 1024 * 1024;
  static const int maxIssues = 200;
  static SqlLexicalAnalysis analyze(String source,
      {SqlDialect dialect = SqlDialect.sqlite, int maxUnits = maxScanUnits});
  static List<SqlToken> tokenize(String source,
      {SqlDialect dialect = SqlDialect.sqlite});
  static List<SqlStatement> statements(List<SqlToken> tokens); // the splitter
}

abstract final class SqlPrepareGuard {
  static const Map<String, String> blockedKeywords;
  static String target(List<String> leadingKeywords);
  static String? blockedReason(SqlStatement statement);
}
```

Guarantees tools worker p2 can rely on:

- Offsets are zero-based, half-open **UTF-16 code units** into the exact text;
  CRLF counts as two units; emoji are two units. Verified in
  `test/sql_syntax_validator_test.dart`.
- `tokenize` is lossless: concatenating every `token.text` reproduces the input
  byte-for-byte (tested with Chinese, emoji, CRLF).
- `statements` is a real splitter, not `split(';')`: semicolons inside literals,
  comments and parentheses do not split, and a SQLite `CREATE TRIGGER … BEGIN …
  END;` body stays one statement (CASE…END handled). The `;` terminator is
  **excluded** from the range; leading/trailing trivia is excluded.
- Codes tools worker p2 may map to UI: `unterminated-string`,
  `unterminated-identifier`, `unterminated-block-comment`,
  `unmatched-open-paren`, `unmatched-close-paren`, `nul-character`,
  `scan-truncated`.
- Dialect is documented, not universal: the MySQL rules assume the common
  default SQL mode (`#` comment, `-- ` requires whitespace, `"` string literal,
  backslash escapes). A session may set `NO_BACKSLASH_ESCAPES`/`ANSI_QUOTES`; the
  scanner cannot read a live session's mode and must not be described as if it
  could.

Reuse note for the formatter: comment/literal tokens carry their exact original
text, so a formatter can re-emit them unchanged and only normalize
`whitespace`/`word` tokens.

## 2. Analyzer adapter (coordinator registers it)

`lib/sql_code_analyzer.dart`

```dart
class SqlCodeAnalyzer implements CodeAnalyzer {
  const SqlCodeAnalyzer({
    SqlSyntaxEngine engine = const SqlitePrepareSyntaxEngine(),
    int maxEngineUnits = 512 * 1024,
  });
}

abstract interface class SqlSyntaxEngine {
  Future<SqlEngineAnalysis> validate(String text);
}

class SqlitePrepareSyntaxEngine implements SqlSyntaxEngine {
  const SqlitePrepareSyntaxEngine({String? libraryPath, Duration? timeout});
  static const String method = 'validate';
}
```

Coordinator action (owned by root, not by me): add
`codeAnalyzer: const SqlCodeAnalyzer()` to `sqlProfile` in `lib/main.dart`.

Behavior contract:

- Only owned `.sql` snapshots inside `request.projectPath` are analyzed; foreign
  paths and non-SQL buffers are dropped. Requires an exact snapshot for
  `activeFilePath`, otherwise `unavailableReason`.
- Always uses `document.text` (unsaved). It never rereads the saved file, never
  saves, never calls a runner, never touches the workbench repository.
- Lexical analysis covers **every** owned open SQL buffer; the engine check runs
  on the **active** buffer only (bounded cost inside core's 12 s lane).
- Diagnostics are absolute paths with clamped ranges (core rejects others).
- Dialect: `.qfli/mysql.json` with a `schema` string, or the current
  `SqlEnginePreference == localMysql`, selects MySQL. A MySQL project is never
  checked with SQLite grammar.
- Honest states — `unavailableReason` is set (so core keeps `checked == false`
  and the Problems bar shows the reason) for:
  - MySQL: “MySQL 方言仅做本地词法检查，未连接 MySQL 服务端校验语法”
  - non-FFI platform (OHOS): native bridge missing
  - NUL text, oversize active text, backend exception, truncated scan
- Not-clean information diagnostics: `schema-gap` (aggregated count),
  `statement-skipped` (guarded statement), `engine-truncated` (>512 statements).

## 3. `sqlite_ffi.dart` addition + required native contract

New method on the existing entry point:
`SqliteFfi.invoke('validate', {'source': String}, libraryPath: …)`.

- Uses a fresh `:memory:` database; **never** opens a caller database. Supplying
  any other `databasePath` throws `ArgumentError` (tested).
- Calls only `sqlite3_prepare_v2` + `sqlite3_finalize`; `sqlite3_step` is never
  called (tested: user DB bytes and table contents unchanged after analyzing
  DROP/DELETE/UPDATE/INSERT/CREATE).
- New bindings: `sqlite3_errcode`, `sqlite3_libversion`, and an **optional**
  `sqlite3_error_offset` (absent on older process-image SQLite → offsets are
  reported as unavailable, never invented). Bundled header is 3.50.0.
- `sqlite3_error_offset` is a **UTF-8 byte** offset; converted to UTF-16 code
  units (tested with emoji: byte 35 → unit 29).
- Statement boundaries come from the same Dart splitter; each statement text is
  prepared separately, tails are followed inside a slice, and nothing is ever
  executed.
- Guard refuses `ATTACH`, `DETACH`, `PRAGMA`, `VACUUM`, `REINDEX`, `ANALYZE`
  (including behind `EXPLAIN [QUERY PLAN]`) because SQLite documents prepare-time
  effects. Refused statements are returned in `skipped` and never prepared.
- “no such table/column/function/index/view/collation/module”, “has no column
  named”, “unknown database” are counted in `schemaGaps`, not reported as syntax
  errors, and still keep the file from being reported clean.
- Result map: `available, engine('sqlite'), version, statements, checked,
  schemaGaps, truncated, issues[{startOffset,endOffset,message,code,severity}],
  skipped[{startOffset,endOffset,keyword,reason}], error`.

### Native bridge contract the coordinator/native owner must implement (OHOS)

`SqlitePrepareSyntaxEngine` already routes non-FFI platforms through
`invokeSqliteNative('validate', {'source': String})` (`qfli_sql/native`), with a
5 s timeout. To enable SQLite diagnostics on OHOS, the bridge must expose method
`validate` returning the **same result map** above, with the same guarantees
(memory DB only, prepare without step, guarded keyword refusal, UTF-16 offsets).
Until then OHOS honestly reports
`当前平台尚未提供 SQLite 语法校验接口（需要原生桥接实现 validate）`.

### MySQL scope (not implemented, by design)

No `mysql_stmt_prepare`-only API exists in `lib/mysql_ffi.dart` and MySQL native
files are outside my allocation. MySQL therefore stays lexical-only with an
explicit `unavailableReason`; SQLite grammar is never applied to MySQL text.

## 4. Evidence

- `test/sql_syntax_validator_test.dart`: 21 tests — lossless tokenizing, dialect
  quoting/comment/escape rules, unterminated literal/identifier/comment,
  parenthesis matching with exact offsets, NUL, emoji+CRLF offsets, issue cap,
  truncation, statement splitting (literals/comments/parens/trigger/CASE), guard
  allow/block lists.
- `test/sql_code_analyzer_test.dart`: 27 tests — ownership filtering, unsaved vs
  saved text, exact snapshot requirement, all-owned-buffer lexical coverage,
  engine on active only, UTF-16 ranges, unavailable/exception/NUL/oversize
  honesty, MySQL marker + selected-engine dialect, schema-gap and skipped
  information, plus a real bundled-engine group: version/`checked` proof,
  real syntax error, UTF-8→UTF-16 mapping, no-offset fallback, schema gaps,
  guard refusal, destructive-SQL leaves user DB bytes/rows and project files
  unchanged, `databasePath` rejection, trigger-body script.
- Regression: `test/sqlite_ffi_test.dart`, `test/sql_database_test.dart`,
  `test/sql_runner_test.dart`, `test/sql_terminal_commands_test.dart` all pass
  (23 tests) with the modified `sqlite_ffi.dart`.
- `flutter analyze --no-pub lib test` clean. Real-engine tests require the built
  library at `native/build/<os>/qfli_sqlite.dll` (or `QFLI_SQLITE_LIBRARY`);
  they skip with a message otherwise, never silently pass.

## 5. Spec text that the coordinator should fold in (I do not own specs)

- `frontend/sql-workbench.md` §Contracts: add the unsaved-buffer diagnostics
  contract, MySQL-lexical-only limitation, and the OHOS `validate` bridge gap.
- `backend/sqlite-native-runtime.md` §2/§3: add method `validate` to the
  documented method list, plus “prepare-only, `:memory:`, `sqlite3_step` never
  called, guarded keywords, UTF-8→UTF-16 offsets, schema gaps ≠ syntax errors”.
