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
