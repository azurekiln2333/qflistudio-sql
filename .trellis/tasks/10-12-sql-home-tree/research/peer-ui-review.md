# Peer UI Review — SQL Home Tree + Projects Page (C1 / pi-mysql)

## Re-review status (round 3, final read-only)

| Item | Round-1 finding | Round-3 status |
| --- | --- | --- |
| U1 | 功能/终端/内容工具 unreachable | **FIXED** (code + test) |
| U2 | `SqlProjectsPage` double app bar | **FIXED** (code + test) |
| U3 | no 1280 / no desktop 2× test | **FIXED** (both tests) |
| U4 | collapse undone by refresh | **FIXED** (code + test) |
| U5 | spec stale re: HomeTab/drawer | **STILL OPEN** (doc only) |
| U6 | no test for 功能 reachability / project CRUD flows | **FIXED** (功能 test added; CRUD still partial) |

Round-3 verdict: U1–U4 and U6 are fixed and verified read-only. The only
residual is **U5**, a stale spec paragraph (no functional impact). No functional
blocker remains.

---

## Re-review status (round 2, after fixes)

| Item | Round-1 finding | Round-2 status |
| --- | --- | --- |
| U1 | 功能/终端/内容工具 unreachable | **FIXED** (code verified; test gap → U6) |
| U2 | `SqlProjectsPage` double app bar | **FIXED** (single toolbar; test asserts one AppBar) |
| U3 | no 1280 / no desktop 2× test | **FIXED** (both tests added) |
| U4 | collapse undone by refresh | **FIXED** (`_collapsed` set + test) |
| U5 | (new) spec stale re: HomeTab/drawer | open (doc only) |
| U6 | (new) no test for 功能 reachability / project CRUD flows | open (test only) |

Round-2 verdict: all four original defects are fixed in code. Remaining items
are documentation (U5) and test coverage (U6); no functional blocker found in
this read-only pass.

---

# Peer UI Review — SQL Home Tree + Projects Page (C1 / pi-mysql)

Independent, read-only cross-review by `pi-sql-curriculum-2`, requested by main
control. **No UI file was modified. No `flutter` was run** (UI owner holds the
toolchain). Existing dirty changes were preserved.

- Baseline note (correction): the dirty change set is **109 pre-existing files**
  at HEAD; the working-tree total grows as new work lands. Earlier wording in my
  round-1 report that cited the running total as the baseline was inaccurate.
- Task under review: `.trellis/tasks/10-12-sql-home-tree` (owner `pi-mysql`)
- Files reviewed: `lib/sql_workbench_page.dart` (diff vs HEAD), `lib/sql_projects_page.dart`,
  `lib/sql_app.dart`, `lib/main.dart`, `test/sql_workbench_page_test.dart`,
  `.trellis/spec/frontend/sql-workbench.md`, plus read-only shared
  `../qfli_studio_core/lib/pages/home_page.dart` and
  `../qfli_studio_core/lib/pages/quick_tools_page.dart`.
- Method: static trace of the widget/navigation graph, HEAD-vs-working-tree diff,
  reachability grep of `lib/`, and inspection of the owner's tests. No candidate
  defect below is architecture critique; each is a concrete, reproducible gap
  against the task's own PRD/AC.

## Verified good (no action)

- **Phone tree is the home body.** `showWorkspace = !narrow || _mobileShowWorkspace`
  (workbench ~L1244); at <700px with `_mobileShowWorkspace=false` the body is
  `SafeArea(_explorer())`, not a drawer. `_mobileShowWorkspace` is set true only
  in `_selectTable` (L417); the app-bar leading back affordance (L1247-1251)
  returns to the tree. Matches R6.
- **Independent expand/collapse.** `_toggleDatabase` (L367-379) adds/removes one
  name in `_expanded` and lazily loads+caches `_expandedTables[name]`; the
  chevron toggles expansion while the row tap selects (`_selectDatabase`). The
  active DB is expanded by default (`_refreshTree` L291). Matches the spec contract.
- **No second-home navigation on the projects route.** `SqlProjectsPage` renders
  only `Scaffold(AppBar('项目'))` + `HomeTab`; there is no `NavigationRail`,
  `NavigationBar`, `PageView`, or shared `HomePage` shell. With
  `sqlProfile.showHomeTabs == false`, `HomeTab` also hides its project-scope
  `TabBar` (`home_page.dart` L446 `if (showHomeTabs ?? true)`). The owner's test
  asserts `NavigationRail`/`NavigationBar` are absent. Matches R2/R3.
- **Tutorials/examples use the injected `SqlContentRepository`.** `_openTutorials`
  / `_openExamples` (L1360-1400) pass `repository: _contentRepository`, which
  defaults to `SqlContentRepository()` (`widget.contentRepository ?? ...`, L84)
  and is injectable for tests. Matches C2 interface + R7.
- **Original workbench feature set preserved.** Engine menu (L1265-1295), refresh,
  database/table create/delete/rename/schema/export, busy-gating, query history
  and saved queries all remain; the owner's tests still cover them.

## Findings (real, reproducible)

### U1 — 功能页（终端 / SQL 工具）入口整体丢失（functional regression, high）
- **Before (HEAD):** `lib/sql_workbench_page.dart` imported `home_page.dart` and
  pushed the shared `HomePage`. For the SQL profile `HomePage._buildPage` exposes
  four destinations: 项目(`HomeTab`), **功能(`FunctionsTab`)**, 教程, 示例. The
  `FunctionsTab` (`quick_tools_page.dart`) forwards to **`TerminaxTerminalPage`**
  (终端) and, because `sqlabKey ∈ _isContentProduct`, to **`ContentToolsPage` →
  `SqlToolPage`** (SQL 工具 / 内容工具).
- **After (working tree):** the workbench pushes `SqlProjectsPage`, which hosts
  **only** `HomeTab`. `HomeTab`'s own "更多" menu is limited to 添加已有项目 /
  新建云项目 / 移除缺失项目 — it has **no** 功能 entry.
- **Evidence:** `grep` over `lib/*.dart` for `HomePage|FunctionsTab|TerminaxTerminalPage|ContentToolsPage`
  returns **nothing** in the working tree; `git show HEAD:lib/sql_workbench_page.dart`
  shows the removed `HomePage` push. So 终端 and SQL 内容工具 are unreachable from
  any screen in the app.
- **Against:** PRD R2 ("other product entries (功能/设置/教程/示例) must remain
  reachable") and AC-adjacent requirement; the updated spec silently narrows the
  guarantee to "教程/示例/刷新/引擎 stay reachable" (`sql-workbench.md` §3), which
  documents rather than fixes the loss.
- **Repro:** launch → workbench → only 项目/教程/示例/刷新/引擎 are offered;
  no path opens FunctionsTab, TerminaxTerminalPage, or SqlToolPage.
- **Suggested fix (pi-mysql):** add a 功能 entry that again reaches
  `FunctionsTab` (terminal + content tool). Since the shared package is
  read-only, expose it as a pushed route from the workbench "更多" menu or from
  `SqlProjectsPage`; the callbacks can construct `TerminaxTerminalPage(store:)`
  and `ContentToolsPage(store:)` directly. Confirm 设置 remains reachable via the
  project editor (it does today: `profile_page.dart` / `editor_page.dart` push
  `SettingsPage`), and record it in the spec.

### U2 — `SqlProjectsPage` renders two stacked app bars (double toolbar / second home title, medium)
- `SqlProjectsPage` (lib/sql_projects_page.dart) is
  `Scaffold(appBar: AppBar('项目'), body: HomeTab(...))`.
- **`HomeTab` itself returns `Scaffold(appBar: AppBar(title: StudioProfile.current?.appTitle ...))`**
  (`home_page.dart` L353-368) with `automaticallyImplyLeading: false`. For the SQL
  profile that inner title is `QFLISQLab`.
- Net effect on the pushed "项目" page: the user sees **two app bars stacked** —
  an outer "项目" bar (with back) and an inner "QFLISQLab" bar (no back). This is
  the "第二主页标题 / 双工具栏" the main control flagged, and it visually reads as
  a second home even though there is no rail/PageView.
- **Repro:** open 项目; the header shows "项目" immediately above a full-width
  "QFLISQLab" bar.
- **Suggested fix (pi-mysql):** do not stack a Scaffold around a widget that
  already owns a Scaffold/AppBar. Either (a) host a local project list (or use the
  shared `HomeTab` via a route that suppresses chrome) — but the shared widget is
  read-only, so the cleanest local option is to build a thin project page that
  reuses `ProjectStore`/`HomeTab`'s list pieces without the inner Scaffold, or
  (b) if `HomeTab` must be reused as-is, present it as the *only* surface (e.g.
  push it without an outer AppBar and rely on its own leading/back) rather than
  double-framing. Report the shared-interface limitation if an edit to
  `home_page.dart` is genuinely required.

### U3 — Desktop 1280px + desktop 2× text scale is uncovered (test gap, medium)
- `test/sql_workbench_page_test.dart` uses only two sizes: **1100×800** (dpr 1,
  many tests) and **390×800** (dpr 1). The only 2× text-scale test is the phone
  one (390, L174-179).
- There is **no test at 1280px**, and **no desktop 2× test**. AC6 explicitly
  requires the tree to render "as a side panel at 1280px ... without overflow at
  2× text scale". The owner's reported verification ("390 的 2x; 1280 沿用旧
  1100/1280") leaves the desktop 2× clause unverified.
- Additionally, no test asserts the **side-panel layout** itself (tree width 252 +
  `VerticalDivider` beside the workspace) — the 1100 tests exercise behavior but
  not the ≥700px layout contract.
- **Repro/check:** search the test file for `1280` or a desktop-wide
  `textScaleFactor` — none exist.
- **Suggested fix (pi-mysql):** add a 1280×800 dpr-1 test asserting the explorer
  side panel + workspace coexist (e.g. 数据库 label visible, no `返回数据库`
  leading, table selectable), and one 1280×800 **2.0** text-scale test asserting
  `tester.takeException() == null` with both panel and workspace mounted.

### U4 — Collapsing the active database is undone by any refresh (minor UX inconsistency)
- `_refreshTree` unconditionally runs `_expanded.add(selectedDatabase)` (L291)
  whenever a database is selected. The toolbar refresh (L1343-1348) and
  `_selectDatabase` (L399) both call `_refreshTree`.
- So if the user collapses the active database via the chevron (`_toggleDatabase`
  removes it from `_expanded`) and then taps 刷新 (or re-selects the same
  database), it silently re-expands. This contradicts the spec's "chevron controls
  collapse" / independent-collapse intent (spec §4 "Database row tap … keep/expand
  it (chevron controls collapse)").
- **Repro:** expand `work`, collapse it with the chevron, tap 刷新 — `work` is
  expanded again.
- **Suggested fix (pi-minor):** track an explicit user-collapsed set (or only
  auto-expand on first load / when the selected database changes), so a manual
  collapse survives refreshes. Low severity, no data loss.

## Test-coverage summary (as found)

| Scenario | Covered? |
| --- | --- |
| Phone tree is home body, no drawer, tap table → back | yes (390) |
| Independent expand/collapse | yes (1100) |
| Projects page without NavigationRail/NavigationBar | yes (1100) |
| Injected tutorials/examples open | yes (1100, fake repo) |
| Phone 2× text scale, no overflow | yes (390) |
| **Desktop 1280 layout (side panel)** | **no** |
| **Desktop 2× text scale** | **no** |
| **功能/终端/内容工具 reachability** | **no (feature lost, U1)** |
| Double-app-bar on 项目 page | **no** |

## Limitations
- Review is static + test inspection; no `flutter test`/`analyze` was run here
  (UI owner owns the toolchain, and the working tree has unrelated dirty files).
- `1920`/`physicalSize` semantics: tests set `devicePixelRatio = 1`, so 1100/390
  are treated as logical px; the 1280 requirement is therefore also a logical-px
  check and is genuinely absent.
- Reachability conclusions are based on a full `lib/` grep plus the HEAD diff; if
  the owner adds a 功能 entry after this review, U1 should be re-checked.
- U2 assumes `HomeTab` continues to own its `Scaffold`; this was confirmed in the
  read-only shared source at review time.

---

## Round-2 detailed verification (read-only, no flutter)

### U1 — FIXED (code)
- `lib/sql_workbench_page.dart` now imports `quick_tools_page.dart`
  (`FunctionsTab`, `ContentToolsPage`) and `terminax_terminal_page.dart`
  (`TerminaxTerminalPage`) (L7-10).
- The app-bar 更多 menu now has three items 功能/教程/示例 (L1318-1330);
  selecting 功能 calls `_openFunctions()` (L1390-1406), which pushes
  `FunctionsTab(onOpenTerminal: → TerminaxTerminalPage(store:), onOpenContentTool:
  → ContentToolsPage(store:))`. Both callbacks push ordinary routes, so 终端 and
  SQL 内容工具 are reachable from the home workbench again.
- `grep lib/*.dart` now finds `FunctionsTab`/`TerminaxTerminalPage`/`ContentToolsPage`
  in `sql_workbench_page.dart`; the U1 regression is resolved.

### U2 — FIXED (code + test)
- `lib/sql_projects_page.dart` is now a self-contained `StatefulWidget` with its
  **own single** `Scaffold`+`AppBar('项目')`; it no longer embeds `HomeTab`. It
  reuses public APIs directly: `ProjectStore` (load/remove/deleteProject/touch/
  setFavorite), `ProjectCard`, `showCreateProjectDialog`, `showAddExistingDialog`,
  `showDeleteProjectConfirm`, and pushes `EditorPage` on open. All referenced APIs
  exist in the shared package (verified `project_store.dart` L68/455/463/501/561,
  `project_dialogs.dart` L15/26/37).
- Confirmed connectivity of the asked flows: 创建 (`_createProject`),
  搜索 (`_searchOpen` + `_visible` name/path filter + 关闭搜索), 打开
  (`_openProject`, missing-path snackbar), 收藏 (`ProjectCard.onToggleFavorite →
  store.setFavorite`), 删除 (`_deleteProject`), 添加已有 (`_addExisting`),
  缺失处理 (`_removeMissing`).
- Test `opens a single-toolbar standalone projects page` asserts exactly one
  `AppBar`, no `QFLISQLab` title, no `NavigationRail`/`NavigationBar`, search
  toggle stays in the same bar, and `移除失效项目` remains in the 更多 menu.

### U3 — FIXED (tests)
- `test/sql_workbench_page_test.dart` now has
  `desktop 1280 keeps the tree side panel beside the workspace` (1280×800, asserts
  数据库/work/people + Ada coexist and no mobile 返回数据库) and
  `desktop 1280 at 2x text scale does not overflow` (1280×800, scale 2.0,
  `takeException()==null`). The AC6 desktop clause is now covered.

### U4 — FIXED (code + test)
- `_collapsed` set added (L67), maintained in `_toggleDatabase` (collapse adds,
  expand removes; L382/L393) and `_refreshTree` only auto-adds the active database
  when `!_collapsed.contains(selectedDatabase)` (L299-301); pruned with the other
  caches (L294). `manual collapse of the active database survives refresh` test
  asserts `people` stays hidden after 刷新.

### U5 — spec is stale (documentation only)
- `.trellis/spec/frontend/sql-workbench.md` still says the projects page "hosts
  the public `HomeTab`" (L8-10 and L31-32) — no longer true after the U2 fix — and
  still says "Use a drawer below 700 logical pixels" (L35), which contradicts the
  line just above it and the implementation (the tree is the body, not a drawer).
- Suggested fix (owner): update §1/§3 to describe `SqlProjectsPage` as a
  self-contained single-toolbar page using `ProjectStore`/`ProjectCard`/
  `ProjectDialogs`/`EditorPage`, drop the "hosts HomeTab" wording, record 功能/终端/
  内容工具 as reachable from the workbench 更多 menu, and remove the stale drawer
  line.

### U6 — test gap for U1 and project CRUD flows (test only)
- No test asserts the 功能 menu entry opens `FunctionsTab` (or that 终端/
  内容工具 are reachable); the tutorial/example test covers only 教程/示例.
- The standalone projects-page test covers toolbar/search/menu presence but not
  create → editor, open existing, favorite toggle, delete, or add-existing.
- Suggested fix (owner): add a widget test that taps 更多 → 功能 and expects
  `FunctionsTab` (then terminal tile → `TerminaxTerminalPage`), and extend the
  projects-page test to exercise favorite toggle and open-with-fake-store.

### Round-2 test-coverage summary

| Scenario | Covered? |
| --- | --- |
| Phone tree home body + back | yes (390) |
| Independent expand/collapse | yes (1100) |
| Manual collapse survives refresh (U4) | yes (1100) |
| Single-toolbar projects page (U2) | yes (1100) |
| Desktop 1280 side panel (U3) | yes |
| Desktop 1280 at 2× (U3) | yes |
| Injected tutorials/examples | yes (1100) |
| 功能/终端/内容工具 reachability (U1) | **no (U6)** |
| Projects create/open/favorite/delete/add-existing | **partly (U6)** |

---

## Round-3 final verification (2026-10-12, read-only, no flutter / no test edits)

Re-checked the current working tree after the返修:

- **U1 FIXED (code + test).** `lib/sql_workbench_page.dart` L1318-1330 (更多 menu
  功能/教程/示例), L1390-1406 (`_openFunctions` → `FunctionsTab` with
  `TerminaxTerminalPage` + `ContentToolsPage`); imports at L7-10. New test
  `restores the 功能 entry so terminal and SQL tools stay reachable` (L219-236)
  taps 更多 → 功能 and asserts the `终端` and `SQL 工具` tiles render. Non-vacuous.
- **U2 FIXED.** `lib/sql_projects_page.dart` still a self-contained single
  `Scaffold`/`AppBar('项目')` (L174-175) with no `HomeTab`; uses `ProjectStore`,
  `ProjectCard` (L266), `setFavorite` (L271), `showCreateProjectDialog` (L72),
  `showAddExistingDialog` (L120), `showDeleteProjectConfirm` (L114), `EditorPage`
  (L102). Test `opens a single-toolbar standalone projects page` asserts one
  `AppBar`, no `QFLISQLab`, no rail/bar, search toggle, and the 移除失效项目 menu.
- **U3 FIXED.** `desktop 1280 keeps the tree side panel beside the workspace`
  (L164) and `desktop 1280 at 2x text scale does not overflow` (L183,
  `textScaleFactorTestValue = 2.0`). Both present.
- **U4 FIXED.** `_collapsed` set (L67), pruned with caches (L294), consulted in
  `_refreshTree` (L299-301), maintained in `_toggleDatabase` (L382/393). Test
  `manual collapse of the active database survives refresh` (L199).
- **U6 FIXED (mostly).** The 功能 reachability test above closes the main gap.
  Projects-page test still does not exercise create→editor/open/favorite/delete
  end-to-end, but the toolbar/search/menu surface is covered; treat the remaining
  CRUD assertions as optional hardening, not a blocker.

### U5 — STILL OPEN (documentation only; the sole residual)

`.trellis/spec/frontend/sql-workbench.md` was not updated with the U2 change:

- L9-10: "Shared project editing stays reachable through `SqlProjectsPage`
  (which hosts the public `HomeTab`) and the editor." — **no longer true**;
  `SqlProjectsPage` is now self-contained and does not embed `HomeTab`.
- L31-32: "Projects are a **pushed route** (`SqlProjectsPage`) hosting the public
  `HomeTab` under a '项目' title." — same stale claim.
- L35: "Use a drawer below 700 logical pixels; keep table data horizontally
  scrollable." — contradicts L25-26 ("the tree is the home **body** (never a
  launch drawer)") and the implementation.

Suggested owner edit (doc-only, no code impact): replace the "hosts `HomeTab`"
wording with "self-contained single-toolbar page using `ProjectStore`,
`ProjectCard`, `ProjectDialogs`, and `EditorPage`"; state that 功能/终端/内容工具
are reachable from the workbench 更多 menu; delete the stale drawer line.

## Final round-3 coverage table

| Scenario | Covered? |
| --- | --- |
| Phone tree home body + back | yes (390) |
| Independent expand/collapse | yes (1100) |
| Manual collapse survives refresh (U4) | yes (1100) |
| Single-toolbar projects page (U2) | yes (1100) |
| Desktop 1280 side panel (U3) | yes |
| Desktop 1280 at 2× (U3) | yes |
| 功能 → terminal + SQL tools (U1) | yes (1100) |
| Injected tutorials/examples | yes (1100) |
| Projects create/open/favorite/delete e2e | partly (optional hardening) |
