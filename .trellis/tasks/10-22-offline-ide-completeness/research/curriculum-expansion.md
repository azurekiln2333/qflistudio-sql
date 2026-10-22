# Curriculum expansion draft evidence

Date: 2026-10-22. Status: **180 authored paired topics prepared, not shipped**.

## Boundary and required order

The coordinator's baseline source and packaged-JSON validators completed with
120/120 SQLite examples and 240/240 exercises passing. Six MySQL lessons were
explicitly not executed. This establishes a host baseline, not OHOS acceptance.
The user's requested order requires existing examples to pass on current OHOS
before expansion. New authoring therefore lives only in
`research/curriculum-drafts/`; no product authoring module, asset, count assertion,
native source, shared-core source or pre-existing WIP was modified for this slice.

## Authored scope

Exactly IDs 127–306, 180 new tutorials/examples, two independently authored
exercises each (360), two specific pitfalls per lesson, complete isolated setup,
display-visible SQLite 3.50 through the existing schema renderer, detailed
explanations and self-contained queries. Expectations were derived from fixture
semantics before execution. The verifier never rewrites authored expectations.

| Draft module | IDs | Distinct problems |
| --- | --- | --- |
| track_14_quality.py | 127–141 | Canonical duplicates, completeness, orphan references, survivorship, source reconciliation and rule reports |
| track_15_temporal.py | 142–156 | Half-open periods, calendar floor, ISO weeks, sparse calendars, fixed timezones, clipping and effective dates |
| track_16_json.py | 157–171 | JSON types/missing fields, relational array expansion, patches, ordering, shape validation and fanout |
| track_17_graph.py | 172–186 | Reachability, paths, BOM quantities, cycles, DAG layers, weighted paths, closure and terminal demand |
| track_18_inventory.py | 187–201 | Per-location balances, reservations, first negative, replenishment, order allocation, FIFO, expiry and counts |
| track_19_billing.py | 202–216 | Invoice balances, historical cutoffs, journal checks, largest remainder, tax rounding and integer FX |
| track_20_cohorts.py | 217–231 | User/event grain, retention, ordered funnels, sessions, streaks, maturity, recency and transitions |
| track_21_intervals.py | 232–246 | Overlap, sweep concurrency, merge islands, coverage, full free windows, capacity, grids and turnaround |
| track_22_window_details.py | 247–261 | GROUPS, frame exclusions, FILTER, chained windows, resets, weighted averages, distribution, median and fill |
| track_23_text_binary.py | 262–276 | Explicit ASCII rules, LIKE escaping, strict digits, literal/identifier quoting, Unicode bytes and BLOB inspection |
| track_24_integrity.py | 277–291 | Deferred/composite/cascade references, partial/expression uniqueness, triggers, views, guarded UPSERT and strict tables |
| track_25_relational.py | 292–306 | Relational division, empty sets, bags, Jaccard, pairwise coverage, weighted quotas and bounded set cover |

## Current evidence

`verify_drafts.py` reads only the task-local modules, combines their structural
audit with the original 126 authoring entries, checks unique titles/explanations/
full code bodies, and rejects any new literal-normalized teaching-query collision
with the baseline or another new lesson. It retains four pre-existing repeated
query patterns in its report without changing old lessons. Each exercise uses a
fresh isolated setup. Existing schema JSON rendering preserves exact code and
JSON-string exercise expectations. Product assets are hashed before and after.

Actual project SQLite C library validation:

```powershell
python -X utf8 .trellis/tasks/10-22-offline-ide-completeness/research/curriculum-drafts/verify_drafts.py --engine bundled --report .trellis/tasks/10-22-offline-ide-completeness/research/curriculum-drafts/bundled-host-results.json
```

Result: **180/180 examples, 360/360 exercises**, twelve tracks of fifteen,
product assets unchanged, exit 0. Engine is `native/build/windows/qfli_sqlite.dll`,
actual `sqlite3_libversion()` **3.50.0**, SHA256
`12bb8326b9ab400472d4b95596cb343512a10ab2ac6e40620e09df2da2c59f93`.
The ctypes harness executes `sqlite3_exec` against a new `:memory:` database and
connection for every script. This is actual bundled-engine host execution;
it does not establish current OHOS packaging, device behavior or MySQL acceptance.

The parallel CLI report command uses `--engine cli --report .../cli-host-results.json`.
Its engine is `D:/ProgramFiles/platform-tools/sqlite3.exe`, version 3.50.6. The
final report run passed **180/180 examples and 360/360 exercises**, including the
final graph exercise review.

Both JSON reports contain per-case SQL, authored-expected and observed-output
SHA256 hashes, return codes, match flags, engine identity and source hashes;
observed outputs are evidence only and never become authoring expectations.

Unchanged product asset SHA256:

- `sql_tutorials.json`: `0ea1071c1aa9a6611ebceba7c4b4a832f6f635f4b57e052406f6455c99e5a2e0`
- `sql_examples.json`: `cacfbf628a56fc42635764e3767981da14325eb9c8802cda94f5be0270276049`

## Failed attempts and corrections retained

- Two interval queries initially reused `r` already present in the shared CTE
  prefix; renamed their derived CTE to `gaps` and re-executed all drafts.
- A draft explanation's transition count and one gap-days exercise originally
  used inconsistent calendar/time reasoning; corrected the prose to two
  view→view transitions and calculated missing days from normalized dates.
- Windows GBK console encoding hid a Unicode mismatch; report output is now
  explicitly UTF-8.
- Host CLI `LOWER('Å')` produced `å` although its `NOCASE` did not equate Å/å.
  The initial lesson assumed base-amalgamation ASCII LOWER behavior. Replaced
  that extension-dependent lesson with an explicit, portable ASCII-only
  code-point transformation rather than copying host output into expectations.
  All examples then passed both the CLI and actual bundled 3.50.0 engine.
- An expanded duplicate check initially rejected four patterns already repeated
  only within the original 126 lessons. The audit now reports that baseline and
  still rejects any duplicate involving a new lesson; no baseline content changed.

## Promotion and remaining acceptance

After current existing-catalog OHOS acceptance passes, promote the twelve
`track_14..25` files to `tool/sql_curriculum/lessons/`, promote the presentation
helper under a hidden module name such as `_advanced_authoring.py`, and change
the modules' import from `_draft_helpers` to `lessons._advanced_authoring`.
The existing loader excludes hidden helper modules and discovers all track files.
No discovery list edit is needed. Render through `build_content.py`, run source
and packaged validators separately, update the count floor to at least 306, and
run the shared catalog Flutter test. Existing IDs and authored outputs 1–126 stay.

Full promoted denominator would be **306** examples/tutorials: **300 SQLite**, six
MySQL;600 SQLite exercises plus six MySQL exercises, for912 total scripts.
The earlier twelve-exercise estimate incorrectly assumed two per MySQL topic;
actual shipped MySQL topics each have one. Current product assets
remain **126**. Do not include drafts in the shipped-catalog OHOS denominator.
Current OHOS acceptance must subsequently cover all promoted entries. Native
MySQL, device builds/signing and product asset promotion remain coordinator-owned
gates; no device, native MySQL or publication pass is claimed here.
