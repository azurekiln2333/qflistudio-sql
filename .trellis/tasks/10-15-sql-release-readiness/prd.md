# SQL Release Readiness

## Goal
Prepare qfli_sql for store submission by verifying the local SQL experience, terminal tools, curriculum, navigation, and Android/OHOS deliverables.

## Authorization and boundaries
The user explicitly requests implementation, Trellis tracking of all remaining work, conventional Git commits, builds on both platforms, and device testing where available. This authorization persists through review and implementation. Work only in D:/MyNewProjects/qfli_sql. Consume ../qfli_studio_core read-only; do not change shared home navigation or other products. Preserve the pre-existing dirty tree and user databases. Coordinate only agents whose live cwd matches this repository.

## Requirements
- R1: Verify standalone and embedded editor terminal capabilities, SQL execution, error handling, and method completeness against actual shared-core APIs.
- R2: Hide network features (Git remotes, cloud terminal/database, login and online services) in this offline product, respecting shared offline policy and removing app-local bypasses.
- R3: Unify SQL home locally into exactly five PageView destinations, preserving database workbench, projects/editor, tools/terminal, tutorials and examples. Avoid nested home shells and duplicate toolbars. This supersedes the prior no-home-tabs requirement of the 10-12 home task.
- R4: Audit every lesson/example. Preserve substantive existing curriculum if verified; if placeholders exist, replace only this product's bundled content with more than 100 substantive progressive lessons and runnable examples. Never erase user project/database data.
- R5: Run full static/unit/widget/curriculum/native checks appropriate to the changed code. Build Android and OHOS; attempt installation/testing on authorized connected devices without uninstalling or clearing user data. Record limitations honestly.
- R6: Commit each coherent verified change with conventional messages and scoped staging. Do not commit unrelated existing changes without review.

## Acceptance criteria
- AC1: Five local home destinations remain reachable and render on phone/desktop; no duplicated home navigation.
- AC2: Offline UI has no reachable cloud/login/Git-network actions; selected stale cloud settings cannot connect.
- AC3: Standalone/editor terminal parity is documented with executed evidence and explicit unsupported cases.
- AC4: More than 100 distinct complete SQL lessons/examples pass integrity and runnable checks; MySQL-specific execution is verified if a real runtime is available or explicitly recorded as unverified.
- AC5: Full analyze/tests, APK build, HAP build and available device checks have saved output and final artifact paths/hashes.
- AC6: Reviewed work is committed, other workspaces/shared core remain untouched by this task, and remaining release blockers are documented.
