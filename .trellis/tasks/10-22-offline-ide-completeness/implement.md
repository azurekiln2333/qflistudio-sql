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
