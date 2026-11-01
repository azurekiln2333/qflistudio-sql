# C2 Design — Local SQL Curriculum and Repository

Parent: `.trellis/tasks/10-12-sql-curriculum-and-home` · Child: C2

## 1. Architecture and Boundaries

All work is **inside `D:\MyNewProjects\qfli_sql`**. The shared package is
read-only reference for contracts.

```
qfli_sql/
  assets/content/sql_tutorials.json     ← 120 tutorial entries (new)
  assets/content/sql_examples.json      ← 120 example entries  (new)
  lib/sql_content_repository.dart       ← SqlContentRepository (new)
  tool/sql_curriculum/                  ← authoring + validation (new)
    lessons/…                           ← structured lesson definitions
    build_content.py                    ← renders the two JSON assets
    validate_content.py                 ← executes examples + exercise answers
    coverage.py                         ← coverage/uniqueness/placeholder checks
  test/sql_curriculum_test.dart         ← catalog + repository tests (new)
  pubspec.yaml                          ← register the two assets
```

`SqlContentRepository implements ContentRepository` (interface from
`package:qfli_studio_core/content/content_repository.dart`): loads both assets
with `rootBundle`, delegates to `ContentCatalog.fromJson`, exposes `tutorials` /
`examples` filtered by `ContentFilter`, and memoizes `load()`.

The UI worker (C1) does:

```dart
final repo = SqlContentRepository();
LocalTutorialsTab(language: 'sql', repository: repo, store: …, auth: …, settings: …)
ExampleCodeTab(language: 'sql', repository: repo, examples: …, store: …, …)
```

No sibling-package edits.

## 2. Content Model Mapping

Tutorial asset root:

```jsonc
{ "schemaVersion": 1, "updatedAt": "2026-10-12", "entries": [ /* 120 tutorials */ ] }
```

Example asset root:

```jsonc
{ "schemaVersion": 1, "updatedAt": "2026-10-12", "entries": [ /* 120 examples */ ] }
```

Each entry uses the exact field names in `content_repository.dart`
(`_parseTutorial` / `_parseExample`). Important parser facts we must honor:

- `_parseTutorial` reads `title` (or falls back to `displayName`), `summary`,
  `concepts`, `source`, `license`, `updatedAt`, `level`, `locale`, and lessons.
- Lessons are read from either `lessons[]` directly or `chapters[].lessons[]`.
  We use `lessons[]` (one lesson per entry). Exercises read from `exercises[]`
  (preferred) or `tasks[]`.
- `_parseExample` reads `code` (or `sourceCode`), `expectedOutput` (or
  `output`), `inputFixtures` (object or string), `templateType`, `sourceLessonId`.
- `_text` trims strings; `_strings` drops empties. So all display fields must be
  already-trimmed, non-empty real text.

Dialect/version visibility (R6) is placed in **display fields**:
`summary` starts with the engine label (e.g. `SQLite 3.50`), `concepts` includes
the dialect tag, `explain` states the dialect/version and why the expected
result holds, and `output` is the actual expected result block. `inputFixtures`
carries `engine`/`version` as machine metadata only.

## 3. Authoring and Validation Pipeline

Authoring: structured Python definitions under `tool/sql_curriculum/lessons/`
(one module per track) providing, per lesson: id, title, level, objective,
prerequisites, explain, setup+query `code`, `expected output`, pitfalls,
exercises (prompt/hint/answer-sql), dialect metadata.

`build_content.py` renders both JSON assets deterministically (sorted by id,
fixed key order, UTF-8) and asserts the shared-schema field set.

`validate_content.py`:
1. For each **SQLite** example: open a fresh temp DB file, execute `code`,
   capture output.
2. For each lesson's **exercise answer**: execute against a fresh DB with the
   lesson's own setup.
3. Compare against the **authored** expectation expressed as a domain check —
   the expectation is authored and reviewed from the lesson semantics, then
   asserted; captured output is *evidence*, not the source of truth. A mismatch
   fails the run.
4. Collect MySQL-only items into a "not executed" list with reasons.
5. Emit `research/validation-report.md`; exit non-zero on any failure.

`coverage.py` checks: counts ≥110/≥120, required fields non-empty, placeholder
token absence, `explain`/`code` uniqueness, R4 category coverage against
`research/coverage-map.md`.

## 4. Domain-Result Verification

Expected results are authored per lesson and independently justified:

- Row-set semantics: expected rows/columns/values derived from the taught
  concept, written by hand (e.g. running total `10,30,60`), then the example is
  executed and the produced rows compared field-by-field.
- Ordering: examples that teach ordering assert ordered rows; unordered examples
  assert a canonical sort or a set comparison.
- NULL/locale/rounding: expectations state the rule explicitly in `explain`.

This avoids "run it once and paste the output as the expectation".

## 5. Compatibility

- `pubspec.yaml` gains two asset paths; no dependency changes.
- `SqlContentRepository` conforms to `ContentRepository`; the shared tabs accept
  it through the existing `repository` parameter. It must also work when
  `StudioProfile.current` is the sql profile or null (tests) — filtering falls
  back to `ContentFilter(language: 'sql')` if the product key is unavailable.
- The shared package and all non-SQL content remain untouched.

## 6. Trade-offs

- Local assets duplicate the "sql" slice that also exists in the shared
  aggregate. This is intentional: it isolates the SQL product from parallel
  multi-language edits and honors the no-external-write constraint.
- Python tooling under `tool/` keeps the Dart build graph untouched.

## 7. Rollback

Delete the two new assets, `lib/sql_content_repository.dart`, `tool/` and the new
test, and revert the two `pubspec.yaml` asset lines. No other file is touched.

## 8. Verification Shape

- `python tool/sql_curriculum/build_content.py`
- `python tool/sql_curriculum/coverage.py`
- `python tool/sql_curriculum/validate_content.py`
- `flutter test --no-pub test/sql_curriculum_test.dart`
- Widget-level reuse of shared tabs is checked with the injected repository by
  C1; C2 provides a repository unit test plus JSON-shape test.

## 9. Flutter/Worker Coordination

Only one worker may run Flutter at a time. C2 does all Python authoring and
validation first; Flutter test/analyze is run only after reporting to main
control that the Flutter step is starting (to avoid clashing with pi-mysql).
