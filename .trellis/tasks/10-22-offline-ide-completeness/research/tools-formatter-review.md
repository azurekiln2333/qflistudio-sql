# SQL command normalization review — 2026-10-22

## Scope and fixed behavior

The previous `formatSqlText` uppercased every word found in a broad keyword set,
including identifiers and aliases such as `text` and `real`. This can alter
MySQL object lookup on case-sensitive configurations. It also changed actual
SQLite output headers for unaliased expressions and aliases: the real-engine
regression initially failed with `NULL`, `1 IN (1)`, `2 BETWEEN 1 AND 3`, `TEXT`
and `REAL` replacing the original lowercase headers.

The final implementation normalizes only recognized command words at lexical
statement starts. Every statement body remains verbatim, including identifiers,
aliases, expressions, types, clauses, function names, quoted content, comments
and separators. Surrounding whitespace is trimmed. Incomplete, resource-limited
or ambiguous lexical analysis returns the trimmed source unchanged. This is
deliberately a limited normalization utility rather than a full SQL formatter;
the button now says **整理语句开头**.

Example:

```sql
select real as text from text; update text set real = 1;
```

becomes:

```sql
SELECT real as text from text; UPDATE text set real = 1;
```

No grammar parser, engine execution, controller/workbench behavior, diagnostics
or native runtime was added or modified for this formatter correction.

## Changed files

- `lib/sql_tools_service.dart`: `sqlFormatKeywords` and `formatSqlText` only.
- `lib/sql_tools_tab.dart`: formatter button label only.
- `test/sql_tools_service_test.dart`: updated limited-behavior expectations and
  added identifier/content/fallback/actual-engine regressions.
- This research report and `research/full-application-check.md`.

## Verification

- MySQL dialect unit regression preserves `text`/`real` as table, qualified
  column, output alias and UPDATE target names. This is source-preservation
  evidence, not a claim that a MySQL server was run.
- Quoted literals/identifiers, MySQL comments, CRLF, separators and trailing line
  comments remain unchanged; no separator is added.
- Incomplete quotes and ambiguous trigger boundaries preserve the trimmed input.
- The real bundled SQLite regression creates an actual `text` table with `real`
  and `text` columns, then compares the exact result headers and row values
  before/after normalization. It passed with the retained Windows SQLite library
  SHA-256 `12bb8326b9ab400472d4b95596cb343512a10ab2ac6e40620e09df2da2c59f93`.
- Focused service/widget run: **66 PASS, 0 FAIL, 0 SKIP**. After extending the
  real-engine test to the actual table fixture, its targeted run passed again.
- Full application analysis: **PASS, zero issues**.
- Final full application test run includes the extended fixture regression:
  **273 PASS, 0 FAIL, 2 SKIP**. See `full-application-check.md` for exact skips,
  source snapshots and complete log paths.

Commands:

```powershell
flutter analyze --no-pub lib/sql_tools_service.dart lib/sql_tools_tab.dart test/sql_tools_service_test.dart test/sql_tools_tab_test.dart
flutter test --no-pub test/sql_tools_service_test.dart test/sql_tools_tab_test.dart --reporter expanded
flutter test --no-pub test/sql_tools_service_test.dart --reporter expanded --plain-name 'command normalization preserves a real SQLite text table'
```

`dart format` ran on the three changed source/test files. The scoped diff
whitespace check passed before the final test-fixture-only extension. No staging,
commit, package build, install or device actions were performed. Production
formatter source is frozen after passing checks.
