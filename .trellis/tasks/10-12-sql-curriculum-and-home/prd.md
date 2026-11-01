# SQL Home, Projects Page, and Real Lesson Curriculum

## Goal

Make the SQL app (`qfli_sql`) usable as a real learning-plus-workbench product:

1. The **home screen is the database/data-table tree** — the primary surface for
   browsing databases and tables. Projects are no longer a home tab.
2. The **project list becomes its own page**, reached from home, with no
   home-level tab switching.
3. **Every placeholder tutorial and example is replaced** with 110+ substantive
   Chinese SQL lessons (target 120) spanning beginner to mastery, each paired
   with a complete, runnable SQL example. No templated filler, no TODOs.

This parent task owns the source requirement set, the child-task map, and the
cross-child acceptance criteria. Implementation happens in the two child tasks.

## Background

- The SQL app is a standalone Flutter app. `lib/main.dart` sets
  `StudioProfile.current = sqlProfile` with `showHomeTabs: false`, so the SQL
  app renders `SqlWorkbenchPage` directly (`lib/sql_app.dart`).
- Today `SqlWorkbenchPage` shows a database/table explorer (drawer under 700px),
  a data/schema/SQL segmented workspace, and an app-bar button that pushes the
  shared `HomePage` ("项目编辑器") for project editing.
- Tutorial and example content is bundled in the **sibling package**
  `../qfli_studio_core` as aggregate assets
  `assets/content/tutorials.json` and `assets/content/examples.json`
  (1.6MB / 3.5MB, 1600 entries each across 16 types).
- The current `sql` entries in those assets are placeholder-generated: 100
  tutorials + 100 examples whose text is generic ("输入、失败路径、边界条件")
  and whose "code" is a token query returning `weighted 22`. Titles repeat a
  template (`SQL 001: 数据建模与不变量`). This is exactly the content the user
  rejects.
- The existing task `10-01-tutorial-code-import` built MD3 content lists,
  `CodeSnippet`, `CodeImportService`, and editor/project import flows in the
  shared package. It is `in_progress` and **must not be archived, overwritten,
  or reverted**. Our work supersedes the *content* only; the import plumbing it
  built is reused.

## Scope

### In scope

- **C1 — Home tree + projects page.** Turn the SQL app home into a
  database/table tree list; move the project list to its own route/page; make
  tutorial and example lists reachable from home. No home tab bar or page
  switcher. Reuse the shared `HomePage`/`LocalTutorialsTab`/`ExampleCodeTab`
  widgets where possible, wrapping them in the SQL app's own navigation rather
  than forking them.
- **C2 — Lesson curriculum.** Replace all `sql` tutorial and example entries
  with 110+ (target 120) real, distinct Chinese SQL lessons and matching
  runnable examples, covering:
  - beginner: SELECT, filtering, sorting, DISTINCT, LIMIT
  - operators, functions, NULL semantics, CASE, date/time, strings
  - aggregation: GROUP BY, HAVING, aggregate functions
  - joins: INNER/LEFT/RIGHT/CROSS/self join
  - subqueries: scalar, IN/EXISTS, correlated
  - CTE / recursive CTE
  - window functions: OVER, PARTITION, ranking, running totals
  - DDL: CREATE/ALTER/DROP table, constraints (PK/FK/UNIQUE/CHECK/NOT NULL),
    defaults, generated columns
  - DML: INSERT/UPDATE/DELETE, UPSERT
  - transactions, isolation concepts, savepoints
  - views, indexes, execution plans (EXPLAIN / EXPLAIN QUERY PLAN)
  - normalization / data modeling
  - SQLite vs MySQL dialect differences, version notes
  - comprehensive capstone scenarios
- **Tutorial/example/list/detail/copy/import integration** works end to end for
  the SQL app: tutorial list → lesson detail, example list → example detail,
  copy code, import into editor/project.

### Out of scope

- Rewriting the shared import plumbing (`CodeImportService`, `CodeSnippet`)
  beyond what is required to consume the new content.
- Non-`sql` content types for other products (c, python, java, …).
- Native runtime / MySQL server lifecycle work (separate tasks).
- Committing or pushing (handled at wrap-up, only if authorized).

## Child Task Map

| Child | Directory | Deliverable | Owner |
| --- | --- | --- | --- |
| C1 | `.trellis/tasks/10-12-sql-home-tree` | Home = database/table tree, projects on own page, tutorials/examples reachable, no home tabs | pi-mysql (UI) |
| C2 | `.trellis/tasks/10-12-sql-lesson-curriculum` | 110+ (target 120) real SQL lessons + runnable examples, validated, wired into lists/details/import | curriculum owner |

C1 and C2 are independently verifiable. C1 depends on C2 only for *content
presence* (a large real catalog to render); C1 must render whatever catalog is
loaded and must not hard-code lesson content. C2 depends on C1 only for the
reachability path; C2 delivers content and its own list/detail wiring test.

## Cross-Child Acceptance Criteria

- [x] AC1 — SQL app home shows a database/table tree list as its primary
      surface; there is no home-level tab switching.
- [x] AC2 — The project list is on its own page reachable from home, and
      existing project editing still works.
- [x] AC3 — Tutorial list, example list, lesson detail, and example detail are
      reachable in the SQL app; copy and editor/project import work.
- [x] AC4 — The `sql` catalog contains ≥110 (delivered 126) distinct lessons with
      objectives, non-templated explanations, complete table setup + data +
      query, expected results, common pitfalls, exercises, and reference
      solutions.
- [x] AC5 — The `sql` catalog contains ≥110 (delivered 126) matching runnable
      examples; each is independently reproducible and dialect/version labeled.
- [x] AC6 — No placeholder/TODO text and no two lessons sharing duplicated
      template bodies; a mechanical de-duplication check passes.
- [x] AC7 — Every runnable example is executed against the supported SQL
      engine(s) and its expected result is verified; MySQL-only items are
      explicitly marked and not falsely reported as executed.
- [x] AC8 — Existing dirty files and unrelated work are preserved; no reset, no
      full-tree format, no unrelated native/repo edits.

Final acceptance evidence: `check.md` (this directory).

## Constraints

- Only project-existing dependencies may be used for implementation and tests.
- Do not modify `lib/main.dart` or `lib/sql_workbench_page.dart` in C2; UI
  ownership is C1 (pi-mysql). File ownership is proposed per child and any
  shared-content interface conflict is escalated to the parent/main control.
- Teaching data may be shared across lessons but each example must stand alone
  and be reproducible; teaching data exists only inside lessons/examples — no
  fake user database content.
- Tests and debugging are performed by the same worker that writes the code
  wherever possible.

## Open Questions

None blocking. Product decisions (home layout, project page placement) are
resolved in C1 `design.md`; content taxonomy is resolved in C2 `design.md`.
