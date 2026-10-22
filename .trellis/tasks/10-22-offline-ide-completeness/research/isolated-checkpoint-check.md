# Isolated checkpoint verification — 2026-10-22

The reviewed source checkpoint passes without the98-item baseline working-tree
changes. Product commit: `9f92d49f6c911adcc36e39792a725d3d7a7733ec`.

## Exact scope

A detached checkout at `D:/MyNewProjects/qfli_sql_checkpoint_review_20261022`
started from SQL HEAD `42602e37e75dff348ed4d2a453f7c8af009a4fbb`. Only the59-file
staged task patch was applied. SHA256 of the exact binary-capable patch:
`864028c6a5b3c8a0d636e061f640ef657ec369235fe8612ca929c1c2c228b8c3`.
Root compared the complete staged patch byte-for-byte again before committing.

Excluded baseline edits include startup/main changes except analyzer registration,
local_mysql_runtime.dart, extra pubspec devdependency, startup_test.dart, Apple
packaging, old research, signing configuration and ArkUI/icon/agreement work.
The working tree preserves those edits. `main.dart` stages exactly two added
lines; each spec index stages only the new task guide rows.

The actual bundled Windows SQLite DLL was copied to the review checkout and
verified as SHA256 `12bb8326b9ab400472d4b95596cb343512a10ab2ac6e40620e09df2da2c59f93`.
No unrelated runtime or baseline source was copied. Offline dependency resolution
used committed pubspec inputs and the existing sibling core path.

## Results

| Command in isolated checkout | Result |
| --- | --- |
| `flutter pub get --offline` | PASS, exit0 |
| `flutter analyze --no-pub lib test integration_test` | PASS,0issues |
| `flutter test --no-pub --reporter expanded` |272PASS,0FAIL,2SKIP |
| `python -m unittest discover -s tool/ohos -p 'test_*.py' -v` |26/26PASS |

The two skips still require `QFLI_MYSQL_TEST_BUNDLE` and are not MySQL runtime
passes. Real SQLite regressions, complete host SQLite curriculum coverage,
new statement-cap acceptance/refusal, deleted-schema UI clearing, actual
editor/Problems integration and real Dart-to-Python report collection all ran.
The count differs from the earlier full working-tree snapshot because unrelated
startup tests are excluded and subsequent task regressions are included.

The initial delegated isolated-check turn failed due provider account concurrency.
Root explicitly stopped/transferred that assignment and executed the verification
commands directly. No source fix was needed in the isolated checkout.

## Stable consumed source

SQL monitored63 Dart/config files and core monitored264 files. Both before/after
manifests are identical; neither repository HEAD nor git status changed during
the gate. Core HEAD was `f8edb0424e40afc5e8dba6a874cb240f467ffd7b`, including the
published optional debugger contract. Core remained dirty under its exclusive
owner, so this is evidence for the captured working-tree source, not a claim
of a clean core checkout. SQL made no shared-core edits.

Local full evidence: `build/offline-ide-check/isolated/{before,after,comparison}.json`,
`flutter-analyze.log/.exit`, `flutter-test.log/.exit`, `python-tests.log/.exit`;
the original exact patch is `build/offline-ide-check/staged-review.patch`.

## Remaining acceptance

Independent current x64 HAP inspection/signature/profile verification passes
for `0c5007b468e3e525d687b4e52983865b4c84d6ad2a89dd006aaf83bd8df76d78`.
That remains static package evidence. The actual original126/372 OHOS run,
subsequent306/912 promotion/run, normal target UI and sibling gates remain open.
This checkpoint does not archive the task or complete the umbrella goal.
