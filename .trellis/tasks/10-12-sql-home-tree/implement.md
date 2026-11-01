# C1 Implementation Plan — Home Tree + Standalone Projects Page

Owner pi-mysql. Preserve the 109 pre-existing dirty files; layer edits on top.

## Ownership

Mine: `lib/sql_workbench_page.dart`, `lib/sql_app.dart` (if needed),
`lib/sql_projects_page.dart` (new), new app-local UI widgets/tests,
`.trellis/spec/frontend/sql-workbench.md`, `lib/main.dart` (only me).
NOT mine: `lib/sql_content_repository.dart`, `assets/content/*.json` (C2); shared
package `../qfli_studio_core` is consume-only.

## Checklist

- [ ] 1. Snapshot `git status --porcelain`; record `lib/sql_workbench_page.dart`
      hash so edits layer, not reset.
- [ ] 2. Add `lib/sql_projects_page.dart`: `Scaffold` with "项目" AppBar + back,
      body = public `HomeTab(store, auth, settings)`. No rail/PageView/HomePage.
- [ ] 3. Workbench AppBar: replace the "项目编辑器" push with a "项目" action that
      pushes `SqlProjectsPage`; add "教程"/"示例" actions pushing
      `LocalTutorialsTab`/`ExampleCodeTab` for `language:'sql'` with injected
      `SqlContentRepository` (fake in tests until C2 lands the file).
- [ ] 4. Phone home body = expandable database→table tree (no launch drawer):
      independent per-db expand/collapse; table tap enters workspace; back
      returns to tree. Desktop keeps the side panel.
- [ ] 5. No home tab/page switcher remains; only the data/schema/sql workspace
      segment. Preserve tree ops + busy-gating.
- [ ] 6. Widget tests: tree visible at 390px; expand/collapse; table→workspace→
      back; projects page has `HomeTab` + "项目" and no home rail/PageView;
      tutorials/examples open; no home tab bar.
- [ ] 7. Layout at 390px and 1280px, 2× text scale.
- [ ] 8. Update `.trellis/spec/frontend/sql-workbench.md`.

## Validation

```powershell
cd D:\MyNewProjects\qfli_sql
flutter analyze --no-pub lib test
flutter test --no-pub test/sql_workbench_page_test.dart test/sql_app_test.dart <new_tests>
```

## Gates

- No second-home navigation on the projects page.
- Phone home body is the tree (not a drawer).
- Tutorial/example entries open and show code + import.
- Existing workbench tests pass unchanged.
- No out-of-ownership edits; no commit/push.
