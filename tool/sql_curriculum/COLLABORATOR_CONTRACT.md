# Collaborator Contract — SQL Curriculum Track Authoring

For the `pi-sql-curriculum-2` worker. Read this fully before writing anything.

## Mission

Add exactly these four lesson-definition files under `tool/sql_curriculum/lessons/`:

| File | Track | Lessons | Range |
| --- | --- | --- | --- |
| `track_04_joins.py` | joins | 12 | 41–52 |
| `track_05_subqueries.py` | subqueries | 10 | 53–62 |
| `track_06_cte.py` | cte | 8 | 63–70 |
| `track_07_windows.py` | windows | 12 | 71–82 |

Total **42 lessons** (41–82 inclusive). Do not touch any other file.

## Hard Rules

- You own ONLY those four new files. Do not edit `schema.py`,
  `build_content.py`, `validate_content.py`, `coverage.py`, `helper.py`,
  `track_01/02/03`, `lib/`, `pubspec.yaml`, the task files, or anything in
  `../qfli_studio_core`.
- Do not commit or push.
- Every lesson must be real teaching content, no templated filler, no `TODO`.
- Do not run `flutter` commands. Do not run `build_content.py` against the
  shared repo if another worker might be editing — instead validate your files
  with your own throwaway command (see below). The integrator runs the real
  build + validate.

## Schema Contract

Import from the shared helper (already present, read-only for you):

```python
from lessons.helper import E, L
LESSONS = [ L(...), ... ]
```

`L(...)` signature (all keyword after the first six):

```python
L(number, slug, title, level, track,
  concepts=[...], objective="...", prerequisites=["..."],
  explain="...",
  setup="CREATE TABLE ...;\nINSERT ...;",   # DDL + data only
  query="SELECT ...;",                       # the teaching query
  expected="col1|col2\nv1|v2",               # authored expected output
  pitfalls=["...", "..."],
  exercises=[E("prompt","hint","answer SQL","expected output"), ...])
```

`E(prompt, hint, answer, expected)`:
- `answer` is a **query-only** statement (SELECT/WITH). It is executed against
  the lesson's `setup` in a fresh database.
- `expected` is the authored expected output in SQLite CLI `|` row format.
  For an empty result set use the literal `"(no rows)"`.

Reference: `tool/sql_curriculum/lessons/track_03_aggregation.py` (read it) shows
the exact style and quality bar.

## Expected-output format

- SQLite CLI default output: fields joined by `|`, one row per line, NO header.
- Floats render as SQLite does (e.g. `250.0`, `132.5`).
- NULL renders as empty field (e.g. `Bob|`).
- You MUST derive `expected` from the taught semantics, not guess. Then run the
  local check below until it passes.

## Local self-check (does not touch shared outputs)

Create a throwaway script that imports ONLY your modules and executes them, or
run the project validator with your tracks present and then remove nothing —
the integrator will run the real one. Minimal safe loop:

```powershell
cd D:\MyNewProjects\qfli_sql
python tool\sql_curriculum\validate_content.py
```

This validates all tracks currently present. It writes no files. If the
integrator's own tracks are mid-edit this could momentarily fail on their
lessons; if that happens, use this targeted check instead:

```powershell
python - <<'PY'
import sys, subprocess, tempfile, shutil
from pathlib import Path
sys.path.insert(0, "tool/sql_curriculum")
sys.path.insert(0, "tool/sql_curriculum/lessons")
import importlib
SQLITE = r"D:\ProgramFiles\platform-tools\sqlite3.exe"
mods = ["track_04_joins","track_05_subqueries","track_06_cte","track_07_windows"]
bad = 0
wd = Path(tempfile.mkdtemp())
for m in mods:
    mod = importlib.import_module(m)
    for les in mod.LESSONS:
        db = wd / (les.tid + ".db")
        p = subprocess.run([SQLITE, str(db)], input=les.code, capture_output=True, text=True, encoding="utf-8")
        if p.returncode != 0 or p.stdout.strip() != les.expected.strip():
            bad += 1
            print("FAIL", les.tid, repr(p.stdout), repr(les.expected), p.stderr[:120])
shutil.rmtree(wd, ignore_errors=True)
print("done, failures:", bad)
PY
```

(The heredoc form is bash; on PowerShell use a `.py` file in your own temp dir.)

## Quality bar (from main control)

- Beginner tracks explain syntax + intent; **advanced tracks (windows, CTE)
  must explain boundaries, performance characteristics, and real use cases**,
  not just one line of syntax.
- The explain paragraph MUST be consistent with the actual data and query
  (audit it: names, numbers, order). Do not describe a value that is not in the
  data.
- `explain` must state the dialect/version (SQLite 3.50) and why the expected
  result holds.
- Each lesson: objective, prerequisites, explain, complete runnable setup+query,
  expected output, pitfalls, and 2 exercises with answers and expected output.
- No two `explain` or `code` bodies may be identical across lessons.

## Your coverage map

- **Track 4 joins (41–52):** CROSS JOIN/cartesian, INNER, multi-table order,
  LEFT JOIN + missing rows, LEFT JOIN + IS NULL anti-join, RIGHT JOIN,
  FULL OUTER (dialect note), self-join, non-equi/range join, USING vs ON,
  join+aggregation, capstone multi-table report.
- **Track 5 subqueries (53–62):** scalar, IN, NOT IN + NULL trap, EXISTS,
  NOT EXISTS, correlated, derived table (FROM subquery), rewrite subquery as
  join, ANY/ALL comparison, aggregate subquery, capstone.
- **Track 6 CTE (63–70):** WITH basics, multiple/chained CTEs, CTE vs subquery
  trade-off, recursive basics, hierarchy, number/date series, cycle/termination
  guard, capstone org-path.
- **Track 7 windows (71–82):** OVER concept, PARTITION BY, ORDER BY + ROWS/RANGE
  frame, ROW_NUMBER, RANK/DENSE_RANK, NTILE, LAG/LEAD, FIRST_VALUE/LAST_VALUE,
  running total + moving average, period-over-period, per-group Top-N/dedup,
  capstone analytics.

## Reporting back

When done, reply to the integrator with: files written, lesson count, the exact
self-check command you ran and its output summary. The integrator (`wC:p3`)
will run the authoritative build + validation and integrate.

## Progress file (optional, recommended)

Append short status lines to `tool/sql_curriculum/lessons/_collab_status-2.md`
(your own file) so the integrator can see progress without interrupting you.
