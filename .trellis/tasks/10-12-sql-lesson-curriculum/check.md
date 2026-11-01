# C2 Verification — SQL Curriculum, Repository, and Assets

Child: `.trellis/tasks/10-12-sql-lesson-curriculum`

## Delivered

- `assets/content/sql_tutorials.json` — 126 tutorial entries (`type: "sql"`),
  regenerated after all peer-review fixes.
- `assets/content/sql_examples.json` — 126 example entries (`type: "sql"`).
- `lib/sql_content_repository.dart` — `SqlContentRepository implements
  ContentRepository`: loads both local assets, delegates to
  `ContentCatalog.fromJson`, filters with `ContentFilter`, memoizes `load()`.
- `pubspec.yaml` — registered the two new assets under `flutter.assets`.
- `tool/sql_curriculum/**` — authoring + validation tooling (schema, builder,
  coverage, validator, per-track lesson definitions, collaborator contract).
- `test/sql_curriculum_test.dart` — catalog integrity + repository unit tests
  (8 tests, all pass).

## Counts and Coverage

| Metric | Value |
| --- | --- |
| Tutorials / examples | 126 / 126 |
| SQLite-executable lessons | 120 |
| MySQL-specific (not executed) | 6 |
| Examples executed & matched | 120 / 120 |
| Exercise answers executed & matched | 240 / 240 |
| Coverage checks (`coverage.py`) | passed |
| Duplicate explain/code bodies | none |
| Placeholder tokens | none |

Track distribution (authoritative output of `coverage.py`):
basics 14, functions 16, aggregation 10, joins 12, subqueries 10, cte 8,
windows 12, ddl 12, dml 8, transactions 6, indexes 8, modeling 4, mysql 6.

## Commands and Results

```powershell
cd D:\MyNewProjects\qfli_sql
python tool\sql_curriculum\build_content.py     # lessons=126 sqlite=120 mysql=6 (exit 0)
python tool\sql_curriculum\coverage.py          # coverage checks passed (exit 0)
python tool\sql_curriculum\validate_content.py  # 120/120 examples, 240/240 exercises (exit 0)
```

## Verification method

- Each SQLite example and exercise answer runs in a **fresh throwaway database
  file** via `sqlite3` 3.50.6; nothing touches a real user database.
- Expected results are **authored from the taught semantics** and then asserted;
  captured output is evidence, not the source of the expectation.
- The empty-result sentinel is `(no rows)`.
- MySQL lessons cannot run here (no local MySQL server/client installed; no
  `mysql` on PATH, no MySQL install, no mysql service) and are reported as
  **not executed**, never as passing. See
  `research/validation-report.md`.

## Dialect/version visibility

Every tutorial's `summary` starts with the dialect label (`SQLite 3.50` /
`MySQL 8.0`), `concepts` carry the dialect tag, and each `explain` states the
dialect/version and why the expected result holds. `inputFixtures.engine` /
`version` are metadata only; the Dart test asserts dialect text is present in
display fields.

## Prose/data audit

Reviewed every lesson's `explain` against its `setup`/`query`/`expected` and
fixed inconsistencies found (e.g. lesson 2 originally claimed the keyboard was
100; corrected to reflect the 199/89/899/100 data). A peer worker also performs
a read-only content review (`research/peer-content-review.md`).

## Flutter verification (completed)

Flutter worker slot was released by the UI worker; C2 ran its own checks:

```powershell
flutter analyze lib\sql_content_repository.dart test\sql_curriculum_test.dart
  # No issues found!  (exit 0)
flutter test --no-pub test\sql_curriculum_test.dart
  # 8/8 tests passed (exit 0)
flutter test --no-pub      # whole repo: 61 passed, 2 skipped (exit 0)
```

The UI worker's own workbench tests now assert the integration end to end:
"shows the database tree as the phone home body", "opens the standalone
projects page without a second home", and "opens injected tutorial and example
content from home" — the UI consumes `SqlContentRepository`.

## Peer review findings resolution

A peer worker (`pi-sql-curriculum-2`) produced
`research/peer-content-review.md`. All findings are resolved:

| ID | Finding | Resolution |
| --- | --- | --- |
| F1 | L102 explain contradicted data ("B 抵消只剩 50") | Fixed: now "B 的 20 与 50 合计 70（0 已删除）" |
| F2 | L82 explain contradicted data | Fixed by peer in `track_07_windows.py`; assets regenerated |
| F3 | L92 TEMP exercise is session-scoped | Documented in explain + pitfalls (same-connection requirement); TEMP teaching kept |
| F4 | L91 ex1 prompt over-promised a DROP | Reworded to a query-only prompt |
| F5 | ~57 explains lacked an explicit dialect clause | `schema.py` now guarantees every explain names the dialect/version (126/126) |

After fixes the assets were regenerated and re-validated; the JSON was
confirmed to contain the corrected L82/L102/L91/L92 text.

## Limits

- Only SQLite execution is verified on this host.
- No UI/navigation changes are made by this child; the UI worker consumes
  `SqlContentRepository` through the shared tabs' `repository:` parameter.
