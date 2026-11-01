# Home = real DB/table tree; projects as a separate page (read-only investigation)

Status: READ-ONLY design. No product code written. Awaiting task path + approval.

## Goal (user)

- App home is the real database → table tree list (expand/collapse, select a
  table to enter the existing data/SQL workflow).
- The project list becomes its own page reached via normal navigation.
- Remove the "two homes / home-mode switch".
- Keep all other navigation and the SQL workbench capability.
- Tutorial content is owned by the sibling `pi-sql-curriculum` task.

## Current wiring (evidence)

- `lib/main.dart` sets `StudioProfile.current = sqlProfile` and runs
  `SqlLabApp`. It defines `sqlProfile` with `showHomeTabs: false`, templates
  `[empty, sql]`, `runner: SqlProgramRunner()`, `supportedFileExtensions: ['.sql']`,
  `entryFileNames: ['main.sql','src/main.sql']`.
- `lib/sql_app.dart`: `SqlLabApp.home` is already
  `SqlWorkbenchPage(store, auth, settings)` (after `SplashScreen`). So the
  workbench is already the app's home widget.
- `lib/sql_workbench_page.dart` (2075 lines) already contains:
  - `_explorer()` — a database list with expandable tables
    (`_databases`, `_tables`, `_database`, `_table`, select/create/delete/rename/
    schema/export), currently rendered in a left `SizedBox(width: 252)` on wide
    screens or a `Drawer` on narrow (`< 700`) screens.
  - `_workspace()` — `_view` switch over data / schema / query panels.
  - AppBar actions: engine menu (SQLite/localMysql), refresh, and a
    **"项目编辑器" button that pushes `HomePage`** (shared core project shell).
- Shared core `D:/MyNewProjects/qfli_studio_core/lib/pages/home_page.dart` is the
  project shell (`HomePage` + `HomeTab`); `StudioProfile.showHomeTabs` controls
  only the project-scope sub-tabs inside `HomeTab`, not a home switch.
- `StudioProfile` has **no `homeBuilder`** extension point; the app already owns
  its own home by setting `MaterialApp.home`. The shared `HomePage` is only
  reached via the pushed "项目编辑器" route.

## Interpretation of "两个主页/主页模式切换"

The two "homes" are: (a) the app's `SqlWorkbenchPage` home and (b) the shared
`HomePage` project shell pushed by the "项目编辑器" button. There is no literal
mode toggle in app-local code; the perceived "switch" is this pushed project
shell vs the workbench home. The change is therefore a **navigation
restructure**, not removal of a core API.

## Recommended design (app-local only; no sibling-repo edits)

1. **Home = database tree** (already exists). Make the database→table tree the
   primary home surface rather than a side pane:
   - Wide: keep the tree as the primary left column but default-open the
     database list; add explicit expand/collapse state per database
     (`Set<String> _expanded`) so databases expand/collapse independently and a
     table tap enters the existing `_selectTable` → data/query workflow.
   - Narrow: the tree becomes the home body (a full-screen list navigating into
     the workspace), not just a drawer; keep a back affordance to the tree.
   - Loading/error/empty states: reuse `_loadError` + retry, add an explicit
     empty state ("暂无数据库" + create) when `_databases` is empty.
2. **Projects as a separate page**: replace the AppBar "项目编辑器" icon push
   with a normal navigation entry that routes to the existing shared `HomePage`
   (project list). Keep `HomePage` reachable but no longer as a competing home;
   label it "项目" and reach it from the tree's app bar / navigation rail.
3. **No nested second home / no switch**: ensure only one home widget
   (`SqlWorkbenchPage`); the project page is a pushed route, not a tab in the
   workbench and not a mode of the home.
4. **Preserve**: SQL engine selection (`sql_engine.json`), persistence, the
   import/tutorial activation contract (`SqlProgramRunner`/`NativeMySqlEngine`,
   `LocalTutorialsTab`/`ExampleCodeTab` in core), and the workbench data/schema/
   query panels.
5. **Mobile/desktop**: `< 700` narrow vs wide layout; keep horizontal scroll on
   the data grid.

### Files likely enough

- `lib/main.dart` (profile labels / route wiring if needed).
- `lib/sql_workbench_page.dart` (home tree + project-page navigation).
- `lib/sql_app.dart` (if a named route or home change is needed).
- `test/sql_workbench_page_test.dart` (extend) and possibly a new
  navigation/tree widget test.
- `.trellis/spec/frontend/sql-workbench.md` (UI spec update).

### Possibly additional files (report to main control)

- A small new widget file, e.g. `lib/database_tree.dart`, if extracting the tree
  keeps `sql_workbench_page.dart` manageable (currently 2075 lines). Otherwise no
  new file is strictly required.
- If a dedicated "项目" page wrapper is wanted instead of reusing core
  `HomePage` directly, a thin `lib/projects_page.dart` would be added. Reusing
  core `HomePage` avoids sibling-repo changes and is preferred.

No sibling-repo (`../qfli_studio_core`) change is required or planned.

## Validation commands (to run after implementation)

- `flutter analyze --no-pub`
- `flutter test --no-pub` (esp. `test/sql_workbench_page_test.dart`,
  `test/sql_app_test.dart`)
- `integration_test/sql_workbench_test.dart` if a device/emulator is available
  (may be out of scope per this task's note).

## Constraints honored

- Read-only now; no product code, no revert/reset/format, no unrelated native
  changes, no commit/push. Preserves the 109 uncommitted changes.
