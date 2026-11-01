# Peer Content Review — SQL Curriculum (worker `pi-sql-curriculum-2`)

Scope of this review: independent, read-only quality review of lessons authored by
**other** workers, focused on the assignment "review track_01/02/03/08/09 and the
later-landed tracks (10–13)". Reviewer owns tracks 04–07 and did **not** modify
any other worker's file.

- Review date: 2026-10-12
- Reviewer: pi-sql-curriculum-2
- Method: read every lesson body by hand + a set of throwaway Python analyzers that
  (a) re-execute every example/exercise in an isolated fresh DB via
  `D:\ProgramFiles\platform-tools\sqlite3.exe`, (b) cross-check `explain` prose
  numbers/named entities against each lesson's own `setup`/`query`/`expected`,
  (c) check prompt-vs-answer intent, (d) check dialect/version visibility and
  duplicate bodies.
- No files owned by others were edited. No `flutter`, no commit/push.

## Verified range

| Track | Lessons | Reviewed | Result |
| --- | --- | --- | --- |
| 01 basics | 1–14 | yes (full) | pass, no defects |
| 02 functions | 15–30 | yes (full) | pass, no defects |
| 03 aggregation | 31–40 | yes (full) | pass, no defects |
| 08 ddl | 83–94 | yes (full) | 1 low finding (L91 ex1) |
| 09 dml | 95–102 | yes (full) | **1 real defect (L102 explain)** |
| 10 transactions | 103–108 | yes (full) | pass (prompts descriptive, OK) |
| 11 indexes | 109–116 | yes (full) | pass, no defects |
| 12 modeling/views | 117–120 | yes (full) | pass, no defects |
| 13 mysql | 121–126 | read | correctly marked `engine="mysql"` (not executed) |
| 04–07 (own) | 41–82 | spot-checked | **1 real defect (L82 explain, self-authored)** |

Authoritative repository checks (read-only, run by this reviewer):

```
python tool\sql_curriculum\validate_content.py
  sqlite examples passed: 120/120
  exercise answers passed: 240/240
  mysql not executed: 6   (L121-L126, correctly reported)
python tool\sql_curriculum\coverage.py
  total lessons: 126  (sqlite 120 / mysql 6)  coverage checks passed
```

## Findings

### F1 — L102 explain contradicts the data (real, reproducible) — owner of track_09
- Lesson: `sql-tutorial-102` "综合练习：幂等写入流水" (dml)
- Data: `ledger` rows B = 20, 0, 50; the setup deletes only the `amount = 0` row.
- `expected`: `A|150` / `B|70` (correct; 20+50=70).
- `explain` says: "账户 B 因两条被抵消只剩 50" — wrong. Nothing is "抵消", and B is 70, not 50.
- Why it slipped past automation: `validate_content.py` only checks SQL execution vs
  `expected`; the prose is never executed, and 50 *is* a legitimate value elsewhere in
  the data, so a naive numeric diff does not flag it.
- Suggested fix (owner): change to "账户 B 的 20 与 50 合计 70（0 金额行已被删除）".

### F2 — L82 explain contradicts the data (real, reproducible) — this reviewer's own file (track_07)
Self-reported for completeness since I authored it in an earlier session:
- Lesson: `sql-tutorial-082` "综合练习：销售分析报表" (windows)
- Data: rows Ann 30, Ann 60, Ben 40, Ben 55. Customer totals: Ann 90, Ben 95.
  Running total by id: 30, 90, 130, 185.
- `expected` is correct: shares `0.3333 / 0.6667 / 0.4211 / 0.5789`, running `30/90/130/185`.
- `explain` is wrong on three points:
  - "90 占 90 的 1.0" — row 2 amount is 60, share 0.6667 (not 90/1.0).
  - "Ben 40 占 40 的 1.0" — Ben total is 95, so 40/95 = 0.4211.
  - "累计按 id 排序为 30、120、185、225" — actual running total is 30, 90, 130, 185.
- This is in my own track (out of the strict assignment scope) and I will fix it in a
  follow-up edit if the integrator prefers not to; flagging so it is not lost.

### F3 — L92 exercises depend on session-scoped TEMP tables (medium, runtime-fragile)
- Lesson: `sql-tutorial-092` "临时表与内存表" (ddl)
- Setup creates `CREATE TEMP TABLE stage ...`; both exercise answers query `stage`.
- TEMP tables are **connection-scoped**. A runner that executes `setup` and the
  exercise `answer` in *separate* sqlite3 sessions will fail with
  `no such table: stage` (verified: two-process run gives rc=1).
- It currently passes only because `validate_content.py` was updated to run
  `setup + answer` in one session. That is a reasonable fix, but it means the
  exercise contract ("answer against a fresh copy of setup") is now
  session-coupled and would silently break in any runner that isolates them.
- Suggested owner action: either document that exercise verification is
  single-session, or make L92's exercises self-contained (e.g. use a normal table,
  or have the answer reference the base tables). Other tracks do not rely on TEMP.

### F4 — L91 exercise 1 prompt over-promises an action the query-only answer cannot perform (low)
- Lesson: `sql-tutorial-091` "DROP TABLE 与 IF EXISTS" (ddl)
- Prompt: "再次执行 DROP TABLE IF EXISTS tmp 后返回 keep 的 id（验证可重复执行）"
- Answer: `SELECT id FROM keep ORDER BY id;` — it never runs the DROP, so the
  "again run DROP" premise is not actually exercised. (Exercises are required to be
  query-only, so the prompt is what is wrong.)
- Suggested fix: reword to "tmp 已删除后，返回 keep 的 id" or state that repeatability
  is demonstrated by the lesson setup.

### F5 — Dialect/version not named in `explain` for ~54 lessons (low, consistency only)
- R6 requires dialect/version to be visible in **display fields**. That is satisfied
  for every lesson regardless of `explain`, because `schema.py` prepends the engine
  label to `summary` and `concepts` automatically (`SQLite 3.50 …`). So this is
  **not an AC violation**.
- It is an authoring-consistency gap: tracks 01/02/03 name the dialect/version in
  nearly every `explain`; tracks 05/06/07/08/09/10/12 mostly do not. Example:
  `sql-tutorial-055` ("NOT IN 与 NULL 陷阱") explains the NULL trap well but never
  states SQLite 3.50 behavior.
- Suggested owner action (optional): add one clause per explain naming the engine
  and the version-specific behavior relied on, matching track 01/02 style.

### Observations (no action needed)
- `expected` uses SQLite CLI `|` format and `(no rows)` sentinel correctly throughout;
  NULL renders as an empty field (checked in L44, L47, L55, L77, L80, L82).
- Track 13 MySQL lessons correctly set `engine="mysql"`, `version="8.0"`, and the
  validator lists all 6 under "not executed" — no false execution claim.
- Duplicate `explain` bodies: 0 across all 126 lessons. Duplicate `code` bodies: 0.
- 4 groups of lessons share an identical `expected` block (L34/L39, L54/L56,
  L59/L63, L62/L64). Each was verified to come from genuinely different setup data
  and queries, so this is not copy-paste; AC3 only forbids duplicate
  `explain`/`code`, which passes.
- No exercise answer is an exact copy of its lesson query.
- Authoring ownership: this reviewer's earlier direct check that used two sqlite3
  processes to validate exercises is now outdated; the repo validator runs
  setup+answer in one session. Findings above use the repo validator as authoritative.

## Limitations
- The review is prose-aware but heuristic for numbers: it cannot prove an `expected`
  was hand-derived rather than pasted. The strongest available signal — whether the
  `explain` states the same derivation the `expected` shows — is exactly what
  surfaced F1/F2; all other capstones (L40, L52, L62, L70, L82 expected, L94, L108,
  L116, L120) were checked by hand and their explain figures match.
- Tracks 13 (MySQL) cannot be executed here (no MySQL server); only syntax/version
  labelling and the "not executed" reporting were reviewed.
- Files were being actively edited by other workers during the window; the numbers
  above reflect the state at review time and were re-confirmed immediately before
  writing this report (126 lessons, validator green).
- No Flutter/analyze/test was run (out of scope / other worker exclusivity).
