# C2 Implementation Plan — Local SQL Curriculum and Repository

Parent: `.trellis/tasks/10-12-sql-curriculum-and-home` · Child: C2
Owner: curriculum worker

## Preconditions

- Work **only inside `D:\MyNewProjects\qfli_sql`**. The shared package is
  read-only reference.
- Do not edit `lib/main.dart` or `lib/sql_workbench_page.dart` (C1 owns UI).
- Preserve the existing dirty working tree (113 files); no reset/format.

## Checklist

- [ ] 1. Finalize `research/coverage-map.md` (120 lesson ids across all tracks).
- [ ] 2. Create `tool/sql_curriculum/lessons/` structured definitions for all
      120 lessons (id, title, level, objective, prerequisites, explain, code
      (DDL+data+query), expected result, pitfalls, exercises with answers,
      dialect/version metadata).
- [ ] 3. Write `tool/sql_curriculum/build_content.py` to render
      `assets/content/sql_tutorials.json` and `assets/content/sql_examples.json`
      from the definitions, deterministic and schema-checked.
- [ ] 4. Write `tool/sql_curriculum/coverage.py` (counts, required fields,
      placeholder absence, explain/code uniqueness, R4 category coverage).
- [ ] 5. Write `tool/sql_curriculum/validate_content.py` to execute every
      SQLite example and every exercise answer in fresh isolated temp DBs and
      assert authored domain expectations; separate MySQL-only items; write
      `research/validation-report.md`.
- [ ] 6. Run build + coverage + validation; fix until all SQLite items pass and
      coverage is complete.
- [ ] 7. Write `lib/sql_content_repository.dart`
      (`SqlContentRepository implements ContentRepository`, memoized load,
      shared `ContentCatalog.fromJson`, `ContentFilter`).
- [ ] 8. Register the two assets in `pubspec.yaml`.
- [ ] 9. Write `test/sql_curriculum_test.dart`: parse both assets via the shared
      catalog, assert counts/fields/uniqueness/dialect-visibility, and unit-test
      `SqlContentRepository` (load, filter, memoization, missing-asset error).
- [ ] 10. Report to main control before running Flutter (single-worker rule),
      then run the Dart test/analyze.
- [ ] 11. Record evidence in `check.md`.

## Volume Strategy

Author by track in batches, validating after each batch. Never stub to reach the
count. Each lesson: real teaching prose, a runnable script, a hand-derived
expected result, pitfalls, and an answered exercise.

## Validation Commands

```powershell
cd D:\MyNewProjects\qfli_sql
python tool\sql_curriculum\build_content.py
python tool\sql_curriculum\coverage.py
python tool\sql_curriculum\validate_content.py
# Flutter (only after reporting to main control)
flutter test --no-pub test\sql_curriculum_test.dart
flutter analyze lib\sql_content_repository.dart test\sql_curriculum_test.dart
```

Isolated SQLite check uses a fresh temp DB per example, never a user database:

```powershell
& "D:\ProgramFiles\platform-tools\sqlite3.exe" ":memory:" ".read <script>"
```

## Risky Files / Rollback Points

- `assets/content/*.json` are new, so risk is limited to schema mismatch; caught
  by the shared-catalog parse test.
- `pubspec.yaml`: add only two asset lines; keep existing entries intact.
- `SqlContentRepository`: must conform exactly to `ContentRepository`; verify by
  compiling the Dart test.

## Review Gates Before Marking Done

- [ ] ≥110 tutorials and ≥110 examples (target 120), all `type: "sql"`.
- [ ] Every lesson complete; uniqueness and placeholder checks pass.
- [ ] All SQLite examples and exercise answers verified by domain expectation.
- [ ] MySQL-only items explicitly listed as not executed.
- [ ] No file outside the repo written; non-SQL content untouched.
- [ ] Repository test + existing content tests pass; analyze clean.

## Evidence to Record in check.md

- Counts, coverage, uniqueness/placeholder results.
- Validation report summary (pass/fail, MySQL-only list, method for domain
  checks).
- Commands + exit codes.
- Explicit Flutter single-worker coordination note.
- Any UI dependency on C1 left open.
