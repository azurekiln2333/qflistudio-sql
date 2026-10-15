# SQL Content Repository

## 1. Scope / Trigger

The SQL app ships its own curriculum assets under `assets/content/` and loads
them through `lib/sql_content_repository.dart` (`SqlContentRepository`). This
keeps the SQL product independent of the shared multi-language aggregate in
`../qfli_studio_core/assets/content/`, which other-language workers edit in
parallel. Use this contract whenever the SQL app needs tutorial/example content.

## 2. Signatures

```dart
class SqlContentRepository implements ContentRepository {
  SqlContentRepository({AssetBundle? bundle});
  static const String tutorialAsset = 'assets/content/sql_tutorials.json';
  static const String exampleAsset = 'assets/content/sql_examples.json';
  Future<ContentCatalog> load();                       // memoized
  Future<List<TutorialContent>> tutorials({ContentFilter filter});
  Future<List<ExampleContent>> examples({ContentFilter filter});
}
```

Assets are registered in `pubspec.yaml` under `flutter.assets`.

## 3. Contracts

- Load both assets with `rootBundle.loadString`; try the plain key first, then
  the `packages/qfli_sql/` qualified form; throw `SqlContentAssetException` with
  every failure if neither resolves.
- Parse with the shared `ContentCatalog.fromJson({tutorialsSource,
  examplesSource})`. Do not re-implement the parser in this app.
- Memoize: `load()` returns the same future/catalog instance on repeat calls.
- Filtering uses `ContentFilter`; the SQL product key is `'sqlab'`
  (`ContentFilter.forProduct('sqlab')` → `type == 'sql'`).
- The shared `LocalTutorialsTab` / `ExampleCodeTab` accept the repository via
  their `repository:` parameter; the UI injects `SqlContentRepository()`. No
  shared-package edit is required or permitted.

## 4. JSON Schema (must match the shared parser)

Aggregate document: `{schemaVersion, language, type, locale, updatedAt, entries:[...]}`.

Tutorial entry: `id, language, type, locale, level, title, summary, concepts[],
source, license, updatedAt, lessons[]`; each lesson: `id, title, summary,
concepts[], objective, prerequisites[], explain, code, output, pitfalls[],
exercises[]{prompt,hint,answer}`.

Example entry: `id, language, type, locale, level, title, summary, concepts[],
source, license, updatedAt, code, output, expectedOutput, inputFixtures{},
templateType, sourceLessonId`.

`ExampleContent.inputFixtures` preserves string values only. `exerciseSetup`
contains the authored setup SQL; `exerciseExpectedOutputs` contains a JSON-encoded
array of authored expected result strings in lesson-exercise order. Never store
the array as a raw JSON value here: the shared parser would discard it. Use
`(no rows)` as the explicit empty-result expectation. Every exercise expectation
must be authored from the SQL semantics rather than captured from execution.

Dialect/version must appear in display fields (`summary`/`concepts`/`explain`),
not only in `inputFixtures`.

## 5. Authoring / Validation

Authoring source of truth: `tool/sql_curriculum/lessons/track_*.py`
(`L(...)`/`E(...)` helpers). Render with `build_content.py`, audit with
`coverage.py`, execute with `validate_content.py`:

```powershell
python tool\sql_curriculum\build_content.py
python tool\sql_curriculum\coverage.py
python tool\sql_curriculum\validate_content.py
python tool\sql_curriculum\validate_assets.py
flutter test --no-pub test\sql_curriculum_test.dart
```

Rules: every example is a complete runnable script (CREATE + INSERT + query);
expected results are authored from semantics then asserted (never paste captured
output as the expectation); SQLite examples run in a fresh throwaway DB. The
packaged-assets validator executes the actual shipped JSON and compares every
SQLite exercise with its bundled authored expectation, independently of source
module validation. Assert generated assets match the current authoring text.
MySQL-only lessons set `engine="mysql"`; host SQLite checks report them as
"not executed", and native acceptance must execute them separately.

## 6. Wrong vs Correct

Wrong: editing `../qfli_studio_core` content assets for SQL, or duplicating the
aggregate parser locally.

Correct: add the SQL entries to the local `assets/content/sql_*.json` and load
them through `SqlContentRepository` + the shared `ContentCatalog.fromJson`.

Wrong: asserting a full `EXPLAIN QUERY PLAN` text (version-fragile).

Correct: assert the domain result and describe the plan concept in prose.

## 7. Tests Required

`test/sql_curriculum_test.dart` parses both assets through the shared catalog,
asserts ≥110 tutorials/examples, complete lesson fields, no placeholders, no
duplicate explain/code, dialect visibility, runnable example DDL, and unit-tests
`SqlContentRepository` (load, filter, memoization, missing-asset error).

`integration_test/sql_curriculum_native_test.dart` executes all six shipped
MySQL-only lessons and exercises through real Oracle 8.4.6 on Android/OHOS. It
requires a separate Android `.integrationtest` app sandbox or an OHOS debug
probe root, verifies socket/skip-networking identity, creates uniquely owned
databases, and cleans only owned test data. Tests fail rather than silently
skip an unavailable native runtime. Native build or host SQLite success does
not establish the MySQL lesson result; record platform PASS/cleanup markers.
