# Execution and acceptance

## Authorization / planning
- [x] Read complete attachment and loaded Trellis workflow/spec indexes.
- [x] Confirmed independent language repositories and global shared-core ownership.
- [x] Created unified requirement/design/execution artifacts with the full scope.
- [x] Activate task after artifacts/manifests validate; implementation explicitly authorized by attachment and repeated continuation.

## Ordered work
1. Capture current baseline git statuses, runtime/core revisions and live Herdr workspace IDs; publish SQL ownership to the global channel.
2. Run existing source AND shipped-assets SQL validators before expansion; preserve their per-engine coverage and failures.
3. Allocate disjoint content, inline-tools and diagnostics deliverables; do not let workers edit core, main.dart or native acceptance target concurrently.
4. Replace hardcoded native curriculum coverage with catalog-derived complete example/exercise execution and stable per-entry outputs.
5. Author 180 NEW paired substantive SQL topics as isolated drafts; validate their source/outputs. Promote and rebuild shipped assets only after step9 proves every original current OHOS script passes, then validate the expanded catalog on OHOS.
6. Flatten SQL-specific tools directly in Tools; add real offline engine-aware execution/plans/schema/index and useful SQL text operations.
7. Connect unsaved-buffer SQL diagnostics to the frozen CodeAnalyzer API; add isolated native syntax validation with no user-database execution.
8. Integrate core filtering/badges/highlighting/explorer/workspace/Problems changes and verify actual SQL behavior.
9. Refresh device/toolchain/signing, build current OHOS package and execute all catalog entries on OHOS when a target is available. Missing hardware/signing is not a pass.
10. Run static/full local suites, focused real-engine checks, responsive/large-text UI checks and review all owned diffs.
11. Update real project specs and evidence ledger; conventional scoped commits; push only reviewed history and compare remote hashes.
12. Cross-check every R1–R12 against current authoritative evidence and owner reports; keep umbrella goal active until all pass.

## Validation commands
- flutter analyze --no-pub lib test integration_test
- flutter test --no-pub --reporter expanded
- Read the source of `validate_content.py` and `validate_assets.py` before invocation; these scripts also have no help parser. Their normal commands execute the host checks and must preserve explicit MySQL exclusions.
- Read `tool/sql_curriculum/build_content.py` to inspect its generation interface. It has no help parser: `--help` still regenerates shipped assets, so never invoke it before the original OHOS gate permits promotion.
- hdc list targets; explicit-device commands only after live target identity and ownership.
- Appropriate owned native test/build commands from runtime audit; do not treat old reports as fresh execution.

## Risks / current limitations
- Existing native curriculum target covers only six MySQL examples; new coverage must include all SQLite examples/exercises.
- Core is changing concurrently under one owner; consumer tests must report exact revision/dirty snapshot.
- Native subagent account concurrency limits can interrupt workers. Inspect authoritative status and use verified Herdr Pi/local fallback; do not continually redispatch failed turns.
- No OHOS device or signing acceptance may be invented. Work that does not need those inputs continues.
- All pre-existing 98 dirty items remain outside scoped staging unless separately reviewed and necessary.

## Integration follow-up boundary (2026-10-22)
- The root coordinator owns sql_runner.dart, analyzer backend decoding after Pi p6 handoff, and the catalog audit/report harness. SQLite transport must never silently select MySQL on OHOS.
- Engine-context implementer owns sql_engine_preference.dart, sql_execution_context.dart and sql_workbench_page.dart. Pi p2 consumes that context in tools; stale preference contexts cannot dispatch SQL.
- Pi p5/p6 stopped after repeated provider 502. Native replacement owns only OHOS bridge/validation core/native tests; existing script fix is preserved. Draft author remains isolated from shipped assets until the original OHOS catalog gate passes.
- Audit failures must retain the full expected denominator and per-script records. A partial engine run or unavailable backend never passes the all-engine device gate.

## SQL workspace consumer follow-up (2026-10-23)
- Existing SQL editor integration proves diagnostics owner/dialect changes, but does not exercise sidebar reopening, session reconstruction or owner-aware Run through the actual SQLite runner.
- Add a SQL-owned `test/sql_workspace_integration_test.dart` using production `sqlProfile`, `EditorPage`, persisted `ProjectStore`/`ProjectHistory` and real bundled SQLite. Operate workspace UI before checking restoration; verify primary/secondary database writes and unsaved-buffer ownership through actual Run buttons.
- This boundary adds consumer acceptance only. Shared editor/tree/workspace implementations remain with their announced C/studio owners; no source patch, compatibility wrapper or production behavior change belongs in SQL for those APIs.
- Capture the exact consumed core source, including current dirty files. Serialize focused checks with other owners under current host memory pressure; a source-only proposal, unrun test or earlier core snapshot does not establish the new gate.
- Target process restart, normal OHOS UI and original/expanded curriculum remain separately required even if the host consumer regressions pass.

## SQL native offline follow-up (2026-10-23)
- R11 gap: platform handlers still open remote agreements/arbitrary URIs and execute Huawei authentication although SQL exposes offline UI. Actual behavior lives in EntryAbility and module permissions; MySQL uses a private Unix socket with skip-networking and does not require TCP permission.
- Change only EntryAbility external/auth dispatch and module.json5: reject openAgreement/openUrl/login with OFFLINE_ONLY before argument access, retain account channel compatibility, remove AccountKit/Want/router imports, client_id and INTERNET. Preserve clipboard, generated/SQLite/MySQL registration, runtime disposal, picker/share/window behavior and the pre-existing startupProgress block.
- AgreementReader page and route are pre-existing user work and stay byte-identical. No shared-core/runtime, user-file, signing or device mutation belongs to this patch. Native source/manifest baseline bytes and hashes are retained under ignored build/offline-ide-check/native-offline.
- Add an actual EntryAbility transpile/handler-double regression with explicit import doubles and no network. Verify refusals, exactly one response, no external effects, local dispatch/native registrations and disposal. Default checks must work on staged HEAD without baseline startupProgress; optional workspace-startup mode checks preserved WIP separately.
- Tighten tool/ohos/inspect_audit_hap.py to reject any permission set other than clipboard-only and add unit regressions. Historical INTERNET-bearing HAP stays historical; a fresh source-bound build/sign/inspection and actual OHOS gate are required after this change. No Flutter/HAP/WSL heavy process starts until explicit resource handoff.

## SQL named workspace integration (2026-10-24)

- Published core2f9039a3 enables standalone named workspaces, but the actual SQL shell uses `SqlLabApp` and `SqlProjectsPage` rather than the shared `QfliApp` Home. Its direct EditorPage route has no retained host, and its project page exposes no saved-workspace reopen entry. A test using QfliApp would bypass this product gap.
- Smallest production boundary: only `lib/sql_app.dart` owns/disposes a shared RetainedEditorController and wires its observer/RetainedEditorHost; only `lib/sql_projects_page.dart` uses public openEditorPage and adds the saved-workspace toolbar action, opening shared SavedWorkspacesTab. Preserve the SQL five destinations, database home, project list/search, offline policy, and unrelated main.dart startup work. Shared core remains C-owned.
- Add `test/sql_named_workspace_test.dart` through the actual SqlLabApp surface: create/save/open named membership via UI, reopen retained state, reconstruct the app, and verify root expansion, ordered document owners, cursors and standalone ProjectHistory isolation. Preserve the older two-case fixture SHA60c73c73 as an exact historical backup. Adapt its obsolete legacy dialog/history expectations to published core2f's named persistence contract while retaining both case names, the full real-engine Run case and all exception assertions; independently reviewed replacement SHAa9d57d5d remains UNRUN. No product-key bypass, final-session seeding or exception suppression.
- Source/static preparation may export the exact published core and rebind only the isolated review configs without pub. Runtime format/analysis/tests, fresh HAP build and target execution require their own new named windows. Preserve the historical HAP and exact metadata before replacement; device122/216 was explicitly deferred onward in527 because no reachable assigned target exists.

## Current native package preparation (2026-10-24)

- Actual inspector previously bound only its audit entrypoint while four helper source matches lived in a separate historical record. Require all five current kernel source/path bindings in the current inspector and cover stale/missing helper/body/path and newline cases, preserving the complete catalog/offline/ELF/signature rules.
- Build wrapper must invoke an explicit resolved Flutter executable, record its identity, and preserve metadata on failure. Source review must prevent a relative-path CWD regression and tests that pass before lock acquisition due to absent default SDK. New actual failed-Flutter transaction regression and corrected early-metadata fixture remain UNRUN until the full host window.
- Root created a file/Git-only isolated source capsule at `D:/MyNewProjects/qfli_sql_hap_src_20261024_1610`:468Git blobs,68 SQL source/config/native files,82 native inputs and four reviewed tooling overlays. No SDK/build/sign/device operation. Its environment/runtime are explicitly unverified; formatted successful host evidence and a fresh named bounded build window remain required before package acceptance. See research/current-native-capsule-20261024.md.
- Follow-up source correction now pins a selected DevEco installation and its process-local Node/npm/OHPM/Hvigor/Java/SDK environment in the existing builder, with exact restoration and authored fake success/failure/preflight/drift regressions. Independent source review fixed missing/relative APPDATA and relative SDK-selector CWD behavior. AST/ParseFile/whitespace checks pass; all36 current Python methods and real build acceptance remain UNRUN. Global Flutter settings and the checkpoint573 capsule were not modified. See research/native-toolchain-pinning-20261024.md.

## Trilingual README addition (2026-10-26)

- User requests a full root README rewrite in Simplified Chinese, Traditional Chinese and English, followed by scoped Conventional Commit and push.
- Ownership: Herdr w2C:p2 -> README.md; w2C:p6 -> README.zh-TW.md; w2C:p5 -> README.en.md; w2C:p7 -> independent research/readme-review-20261025.md. All four Pi run in the SQL workspace. Retry only confirmed failed requests and preserve active turns.
- Chinese acceptance: one action per sentence, active voice, one term per concept, instructions at most25 characters and explanations at most40, no semicolon joining, empty verbs, stock phrases, marketing adjectives or vague terms. Preserve modal uncertainty. Mechanical first check: python scripts/ste-lint-zh.py README.md README.zh-TW.md. Manually inspect Traditional equivalents and instruction length.
- Docs must have reciprocal language links, useful setup/build/check instructions, accurate offline and engine/platform limits. Do not claim pending workspace/full native/device gates passed. Link only paths shipped by the final commit. Keep baseline linter and all product WIP unchanged.
- Validate docs, language parity, Git-object link targets and whitespace. Stage only the three README files after independent final review. Do not archive this umbrella task or claim its device/all-product gates complete.


## C616 source-only fixture correction boundary (2026-10-26)

- Failure gap: two cases read a checkbox before an async real-IO workspace dialog becomes visible. A third case uses element existence as evidence that a retained tree is interactive. Keep all three names and all workspace ownership/history/cursor/real-engine assertions.
- Ownership: Herdr p2 edits only test/sql_workspace_integration_test.dart to await the actual dialog using the existing bounded real-IO-aware helper. Herdr p6 edits only test/sql_named_workspace_test.dart to require interactive tree controls/positive rows before actions. No blind repeated toggle.
- Product integration and shared core remain unchanged. No final-session seeding, skipped assertions, hit-test warning suppression or new runtime command. The causes of the third case geometry remain unconfirmed. A new named grant must verify the revised three cases.
- Preserve C616 pre/post-format source bytes and consumed launch. Independently review the exact test-only diff, then refreeze source/review hashes without SDK invocation. Do not install a failure receipt into full-gate success prerequisites or commit unverified product integration.


## Saved terminal coordinator preparation (2026-10-26)

- Preserve immutable run-bounded-retry.py and revised3case launch. Add only a saved source-only control-plane observer under ignored build/workspace so the successful C616 automatic parent observation can be reviewed and repeated without model scheduling lag.
- Native trellis-implement owns coordinator creation and readiness research. Native trellis-check reviews/fixes only those artifacts. Four existing SQL Herdr Pi independently inspect fixture waits, tree interaction, child proof fields and native acceptance gaps. Retry confirmed request failures; reset only a settled failing Pi session with documented /new if repeated model refusal prevents progress, preserving files/transcripts.
- Before ACK bind exact current author/slot/actual channel sequence/text hash and exclusive replay claims, source4/review68/core/archive/runner identities. No source copy, dependency resolution or preparation inside the accepted window. Suspended outer Job containment and exact HANDLE/PID/FILETIME provide a97s wrapper deadline inside110s total.
- No runtime until the observer source passes review and a NEW named grant explicitly accepts the bound command and control-plane publication contract. Separate immutable gate results from final publication metadata errors. Every validation/pending-publisher root must be terminal+active0 before release; the final sender cannot attest its own terminal state while sending. Coordination question697 records this protocol boundary.
- Current observer remains UNRUN/non-READY. No old C586/C616 grant replay. All source-only current-source/HAP/device/catalog/all-product gaps remain open.


## Same-device MySQL sharing implementation (2026-10-26)

- User explicitly authorized implementation, scoped commit and push. The backend owns OHOS runtime/channel/NAPI/manifest. Tools owns the inline service card and typed controller. Root owns integration/docs/specs. Existing Herdr Pi own audit permission policy and independent account/lifecycle/UI source reviews. Preserve unrelated WIP and all shared-core ownership.
- Internal clients retain the private Unix socket. The explicit service binds only 127.0.0.1:3306. Provision and verify generated persisted admin/shared credentials while networking is disabled, then stop before enabling TCP. Never expose insecure initialization or use init-file as the only security barrier. Disable MySQLX.
- The Tools page exposes start/stop/status and connection details. Do not claim background persistence or cross-app OHOS reachability until a real two-app target test. Runtime failure remains visible. Cloud requests remain blocked.
- Source/AST/Chinese lint and independent review may proceed now. Analyze, focused driver/controller tests, native compilation and two-app target acceptance require fresh named grants. No old C586/C616 replay, device inference or source snapshot parity claim.


## OHOS 14u delivery preparation (2026-10-26)

- User explicitly requested a current OHOS build and HDC file delivery to 192.168.68.207:46551. Build the normal production main.dart ARM64 app, not the separate curriculum audit target. Preserve installed application data. No install/start/reset is requested.
- C actual939/943 queue: Web, Python HAP, Rust, SQL, Note. SQL remains source-only until a fresh named grant covers both incremental qfli_mysql bridge rebuilding/staging and normal HAP packaging. No historical grants or idle-state inference.
- Configured SQL signing cert/profile/store are absent. An explicitly unsigned HAP may be delivered after genuine current build emission and independent package verification. No foreign signing identity, fabricated signing pass or stale output substitution.
- Freeze exact scripts, source/core/config/tool hashes and old artifacts before admission. Bound owned Windows process trees and WSL native groups independently. Retain exact process/Job handles until terminal plus active0. Release back to c-coordinator only after original tool completion is observed.
- Inspect the new production bundle/release mode, exact permissions, ARM64 AOT/native ELF, new sharing methods and rebuilt bridge hash, unchanged retained server images and current curriculum assets before file send. Record remote file bytes/hash after a separate exact-target transfer grant.
