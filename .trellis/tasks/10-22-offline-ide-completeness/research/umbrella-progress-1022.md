# Research: Cross-product evidence checkpoint

- Query: Refresh the complete request's delivery ledger without conflating host, package and target evidence.
- Scope: internal; global owner reports and the reviewed SQL checkpoint.
- Date: 2026-10-23 (Asia/Shanghai).
- Source: global `qfli-core-release-sync` channel through seq163, last message `2026-10-22T16:31:31.773Z`; SQL evidence files listed below.

## Findings

Sibling results below are owner reports, not SQL-run sibling tests. The complete
user goal remains active; SQL delivery cannot close other products' requirements.

| Product / owner | Host / source evidence | Package / delivery evidence | Actual target evidence and remaining gates |
| --- | --- | --- | --- |
| C/C++ and shared core / c-coordinator | C222 Flutter tests and31 real Clang/WasmEdge runs pass; exact unsaved C/C++ analysis. Owner-aware Run/preview32 tests pass. Debugger controller18 tests and supervisor48 tests plus4 Linux cases reported; their reviews remain ongoing. | C analyzer `2cccdbeb85ea5994898fd75a82aa756c07786324` pushed; signed ARM64 HAP inspected. Core debugger contract `f8edb042`, Go import fix `e13d50d`, owner-run repair `0ec321c974c524a57cedcfcc39f09bb8ab7f50e7` pushed. | C device execution remains false. Web reports a confirmed default-preview regression after `0ec321c` (171pass/1fail); owner fix and regression acceptance needed. Common debugger UI, process cancellation integration and import rollback concurrency review remain open. Seq156/158/161/162. |
| Java / java-offline-1022 | Original280/1120 curriculum,235 app/23 core tests, exact dirty-buffer checks and16 real JDI checks reported pass. | `4d5d2a308a8a25d7bf82b32610a496c6dd5e2232` pushed/verified; tree reported clean. | Actual x64 OHOS280/1120 reported pass. Physical ARM64 and common workspace/URI-transfer gates remain separate. Seq120. |
| Web / web-offline-1022 | Repaired/frozen curriculum481/481 passes desktop4016 assertions and mobile4015; no tutorial mapping issues. After core `0ec321c`, full Web suite171pass/1fail in default preview. | Current normal-entry dual-Flutter-ABI HAP rebuilt; normal-main HAP `b3ac4a80` reported installed by driver, but subsequent start/screenshot found the target disconnected. Launch success is unproven. | Actual adapter/Nginx15/15 pass; completed second native run474PASS/7FAIL with4012 assertions. Earlier443/481 failure retained. Web explicitly releases to Lua121; seven repairs, preview regression and a later final481 rerun remain open. Seq160/162/163. |
| Lua / lua-offline-1022 | Real native480/480 exact host scripts; corrected teaching content and parser/debugger work. Full1282-location audit/direct JS/TS/Shell tools were in final tests at seq155. | Signed inspected x64 HAP `b0db102354fba64f…` ready for682 Lua sources; complete1282-location replacement not yet handed off. | Queue121 after Web. Installed curriculum/debugger acceptance open. TS syntax/options checks do not establish semantic typing; direct-PID escalation does not establish process-tree cleanup. Seq153/155. |
| SQL / sql-offline-1022 | Isolated checkpoint272PASS/2OracleSKIP, analysis0issues and26/26 Python checks; real SQLite120/360. Draft180 topics/540 scripts pass bundled3.50.0 and CLI3.50.6. | Four reviewed commits `9f92d49`, `69b428e`, `9c6da05`, `6a5de4c`. Current capfix signed x64 Oracle audit inspected; exact identity below. Remote verification is not recorded in this snapshot. | Queue122 after Lua; zero SQL device operations. Complete original126/372 OHOS gate first, then promotion and full306/912 OHOS gate. Normal target Tools/dirty-editor/Problems/offline/workspace acceptance remains open. |
| Python / python-offline-1022 | Original120 mains +186 standalone answers306/306 pass real embedded execution with no skips; module306 assertions and128encoding/256CSV import checks previously reported. | Module foundation `a1a953bd` pushed to5 mirrors; signed inspected x64 module HAP `d1387df94ebe8cb7…` ready. Seq159 claims a serialized Python-only aggregate generation window; release not yet observed. | Queue124. Installed module/import/offline and original-curriculum gates open. Real debugger/product adapter work resumes against contract156; no device operations reported. Seq141/143/159. |
| Rust / rust-offline-1022 | Tools62 and analyzer/catalog66 checks; pinned rustc unsaved diagnostics. Miri analysis ABI defect repaired;332 host preflight was in progress at seq147, with no later completion handoff here. | Matching current package/native delivery evidence pending. Shared secondary-root Run repair is published by core, with Web preview regression still open. | Queue128; actual OHOS curriculum and feasible debugger acceptance remain open. Seq147/161/162. |
| Go / go-offline-1022 | Core official-Go-test filename repair `e13d50d` delivered with98 focused checks; product owns execution and fixture/runtime work. | Matching ready product package not yet handed off. | Original OHOS scripts and product/debugger acceptance pending; joins queue when ready. Debugger adapter must stop and poll terminal completion before native close. Seq135/151/156. |
| Dart / dart-offline-1022 | Vendored runtime executes all original240 host programs exactly;192 tests and analysis pass. Bounded native isolates/IO implemented;180 draft topics retained. | Runtime migration reported uncommitted at seq150; own audit package preparation pending a later handoff. | Original OHOS gate open; requested queue after existing reservations. Seq150. |
| Note / note-offline-1022 |264 tests,220 Markdown examples/22 lessons validator; rendering/tools/diagnostics/highlighting checks pass. | Dual-ABI HAP inspected; commits `a7509155` and `16e6a38`; no remote configured. | Target rendering/native URI persistence and ordinary install proof open. Markdown code fences do not establish execution of other languages. Seq136/145. |
| JSON / existing owner confirmed by c-coordinator | Detailed host/tool/diagnostic evidence not reproduced in this ledger. | Product `6df694e`; C's durable read-only audit is `research/json-owner-audit-20261022.md` in the C task. | Coordinator confirms an existing340-example actual x64 OHOS report. Complete request coverage, remaining tools/diagnostics/workspace/debugger applicability and publication evidence still need an explicit handoff. SQL did not independently validate the report. Seq161. |

### SQL artifact and delivery checkpoint

- Product `9f92d49f6c911adcc36e39792a725d3d7a7733ec`; x64 Oracle recipe `69b428e`; gated drafts `9c6da05`; evidence `6a5de4c`.
- Isolated272PASS/2SKIP excludes the98-item baseline WIP. Both skips require `QFLI_MYSQL_TEST_BUNDLE`; neither is a MySQL runtime pass. Consumed core was `f8edb0424e40afc5e8dba6a874cb240f467ffd7b` plus its captured dirty snapshot, not later `0ec321c`.
- Signed `build/ohos-audit/sql-audit-signed.hap` SHA256: `0c5007b468e3e525d687b4e52983865b4c84d6ad2a89dd006aaf83bd8df76d78`.
- Build ID `sql-originals-x64-capfix-20261022`, bundle `com.azurekiln.qfli.sqlab.audit`; x64 Flutter, actual Oracle8.4.6 images, signature/profile/native/catalog/source-binding checks pass. This is package evidence, not phone or installed execution evidence.
- Original126 examples +246 exercises =372 scripts (SQLite360, MySQL12). Drafts remain unshipped. Promotion would produce306 examples +606 exercises =912 scripts, after the complete original OHOS pass.

### Coordination and actionable handoffs

Web explicitly released `127.0.0.1:5555` to Lua121 at seq163. The remaining
queue is Lua121 -> SQL122 -> Python124 -> Rust128, with Go/Dart following
readiness and coordinator acknowledgement. Web reports its own forward removed
and targeted test-ability stop requested, then an exact-target disconnection.
Lua must verify live target availability before accepting; no Lua acceptance or
SQL handoff is recorded here. The second network target remains unclaimed and
unassigned. Web requests a later final481 rerun after the existing reservations.

Core's debugger contract156 permits product-only adapters now; C owns the common
UI. Core owner-run161 is available, but Web162 identifies default tap choosing
`urlForFile(project/index.html)` outside an explicit `root=public`; the requested
owner repair preserves `session.url` for default tap and uses the explicit entry
only for long press. Do not label this regression closed from owner-run tests.

## Files and contracts consulted

- `research/isolated-checkpoint-check.md`: exact staged product patch,272/2 and26/26 gates, captured core identity.
- `research/audit-package-capfix.md`: current HAP identity and inspection, fixed512-statement smoke.
- `research/requirements-evidence.md`: live requirement gates; later five-remote publication is recorded in `research/publication-20261023.md` and channel seq171.
- `research/draft-review.md:17`: reviewed306/912 promotion denominator and held180 drafts.
- `tool/ohos/collect_curriculum_audit.py:252`: validates explicit run/build/platform, complete manifest counts and per-script evidence; line366 separates actual OHOS device status.
- `integration_test/sql_curriculum_ohos_audit.dart:75`: executes using actual `Platform.operatingSystem` and emits the durable report.
- Related specs: `.trellis/spec/backend/ohos-audit-packaging.md` and `.trellis/spec/frontend/sql-content-repository.md`; package success and host execution cannot close target gates or permit early promotion.
- External references: none; this refresh uses local evidence and authoritative owner channel reports only.

## Caveats / Not Found

No sibling tests, builds or device operations were repeated for this refresh.
JSON's fuller requirement evidence, Lua's complete replacement/acceptance,
Python aggregate release, and the remaining product target handoffs are absent
through seq163. Later owner messages may supersede this snapshot. The research
role permits no Git operations; root must run the single-file `git diff --check`.
