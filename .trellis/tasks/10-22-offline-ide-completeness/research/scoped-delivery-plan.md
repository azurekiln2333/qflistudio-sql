# Reviewed checkpoint scope

This is a staging plan, not a record of a commit. User authorization covers
Conventional Commits and pushes. The umbrella remains active after any host
checkpoint; original OHOS372 scripts, expansion and other owners' gates remain
open until actual evidence exists.

## Baseline preserved

The initial98 dirty/untracked items are recorded in baseline-git-status.txt.
Do not stage the whole repository or use reset/clean. In particular preserve
local_mysql_runtime.dart, pubspec.yaml/lock, startup_test.dart, native desktop
and Apple changes, startup/splash/AgreementReader/icon/signing changes and the
old task/research trees.

- `lib/main.dart`: stage only `sql_code_analyzer.dart` import and the
  `codeAnalyzer: SqlCodeAnalyzer()` profile entry. Startup changes are baseline.
- Backend index: stage only new diagnostics/audit guide rows; preserve existing
  desktop/OHOS baseline edits. Frontend index: only the new diagnostics row.
- `ohos/entry/build-profile.json5`: HEAD already selects both ABIs. The current
  remaining diff only adds an empty exclusion filter; no task hunk is necessary
  for the commit. Preserve the working-tree configuration without staging it.
- Newly authored specs are ignored by repository rules; explicit force-add of
  selected new guides is appropriate after review, never force-add a directory.
- The task directory belongs to this request, but individual evidence/authoring
  files must be selected explicitly. Native binaries, HAPs, certificates,
  generated build outputs and transient locks remain build evidence, not source.

## Logical commits after independent review

1. SQL engine context/tools/diagnostics and real SQLite script bridge, focused
   regressions and corresponding spec contracts. Include the new files needed
   by every changed import and native CMake source list.
2. Real x64 Oracle staging and full catalog audit, reproducible build/sign/package
   inspection/report collection tools, audit regressions and scoped evidence.
   Preserve isolated x64 build scripts/provenance needed to recreate artifacts.
3. Task planning/evidence and draft curriculum authoring as an explicit pending
   checkpoint, if appropriate. Drafts must remain outside shipped assets until
   the current original372-script OHOS gate passes.

Before committing inspect the staged name/status/diff, run staged whitespace
checks and verify baseline-only paths/hunks are absent. Record completed gates
and pending target evidence in the commit documentation. Push non-forced to all
five configured destinations and independently compare remote branch OIDs;
partial publication must be reported accurately.
