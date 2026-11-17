# Journal - lichengyu (Part 1)

> AI development session journal
> Started: 2026-09-30

---



## Session 1: Oracle MySQL port and workbench implementation
<!-- trellis-session: v=2 fp=77c8b1224f7e434d -->

**Date**: 2026-09-30
**Task**: Oracle MySQL port and workbench implementation
**Branch**: `main`

### Summary

Compiled and packaged Oracle MySQL 8.4.6 arm64 server/client, integrated native lifecycle and Oracle adapters, and added schema tools plus capped SQL import/export. Phone process hosting remains blocked by documented platform API restrictions; task stays in progress.

### Main Changes

- Added pinned native build inputs, child entry, async query/script channels and app-private lifecycle management.
- Added schema operations and independent metadata view; corrected primary-key discovery and exact URI I/O.

### Git Commits

| Hash | Message |
|------|---------|
| `40964aa` | feat(mysql): package Oracle runtime and native lifecycle |
| `bb02a71` | feat(sql): add Oracle schema tools and SQL import export |

### Testing

- [OK] Native Oracle server/client linked with --no-undefined; full Hvigor HAP compilation and signing succeeded. Automated tests, analyze and device probes were deferred at user request.

### Status

[OK] **Completed**

### Next Steps

- Establish a supported phone process host before claiming Oracle runtime availability; target initialization, persistence and shutdown acceptance remain pending.


## Session 2: SQL curriculum: 126 lessons, examples, and local content repository
<!-- trellis-session: v=2 fp=48b5ea20dbf837dd -->

**Date**: 2026-10-12
**Task**: SQL curriculum: 126 lessons, examples, and local content repository
**Branch**: `main`

### Summary

Delivered an app-local SQL curriculum (126 lessons/examples) with a local ContentRepository, replacing placeholder content; 120 SQLite lessons executed/verified, 6 MySQL lessons marked not executed.

### Main Changes

- Added assets/content/sql_tutorials.json + sql_examples.json (126 each) and lib/sql_content_repository.dart implementing the shared ContentRepository over local assets.
- Added tool/sql_curriculum authoring/validation pipeline (Python) and test/sql_curriculum_test.dart; registered assets in pubspec.yaml.
- Fixed peer-review findings (L82/L102 explain, L91 prompt, L92 TEMP note) and guaranteed dialect/version visibility in every explain.

### Git Commits

(No commits - planning session)

### Testing

- [OK] [OK] python build_content.py / coverage.py / validate_content.py: 126 lessons, 120/120 SQLite examples, 240/240 exercise answers, 6 MySQL not executed.
- [OK] [OK] flutter analyze (2 files) clean; flutter test test/sql_curriculum_test.dart 8/8; whole-repo flutter test 61 passed, 2 skipped.

### Status

[OK] **Completed**

### Next Steps

- Await UI stabilization, then run parent-task final integration review; no commits/push per instruction.


## Session 3: SQL home tree, standalone projects page, and final integration acceptance
<!-- trellis-session: v=2 fp=dfc969408d2b5ba1 -->

**Date**: 2026-10-12
**Task**: SQL home tree, standalone projects page, and final integration acceptance
**Branch**: `main`

### Summary

Completed C1 (home = DB->table tree; standalone single-toolbar projects page; 功能/终端/SQL tools reachable; collapse survives refresh; 390/1280 2x layouts) and accepted the parent task after resolving all content (F1-F5) and UI (U1-U6) peer-review findings.

### Main Changes

- C1: SqlWorkbenchPage home body = DB/table tree; SqlProjectsPage self-contained single AppBar reusing ProjectStore/ProjectCard/ProjectDialogs/EditorPage; _collapsed set; 功能 menu restores FunctionsTab (terminal + content tools).
- Resolved content peer F1-F5 (L82/L102 explain, L91 prompt, L92 TEMP note, dialect clause) and regenerated assets; resolved UI peer U1-U6 incl. spec sql-workbench.md.

### Git Commits

(No commits - planning session)

### Testing

- [OK] [OK] python coverage.py passed; validate_content.py 120/120 examples, 240/240 exercises, 6 MySQL not executed.
- [OK] [OK] flutter analyze lib test: only 1 pre-existing baseline info (unrelated sql_document_service.dart); changed files net-pass.
- [OK] [OK] flutter test --no-pub: 65 passed, 2 skipped (exit 0).

### Status

[OK] **Completed**

### Next Steps

- Await user instruction to commit/wrap up; do not push. MySQL 6 lessons remain not executed on this host.


## Session 4: SQL offline release implementation and build audit
<!-- trellis-session: v=2 fp=d7009cb4a36cf15e -->

**Date**: 2026-10-15
**Task**: SQL offline release implementation and build audit
**Branch**: `main`

### Summary

Delivered SQL-only five-page home, offline guards and terminal delegate; audited126 lessons/examples; committed native lifecycle fixes and final Android/OHOS build evidence. Release task remains active for isolated Android runtime acceptance and missing production signing inputs.

### Main Changes

- Preserved the original dirty worktree and all user databases; verified three Pi working directories; consumed source-clean shared core8b33443 read-only.

### Git Commits

| Hash | Message |
|------|---------|
| `41b710d` | docs(trellis): plan SQL release readiness verification |
| `6457be4` | feat(sql): ship 126 verified lessons and runnable examples |
| `91717ae` | fix(sql): enable local terminal SQL and block offline cloud access |
| `0eb72c7` | refactor(sql): unify five-page home and preserve offline workflows |
| `db5209a` | fix(ohos): complete private MySQL host lifecycle and packaging |
| `cc68a2a` | test(native): resolve runtime checks from their own workspace |
| `d9ff3a7` | test(sql): add native curriculum acceptance and exercise expectations |
| `2753499` | chore(quality): isolate build snapshots and preserve shell line endings |
| `1bfb0cb` | feat(mysql): allow isolated native runtime plugin directories |
| `84746f1` | fix(android): isolate generated integration test targets |
| `c0a88bc` | test(android): harden native acceptance isolation and cleanup |
| `8461bd6` | docs(sql): codify offline terminal and five-page release contracts |
| `36d821e` | docs(release): record SQL build and acceptance evidence |

### Testing

- [OK] Flutter and repository Dart analysis clean; complete host suite92 passed with2 unavailable desktop Oracle skips.120 SQLite examples/240 exercises and6 real Linux MySQL examples/6 exercises pass; production OHOS preload host30 assertions plus lifecycle/mechanism/stdio checks pass.
- [OK] Android ARM64 production-entry release APK built and audited for native/assets/16KiB alignment; unsigned OHOS HAP freshly rebuilt and hash-checked. Android isolation matrix4/4 passes.

### Status

[OK] **Completed**

### Next Steps

- Run shipping Oracle8.4.6 Android emulator/device curriculum, lifecycle and workbench targets; restore final production app when physical-device window is free.
- Provide SQL-specific OHOS key/profile/certificate and production Android keystore; retain explicit signing/device blockers and do not archive release task.


## Session 5: SQL physical Android release acceptance
<!-- trellis-session: v=2 fp=0f3a423e6c3aadc9 -->

**Date**: 2026-10-15
**Task**: SQL physical Android release acceptance
**Branch**: `main`

### Summary

Completed physical ARM64 Android acceptance and production restoration; retained explicit external signing and OHOS device requirements.

### Main Changes

- Shortened isolated curriculum Unix socket paths and preserved canonical cleanup ownership.
- Verified and committed physical evidence; released OPD2413 in global event53 after restoring production without uninstall/data clear.

### Git Commits

| Hash | Message |
|------|---------|
| `30ee9cb` | test(android): shorten isolated curriculum socket paths |
| `b3a204d` | docs(release): record physical Android acceptance and signing blockers |

### Testing

- [OK] Four physical targets: curriculum6, Oracle2, SQLite6, workbench1; all15 passed, twelve authored MySQL outputs plus cleanup verified.
- [OK] Five normal product home pages visually inspected; surviving production PID had zero matching fatal/unhandled/overflow log entries. Exact final APK/HAP SHA256 identities verified.

### Status

[OK] **Completed**

### Next Steps

- Supply SQL-specific OHOS signing and Android production keystore; sign/rebuild as needed and perform OHOS phone acceptance. Keep release task active.
- Provide QFLI_MYSQL_TEST_BUNDLE for the two skipped desktop Oracle checks.


## Session 6: SQL five-host Git publication
<!-- trellis-session: v=2 fp=bc06a0755f163911 -->

**Date**: 2026-10-16
**Task**: SQL five-host Git publication
**Branch**: `main`

### Summary

Configured origin with five push URLs; published main and verified identical tips on CNB, GitHub, Gitee, GitCode and GitLab.

### Main Changes

- CNB is the fetch remote; ordinary git push targets all five destinations. GitLab uses the existing authenticated SSH key.

### Git Commits

| Hash | Message |
|------|---------|
| `42602e3` | docs(git): record five-host publication configuration |

### Testing

- [OK] Plain git push completed successfully for all five. Independent ls-remote refs/heads/main checks matched 42602e37e75dff348ed4d2a453f7c8af009a4fbb everywhere.

### Status

[OK] **Completed**

### Next Steps

- Release-readiness signing and OHOS device requirements remain in the active task; no unrelated dirty files were staged.


## Session 7: SQL native offline policy and third workspace gate
<!-- trellis-session: v=2 fp=5f63b4f523aaab2d -->

**Date**: 2026-10-23
**Task**: SQL native offline policy and third workspace gate
**Branch**: `main`

### Summary

Published native offline refusals and clipboard-only permissions; host guards pass, actual third workspace run fails honestly and releases the serial slot.

### Main Changes

- Committed native offline policy6999b0d, excluding baseline startup WIP; all5 mirrors independently matched.
- Recorded three workspace failures and source-only fixture corrections; C adopted the real focus-context lifecycle defect282.

### Git Commits

| Hash | Message |
|------|---------|
| `6999b0d` | fix(ohos): enforce native SQL offline policy |

### Testing

- [OK] Actual EntryAbility303 assertions PASS, preserved-startup337 PASS, independent7mutation controls rejected; package Python7PASS.
- [FAIL] Explicit grants263264: scoped analyze0issues; exact2workspace tests0PASS/2FAIL, PID12368/tool40310 exit1 after9.5s; released274 toGo.

### Status

**In progress** — native fix published; workspace, OHOS and umbrella gates remain open.

### Next Steps

- Consume a verified C checkpoint with focus fix, then format/analyze/rerun both workspace cases in a new named slot.
- Fresh source-bound HAP build/sign/inspection and exact-device original126/372 audit; hold180drafts until original OHOS passes.


## Session 8: GitHub native builds, GPL license and main merge
<!-- trellis-session: v=2 fp=72c776a357d48938 -->

**Date**: 2026-11-17
**Task**: GitHub native builds, GPL license and main merge
**Branch**: `main`

### Summary

Built OHOS and Android Oracle/SQLite plus iOS SQLite on GitHub. Verified downloaded hashes, architecture and dependencies. Added GPL v3 matching qflistudio, merged the CI branch into main, and preserved local data.

### Main Changes

- Added pinned hosted mobile native workflow, manual platform selection and artifact/source provenance.
- Copied the main project GPL v3 license and preserved upstream notices.

### Git Commits

| Hash | Message |
|------|---------|
| `191f918` | ci: build mobile native runtimes on GitHub |
| `9a86d8f` | fix(ci): use available Android tools and macOS runner |
| `5a83aea` | fix(ci): pin observed Linux OpenHarmony SDK metadata |
| `59f6324` | docs(license): add GPL-3.0 to match qflistudio |
| `08a3b41` | fix(ci): repair native packaging and enable targeted retries |
| `07bb4b1` | docs(ci): record verified native artifacts and main merge |

### Testing

- [OK] actionlint, shell syntax, Python packaging round-trip and actual hosted builds passed.
- [OK] Downloaded OHOS, Android arm64/x86_64 and iOS packages passed checksum and binary inspection.

### Status

[OK] **Completed**

### Next Steps

- Download accepted artifacts before their December 1, 2026 expiry. Device/application integration remains separate.
