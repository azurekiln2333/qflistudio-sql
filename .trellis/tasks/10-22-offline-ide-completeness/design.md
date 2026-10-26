# Design

## Change boundary
The behavior gaps are incomplete curriculum execution coverage, generic secondary SQL tools, and missing SQL diagnostics. They live in SQL content authoring/assets, the native curriculum integration target, SQL-owned tools/services, and a typed CodeAnalyzer adapter. Common filtering/badges/explorer/workspace/highlighting/Problems rendering remain owned by the C/core team.

## Ownership
- SQL coordinator owns task artifacts, integration, source review, commits/push, and cross-product evidence.
- Content worker owns tool/sql_curriculum source/build/validation and assets/content JSON only.
- Tools worker owns lib/sql_tools_tab.dart, new SQL text/tool service and focused tests only.
- Diagnostics/native worker owns lib/sql_code_analyzer.dart, isolated syntax-validation service/FFI extension and matching tests when allocated.
- Coordinator serializes lib/main.dart registration and native acceptance target. Workers must adapt to concurrent changes, never revert them or stage/commit.

## Content/data contract
Retain IDs 1–126 and authored outputs. Add 180 distinct paired lessons/examples with self-contained fixtures and exercise answers. Generate shipped assets through the existing authoring pipeline. Check exact lesson/example identity and code/output equality, and execute every example/exercise under the declared SQLite/MySQL engine. Dynamic native acceptance derives IDs from the actual catalog, verifies complete coverage and emits per-entry markers; a hardcoded six-item list cannot prove all content.

## Tools contract
Tools is a retained, responsive app-local body under the existing single toolbar. SQL-specific controls render directly in it. Use SqlWorkspaceRepository/NativeMySqlDatabase/NativeSqliteDatabase and the existing engine preference/owned database-path rules. Query/plan/schema/index results preserve columns, rows, SQLSTATE, truncation, partial results and backend-unavailable status. Plain EXPLAIN does not become EXPLAIN ANALYZE. No separate Begin/Commit buttons across per-call connections. Common tools and terminal keep their working routes.

## Diagnostic contract
Consume qfli_studio_core/services/code_analysis.dart:
CodeAnalyzer.analyze(CodeAnalysisRequest), immutable unsaved document snapshots, UTF-16 half-open offsets, typed severities and explicit unavailableReason. Lexical scans handle literals/comments/parentheses with correct dialect considerations and source bounds. Full SQLite grammar validation uses an isolated database/connection, never writable user state, binds sqlite3_error_offset with UTF-8-to-UTF-16 conversion, and distinguishes missing-schema/unsupported from syntax failures. MySQL validation must prepare without execute if implemented. Core owns debounce, stale-result rejection, waves, Problems navigation and editor lifetime.

## Offline and compatibility
Developer research and Git publication may use network; app tools use only bundled engines, owned local files and pure computations. Preserve existing profile/runner/terminal contracts and all baseline WIP. Keep old curriculum IDs and valid persisted user databases. No destructive migration.

## Validation and rollback
Use injected engine/repository seams for unit/widget behavior, real isolated SQLite/MySQL for semantics, current OHOS builds and device acceptance for target claims. Retain accurate unavailable results. Scoped corrective patches only; never reset/clean baseline work. Review each worker diff and the final integration before scoped commits.


## Same-device MySQL sharing implementation (2026-10-26)

- User explicitly authorized implementation, scoped commit and push. The backend owns OHOS runtime/channel/NAPI/manifest. Tools owns the inline service card and typed controller. Root owns integration/docs/specs. Existing Herdr Pi own audit permission policy and independent account/lifecycle/UI source reviews. Preserve unrelated WIP and all shared-core ownership.
- Internal clients retain the private Unix socket. The explicit service binds only 127.0.0.1:3306. Provision and verify generated persisted admin/shared credentials while networking is disabled, then stop before enabling TCP. Never expose insecure initialization or use init-file as the only security barrier. Disable MySQLX.
- The Tools page exposes start/stop/status and connection details. Do not claim background persistence or cross-app OHOS reachability until a real two-app target test. Runtime failure remains visible. Cloud requests remain blocked.
- Source/AST/Chinese lint and independent review may proceed now. Analyze, focused driver/controller tests, native compilation and two-app target acceptance require fresh named grants. No old C586/C616 replay, device inference or source snapshot parity claim.
