# UI Report — five-page SQL home shell (task 10-15-sql-release-readiness)

Owner: UI implementation worker (`lib/main.dart`, `lib/sql_app.dart`,
`lib/sql_workbench_page.dart`, `lib/sql_projects_page.dart`, new home-shell file,
UI tests).

Repository: `D:/MyNewProjects/qfli_sql` (verified cwd). Shared core
`../qfli_studio_core` consumed **read-only** at revision
`ad17f35ac728e19670de1df305bc3e55c3b5172c`. No core, curriculum, native runtime,
or other workspace file was edited.

## 1. Requirement implemented

PRD R3 / AC1: unify the SQL home locally into **exactly five swipeable PageView
destinations** — 数据库、项目、功能、教程、示例 — while preserving the database tree,
project editor, terminal and curriculum entries, and avoiding a double home /
duplicate toolbars. This supersedes the prior 10-12 no-home-tabs rule.

## 2. Changes (all inside qfli_sql)

### New: `lib/sql_home_shell.dart`
`SqlHomeShell` owns the top-level navigation:
- `PageView.builder` with `itemCount == 5`, key `sql-home-page-view`.
- Phone (`< 900px`): `NavigationBar` (bottom). Desktop (`>= 900px`):
  `NavigationRail` (extended at `>= 1200px`).
- The shell renders **no `AppBar`**. Each page keeps its own single toolbar, which
  is what removes the duplicate/stacked toolbar. Pages are built lazily and
  retained via the shared `RetainedPage` + `TickerMode`, so switching tabs does
  not re-query the workbench or re-parse content.
- Injects one shared `SqlContentRepository` into both 教程 and 示例.

### `lib/sql_app.dart`
`home:` now hosts `SqlHomeShell` instead of `SqlWorkbenchPage`.

### `lib/sql_workbench_page.dart` (数据库 page)
- New `embedded` flag. Embedded (in the shell):
  - hides the 项目 toolbar push (项目 is a sibling tab now);
  - drops the 更多 menu that pushed 功能/教程/示例 (they are tabs now).
  - keeps the database toolbar: engine menu, 刷新, tree/workspace body, and the
    phone back-to-tree affordance.
- Standalone mode (`embedded == false`, used by pushed routes/tests) keeps the
  old 更多 + 项目 actions, so no existing external behavior regresses.
- Offline defense-in-depth: `_offlineOnly` short-circuits a stale persisted
  `cloud` choice (`_initialize`) and ignores `_selectEngine(SqlEngineKind.cloud)`
  when the product profile is offline, so the offline UI can never open a network
  repository. The engine menu already only offered `SQLite` / `本机 MySQL`.

### `lib/sql_projects_page.dart` (项目 page)
- New `embedded` flag. Embedded: `automaticallyImplyLeading: false` and no
  "返回数据库" back button. It keeps its own **single** AppBar toolbar (title 项目,
  search toggle, 更多 menu), so the shell does not add a second toolbar.

### `lib/main.dart` (profile wiring)
- `sqlProfile.terminalCommandDelegate = SqlTerminalCommands.execute` so the
  standalone and editor terminals recognise the SQL product's commands (the
  class is authored by the native/terminal subagent in `lib/sql_runner.dart`;
  this worker did not implement it). Signature matches
  `TerminalCommandDelegate = Future<bool> Function(SandboxShellBackend backend, String command)`.

### Tests
- New `test/sql_home_shell_test.dart` (6 tests): five destinations; swipe to
  项目/功能/教程/示例; desktop rail + tree-beside-workspace; no second home
  toolbar/rail; embedded workbench hides 项目 push + 更多; 2× text scale.
- `test/sql_workbench_page_test.dart`: corrected the pre-existing broken
  expectation `内置终端` → `终端` (the shared `ToolsGrid` labels the quick entry
  终端), and added an offline reachable-UI test asserting no cloud/login/Git
  control renders.

## 3. Verification

| Command | Result |
| --- | --- |
| `flutter analyze lib/main.dart lib/sql_home_shell.dart lib/sql_app.dart lib/sql_projects_page.dart lib/sql_workbench_page.dart` | **No issues found** (after `SqlTerminalCommands` landed) |
| `flutter test test/sql_home_shell_test.dart test/sql_workbench_page_test.dart test/sql_app_test.dart` | **32/32 passed** |

`SqlTerminalCommands` now exists in `lib/sql_runner.dart` (line 340) with the
matching signature `Future<bool> Function(SandboxShellBackend, String)`, so
`lib/main.dart` resolves and the delegate is wired.

## 4. Offline audit (R2) — findings, reachable UI only

What is actually reachable from the SQL home shell's five tabs in the offline
SQL product:
- **数据库**: database tree + SQL workbench. Engine menu is hardcoded to only
  `SQLite` / `本机 MySQL`; no cloud, login or Git control, and no `云 MySQL` text
  renders.
- **项目**: local `ProjectStore` list and the shared `EditorPage` project editor.
- **功能**: shared `FunctionsTab`/`ToolsGrid` — local offline tools plus the
  terminal card only.
- **教程 / 示例**: shared `LocalTutorialsTab`/`ExampleCodeTab` over the app-local
  content repository.

Reachable-UI assertion (test `offline workbench exposes no cloud or login
controls`): the offline workbench renders no `云 MySQL`, no `登录`, no `Git`
text and no login/logout control.

### Correction: shared-core editor Git entry is NOT reachable offline
The earlier draft of this report claimed the shared-core editor's Git page was
unprotected. **That was a false positive and is withdrawn.** Re-inspection of
`../qfli_studio_core/lib/editor/editor_page.dart` shows the Git entry is guarded
twice for an offline product:
- the `'git'` `PopupMenuItem` is only built when
  `StudioProfile.current?.offlineOnly != true` (editor_page.dart ~line 1598); and
- the `'git'` case in the menu's `onSelected` dispatch only calls `_openGit()`
  when `StudioProfile.current?.offlineOnly != true` (editor_page.dart ~line 1432).

`_openGit()` (line 590) is the only caller of `GitPage`, and `GitPage(` appears
only there, so with `sqlProfile.isOffline == true` (→ `offlineOnly == true`) the
Git page — and its `git push` / `git pull` / `git remote add origin` actions in
`pages/git_page.dart` — cannot be reached from the SQL app UI. No core defect to
report here.

### Remaining core-adjacent item (not edited): stale `cloud` engine path
`lib/sql_runner.dart` `PreferredSqlEngine` and `lib/sql_engine_preference.dart`
still honor a stale persisted `"engine":"cloud"` and would construct
`CloudMySqlDatabase`. The workbench adds an app-local guard (see §2) so the
reachable offline UI never opens a network repository, but the runner/engine-
preference path itself remains the owning worker's follow-up.

## 5. Suggested commit (main coordinator serializes staging)

Scope: only this worker's files.
- `lib/sql_home_shell.dart` (new)
- `lib/sql_app.dart`
- `lib/sql_workbench_page.dart`
- `lib/sql_projects_page.dart`
- `lib/main.dart`
- `test/sql_home_shell_test.dart` (new)
- `test/sql_workbench_page_test.dart`

Suggested conventional message:

```
refactor(sql): unify home into five PageView destinations

Add SqlHomeShell owning 数据库/项目/功能/教程/示例 with a bottom
NavigationBar on phones and a NavigationRail on desktop, and no shell
AppBar so each page keeps a single toolbar. Embed the workbench and
projects page (hiding the duplicate 项目 push and 更多 menu), keep the
database tree, terminal and curriculum entries reachable, and block a
stale cloud engine choice in the offline UI.
```

Do **not** `git add .`; stage exactly the files above. The UI suite and analyze
are green; this batch is ready for the coordinator to stage and commit.

## 6. Handoff / freeze status

- UI source and UI tests are **frozen** for independent review. No further edits
  were made by this worker after the handoff request.
- No unlanded fix remains on this worker's side: all intended changes are on
  disk in the files listed in §5. In particular the offline stale-`cloud` guard
  in `lib/sql_workbench_page.dart` **is landed** (not pending).
- The only pending cross-worker coordination noted here is the runner/engine-
  preference stale-`cloud` handling (§4), owned by another worker.
