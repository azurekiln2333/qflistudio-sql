# SQL snapshot diagnostics

## 1. Scope / Trigger

Read when changing `SqlCodeAnalyzer`, `SqlSyntaxValidator`, SQLite validation,
the OHOS validate bridge or the shared `CodeAnalyzer` adapter registration.
Shared editor scheduling, waves and Problems UI belong to the core owner.

## 2. Signatures

- `sqlProfile.codeAnalyzer = const SqlCodeAnalyzer()`.
- `SqlCodeAnalyzer.analyze(CodeAnalysisRequest) -> Future<CodeAnalysisResult>`.
- `SqlSyntaxEngine.validate(String text) -> Future<SqlEngineAnalysis>`.
- `SqlitePrepareSyntaxEngine.decodeResult(Map<String,Object?>, String text)`.
- FFI: `SqliteFfi.invoke('validate', {'source': text})`.
- OHOS channel `qfli_sql/native`: `validate({source})`; NAPI
  `validate(source) -> Promise<QfliSqlValidationResponse>` on an async worker.

## 3. Contracts

Analyze the exact supplied unsaved snapshots. Never reread/save source files or
execute user SQL for diagnostics. Accept owned `.sql` documents only; require the
active snapshot. Lexical analysis runs on owned buffers; engine preparation runs
on the active buffer. Ranges are zero-based half-open UTF-16 units, including
CRLF, Chinese and supplementary characters. Convert native UTF-8 error offsets.

SQLite validation opens a fresh private `:memory:` connection. It only prepares
and finalizes statements; no `sqlite3_step`. It rejects a user database path,
guards PRAGMA/ATTACH/DETACH and other external-state forms, and installs an
authorizer denying external/file/extension helpers. A successful preparation
tail is authoritative; never split engine input using the lexical statement
count or trust the tail after an error. DDL is not applied to invent schema.

Response fields: `available:bool`, `engine:'sqlite'`, `version:String`,
`statements/checked/schemaGaps:int`, `truncated:bool`, `issues:List`,
`skipped:List`, `error:String`. Issues include `startOffset/endOffset`, `message`,
`code`, `severity:error|warning`; skipped ranges include offsets, `keyword` and
`reason`. Validate types/ranges/counts strictly. Nonempty SQL with zero checks
and no explicit skipped/truncated state is not a clean response.

Counts describe discovered/attempted ranges, not a fabricated complete total
after an early failure. Refusal, schema gap, syntax or other prepare failure stops
the engine scan and marks the remaining source unvalidated. Missing schema may
hide syntax/type problems and must remain visible. Do not label every truncation
as the 512-statement limit.

Lexical scan is capped at1Mi UTF-16 units and200 issues; artificial cutoffs must
not generate EOF-dependent red errors. Active engine input is capped at512Ki
UTF-16 units; OHOS native input is additionally capped at1MiB UTF-8. Both stop
at512 attempts. FFI checks250ms between calls; that deadline and the Dart5s wait
do not cancel a single ongoing native prepare. OHOS also uses SQLite limits and
a prepare progress deadline. Lexical trigger boundaries are conservative; tools
must report detected ambiguity instead of a definite count.

MySQL markers/preference select MySQL lexical rules and an explicit lexical-only
unavailable reason. Never apply SQLite grammar to MySQL or use a real user
database to fake schema-aware completeness.

## 4. Validation & Error Matrix

| Condition | Required result |
| --- | --- |
| Missing active/foreign snapshot | Explicit unavailable; no engine call |
| NUL/oversize input | Visible limitation; no engine dispatch |
| Missing bridge/library or malformed response | Unavailable, never empty success |
| Actual syntax error | Real range/message and skipped remaining coverage |
| Missing table/function/context | Informational incomplete coverage, no false clean claim |
| Guarded operation | Skipped with reason; no file open/SQL step |
| MySQL project | Lexical diagnostics plus grammar limitation |

## 5. Good / Base / Bad Cases

Good: diagnose unsaved `SELECT '😀';\r\nSELEC 1;` at its real UTF-16 location.
Base: prepare `SELECT 1; SELECT 2;` without executing either statement.
Bad: execute CREATE TABLE to populate a temporary schema or continue at an error
tail and claim the whole document was checked.

## 6. Tests Required

Run SQL analyzer/scanner/validation-response and real FFI tests. Assert exact
unsaved ranges, no writes, strict decoding, schema/refusal coverage and budgets.
`native/tests/run-sql-validation-test.ps1` exercises the production core with
actual bundled SQLite and audited zero step/VFS-open calls. SDK syntax checks
cover ARM64/x86 with `-Werror`. Actual OHOS channel and editor UI acceptance are
separate from host/native compilation results.

## 7. Wrong vs Correct

Wrong: semicolon-split trigger bodies, treat missing schema as clean, or change
SQLite to MySQL because OHOS has no desktop FFI.

Correct: preserve exact snapshots, use prepare/tail on the selected SQLite
transport, and publish honest limits alongside supported lexical diagnostics.
