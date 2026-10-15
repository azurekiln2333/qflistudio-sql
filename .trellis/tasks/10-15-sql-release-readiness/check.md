# SQL release acceptance

Status: implementation, host checks and physical Android acceptance pass.
OHOS compilation/package audit passes; signing and OHOS device acceptance remain
blocked on SQL-specific signing material. This task is not marked store-ready.

## Scope and source identity

- Only `D:/MyNewProjects/qfli_sql` was modified by this SQL team. The three
  existing Pi panes were verified as `wC:p5`, `wC:p6`, `wC:p7` with this exact
  live working directory. The inherited `wY` identifier was stale and unused.
- Shared core is consumed read-only at source-clean `8b33443`. Its owners
  delivered shared policy/layout/import/About fixes; SQL navigation stays local.
- The initial 121 dirty/untracked changes were inventoried before edits.
  Unrelated macOS, privacy, signing, icon and exploratory work remains with its
  original owner. No broad staging, reset, clean or production data removal.
- Code deliveries use scoped Conventional Commits; current release source and
  tests include `84746f1`, `c0a88bc`, `8461bd6` and `30ee9cb`, in addition to
  the earlier implementation commits recorded in `implement.md`.

## Requirements and evidence

| Requirement | Result | Evidence |
| --- | --- | --- |
| R1 terminals | PASS for supported commands | `terminal-offline-report.md`, 75 combined local/shared terminal checks |
| R2 offline mobile UI | PASS | Local cloud selection/execution guards; coordinated shared editor/background/shortcut gates |
| R3 five-page SQL home | PASS | Database/projects/tools/tutorials/examples; actual PageView swipes and retained state; `ui-integration-check.md` |
| R4 complete curriculum | PASS | 126 tutorial/example pairs; 120 SQLite scripts and 240 exercise results from both source and shipped JSON; six MySQL examples + six exercises on physical Android Oracle 8.4.6; `curriculum-native-test.md` |
| R5 static/unit/native host | PASS with explicit desktop skips | Final logs below; production preload-host 30 assertions plus lifecycle/mechanism/stdio regressions |
| R5 Android | Compile/package and physical-device PASS | `android-final-report.md`; four manifest-isolation cases and 15 physical native/UI tests pass; production release restored in place |
| R5 OHOS | Compile/package/audit PASS; signing/device BLOCKED | `ohos-final-hap-audit.md` |
| R6 review/commits | Reviewed implementation committed; final device evidence recorded | `final-quality-review.md`, scoped Git history |

No placeholder curriculum was found. Existing complete content was retained
and repaired where actual expectation/fixture defects were demonstrated;
user projects and databases were never deleted to regenerate tutorials.

## Final host quality gate

Executed after the native UI test repairs against core `8b33443`:

- `flutter analyze --no-pub lib test integration_test`: no issues.
- Repository-root `dart analyze`: no issues.
- Full `flutter test --no-pub --reporter expanded`: **92 passed, 2 skipped**.
  The two explicit desktop Oracle skips require `QFLI_MYSQL_TEST_BUNDLE`;
  they do not establish desktop acceptance.
- Python coverage/authoring/packaged-asset validation passes all 126 structural
  entries and every SQLite example/exercise. All 246 exercise expectations are
  authored. The remaining **6 MySQL examples and 6 exercises also pass** using
  an owned private Linux Oracle 8.0.46 server with TCP/mysqlx disabled; see
  `research/mysql-host-curriculum-review.md`. That proves their SQL semantics,
  and the shipped Oracle 8.4.6/FFI path now also passes the twelve authored-output
  checks on physical Android. OHOS runtime acceptance remains separate.

## Physical Android acceptance

At SQL revision `30ee9cb` / shared core `8b33443`, OPD2413 ARM64/API 36 passed
all four isolated integration targets: curriculum **6/6**, Oracle lifecycle /
workspace / editor **2/2**, SQLite native **6/6**, SQLite workbench **1/1**.
The curriculum log includes twelve exact authored-output matches, Oracle 8.4.6
identity, TCP networking disabled, and owned-root cleanup. Logs are
`research/device-curriculum-run.log`, `device-mysql-native-run.log`,
`device-sql-native-run.log` and `device-sql-workbench-run.log`.

The preserved final production APK was restored with `install -r`; production
was never uninstalled or cleared. All five home destinations were visually
checked after launch; PID 28316 stayed alive, with zero matching fatal,
unhandled-exception or RenderFlex-overflow lines in its available logcat.
`research/device-production-final-check.log` records package identity and
unchanged first-install time. This is a current-size tablet visual check;
phone/large-text variants are covered by the widget suite. The normal app was
force-stopped and the physical window explicitly released in global channel
event **53**; SQL's own temporary 5582 emulator was already stopped.

Logs: `research/final-core8b33443-analyze.log`,
`research/final-core8b33443-repository-analyze.log`,
`research/final-core8b33443-tests.log`,
`research/native-host-regressions.log`.

## Final artifacts

OHOS unsigned release:
`ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`.
Size **193,021,465 bytes**, SHA256
`25FD3C1944A077061B98FE120F5CA0F894A2E44499A3BF701005AAA28C9A27BE`.
Built against core `8b33443`; all four packaged libraries match the fresh native
build after the packager's exact stripping, and both curriculum assets match
the repository. ArkTS/CMake/package/check succeed; only SignHap fails.

Android ARM64 release:
`build/release-ready/QFLISQLab-1.0.0-arm64-release.apk`
(also `build/app/outputs/flutter-apk/app-release.apk`).
Size **45,745,907 bytes**, SHA256
`9965F512D51022CC5E2AB875EA8F4DDD24F6D467C307B6867657AAA5B39BCD41`.
Production package `com.azurekiln.qfli.sqlab`, built against core `8b33443`.
Packaged native inputs/assets match staging; all seven ELF LOAD alignments are
at least 16 KiB, and `zipalign -c -P16 4` exits 0. Signed with Android Debug.
See `research/android-final-report.md` for the complete audit and device results.
The test APK package is actually inspected as
`com.azurekiln.qfli.sqlab.integrationtest` before any installation.

## Remaining release requirements and limitations

1. Supply a valid SQL-specific OHOS signing configuration for
   `com.azurekiln.qfli.sqlab`; the locally referenced key/profile/certificate
   files do not exist. No available profile belongs to SQL. Then sign, install
   in place, run native/UI/curriculum acceptance and restore the normal app.
2. Android currently uses the Android Debug certificate. Provide the production
   release keystore/configuration before store submission. Device testing and
   successful debug-signed release compilation do not satisfy this requirement.
3. The completed Android checks apply to the tested ARM64/API 36 device and
   recorded artifacts. The two desktop Oracle tests still require the explicit
   runtime bundle; their skips are not execution passes.
4. Supported terminal SQL commands are `sql <file.sql>`, `sql -e/--execute` and
   `sql --help`, alongside real sandbox file commands. A complete interactive
   mysql/sqlite3 CLI and native cancellation/rollback handle are not provided.
   Desktop host-shell fallback can execute manually typed network tools; mobile
   has no fallback. Hidden offline UI does not imply global desktop networking
   isolation or universal service-level authorization.
5. Host stubs, x86 evidence and unsigned packaging never replace OHOS/Android
   device results. Apple and unrelated baseline changes are outside this
   platform acceptance; no Apple execution claim is made.

Keep the task active until the remaining acceptance requirements have concrete
evidence. Signing material is an external input already requested from the user.
