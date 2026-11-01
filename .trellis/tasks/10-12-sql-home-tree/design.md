# C1 Design — Home Tree + Standalone Projects Page

Parent: `10-12-sql-curriculum-and-home` · Child C1 · Owner pi-mysql

## Shape

```
SqlLabApp (lib/sql_app.dart, home:)           // unchanged widget
   └── SqlWorkbenchPage (existing)             // home = database/table tree
         ├── push SqlProjectsPage (new)        // standalone project list
         │      └── hosts public HomeTab(store, auth, settings) under "项目"
         ├── push LocalTutorialsTab   (core, repo injected)
         └── push ExampleCodeTab      (core, repo injected)
```

Keep `SqlWorkbenchPage` as home (it already is tree + workspace). Add explicit
pushed entries. **Do not wrap shared `HomePage`** — that reintroduces the second
home. The projects page hosts only the public `HomeTab` with a clear "项目" title
and no rail/PageView/home navigation.

## Layout (correction 2)

- Phone (<700px): home **body is the expandable database→table tree** (not a
  drawer). Database rows expand/collapse independently (`Set<String> _expanded`);
  tapping a table enters the existing workspace; a back affordance returns.
- Desktop (≥700px): tree remains a side panel beside the workspace.
- Tree is never hidden at phone launch.

## Contracts

- Tree data: `SqlWorkspaceRepository.listDatabases()` / `listTables(db)` — no
  signature changes; keep busy-gating and all operations (create/delete/rename/
  schema/export).
- Projects page: `HomeTab` reuse preserves create/open/edit + search; other
  product entries stay reachable.
- Content: `LocalTutorialsTab(language:'sql', repository: SqlContentRepository(),
  store, auth, settings)` and `ExampleCodeTab(...)`. `SqlContentRepository`
  (`lib/sql_content_repository.dart`) is **C2-owned** — code against the agreed
  import, use a fake in tests, never create it here.
- Keep `sql_engine.json`, engine switching, persistence, and the data/schema/SQL
  workspace unchanged.

## Verification

- Widget tests: tree visible at 390px (not drawer); per-db expand/collapse; table
  tap → workspace → back; projects pushed with `HomeTab` + "项目" and no home
  rail/PageView; tutorials/examples open; no home tab bar.
- Layout at 390px and 1280px, 2× text scale.
- `flutter analyze` on changed files; existing workbench tests pass unchanged.

## Rollback

Changes confined to app-local UI + optional thin project page. Revert only this
child's files/hunks. Never reset the 109 pre-existing dirty files.
