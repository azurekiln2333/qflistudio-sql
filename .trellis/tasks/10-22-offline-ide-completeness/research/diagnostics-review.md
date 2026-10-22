# SQL diagnostics review — 2026-10-22

## Scope and provenance

Reviewed `lib/sql_code_analyzer.dart`, `lib/sql_syntax_validator.dart`,
`lib/sqlite_ffi.dart` and the focused diagnostics tests. No main/core/native,
build, signing, device, tools, curriculum or production-asset changes were made.
No files were staged or committed.

SQL base HEAD: `42602e37e75dff348ed4d2a453f7c8af009a4fbb`.
Shared core HEAD at verification: `daddce27eed1f9389efed0360a0ca954af422da8`.
The shared core also had concurrent, unreviewed changes to
`lib/editor/editor_controller.dart` and `test/editor_workspace_backup_test.dart`.
This review does not claim a clean core checkout or verify those changes.

Actual Windows SQLite library:
`native/build/windows/qfli_sqlite.dll`, runtime version 3.50.0, SHA-256
`12bb8326b9ab400472d4b95596cb343512a10ab2ac6e40620e09df2da2c59f93`.

## Findings fixed

1. **Artificial lexical EOF generated false errors.** A valid string, quoted
   identifier, block comment or parenthesis extending beyond `maxUnits` was
   reported as unclosed. A truncated prefix cannot prove its closing delimiter
   is absent. Suppress only those EOF-dependent errors when scanning is
   truncated; retain proven unmatched closing parentheses, NUL errors and the
   explicit incomplete-scan information. A regression failed before the fix and
   passes after it for strings, all three identifier forms, comments and
   parentheses.
2. **Blocked statements bypassed the FFI output budget.** Guard filtering ran
   before the 512-statement loop, so 513 PRAGMAs emitted 513 skipped statements
   with `truncated=false`, with much larger outputs possible within the source
   budget. The final implementation bounds actual validation attempts rather
   than lexical slices. A refused statement stops checking and marks the entire
   remaining range skipped; it cannot emit thousands of refusal diagnostics or
   guess how many statements remain. `checked` counts actual prepare attempts.
   A successful 512-statement run followed by more SQL reports 512 checked plus
   one discovered unvalidated remainder, with `truncated=true`.
3. **Trigger declaration recognition confused ordinary table names and omitted
   long EXPLAIN prefixes.** `CREATE TABLE trigger (begin); SELECT 1; SELECT 2;`
   became one lexical slice; `EXPLAIN QUERY PLAN CREATE TEMP TRIGGER ...` split
   inside its body. Match the actual CREATE [TEMP|TEMPORARY] TRIGGER prefix,
   optionally following EXPLAIN [QUERY PLAN], with six internal prefix words.
   Preserve the existing public four-word leading-keyword result. Both lexical
   regressions failed before correction. The actual-library budget regression
   now sees 513 statements, checks 512 and marks the remainder truncated.
4. **FFI grammar validation trusted lexical statement boundaries.** After the
   coordinator explicitly approved the parser-boundary change, replaced sliced
   preparation with one original UTF-8 allocation and a loop following only
   successful `sqlite3_prepare` tails. Failed/refused preparation stops with an
   explicit skipped range through the end of the exact source; error tails are
   never treated as complete statements. Diagnostic error state is captured
   before finalization. Schema failures and non-syntax preparation failures
   remain informational, not false syntax errors. The source limit remains
   512 Ki UTF-16 units; actual attempts are bounded to 512 with a 250 ms deadline
   checked between calls. Additional authorizer exclusions align with native
   external-function/virtual-table protection.

Added a behavioral regression for the coordinator's early-prepare-failure
message: incomplete engine coverage remains information, describes incomplete
validation, and does not falsely claim the 512-statement resource limit was hit.
The schema-gap explanation continues to disclose unchecked syntax/type issues.

## Findings not fixed

### Pure lexical trigger boundaries remain deliberately limited

SQLite permits unquoted columns named `begin` and `end`. The remaining trigger
body scanner treats every such word as a block delimiter, including identifiers
in UPDATE expressions. A pure Dart probe against the current scanner produced:

```sql
CREATE TRIGGER tr AFTER INSERT ON t BEGIN UPDATE t SET begin = 1; END; SELECT 1;
-- One lexical slice, swallowing the SELECT.

CREATE TRIGGER tr AFTER INSERT ON t BEGIN UPDATE t SET end = 1; END; SELECT 1;
-- Three lexical slices, splitting before the trigger's actual END.
```

The FFI dependency on those slices is now removed. Actual bundled-engine tests
execute valid begin/end-column trigger scripts in a separate disposable
`:memory:` database, then check the diagnostics backend emits no false syntax
errors. An appended invalid statement after a schema-limited trigger remains
explicitly within the skipped range, so it is never declared checked or clean.

Pure lexical tools still cannot universally parse trigger identifier contexts.
The lexer now emits informational `statement-boundary-unsupported` issues for
repeated BEGIN words inside a body and END followed by `=` or `.`. The tools
owner independently added service/count/UI refusal for this explicit issue;
those files are outside this review's ownership and test count. No lexical red
error is emitted for these valid column names. Other identifier expression
contexts, such as `SET value = end`, are not universally recognized by this
conservative detector. Do not advertise exact trigger statement counts or full
SQLite grammar coverage from the pure lexical splitter. Further generalization
belongs to the tools/parser contract; production sources were frozen at the
coordinator's request after the passing verification.

### Single native prepare cannot be interrupted by the between-call deadline

The 250 ms stopwatch is checked before each prepare attempt, not during a native
call. The outer Future timeout can report an unavailable result but does not
cancel an already-running FFI isolate/native prepare. Source and attempt limits
bound input and repeated work; they do not prove a hard wall-clock limit for a
single expensive statement. A cancellable single-prepare mechanism would need
an additional native resource/cancellation contract. This limitation remains
explicit and was not disguised as a guaranteed timeout.

### Spec synchronization belongs to coordinator

The backend native-runtime and frontend terminal specs still describe earlier
OHOS dispatch/script behavior. This review was explicitly restricted to the
diagnostics files/tests and this report, so it did not edit those shared task
contracts. The coordinator should synchronize the real SQLite transport and
diagnostics contract: isolated `:memory:` validation, no stepping, denied
external-state operations, source/statement/issue budgets, UTF-16 ranges,
  schema gaps and incomplete/unavailable coverage. Preserve the lexical trigger
  and single-prepare deadline limitations above.

## Verified behavior

- Analysis uses supplied unsaved snapshots rather than saved SQL files;
  normalized foreign/non-SQL paths are ignored, and the active snapshot is
  required.
- UTF-16 positions preserve CRLF, Chinese and supplementary characters;
  real `sqlite3_error_offset` byte positions convert to editor code units.
- SQLite validation creates only an isolated in-memory connection and refuses
  a caller-supplied user database path. Validation/prepare code does not call
  `sqlite3_step`. Actual-library regressions preserve user database bytes,
  rows and project files while analyzing destructive DDL/DML.
- PRAGMA/ATTACH/DETACH and guarded operations remain skipped; the synchronous
  authorizer also denies dangerous external-state functions, including the
  coordinator's newly added `eval` and `fts3_tokenizer` entries. The existing
  actual-library external-function regression passed. It does not pretend
  unavailable extension functions prove a particular authorizer callback ran.
- Damaged backend engine/types/counts/ranges/severities are rejected; nonempty
  SQL with zero unchecked success cannot be treated as clean; partial and
  unavailable states remain visible. MySQL reports lexical-only support and
  does not invoke SQLite grammar validation.
- Schema gaps, skipped statements and truncated preparation remain visible;
  no schema-gap or OHOS runtime completeness is inferred from host-only tests.
- A BOM-prefixed PRAGMA bypasses only the optional ASCII prefix check and is
  still refused by the actual SQLite authorizer in a real-library test.
- Native tails preserve the exact later error offset after emoji, Chinese,
  CRLF and a preceding CREATE TABLE statement. The original semicolons reach
  SQLite unchanged, so an incomplete no-offset test intentionally omits its
  final semicolon instead of relying on lexical stripping.

## Verification

Initial diagnostics-only baseline: **54/54 PASS**.

After local fixes and regressions:

```powershell
flutter analyze --no-pub lib/sql_code_analyzer.dart lib/sql_syntax_validator.dart lib/sqlite_ffi.dart test/sql_code_analyzer_test.dart test/sql_syntax_validator_test.dart test/sql_validation_response_test.dart
# No issues found. Dart lint/type analysis PASS.

flutter test --no-pub test/sql_syntax_validator_test.dart test/sql_code_analyzer_test.dart test/sql_validation_response_test.dart test/sqlite_ffi_test.dart --reporter expanded
# Final checkpoint: 71/71 PASS, no skipped tests.
# Actual bundled-library tests executed.

git diff --check -- lib/sqlite_ffi.dart
# PASS.
```

`dart format` ran on the six scoped source/test files. No Flutter package build,
device action or large native build was run. Full application analysis/tests
and OHOS acceptance remain coordinator-owned gates.

## Final changed-file handoff

- `lib/sql_syntax_validator.dart`
- `lib/sqlite_ffi.dart`
- `test/sql_code_analyzer_test.dart`
- `test/sql_syntax_validator_test.dart`
- This research report.

`lib/sql_code_analyzer.dart` and `test/sql_validation_response_test.dart` were
reviewed/formatted/analyzed without further source edits in this review. Sources
are frozen for the coordinator's build; no commit or staging was performed.
