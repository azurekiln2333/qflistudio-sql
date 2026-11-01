# SQL named-workspace consumer gate

Date: 2026-10-24. Status: authored / UNRUN; no runtime acceptance.

## Product surface at initial investigation

- The production entry in `lib/main.dart` runs `SqlLabApp`, not the shared `QfliApp`. `SqlLabApp` builds the SQL-specific five-destination `SqlHomeShell`.
- The SQL project destination is the app-local `SqlProjectsPage`. Its `_openProject` currently pushes a direct `EditorPage` route. The app does not install `RetainedEditorHost` or its controller/observer.
- The SQL shell does not contain shared `HomeTab` or `SavedWorkspacesTab`. Consequently the shared core's new Home workspace tab is not reachable through this product's actual shell, even though `sqlProfile` inherits `supportsSavedWorkspaces == true`.
- A test that mounts shared `QfliApp` with `sqlProfile` would bypass these SQL-owned surfaces. It would not prove the production SQL save/reopen flow.

## Approved app-local boundary

- `lib/sql_app.dart`: own a `RetainedEditorController` for the app lifetime, add its Navigator observer, install `RetainedEditorHost` in `MaterialApp.builder`, and dispose the controller with the app.
- `lib/sql_projects_page.dart`: open projects through published `openEditorPage` and provide a discoverable saved-workspace action leading to a single-toolbar route hosting shared `SavedWorkspacesTab`.
- Preserve the five SQL destinations and the database home, project list/search, offline policy and existing main-entry WIP. No shared-core or product-key change is needed.
- Published core `2f9039a3ba95449679b17257b0313c1ee3644a2c` supplies the required host, explorer save/promotion and latest-record reopen APIs. Its original tree is `d21ffcdc7ac9c834e0b788b21178e9f80768a519`; dirty sibling source is not the contract.

## Required regression

Drive actual `SqlLabApp` and the project destination, then the real file-explorer workspace dialog. Create two real SQL projects, save a named workspace through the UI, preserve both dirty buffers through minimize/reopen, and verify ordered document owners, distinct cursors and per-root expansion after whole-app unmount/reconstruction. Fence real `WorkspaceStore` and `ProjectHistory` writes and compare standalone history bytes after entering named mode. Never seed the expected final workspace session, suppress framework exceptions or mock profile/core behavior.

The historical `test/sql_workspace_integration_test.dart` at SHA256 `60c73c73c062153fb590951d6f7197a5b3cbcc73bc3c5e0f1441cbbe48b110fd` covers the earlier legacy membership contract, not named saved-workspace UI. It was kept separate and byte-identical during this test's initial authoring; the coordinator has assigned its adaptation to the published named-workspace contract. Process restart, actual OHOS UI, current package/native policy and original/expanded curriculum gates remain separate.

## Authored actual-shell regression

`test/sql_named_workspace_test.dart` mounts production `SqlLabApp`, not shared `QfliApp`. It navigates the actual SQL project's rail destination, opens a real SQL project, saves both roots through the file-explorer name/member dialog, and asserts that the retained page adopts that workspace identity. The root approved a toolbar action with tooltip `已保存的工作区`; its single-toolbar route is titled `工作区` and hosts the shared saved-workspace list. Production integration belongs to a separate worker in exactly `lib/sql_app.dart` and `lib/sql_projects_page.dart`.

The case opens both `main.sql` files with actual SQL owner metadata, expands each root's `nested` directory, collapses only the second root, closes/reopens the sidebar, and verifies the restored first child's visibility plus the second root-row's positive collapsed arrow. It makes both buffers dirty, minimizes and reopens the named card through the SQL toolbar, and requires the identical retained editor with both drafts intact and unchanged source files. It then restores clean text in memory, assigns distinct collapsed cursors, destroys the entire `SqlLabApp`, reloads real stores, and reopens through the same actual product UI. Ordered files/owners, active owner, complete cursor endpoints, independent root expansion and nested expansion recovery are asserted.

Both pre-existing standalone `history.json` files are captured after the initial standalone editor's 1500ms debounce and actual history queues have drained. Named changes must leave those exact bytes intact during editing and whole-app disposal. Only initial standalone history is seeded; no expected final named-workspace document/session is written by the fixture. The actual bundled SQLite identity is checked as `3.50.0`; a missing library explicitly skips and cannot pass this gate. The new case does not exercise Run; the separate real-engine owner-run gate retains that responsibility.

The published core's default-true capability also changes `FileExplorer._manageWorkspace`: it chooses the named dialog with `保存`, whereas the frozen legacy `60c73c73` fixture expects the older membership dialog's `应用` and project-history session. Its exact bytes and failed-run evidence remain historical; the coordinator's separately assigned adaptation must preserve its real-engine owner-run assertions while consuming the current contract. An unchanged retry would exercise an obsolete dialog precondition.

No Flutter/Dart formatter, analyzer, test, pub resolver, native build or device command was started. This worker changed only the new test and this note. Formatting, independent review, scoped analysis and actual execution against the immutable published core plus the approved SQL integration remain required. Widget reconstruction is not actual process restart or OHOS acceptance, and unsaved source recovery after process death is not claimed.

## Independent source review

Reviewed the two SQL production integration files and this actual-shell fixture against published core `2f9039a3`, including the public `openEditorPage`, retained host/controller/observer, workspace save/promotion and latest-record reopen paths. The production controller lifetime and MaterialApp integration match the shared app contract. Project opening still preserves the standalone fallback when no retained host is mounted; the SQL five-destination shell and database home are unchanged.

The positive collapsed-root wait now first requires the second root and its title to exist before querying the title's nearest row ancestor. An absent asynchronously restored root therefore keeps the wait pending instead of letting `.first` throw before the row exists. The original first-root expanded child, second-root hidden child and positive root-row arrow conditions remain required. No state is seeded or exception consumed by this correction.

This is a source review only. The scoped diff has no whitespace errors, but formatter, analysis/type-check and all runtime gates remain UNRUN pending the new named host window. The SQL workbench spec should record the new app-owned retained-host and saved-workspace entry contract before publication; that spec is outside this reviewer's assigned write scope.
