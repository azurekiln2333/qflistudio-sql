# Execution

- [x] Confirm repository and shared-core dependency; inventory initial dirty tree and existing related tasks.
- [x] Persist requirements, design, execution plan and spec manifests using the user's explicit implementation authorization.
- [x] Verify live Herdr workspace identity; dispatch three existing qfli_sql Pi agents with non-overlapping ownership (live wC:p5/p6/p7; inherited wY environment was stale and never used for mutation).
- [x] Implement app-local five-page home and verify phone/desktop navigation (0eb72c7, 92 tests pass, 2 unavailable desktop Oracle skips).
- [x] Audit terminal methods and offline surfaces; repair app-local bypasses and add meaningful regressions (91717ae; 75 combined terminal/offline/shared checks pass).
- [x] Audit all existing SQL lessons/examples and execute validator, correcting only demonstrated defects (6457be4/d9ff3a7; 126 complete pairs, 120 SQLite examples + 240 authored exercise results pass from source and shipped JSON).
- [x] Build final Android ARM64 release APK and OHOS unsigned release HAP against source-clean core 8b33443; record native/asset hashes and Android 16 KiB packaging audit in the final platform reports.
- [x] Run full repository Dart analysis with zero issues; run appropriate native host regressions (30 preload checks plus lifecycle/mechanism/stdio suites; db5209a/cc68a2a/2753499).
- [x] Finish Android manifest isolation regression (4 actual cases); commit 84746f1. Harden old native UI targets against production sandbox access, stale tree navigation and incomplete cleanup; commit c0a88bc.
- [x] Finish Android native curriculum/lifecycle/workbench device tests; restore final production release after physical-device testing. OPD2413 ARM64/API 36 passed all four targets (6+2+6+1=15), including 12 authored MySQL outputs. Production release restored with install -r, five pages visually checked, production PID log clean for matching fatal/unhandled/overflow patterns. SQL explicitly released the window in global seq53. SQL's temporary 5582 emulator is stopped; no Go/Rust 5580 actions.
- [x] Revalidate final app tests/builds against clean shared-core 8b33443 (Flutter/scoped and repository Dart analysis clean; 92 tests pass/2 unavailable desktop Oracle skips).
- [x] Review complete owned source diffs and update SQL frontend/runtime specs; conventionally commit verified deliveries (8461bd6 and prior implementation batches).
- [x] Record final evidence and remaining work. Preserve the active release task because production signing and OHOS device acceptance remain external requirements; do not archive it as store-ready.

## Git publication follow-up (2026-10-16)

- [x] Configure origin to fetch from CNB and push main to CNB, GitHub, Gitee, GitCode and GitLab; use existing GitLab SSH authentication where HTTPS credentials are unavailable.
- [x] Publish the reviewed main history to all five repositories without force; preserve the unrelated dirty tree and consume shared core read-only.
- [x] Record publication configuration and evidence in `research/git-publication.md`; require synchronization of the documentation commit and explicit comparison of all five remote main hashes with final local HEAD.

## Remaining external acceptance requirements

- OHOS SignHap references a missing sqlab .p12/.p7b/.cer set; every available profile belongs to another product. Await a valid com.azurekiln.qfli.sqlab signing configuration before signing, in-place installation or actual phone acceptance. The unsigned HAP is compiled/packaged and verified; it is not an install/run pass.
- Android release currently uses the Android Debug certificate. Test builds/installations may proceed; production store submission requires a real release keystore/configuration.
- The two desktop Oracle tests require QFLI_MYSQL_TEST_BUNDLE. Their explicit skips do not establish desktop runtime acceptance.
- Never archive this release task as complete while signed OHOS device acceptance or production signing is still missing.

## Validation
Use the installed Flutter OHOS SDK for OHOS and a compatible Android Flutter SDK discovered from the environment. Run tool/sql_curriculum/validate_content.py with its documented options. Save long logs under research; do not claim builds, device runs or MySQL-only curriculum execution without actual evidence. Device commands must use explicit live serials and this application's bundle/application IDs.

## Rollback
Use narrowly scoped corrective patches, never tree reset/revert of other sessions. Avoid shared-core modifications and destructive installation flags. Main coordinator serializes Git staging/commits after inspecting the index.
