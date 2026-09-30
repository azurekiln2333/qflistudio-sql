# Implementation

- [x] Make the existing bundled SQLite bridge executable from the current runner, including directory creation, honest runtime errors, and tests. Verified with a signed HarmonyOS HAP and on-device SQL round-trip. This is groundwork, not MySQL completion.
- [x] Define structured database results and parameterized mutation operations for the grid. Verified on HarmonyOS with quoted text and NULL round-trips; the current script runner remains a separate multi-statement path until engine unification.
- [x] Build the database explorer, editable table grid, create/delete database and table dialogs, and SQL editor as the SQL app's main workspace while retaining project/editor access. Current engine remains SQLite; frontend and native x86_64 emulator tests pass.
- [x] Cross-compile and package Oracle MySQL 8.4.6 server/client for HarmonyOS arm64.
- [ ] Complete a supported Oracle process host for the phone target. Native-child
  lifecycle and socket transport are implemented, but HarmonyOS restricts that
  hosting API to PC/2-in-1 and tablets; the current phone target is rejected.
- [ ] Complete acceptance of the default Oracle workbench and runner. The default
  adapters are now wired to MySQL; on-device readiness and persistence checks
  are deferred at the user's request and remain required for completion.
- [x] Add persistent query history and saved queries, with storage errors exposed and failed writes leaving visible state unchanged. Filtering, sorting, and paging are present in the SQLite workspace.
- [x] Implement table rename, column add/rename/delete, index inspection/create/delete,
  and SQL import/export in the Oracle workbench.
- [ ] Verify the new tools against the final Oracle MySQL runtime.
- [ ] Remove development-status UI copy and verify empty/error states against real data.
- [ ] Run `flutter analyze`, `flutter test`, HarmonyOS build, and on-device create/edit/restart smoke checks. Review full acceptance criteria before task completion.
- [x] Commit the implemented runtime and workbench batches using conventional
  messages and narrow staging. Future phone-hosting work still requires its own batch.

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
- Oracle MySQL runtime was not implemented at this verification stage. See
  `research/oracle-mysql-port.md` for source and cross-build progress.

## Oracle Client and Repository Verification (2026-09-30)

- Added an opt-in `MySqlWorkspaceRepository`; production still used SQLite at
  this verification stage. The later continuation switches the default adapters.
- Added the Oracle C API socket client with prepared parameters, exact numeric
  text, nullable rows, binary hex values, matched-row counts, and result caps.
- Native client compiled with Clang and `-Wall -Wextra -Werror`; actual Oracle
  MySQL 8.0.46 round-trip tests passed on WSL. This is a host test engine, not the
  pinned 8.4.6 target artifact.
- Four repository integration tests passed on actual Oracle MySQL, covering
  schema/data operations, composite and binary keys, BLOB/empty/NULL values,
  Unicode, filtering/sorting/paging, and read-only tables without primary keys.
- At this verification stage the client still needed an async HarmonyOS channel
  and lifecycle integration. The continuation below adds these components.
  Host results do not complete any bundled-server acceptance criterion.
- `flutter analyze --no-pub`: passed; `flutter test --no-pub`: 36 tests passed.
- The host test CMake project configured and built both executables successfully.

## Implementation Continuation (2026-09-30)

- User explicitly requested implementation to continue without further tests
  or device connection probes. Do not mark acceptance criteria complete from
  compilation alone.
- Added async HarmonyOS Oracle query/script channels, app-private resource
  installation, initialization, live version readiness, and clean shutdown.
- EntryAbility registers the Oracle runtime and awaits shutdown on destruction.
- The project runner now uses Oracle and stores a stable schema name in
  `.qfli/mysql.json`; the workbench factory now uses the Oracle
  repository. Legacy SQLite adapters remain explicit options.
- Native script execution uses CLIENT_MULTI_STATEMENTS and reads every result
  on one connection; output truncation does not skip subsequent statements.
- Hvigor stages libraries/resources from the runtime package. arm64 CMake fails
  when the package is absent; x86_64 builds expose an unavailable Oracle module.
- Oracle MySQL 8.4.6 server and client linked successfully for arm64 with
  `--no-undefined` and the corrected SDK libcxx-ohos headers. Packaging includes
  versioned error messages, charsets, ICU data, and upstream licenses.
  The target startup and persistence checks are deferred.
- Production Flutter kernel compiled with `flutter build bundle --no-pub
  --debug --target-platform windows-x64` through the direct Dart launcher.
  This establishes Dart compilation only, not platform/runtime acceptance.
- SQL export is a single-table InnoDB snapshot with UTC timestamps and HEX
  values. It rejects truncation, spatial fields, and output over 1 MiB. Foreign
  key dependencies must exist in the target database. Import accepts server SQL,
  not mysql-client commands such as DELIMITER. Oracle database rename is not
  offered because the server does not provide that operation.
- Direct Hvigor invocation of the internal CompileArkTS task did not register
  that task in this SDK. Full `assembleHap` succeeded after replacing the ArkTS
  constructor parameter property with an explicit class field.
- The signed HAP contains both Oracle arm64 libraries and all 73 MySQL rawfiles.
  This is a package inspection, not runtime acceptance. The compiler identifies
  the current ArkTS native-child API as unavailable on the phone target; the
  runtime now rejects unsupported devices before extracting assets or writing
  initialization state. NDK native-child entry APIs have the same device
  restriction; switching to them does not provide a phone hosting path.
- Static review fixes: capped SQL URI reads reject oversized input before
  allocation; native reads/writes loop to completion and export fsyncs before
  success. Schema view loads columns/indexes independently of capped row data.
  Primary keys are resolved from the actual PRIMARY index rather than the
  ambiguous COLUMNS.COLUMN_KEY field. Existing metadata fixtures were updated;
  no tests or device checks were run for these fixes.
- Final full `assembleHap` compiled and signed successfully after these fixes.
  Output: `ohos/entry/build/default/outputs/default/entry-default-signed.hap`.
  Static review found no remaining issues in the corrected URI, primary-key,
  and independent-schema paths. Phone hosting remains the known open blocker;
  the task remains in progress and runtime acceptance is not marked complete.
