# Parent Final Acceptance — SQL Home, Projects Page, and Lesson Curriculum

Parent: `.trellis/tasks/10-12-sql-curriculum-and-home`
Children: C1 `.trellis/tasks/10-12-sql-home-tree`,
C2 `.trellis/tasks/10-12-sql-lesson-curriculum`

Coordinated and accepted by the curriculum/coordinator worker (not main control).

## Cross-Child Acceptance Criteria

| AC | Criterion | Status | Evidence |
| --- | --- | --- | --- |
| AC1 | Home is the database/table tree; no home tab switching | PASS | `shows the database tree as the phone home body`; `desktop 1280 keeps the tree side panel beside the workspace` |
| AC2 | Projects on their own page; editing still works | PASS | `opens a single-toolbar standalone projects page`; `SqlProjectsPage` uses `ProjectStore`/`ProjectCard`/`EditorPage` |
| AC3 | Tutorial/example list + detail reachable; copy/import work | PASS | `opens injected tutorial and example content from home` + shared `CodeSnippet` import plumbing (unchanged) |
| AC4 | ≥110 real lessons (delivered 126) with full fields | PASS | `coverage.py` (126 lessons, all fields, no placeholders) |
| AC5 | ≥110 matching runnable examples (delivered 126), dialect labeled | PASS | `validate_content.py`; dialect label in summary/concepts/explain (126/126) |
| AC6 | No placeholder/TODO, no duplicated template bodies | PASS | `coverage.py` + `sql_curriculum_test.dart` uniqueness checks |
| AC7 | Every runnable example executed & verified; MySQL-only marked | PASS | 120/120 SQLite examples, 240/240 exercises; 6 MySQL lessons reported NOT executed |
| AC8 | Pre-existing dirty files / unrelated work preserved | PASS | No reset/format; sibling repo edits are other-language workers only |

Additional user-stated acceptance:
- Phone: home is the DB→table tree. PASS.
- Desktop: tree side panel + workspace. PASS.
- Projects page: one toolbar, no second home, original project operations kept. PASS (U2).
- 功能/终端/SQL 工具/设置 entries reachable. PASS (U1; 设置 via editor, unchanged).
- Refresh preserves manual collapse. PASS (U4).
- 390px and 1280px 2× text layout checks. PASS.
- Default `SqlContentRepository` exposes the 126 tutorials + 126 examples. PASS.

## Final combined verification (single Flutter worker)

```powershell
cd D:\MyNewProjects\qfli_sql
python tool\sql_curriculum\coverage.py         # coverage checks passed
python tool\sql_curriculum\validate_content.py # 120/120 examples, 240/240 exercises, 6 not executed
flutter analyze lib test                        # 1 pre-existing baseline info only (unrelated file); changed files net-pass
flutter test --no-pub                           # 65 passed, 2 skipped (exit 0)
```

## Reviews

- Content peer review: `.trellis/tasks/10-12-sql-lesson-curriculum/research/peer-content-review.md` (F1–F5 all resolved).
- UI peer review: `.trellis/tasks/10-12-sql-home-tree/research/peer-ui-review.md` (U1–U4, U6 fixed; U5 doc fixed).
- Child checks: C1 `check.md`, C2 `check.md`; validation report C2 `research/validation-report.md`.

## Known Limits (honest)

- 6 MySQL-specific lessons (121–126) are **not executed** on this host (no local
  MySQL server/client installed); they are reported as NOT executed, never as
  passing.
- Full-repo `flutter analyze` reports **1 pre-existing baseline info**
  (`lib/sql_document_service.dart` `unnecessary_import`) unrelated to this work;
  there are also ~1015 analyzer entries coming from generated `build/` copies in
  the broader baseline. All changed files are net-pass.
- Projects-page CRUD end-to-end assertions remain optional hardening (toolbar,
  search, menu, open, favorite covered; create→editor/delete e2e not asserted).
- **Out-of-scope observation (no action)**: the sibling repo
  `../qfli_studio_core` has 2 modified files (lib/pages/home_page.dart,
  lib/services/studio_profile.dart, adding `contentRepositoryFactory`) that this
  task did not author and `qfli_sql` does not reference. They belong to other
  parallel work and are retained as-is; no revert or reassignment. They are
  inert for this feature (the SQL app injects `SqlContentRepository` directly via
  `SqlWorkbenchPage(contentRepository:)`).
- No commits or pushes were made.

## Verdict

Both children meet their acceptance criteria; the parent's cross-child AC1–AC8
and the user's stated final acceptance points are verified. Ready for
commit/wrap-up on instruction.
