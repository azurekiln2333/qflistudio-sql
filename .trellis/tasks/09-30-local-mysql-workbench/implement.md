# Implementation

- [x] Make the existing bundled SQLite bridge executable from the current runner, including directory creation, honest runtime errors, and tests. Verified with a signed HarmonyOS HAP and on-device SQL round-trip. This is groundwork, not MySQL completion.
- [x] Define structured database results and parameterized mutation operations for the grid. Verified on HarmonyOS with quoted text and NULL round-trips; the current script runner remains a separate multi-statement path until engine unification.
- [x] Build the database explorer, editable table grid, create/delete database and table dialogs, and SQL editor as the SQL app's main workspace while retaining project/editor access. Current engine remains SQLite; frontend and native x86_64 emulator tests pass.
- [ ] Port and package a MySQL server for HarmonyOS arm64; add lifecycle management and local client transport.
- [ ] Switch the default workbench and runner to the local MySQL engine after on-device readiness and persistence checks.
- [x] Add persistent query history and saved queries, with storage errors exposed and failed writes leaving visible state unchanged. Filtering, sorting, and paging are present in the SQLite workspace.
- [ ] Complete import/export and full schema tools, then verify all tools against the final Oracle MySQL runtime.
- [ ] Remove development-status UI copy and verify empty/error states against real data.
- [ ] Run `flutter analyze`, `flutter test`, HarmonyOS build, and on-device create/edit/restart smoke checks. Review full acceptance criteria before task completion.
- [ ] Commit each coherent implementation batch using conventional messages and narrow staging.

## Workbench Verification (2026-09-30)

- `flutter analyze --no-pub`: passed.
- `flutter test --no-pub`: 29 tests passed.
- HarmonyOS x86_64 native suite: 5 tests passed, including row-id shadowing and
  `WITHOUT ROWID` metadata handling.
- HarmonyOS workbench integration: cell editing, SQL results, and saved-query
  reopening passed against the actual native database.
- Normal `lib/main.dart` debug HAP built and signed successfully. The emulator
  disconnected before normal-home screenshot inspection; that check is pending.
- Commits: `b0415fb` (stable grid row identity) and `6585023` (workbench and saved
  queries). Original unrelated platform changes were not included.
- Oracle MySQL runtime remains unimplemented. See
  `research/oracle-mysql-port.md` for source and cross-build progress.
