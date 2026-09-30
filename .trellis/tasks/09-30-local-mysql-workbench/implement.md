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

## Oracle Client and Repository Verification (2026-09-30)

- Added an opt-in `MySqlWorkspaceRepository`; production remains SQLite until
  arm64 startup and persistence are verified.
- Added the Oracle C API socket client with prepared parameters, exact numeric
  text, nullable rows, binary hex values, matched-row counts, and result caps.
- Native client compiled with Clang and `-Wall -Wextra -Werror`; actual Oracle
  MySQL 8.0.46 round-trip tests passed on WSL. This is a host test engine, not the
  pinned 8.4.6 target artifact.
- Four repository integration tests passed on actual Oracle MySQL, covering
  schema/data operations, composite and binary keys, BLOB/empty/NULL values,
  Unicode, filtering/sorting/paging, and read-only tables without primary keys.
- The client still needs an async HarmonyOS channel and lifecycle integration.
  These results do not complete any bundled-server acceptance criterion.
- `flutter analyze --no-pub`: passed; `flutter test --no-pub`: 36 tests passed.
- The host test CMake project configured and built both executables successfully.
