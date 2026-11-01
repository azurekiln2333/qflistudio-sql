# C1 Verification — SQL Home Tree + Standing-alone Projects Page

Verified by: UI owner (pi-mysql) + independent read-only cross-review
(pi-sql-curriculum-2, `research/peer-ui-review.md`) + integration re-check by the
curriculum/coordinator worker.

## Delivered

- Home body is the **database → table tree** (phone <700px: tree is the body with
  a back affordance to return from the workspace; desktop ≥700px: 252px side
  panel + workspace).
- **Standalone projects page** (`lib/sql_projects_page.dart`): self-contained
  single `Scaffold`/`AppBar('项目')`, no second home, reuses `ProjectStore`,
  `ProjectCard`, `ProjectDialogs`, `EditorPage`.
- Tutorials/examples reachable from home via the injected
  `SqlContentRepository` (C2's `lib/sql_content_repository.dart`).
- 功能 entry restored: workbench 更多 menu → `FunctionsTab` →
  `TerminaxTerminalPage` (终端) + `ContentToolsPage` (SQL 工具).
- Manual database collapse survives refresh (`_collapsed` set).

## Cross-review findings resolution (U1–U6)

| ID | Finding | Status |
| --- | --- | --- |
| U1 | 功能/终端/内容工具 unreachable | FIXED (code + test) |
| U2 | Projects page double app bar | FIXED (single toolbar; test asserts one AppBar) |
| U3 | No 1280 / desktop 2× test | FIXED (both tests added) |
| U4 | Collapse undone by refresh | FIXED (`_collapsed` set + test) |
| U5 | Spec stale re: HomeTab/drawer | FIXED (spec updated) |
| U6 | No 功能 reachability test | FIXED (test added); projects CRUD e2e remains optional hardening |

## Acceptance evidence

`test/sql_workbench_page_test.dart` (all passing):
- `shows the database tree as the phone home body`
- `desktop 1280 keeps the tree side panel beside the workspace`
- `desktop 1280 at 2x text scale does not overflow`
- `phone home tree survives 2x text scale without overflow`
- `opens a single-toolbar standalone projects page`
- `manual collapse of the active database survives refresh`
- `restores the 功能 entry so terminal and SQL tools stay reachable`
- `opens injected tutorial and example content from home`

## Commands and results

```powershell
cd D:\MyNewProjects\qfli_sql
flutter analyze lib test      # 1 pre-existing baseline info only
                              # (lib/sql_document_service.dart unnecessary_import);
                              # all changed files net-pass
flutter test --no-pub         # 65 passed, 2 skipped (exit 0)
```

## Limits

- Independent review (U1–U6) was static/read-only, not test-executing; the
  coordinator's combined `flutter test` run above is the execution evidence.
- Projects-page CRUD (create→editor/open/favorite/delete) is partially covered;
  treated as optional hardening, not a blocker.
- No commits/push.
