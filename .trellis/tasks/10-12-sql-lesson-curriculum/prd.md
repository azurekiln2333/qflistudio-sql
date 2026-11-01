# C2 — 120 SQL Lessons, Runnable Examples, and Local Content Repository

Parent: `.trellis/tasks/10-12-sql-curriculum-and-home`

## Goal

Deliver 120 substantive Chinese SQL lessons (floor 110) and 120 complete,
independently runnable SQL examples **inside this repo** (`qfli_sql`), plus an
app-local `SqlContentRepository implements ContentRepository` that loads them and
is injected into the shared `LocalTutorialsTab` / `ExampleCodeTab` by the UI
worker. Nothing outside this repository is written.

## Background / Evidence

- **Hard constraint from main control**: no file outside `D:\MyNewProjects\qfli_sql`
  may be written. The shared package location of the old content does not imply
  we must edit there, and other-language workers are editing it in parallel.
- Repo has only `assets/app_icon.png`; assets are declared in `pubspec.yaml`
  under `flutter.assets` (currently `assets/app_icon.png`). C2 owns the
  `pubspec.yaml` assets registration.
- New local assets: `assets/content/sql_tutorials.json` and
  `assets/content/sql_examples.json`.
- Shared contract to satisfy (from
  `../qfli_studio_core/lib/content/content_repository.dart`, read-only):
  - `ContentRepository` interface: `load()`, `tutorials({filter})`,
    `examples({filter})`.
  - `ContentCatalog.fromJson({tutorialsSource, examplesSource})` accepts
    `{entries:[...]}` aggregate documents.
  - `ContentFilter.forProduct('sqlab')` selects `type == "sql"`; a plain
    `ContentFilter(language: 'sql')` also works.
  - Tutorial entry fields: `id, language, type, locale, level, title, summary,
    concepts[], source, license, updatedAt, lessons[]`; lesson fields:
    `id, title, summary, concepts[], explain, code, output, objective,
    prerequisites[], pitfalls[], exercises[]{prompt,hint,answer}`.
  - Example entry fields: `id, language, type, locale, level, title, summary,
    concepts[], source, license, updatedAt, code, expectedOutput,
    inputFixtures{}, templateType, sourceLessonId`.
- Shared `LocalTutorialsTab` / `ExampleCodeTab` already accept a
  `ContentRepository? repository` parameter; no sibling-package edit is needed.
  The UI worker constructs `SqlContentRepository` and injects it.
- Validators available: `sqlite3` 3.50.6 CLI at
  `D:\ProgramFiles\platform-tools\sqlite3.exe`; the repo's own FFI
  (`lib/sqlite_ffi.dart`, `native/third_party/sqlite`); the repo's local MySQL
  test facilities under `native/` and `integration_test/`.

## Requirements

- R1 — ≥110 distinct lessons (target 120); each covers a distinct knowledge
  point (no near-duplicates).
- R2 — Each lesson has: objective, real concept explanation (not a template), a
  complete setup (CREATE TABLE + data) plus the query, expected result, common
  pitfalls, ≥1 exercise, and a reference solution.
- R3 — ≥110 matching examples (target 120), one per lesson, each independently
  reproducible: a single script that creates its own objects and produces
  `expectedOutput`. Entry code must be runnable SQL including DDL + data, not
  just a SELECT.
- R4 — Coverage must include at minimum: SELECT/WHERE/ORDER/LIMIT/DISTINCT;
  operators, string/date/numeric functions, NULL (IS NULL/COALESCE/NULLIF),
  CASE; aggregation (COUNT/SUM/AVG/GROUP BY/HAVING); joins
  (INNER/LEFT/RIGHT/FULL/CROSS/self); subqueries (scalar/IN/EXISTS/correlated/
  derived); CTE + recursive CTE; window functions (OVER/partition/ranking/
  LAG/LEAD/running totals/moving averages); DDL + constraints
  (PK/FK/UNIQUE/CHECK/NOT NULL/DEFAULT/generated); DML + upsert; transactions +
  savepoints + isolation concepts; indexes + when they are ignored;
  EXPLAIN/EXPLAIN QUERY PLAN; views; modeling/normalization; SQLite vs MySQL
  dialect differences with version labels; multi-table capstone scenarios.
- R5 — Every SQLite example and every exercise answer must be executed and its
  result verified. MySQL-specific items that cannot run are explicitly marked
  and reported as "not executed" — never falsely claimed as executed. The
  verifier must check the **domain result** (row values/relations), not blindly
  treat captured execution output as the expectation.
- R6 — Dialect and version must be visible in the tutorial/example **display
  fields** (`summary`/`concepts`/`explain`/`output`) — `inputFixtures` alone is
  metadata and is not sufficient. Expected-result explanations must be visible.
- R7 — Teaching data may be shared across lessons but each example is
  self-contained; teaching data exists only inside lessons/examples. Examples
  must never operate on a real user database; SQLite validation uses a fresh
  isolated test database.
- R8 — `SqlContentRepository implements ContentRepository` loads the two local
  assets, delegates parsing to the shared `ContentCatalog.fromJson` /
  `ContentFilter`, and caches the parsed catalog (`load()` memoized).
- R9 — JSON root schema must match the existing model exactly.

## Acceptance Criteria

- [x] AC1 — `sql_tutorials.json` has ≥110 (delivered 126) tutorial entries and
      `sql_examples.json` has ≥110 (delivered 126) example entries, all `type: "sql"`.
- [x] AC2 — Every lesson has non-empty objective, explain, code, output,
      pitfalls, and ≥1 exercise with a reference answer.
- [x] AC3 — No placeholder tokens and no two lessons share identical `explain`
      or `code`; mechanical uniqueness check passes.
- [x] AC4 — 120 SQLite examples execute and match verified expectations;
      240 exercise answers verified; the validation report lists the 6
      MySQL-only (not executed) items.
- [x] AC5 — Coverage checklist (R4) complete and recorded in `research/`.
- [x] AC6 — `SqlContentRepository` loads both assets via the shared parser and
      caches; the UI worker's workbench test proves tutorial/example content is
      reachable from home (8/8 C2 tests + 61/61 repo tests pass).
- [x] AC7 — No file outside this repo is written; all other content types and
      unrelated assets are unchanged.
- [x] AC8 — `pubspec.yaml` registers the two new assets; JSON is valid; the new
      repo test and existing content tests pass.

## File Ownership (local repo only)

**Owned by C2:**

- `assets/content/sql_tutorials.json` (new) — tutorial entries.
- `assets/content/sql_examples.json` (new) — example entries.
- `tool/sql_curriculum/**` (new) — authoring + validation tooling.
- `lib/sql_content_repository.dart` (new) — `SqlContentRepository implements
  ContentRepository`.
- `test/sql_curriculum_test.dart` (new) — catalog integrity + repository tests.
- `pubspec.yaml` — **only** the `flutter.assets` list additions.

**NOT owned by C2:**

- `lib/main.dart`, `lib/sql_workbench_page.dart` — UI, owned by C1 (pi-mysql).
- All `../qfli_studio_core/**` files (read-only reference).
- `lib/*.dart` repository/runner logic (consume shared contracts only).
- Non-SQL content.

## Dependencies / Ordering

- C2 owns content + repository and proceeds independently of C1.
- C2's AC6 navigation depends on C1; verify AC6 with an injected
  `SqlContentRepository` and shared `/` custom list widgets, and record the
  remaining UI dependency explicitly.
- Interface handshake with C1: C1 constructs `SqlContentRepository()` and passes
  it as `repository:` to `LocalTutorialsTab` / `ExampleCodeTab`. C2 guarantees
  the class name, constructor, and `ContentRepository` conformance.

## Out of Scope

- Home/projects navigation (C1).
- Non-SQL languages.
- Native runtime work.
- Committing/pushing.

## Open Questions

None blocking.
