# Native integration commit review

2026-10-15. Read-only follow-up after the four repairs described in
`research/native-review.md` (the coordinator will relocate that report).
No additional source changes, builds, device operations or Git mutations.

## Verdict

No additional blocker was found in the reviewed production OHOS call chain.
The native delivery is coherent if all source dependencies below are staged.
Fresh linked target libraries, final packaging and phone acceptance remain
platform verification gates; the host tests do not establish those results.

Two mixed diffs require selective staging: `EntryAbility.ets` contains unrelated
agreement routing, and `local_mysql_runtime.dart` contains a macOS helper-layout
switch that requires the separate macOS packaging delivery.

## Production chain checked

- `NativeMySqlDatabase` uses the OHOS `qfli_sql/mysql` method channel. An explicit
  injected channel retains priority; Android and desktop use their installed
  `LocalMySqlRuntime` path. No changed C++ signature removes the existing OHOS
  query/script/shutdown overloads.
- `QfliMysqlNative.ets` maps query/script/stop to the one ability-owned runtime.
  `EntryAbility.onDestroy` calls final `dispose`, which marks disposed before
  awaiting stop. Public query/script reject while closing or disposed, and
  the queue serializes operations.
- The `QfliMysqlModule` interface and NAPI export array match exactly: all 12
  methods are present (`query`, `executeScript`, `shutdown`, `startChild`,
  `registerChild`, `completeRegisteredChild`, `releaseChild`, `pollChild`,
  `signalChild`, `version`, `protoProbe`, `preloadStart`). A read-only set
  comparison passed; no missing/stub lifecycle export was found.
- Actual native-child capability selects the host. On the established phone
  path capability is false, so fork chooses available production `preloadStart`
  before the legacy exec fallback. Removing `preloadStart` from release would
  regress that path; its stale debug-only comments are not runtime guards.
- `configureProbeRoot` and the Dart-facing `protoProbe` both explicitly reject
  `!BuildProfile.DEBUG`. Root selection validates the run key, rejects existing
  probe directories and enforces the socket length before any server is owned.
  Normal production root remains `<filesDir>/mysql`. `runtimeRoot` only reports
  that internal path and cannot change it. Artifact release-mode selection is
  still for the platform agent to verify.
- Initialization and startup polling use 120-second deadlines; shutdown first
  waits up to 30 seconds after successful SQL shutdown, then owned escalation
  uses 15-second TERM and 10-second KILL polling budgets. These polling budgets
  are not total end-to-end wall-time promises: queued SQL and native client
  connection/read/write timeouts can add time. The client sets 5-second connect
  and 60-second operation timeouts. The public native-child creation API has no
  extra application timeout; no new platform liveness guarantee is inferred.
- A failed preload/exec start with `owned/pendingPid` writes `this.pid` before
  throwing. The surrounding awaited assignment does not overwrite it on
  rejection. `stop` can reap it, and beginning-of-start cleanup runs before
  config/assets/exit files are rewritten or a new server is spawned. Failed
  unconfirmed stop keeps closing and ownership; confirmed exit releases it.
- Fork children use waitpid-owned status; framework children use verified
  identity and completion from their exit record. Repeated status reads retain
  exact observed exit until release. No raw PID-1/unowned signal method exists.
- The repaired preload host now closes inherited descriptors, requires its
  watchdog and signal mask before ready, enforces the monotonic poll handshake,
  and returns negative PID for a recorded failure. Actual production-host tests
  cover these paths. The private image exposes its named entries while hiding
  other symbols, uses symbolic internal binding and eager libc resolution, and
  enters child exit scope before Oracle runs. The existing Oracle patch invokes
  `qfli_mysql_record_exit` before Oracle exit; that hook is retained/exported.
- Local MySQL transport remains socket-only with `skip-networking`; no TCP
  fallback or new online transport was introduced by this native delivery.

## Required OHOS commit manifest

Reviewed tracked production changes to stage together:

```text
native/CMakeLists.txt
native/mysql/build-mysql-ohos.sh
native/mysql/ohos-targets.cmake
native/mysql/package-runtime.cmake
native/mysql/qfli_mysql_server.cpp
ohos/entry/hvigorfile.ts
ohos/entry/src/main/cpp/qfli_mysql_napi.cpp
ohos/entry/src/main/ets/plugins/QfliMysqlRuntime.ets
ohos/entry/src/main/ets/plugins/QfliMysqlNative.ets
```

Required untracked production sources, headers and linker map:

```text
native/mysql/qfli_mysql_host.cpp
native/mysql/qfli_mysql_host.h
native/mysql/qfli_mysql_launcher.cpp
native/mysql/qfli_mysql_server_proto.cpp
native/mysql/qfli_mysql_server_proto.map
native/mysql/qfli_mysql_stdio_protocol.h
ohos/entry/src/main/cpp/qfli_mysql_proto_probe.cpp
ohos/entry/src/main/cpp/qfli_mysql_proto_probe.h
```

Also stage the `stop()` to `dispose()` lifecycle hunk in `EntryAbility.ets`.
Its router import and `openAgreement` branch require `pages/AgreementReader.ets`
and the page-profile registration if committed; they are a separate delivery and
are not certified here. Stage only the lifecycle hunk for the native commit.

For the changed `native/tests/CMakeLists.txt`, stage every referenced new test:

```text
native/tests/CMakeLists.txt
native/tests/qfli_mysql_child_stub.cpp
native/tests/qfli_mysql_host_test.cpp
native/tests/qfli_mysql_preload_host_stub.cpp
native/tests/qfli_mysql_preload_host_test.cpp
native/tests/run-preload-host-test.sh
```

These additional executed test sources/scripts support the recorded mechanism,
stdio and exec-host results and are suitable for the same test delivery:

```text
native/tests/qfli_mysql_preload_closure_stub.cpp
native/tests/qfli_mysql_preload_mechanism_test.cpp
native/tests/qfli_mysql_stdio_protocol_test.cpp
native/tests/run-host-test.sh
native/tests/run-preload-mechanism-test.sh
native/tests/run-stdio-protocol-test.sh
```

`native/mysql/qfli_mysql_server.map` is not referenced by the reviewed build and
is not required. Exclude experimental inspection/rebuild/staging scripts unless
separately reviewed. Build outputs and staged `.so` files are generated inputs,
not source substitutes; fresh normal packaging must supply all four libraries.

## Desktop Dart/test split

`lib/local_mysql_runtime.dart` has two independent changes:

1. Optional `pluginDirectory` constructor/field and its initialization/start
   arguments. Null keeps prior Windows/Linux/Android plugin-path behavior.
   These local changes are compatible with the existing desktop test overrides.
2. A macOS-only `_discover` switch, plus `dart:ffi`, from the old Resources
   layout to `Helpers/QfliMySql-{arm64,x64}.app/Contents`. This requires the new
   `native/mysql/macos` packaging scripts, Runner bundle phase, entitlements and
   native helper packaging settings. Do not commit that entire Dart diff while
   deliberately leaving those macOS artifacts out.

`test/mysql_desktop_database_test.dart` correctly selects `.dylib` on macOS and
adds optional test server/plugin overrides. `native/mysql/desktop/runtime_test.dart`
adds the same plugin override. They use disposable test storage and do not alter
the production default. The full test diffs require at least the pluginDirectory
Dart constructor/field/argv hunks; they do not require `_discover` or `dart:ffi`.
No SQL runner method directly depends on the new macOS layout or plugin option.
The runner can consume the already tracked native adapter without committing the
separate macOS integration. Native desktop CMake/README/macOS spec edits belong
to that macOS delivery, not the OHOS source manifest above.

## Verification and exclusions

- Prior actual-preload production-host regression: 30 checks PASS, including
  bounded stall, early death, no zombie, descriptor isolation, watchdog failure
  and signal-mask restoration. Existing host/stdio/mechanism checks PASS.
- OHOS ARM64 SDK23 syntax/type compilation of the repaired preload host PASS.
- Additional final NAPI target syntax/type compilation PASS with `-Wall -Wextra
  -Werror` (only unused callback parameters exempted).
- All 12 ArkTS module methods match the NAPI export set: PASS.
- Portable macOS packaging validator: 12 tests PASS from prior review. This is
  not actual macOS signing, build or runtime acceptance.
- No Flutter/ArkTS full compiler or platform build was run in this follow-up;
  the platform agent is rebuilding. No source was changed during that rebuild.

Do not stage local signing material, icons, agreement routing, generated plugin
registrants, cloud/UI/content changes, unrelated macOS files or exploratory
scripts based on this report. `ohos/entry/.gitignore` only has an unrelated
leading-space alteration of `/node_modules`; it is not a runtime dependency.
Android release debug signing remains the previously reported distribution
configuration limitation, separate from native source correctness.
