# HarmonyOS phone verification: observed evidence

The user resumed phone MySQL work and stopped the terminal UI task. All device
verification below is authorized. No uninstall, data clearing or security
setting changes are allowed or have been performed.

## Device and ownership

- HDC target: 192.168.68.207:46551; MRT-AL10; aarch64.
- System: OpenHarmony-7.0.0.105. Dart reports HarmonyOS HongMeng Kernel 1.13.0.
- Bundle: com.azurekiln.qfli.sqlab; EntryAbility; normal/debug app.
- Pi in Herdr wC:p2 (pi-mysql) now owns native and HAP builds plus the complete
  install/start/report/debug loop, following the user's latest instruction.
  Root coordinates/reviews; other agents must not build or operate the phone.

## Observed results

1. A HAP declaring executableBinaryPaths for the packaged launcher failed
   installation with 9568449: check bin file failed. The same native binaries
   with that declaration removed installed successfully. The official field
   is PC/2-in-1-only; no alternative phone host is established by this result.
2. First phone run 1791522142230166_8cb099855825b500 (app PID 13808) failed at
   Oracle identity with child status 159 (128 + SIGSYS). Final stop passed and
   the app survived. No test schema was created. Full report:
   build/mysql-port/phone-probe-first-result.json.
3. After startup portability changes, run 1791524859941873_33d0ba34a034491e
   (app PID 45800) failed with Permission denied. Correct module log stages:
   fork -> parent-ok -> signals -> fds-closed -> exec-failed. Direct exec of
   the installed launcher failed before its main. Final stop passed; no test
   schema was created. Reports: build/mysql-port/phone-probe-stages-result.json
   and build/mysql-port/phone-initialize-stages.log.
4. /lib/ld-musl-aarch64.so.1 and /system/lib/ld-musl-aarch64.so.1 both exist
   with mode0755. The HDC shell cannot execute the former with --help
   (Permission denied). This is shell-domain evidence, not an app-domain test.
5. User additionally pasted run 1791527503013601_296a6ac99d485e75 with the same
   Permission denied identity failure. Pi is retrieving its full diagnostics.
6. The selected MySQL adapter/repository, SQL runner and query persistence
   Dart tests passed 21 cases (build/mysql-port/phone-dart-tests.log). The
   probe passed format and targeted Dart analysis. Native lifecycle tests and
   HAP builds passed for tested snapshots. None establishes phone Oracle PASS.

## Diagnostic paths and corrected inference

HDC file recv -b com.azurekiln.qfli.sqlab can retrieve debug-app files. Direct
shell reads of protected app paths fail.

- Dart AppPaths: /data/storage/el2/base/files; latest probe report is beneath
  mysql-ohos-probe/latest.json.
- ArkTS UIAbilityContext.filesDir: /data/storage/el2/base/haps/entry/files;
  native logs are beneath mysql/ (initialize.log, server.stderr.log,
  mysql.log, capability.log).

Earlier initialize.log ENOENT checks used the wrong app-global directory.
They do NOT prove which syscall caused SIGSYS. Do not assert prctl was
confirmed. Likewise EACCES alone does not prove universal phone exec denial
or a missing execute bit. API26 capability and interpreter invocation require
their own actual app-domain results. See the two SDK/musl research notes.

## Completion gate

Require actual probe PASS for Oracle8.4.6/socket, SQL/exact values/errors,
repository/editor operations, stop/restart and persistence. Then build/install
normal lib/main.dart and verify its workbench. Do not leave only the probe app.
Original production HAP: build/mysql-port/entry-production-before-phone-probe-20261009.hap.
Keep this task in progress until required phone acceptance is complete.

## Later evidence and director decision

The phone's API 26 native and Ark capability queries both ran successfully and
returned false. The app-domain log now records direct errno=13 and interpreter
errno=13 separately. The installed launcher and sibling NAPI DSO have mode0644;
the system interpreter has mode0755. This is evidence for denial of these
specific exec attempts, not proof that all future phone hosting is impossible.

Evidence naming needs care: the first retrieved
build/mysql-port/run-1791527503013601/latest.json actually contained runId
1791527638828183_5606e50c9450c6a0, not the user-pasted run. Native logs append
across runs. Pi has been directed to retrieve the exact nested report and label
each result using its internal runId, preserving this distinction.

Root authorized Pi to develop an isolated private-preload/fork prototype and
its binding/constructor/lifecycle evidence. Production activation still needs
those engineering gates and actual phone acceptance; no user reapproval is
needed for the already authorized implementation/debugging work. The design
keeps Oracle in separate children and does not run mysqld_main in Flutter.
Independent reviewers are checking the runtime boundary and probe data
isolation. Pi remains the exclusive build/device operator. No phone PASS has
been observed at this point.
