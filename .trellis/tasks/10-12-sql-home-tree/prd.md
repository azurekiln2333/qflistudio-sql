# C1 — SQL Home Tree and Separate Projects Page

Parent: `.trellis/tasks/10-12-sql-curriculum-and-home`

## Goal

Make the SQL app home screen primarily a **database/data-table tree list**, and
move the **project list to its own page** reached from home. Remove any
home-level tab/page switching. Tutorial and example lists must be reachable from
the home surface.

This is the UI child. It is owned by the `pi-mysql` worker. It must not hard-code
lesson content — it renders whatever catalog C2 loads.

## Background / Evidence

- `lib/main.dart:29` sets `showHomeTabs: false`; `lib/sql_app.dart` renders
  `SqlWorkbenchPage` directly as `home`.
- `lib/sql_workbench_page.dart` already renders the database/table explorer:
  - `_explorer()` (~line 1300+) lists databases and, for the selected database,
    its tables, with per-item popup menus (delete/rename/schema/export).
  - App bar pushes shared `HomePage` via an `Icons.folder_open_outlined`
    "项目编辑器" button (~line 1262).
  - Workspace has a `SegmentedButton<_WorkbenchView>` for data/schema/sql
    (~line 1448).
- Shared content lists live in `../qfli_studio_core/lib/pages/local_content_pages.dart`
  (`LocalTutorialsTab`, `ExampleCodeTab`, `ExampleDetailPage`, `_LessonPage`),
  which render inside their own `Scaffold`+`AppBar` and take an optional
  `ContentRepository`.
- Shared `HomePage` (`../qfli_studio_core/lib/pages/home_page.dart`) is the
  existing project/editor surface.

## Requirements

- R1 — Home screen's primary surface is the database/data-table tree list.
- R2 — Projects are NOT a home tab/segment. The project list (and project
  editing entry) lives on its own page reached from home via an explicit action.
  The projects page must NOT wrap the shared `HomePage` shell (that reintroduces
  the second home). Reuse only the public **`HomeTab`** (project list + search +
  new/open) as a standalone route, or a thin local `SqlProjectsPage` hosting
  `HomeTab` with a clear "项目" title. No second home navigation/rail/PageView is
  allowed, and other product entries (功能/设置/教程/示例) must remain reachable.
- R3 — No home-level tab bar or page switcher that flips between "database" and
  "projects" as home tabs. Navigation to projects is a pushed route.
- R4 — Tutorial list and example list are reachable from home (entry actions),
  and their detail pages show code with copy and import actions.
- R5 — The database/table tree keeps its current capabilities: select database,
  select table, create/delete database, create/delete/rename table, schema view,
  export — disabling mutation controls while busy exactly as today.
- R6 — The phone home body IS the expandable database→table tree (NOT hidden in
  a drawer at launch); tapping a table enters the existing data/schema/SQL
  workspace and a back affordance returns to the tree. Desktop may keep the tree
  as a side panel beside the workspace. Each database expands/collapses
  independently. No layout may hide the tree at phone launch.
- R7 — Content lists must accept an injectable `ContentRepository` so tests run
  without real assets, and must filter to the product's type set (sql) via
  `StudioProfile.current.productKey` when available.
- R8 — `lib/main.dart` may be edited only by this child's owner (pi-mysql) and
  only if required for navigation wiring; keep the profile and runner unchanged.

## Acceptance Criteria

- [ ] AC1 — Launching the SQL app lands on a database/table tree list; there is
      no home tab switcher.
- [ ] AC2 — A single explicit action on home opens the project list page;
      back returns to the tree.
- [ ] AC3 — Existing project create/open/edit flow is reachable and unchanged
      from the UI's perspective.
- [ ] AC4 — Tutorial list and example list open from home; lesson and example
      detail show code and expose copy + editor import + project import.
- [ ] AC5 — Tree operations (select/refresh/create/delete/rename/schema/export)
      behave as today; mutation controls disabled while busy.
- [ ] AC6 — Tree renders as the phone home body at 390px and as a side panel at
      1280px, both without overflow at 2× text scale; a table tap enters the
      workspace and returns to the tree.
- [ ] AC7 — `flutter analyze` clean for changed files; focused widget tests
      pass.

## Content Interface (synced from C2)

C2 delivers `lib/sql_content_repository.dart` with
`SqlContentRepository implements ContentRepository`. C1 constructs it and passes
it to the shared tabs; the shared package is **read-only** (no writes):

```dart
final repo = SqlContentRepository();
LocalTutorialsTab(language: 'sql', repository: repo, store: store, auth: auth, settings: settings)
ExampleCodeTab(language: 'sql', repository: repo, examples: examples, store: store, auth: auth, settings: settings)
```

`SqlContentRepository` reads `assets/content/sql_tutorials.json` and
`assets/content/sql_examples.json`, filters with `ContentFilter`, and caches the
loaded catalog. C1 only consumes it.

## Proposed File Ownership

**Owned by C1 (pi-mysql may edit):**

- `lib/sql_workbench_page.dart` — home surface: add projects-page entry, tutorial
  and example entry points, remove any home tab switching, and make the tree the
  phone home body. NOTE: this file is currently dirty with pre-existing work;
  preserve those changes and add on top.
- New file(s) under `lib/`: `lib/sql_projects_page.dart` (thin standalone project
  page hosting the public `HomeTab` with a "项目" title) and optionally
  `lib/sql_schema_tree.dart` if extracting the tree is warranted.
- `lib/sql_app.dart` (only if navigation wiring needs it), `lib/main.dart` (only
  by this owner), `.trellis/spec/frontend/sql-workbench.md`.
- `test/` files for the new UI.

**Shared package `../qfli_studio_core` (consume only; do not edit):**

- Consume public `HomeTab`, `LocalTutorialsTab`, `ExampleCodeTab` as-is. Do not
  edit `home_page.dart` or `local_content_pages.dart`. If an edit is unavoidable
  it is a shared-interface change and must be reported before editing.

**NOT owned by C1:**

- `lib/sql_runner.dart`, `lib/sql_database.dart`, `lib/mysql_workspace_repository.dart`
  (repository logic) — only consume their public API.
- `lib/sql_content_repository.dart` and the asset JSON — owned by C2.
- `../qfli_studio_core/**` — **read-only; no writes permitted**.

Any need to change a shared-package file must instead be solved locally or
reported to the parent.

## Dependencies / Ordering

- C1 can start immediately and render the current (placeholder) catalog; it must
  not block on C2.
- C1's AC4 is verified with a stub/injected repository in tests and, for the
  device/live check, depends on C2 having written real `sql` entries. If C2 is
  not yet merged, verify AC4 with the injected repository and state the
  dependency explicitly in `check.md`.

## Out of Scope

- Writing lesson/example content (C2).
- Native runtime, MySQL lifecycle, build/signing changes.
- Committing.

## Open Questions

None blocking.
