# SQL UI integration review

Reviewed only `D:/MyNewProjects/qfli_sql`. Shared core was read-only. The main
coordinator serializes commits; this reviewer did not stage or commit changes.

## Verified final behavior

- `SqlLabApp` opens the app-local `SqlHomeShell`, with exactly five PageView
  destinations: 数据库、项目、功能、教程、示例. Phone navigation uses one bottom bar;
  desktop uses one rail. Each active destination owns one toolbar.
- Actual drag gestures reach each destination. Jumping to a distant destination
  and returning retains the selected table/workspace; swiping preserves manual
  database collapse. The injected database factory is called only once.
- All five destinations render without layout exceptions at widths 390, 900,
  and 1280 logical pixels with 2x text scaling. Database/workbench tests also
  cover narrow tree navigation, desktop side-panel data, query state, edits,
  empty tables, failure clearing, and saved-query storage failures.
- Settings are reachable from the database toolbar before creating a project.
  The shared SettingsPage receives the existing stores, with AI settings hidden
  in the offline profile.
- Tutorial and example tabs receive the SQL content repository and all three
  stores. Opening real injected lesson/example details renders CodeSnippet with
  the import dependencies. File import/write correctness remains owned by the
  shared CodeImportService contract/tests, rather than claimed from this test.
- Terminal, SQL query tools and every entry in shared `commonTools` remain
  reachable in the SQL tools body. A shared tool detail route opens and returns
  to the same active tab.

## Findings fixed

1. `lib/sql_projects_page.dart`: `_visible` was computed outside the
   ListenableBuilder. Store notifications rebuilt a closure containing stale
   data, so completed loads, new projects and removals could leave the page
   unchanged. Compute the visible list inside the listener. Added notification
   and active-search regression coverage.
2. `lib/sql_projects_page.dart`: persisted cloud projects were displayed by this
   app-local list, bypassing the offline home policy. Filter them in offline
   mode and reject a stale cloud open request, preserving registry entries.
   Activity-report calls are also omitted in this offline app-local flow:
   TaskActivityService.record otherwise queues and syncs server events when a
   previous session token/user is present.
3. `lib/sql_workbench_page.dart`: standalone tutorial/example pushes wrapped the
   shared page's own Scaffold/AppBar in another Scaffold/AppBar. Push the public
   shared page directly, preserving its normal route back button. Updated tests
   to assert a single toolbar and use the route back affordance.
4. `lib/sql_workbench_page.dart`: the new home shell had no settings entry
   accessible without opening a project. Restored a database-toolbar Settings
   action; offline mode passes `showAi: false`.
5. The shared ToolsGrid uses a fixed 132px card height and a Column containing
   an icon, title, description and Spacer. Executed 2x-text tests overflowed by
   12–44px at phone and desktop widths (`qfli_studio_core/lib/pages/tools_grid.dart`
   grid delegate; `lib/widgets/tool_widgets.dart` ToolCard Column). With explicit
   coordinator approval, `lib/sql_tools_tab.dart` supplies natural-height SQL
   tool rows through `sqlProfile.toolsTabBuilder`. It reuses `commonTools`
   metadata and original shared routes; shared core was not changed. The
   standalone FunctionsTab now also receives the store required by this hook.

## Verification evidence

- Initial focused UI suite: 21 passed.
- Expanded checks demonstrated the layout failure before its local fix; see
  `ui-focused-fix.log`.
- After fixes, focused UI suite: 29 passed (`ui-focused-final.log`). The added
  complete-tool-list route regression subsequently passed in the full suite.
- Final command: `flutter test --no-pub` — **92 passed, 2 skipped**, zero failures.
  Log: `flutter-test-final.log`.
- Both skips are real desktop Oracle tests in
  `test/mysql_desktop_database_test.dart`; the required
  `QFLI_MYSQL_TEST_BUNDLE` environment variable was not set. These are not device
  acceptance results.
- Final command: `flutter analyze --no-pub lib test integration_test` — **No
  issues found**. Log: `flutter-analyze-final.log`. Flutter analysis provides
  both Dart lint and type checking for the app and its tests.
- SDK command: `D:/ProgramFiles/flutter_ohos/bin/flutter.bat`.
- Shared core HEAD during final validation:
  `8731df838432d24ba9b5f2b73689d26b97693ba7`; it had eight externally owned dirty
  entries. No shared-core file was written by this reviewer.

## Findings left to owning workstreams

- Shared fixed-height tool cards still require a coordinated core fix for
  other products; SQL avoids the faulty layout through its local public hook.
- The shared TaskActivityService has no offline guard in `record`/`syncPending`.
  This review gated SQL's local project calls; a general core policy change
  belongs to the shared-core owner. No claim is made that every shared caller
  was repaired here.
- Terminal/offline engine implementation, curriculum execution, native runtime,
  Android/OHOS builds and physical-device checks belong to the other owners.
  The passing widget suite does not establish native or platform acceptance.

## Spec synchronization requested from coordinator

Update `.trellis/spec/frontend/sql-workbench.md` to document the product-owned
tools body hook, always-reachable offline settings, notification-driven project
lists and cloud-entry filtering. Keep the shared-core boundary explicit.
