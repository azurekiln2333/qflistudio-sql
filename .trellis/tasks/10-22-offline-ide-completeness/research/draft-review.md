# Independent review of the 180 SQL curriculum drafts

Date: 2026-10-22. Reviewer: `review_curriculum_drafts`.
Scope: read-only review of source, existing evidence and promotion mechanics.
Only this report was written. No assets, authoring modules, native engines,
device state or Git state were changed. No SQL execution was repeated.

## Conclusion

The drafts are substantial additions to the original 126 topics. They cover
180 complete paired topics, IDs 127–306, with 360 authored exercises. There is
no blocking ID, import, renderer, expected-output or duplicate-content defect
in the reviewed snapshot. Promotion is mechanically compatible with the
existing loader once the helper import is relocated. **Promotion still requires
the complete original OHOS gate first.** Existing host results are not that gate.

The resulting denominator is **306 examples + 606 exercises = 912 scripts**:
300 SQLite examples + 600 SQLite exercises = 900; six MySQL examples + six
MySQL exercises = 12. The current shipped denominator remains **126/372**.

Before promotion, account for the hardcoded consumer-test count and the dated
metadata described below. The teaching-quality suggestions are small scoped
improvements, not evidence that the draft collection is recycled material.

## Evidence checked without executing SQL

- Read task PRD/design/implementation, context manifests, the content spec,
  `curriculum-expansion.md`, renderer/schema/loader, source/assets validators,
  current catalog tests, all baseline titles/concepts, draft explanations and
  exercises, and concrete source for the overlapping/advanced topics.
- Python was invoked with `-B` to avoid writing import caches. Ran only static
  imports, structural `audit`, hash checks, in-memory rendering and comparison.
- The original source has 126 lessons and 246 exercises; drafts have exactly
  180 lessons and 360 exercises. Draft IDs equal `range(127, 307)`.
- All 180 drafts use `advanced`, `sqlite`, version `3.50`, two exercises and two
  pitfalls. Every full script contains its own CREATE setup; every exercise
  is enabled for verification and uses the owning lesson's fresh setup.
- Across all 306 lessons, numbers, slugs, titles, explanations and complete code
  bodies are each unique. Literal-normalized teaching-query fingerprints have
  no new-to-original or new-to-new collision.
- No exercise answer is identical to its own teaching query. Across 360 draft
  answers, the only exact SQL reuse is `PRAGMA foreign_key_check;` in 277/e1 and
  279/e2, intentionally checking different deferred-reference/deletion fixtures.
- Every draft's in-memory tutorial/example render preserves exact code,
  expected output, sourceLessonId, exercise setup and JSON-string encoded
  exercise expectations. The relocated helper/track import was also simulated
  using in-memory modules: all 180 still import and pass structural audit.
- Both existing reports (`bundled-host-results.json`, `cli-host-results.json`)
  contain 540 passing cases, 180 examples and 360 exercises. Every recorded
  draft Python source hash still matches its current file. This preserves the
  validity of the prior host runs; this review did not recreate them.
- Both shipped assets still equal the renderer's original-126 source entries
  exactly, including metadata. Their bytes retain the recorded hashes:
  tutorials `0ea1071c1aa9a6611ebceba7c4b4a832f6f635f4b57e052406f6455c99e5a2e0`;
  examples `cacfbf628a56fc42635764e3767981da14325eb9c8802cda94f5be0270276049`.

## Distinct material and near-duplicate review

The original collection primarily introduces SQL operators, joins, grouping,
subqueries, CTEs, windows, DDL/DML, transactions and indexes. The new collection
adds both missing engine features and concrete multi-step applications:

| Draft track | Additional learning objective |
| --- | --- |
| 127–141 quality | Canonical business keys, survivorship, per-field/record denominators, reconciliation and explanatory issue lists |
| 142–156 temporal | Half-open reporting, calendar floor/ISO week-year, sparse calendars, explicit offsets, clipping and effective versions |
| 157–171 JSON | Missing versus JSON null, shape/types, array fanout, mutation-expression distinctions and ordered JSON output; no baseline JSON track |
| 172–186 graph | Diamond paths, BOM multiplication, closure, cycle witnesses, undirected components, longest-path scheduling and weighted paths |
| 187–201 inventory | Per-location ledger, reservations, first deficit, historical snapshots, allocations, FIFO, coverage and reconciliation |
| 202–216 billing | Header/detail and receipt grains, credits, historical cutoffs, journals, largest remainder and integer rounding |
| 217–231 cohorts | User/event grain, ordered funnels, sessions, streaks, maturity and cohort denominators |
| 232–246 intervals | Half-open collision, sweep line, nested-interval union, full-window complement, capacity and buffers |
| 247–261 window_details | GROUPS and EXCLUDE variants, FILTER/windows, chaining, resettable aggregates, distributions, median and directional fill |
| 262–276 text_binary | Explicit ASCII contracts, whole-string digit validation, SQL literal/identifier encoding, NUL/UTF-8/BLOB and bounded tokenization |
| 277–291 integrity | Deferred/composite/cascading references, partial/expression uniqueness, audit/view triggers, guarded UPSERT, UPDATE FROM and schema flags |
| 292–306 relational | Universal/exact-set logic, empty-set semantics, multiset operations, similarity/co-occurrence, finite cover and quotas |

I also compared the closest literal-normalized teaching-query pairs using
SequenceMatcher and inspected their semantics. High similarity mostly comes
from shared CTE prefixes or intentionally contrasting operations: 234/242/243
derive segments, breach duration and peak witnesses from the same sweep;
297/298 implement multiset difference versus intersection; 248/249/250 contrast
three window exclusion rules; 255/256 distinguish distribution denominators;
221/222 return qualifying users versus ordered step populations. These are
separate outputs and concepts, not title-only copies. 187/191 reuse aggregation
to distinguish current versus historical stock; the changed cutoff is the
actual subject. Baseline overlaps are developed further: 180 introduces a real
cycle absent from baseline 69; 288 updates and inspects a generated column after
baseline 89's insertion; 285 adds a revision guard beyond baseline 101's UPSERT.

Exercise richness is adequate overall: prompts include counterexamples,
alternative denominators, reverse traversal, independent conservation checks,
metadata queries and different boundary cases. Some secondary exercises are
simple counts, but they are contextual checks rather than empty answer fillers.

## Concrete follow-ups

### Required promotion bookkeeping

1. `curriculum-expansion.md:106` says there are twelve MySQL exercises. There
   are six. Correct it to the **912-script** expanded denominator; do not alter
   actual catalog coverage to fit the stale prose.
2. `test/sql_shared_core_integration_test.dart:52`, `:53`, `:75`, `:156`, `:176`
   currently pin 126 and its visible count labels. Update those expectations
   alongside promotion to 306. The existing title-filter loop will then cover
   612 tutorial/example interactions.
3. `test/sql_curriculum_test.dart:28`/`:29` and `coverage.py:49` still accept
   110. Raise the shipped minimum to 306 and add the twelve new track minima
   of 15 to `coverage.py:28`, or use the explicit `--min 306` plus a persistent
   equivalent assertion. Keep original IDs 1–126 and outputs intact.
4. The schema's global `UPDATED_AT` is `2026-10-12` (`schema.py:24`). Relocated
   drafts inherit that value exactly; it is not an import/render drift. For the
   October 22 content release, update that batch metadata deliberately rather
   than implying the new lessons were updated October 12. Changing the global
   constant also changes original entries' metadata, so review that intended
   metadata-only diff separately from unchanged original code/expectations.

### Small teaching improvements worth making while still drafts

- `track_17_graph.py:50` (178) and `:74` (182): the diamond's alternative paths
  have equal lengths. The code and expected results are correct, but swapping
  MIN/MAX would not expose the difference being taught. Add a lesson-local
  unequal-length route or an exercise that gives different minimum/maximum
  depths; avoid changing the common graph fixture across all 15 topics unless
  all affected expectations are deliberately re-authored and checked.
- `track_21_intervals.py:33` (235): the fixture contains a nested interval but
  its following interval is already beyond the outer endpoint. Both a wrong
  LAG(e) algorithm and the correct historical MAX(e) produce the same groups
  here. A local fixture such as [1,10), [2,3), [4,5) makes the stated failure
  visible without replacing the entire track's fixture.
- `track_18_inventory.py:60` (193): the allocation uses nonnegative **on-hand**
  stock 8 and intentionally does not subtract reservation 3. Say explicitly
  that reservation is excluded from this lesson's allocation policy; the
  present phrase “可用现存” could be confused with lesson 188's available 5.
- `track_21_intervals.py:81` (243) has a small wording error: the final segment
  lacks a next upper bound, not a lower bound. At `:87` (244), prose says it
  counts overlaps per slot while the teaching query returns only free slot
  starts; align the explanation with its actual NOT EXISTS output.

These suggestions do not invalidate the previous output matches. If adopted,
refresh only affected execution evidence before promotion; do not label changed
draft source as covered by the current source-hash reports.

## Exact promotion mechanics after the original OHOS gate

Do **not** invoke `build_content.py --help` for discovery. It has no argument
parser and unconditionally calls `main` (`:128`, `:161`), writing both production
assets (`:150`/`:151`) even with `--help`. The two validators likewise have no
help parser. `coverage.py` is the one listed tool with actual `--min` support.

The following is an execution recipe for the coordinator **after** the actual
original OHOS gate and any selected draft corrections. It was not executed:

```powershell
$draftRoot = Join-Path (Get-Location).Path '.trellis/tasks/10-22-offline-ide-completeness/research/curriculum-drafts'
$lessonRoot = Join-Path (Get-Location).Path 'tool/sql_curriculum/lessons'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$tracks = @(Get-ChildItem -LiteralPath $draftRoot -Filter 'track_*.py' -File)
if ($tracks.Count -ne 12) { throw 'Expected exactly twelve draft tracks.' }
$helperDestination = Join-Path $lessonRoot '_advanced_authoring.py'
if (Test-Path -LiteralPath $helperDestination) { throw 'Review existing helper before overwriting.' }
foreach ($track in $tracks) {
    $destination = Join-Path $lessonRoot $track.Name
    if (Test-Path -LiteralPath $destination) { throw "Review existing track: $destination" }
}
[System.IO.File]::WriteAllText(
    $helperDestination,
    [System.IO.File]::ReadAllText((Join-Path $draftRoot '_draft_helpers.py')),
    $utf8NoBom)
foreach ($track in $tracks) {
    $source = [System.IO.File]::ReadAllText($track.FullName)
    $oldImport = 'from _draft_helpers import topic'
    if ([regex]::Matches($source, [regex]::Escape($oldImport)).Count -ne 1) { throw "Unexpected import in $($track.Name)" }
    $source = $source.Replace($oldImport, 'from lessons._advanced_authoring import topic')
    [System.IO.File]::WriteAllText((Join-Path $lessonRoot $track.Name), $source, $utf8NoBom)
}
python -B -X utf8 tool/sql_curriculum/build_content.py
if ($LASTEXITCODE -ne 0) { throw 'Content generation failed.' }
python -B -X utf8 tool/sql_curriculum/coverage.py --min 306
if ($LASTEXITCODE -ne 0) { throw 'Coverage check failed.' }
python -B -X utf8 tool/sql_curriculum/validate_content.py
if ($LASTEXITCODE -ne 0) { throw 'Authored-source execution failed.' }
python -B -X utf8 tool/sql_curriculum/validate_assets.py
if ($LASTEXITCODE -ne 0) { throw 'Packaged-asset execution failed.' }
flutter test --no-pub test/sql_curriculum_test.dart test/sql_curriculum_audit_test.dart test/sql_shared_core_integration_test.dart
if ($LASTEXITCODE -ne 0) { throw 'Catalog/consumer tests failed.' }
```

Stop on a failing command rather than continuing the sequence. Make the count
and chosen date changes above before generation/testing. The loader already
discovers all track files and excludes underscore-prefixed helpers; no discovery
list or shared-core edit is needed.

After generation, compare all in-memory source renders with both complete asset
entry lists, not just tutorial-to-example agreement. `validate_assets.py`
executes packaged assets but does not independently compare them to Python
authoring modules. This read-only Python check can be sent via stdin:

```python
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path.cwd() / 'tool/sql_curriculum'))
import schema
from build_content import audit, load_lessons, render_example
lessons = sorted(load_lessons(), key=lambda lesson: lesson.number)
audit(lessons)
assert [lesson.number for lesson in lessons] == list(range(1, 307))
assert sum(1 + len(lesson.exercises) for lesson in lessons) == 912
assert json.loads(schema.TUTORIAL_ASSET.read_text(encoding='utf-8'))['entries'] == [lesson.tutorial_entry() for lesson in lessons]
assert json.loads(schema.EXAMPLE_ASSET.read_text(encoding='utf-8'))['entries'] == [render_example(lesson) for lesson in lessons]
```

Do not rerun the current `verify_drafts.py` after promotion: its `load_lessons()`
will then load 306 and append the same 180 drafts again, deliberately failing
duplicate IDs. It is a pre-promotion evidence tool. Post-promotion checks use
the real source/assets validators plus a newly built **full 306/912 OHOS audit**.
Host validators must still label the six MySQL examples unexecuted; the native
catalog audit supplies their actual 12-script acceptance.

Expected product changes: twelve `tool/sql_curriculum/lessons/track_14..25_*.py`
files, `_advanced_authoring.py`, both SQL JSON assets, the two named Flutter
test files, `coverage.py`, and optional deliberate schema date update. Update
task/spec evidence to the new counts. Existing modules 1–13, native runtime,
core files and app content discovery require no change for promotion itself.
