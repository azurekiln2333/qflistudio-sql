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

## Subsequent coordination — 2026-10-23

- SQL's six scoped commits through `3bd36f1a0c5759f568d5e9eea823064b877d8bb0` were pushed and independently verified on all five mirrors. `research/publication-20261023.md` records the initial delivery checkpoint; local `build/offline-ide-check/publication-docs-1023.json` records the subsequent documentation tip.
- Exact emulator `127.0.0.1:5555` returned after the disconnection. SQL read-only preflight confirms API26/x86_64/OpenHarmony7.0.0.105, a match with its debug profile and unchanged signed HAP. Lua121 acceptance/defer/handoff remains requested in seq186/188; no SQL device mutation has occurred.
- Core process-supervision fix `9b0c01fe` was published with48 focused tests and4 real Linux cases (seq177); its OHOS boundary remains product-owned. Web preview default-tap repair `e025805b` was published with9 Web and23 isolated core passes (seq181), superseding the open preview defect in this historical snapshot.
- Studio main reports legacy workspace revision protection restored and short-height explorer layout repaired (seq187). Its new saved-workspace work and C debugger integration still change shared source. SQL's two new real-SQLite workspace consumer tests are authored and await the serialized C176/SQL188 check window; they are not part of the earlier272-pass checkpoint.
- Independent JSON evidence review is now in `research/json-owner-evidence.md`:340 actual target Runner passes,240 added topics,16 tool smoke results and116 historical tests are attributable. Current app bytes still match, but13 recorded core files have changed; ordinary current-core workspace/UI acceptance remains open. Python released its aggregate generation window (seq167/168), preserving1700 non-Python tutorial and1700 example rows. Python native debugger Windows/POSIX28/28 reports (seq180) remain separate from OHOS/debugger UI acceptance and its open performance-cost gate.

## Device handoff and consumer execution — later 2026-10-23

- Lua explicitly deferred its device reservation and handed the exclusive window to SQL in seq209; SQL accepted in216. The immediate exact-client query returned `[Empty]` and local5555 had no listener. No SQL install/start/stop or other device mutation followed. Earlier target/profile-match evidence does not establish current availability; Python124 remains next when SQL releases.
- SQL's first isolated consumer invocation completed against SQL3bd36f1 plus the new test and a read-only archive of published coree025805b. Offline dependency resolution and scoped analysis passed; both tests failed the initial empty-editor fixture condition before exercising workspace actions. The empty editor does not build an `EditorProblemsBar`, so a test expecting that bar before opening a file cannot finish. This is being corrected in the fixture; no SQL/core runtime pass or production defect is inferred. All66 captured SQL and265 core file hashes stayed unchanged during the failed invocation; the host slot was explicitly released to main in213.
- Independent read-only review of the collection/umbrella/JSON notes found two collection-document issues, both fixed: consistent pulled-file destinations and explicit persistence-failure marker wording. The examples now select the verified DevEco HDC path rather than an older PATH client. No private identifier/key/certificate payload was found in those three notes.
- C reports dedicated Clang/native/ArkTS bridge checks for nested local headers, mixed sources and link diagnostics; the200/200 original native+LLVM/WASI runs remain host-only. Its signed ARM64 HAP has no current C owning-app execution proof, so R8 remains open (seq223). The common supervisor's published9b0c01fe contract guarantees verified descendant handling only on its supported Linux path and preserves Windows owned `taskkill`; macOS/other POSIX fallback bounds the parent and does not guarantee descendant cleanup (seq232).
- Main's focused explorer gate reports4PASS including actual1100x175 layout at1x/2x text with a reachable workspace action (seq231), after its earlier fake-time fixture hang and the transient terminal API compilation gap. Further Home/workspace/owner checks are running separately; these four cases do not prove all current-core consumer or device behavior.

## Native offline / serialized verification follow-up — 2026-10-23

- SQL source now rejects native openAgreement/openUrl/login with OFFLINE_ONLY before arguments and removes AccountKit/client_id/INTERNET, preserving local picker/share/MySQL Unix socket/startup WIP. Actual-handler host harness303 assertions PASS; working startup mode337 PASS; publishable candidate excluding baseline startup303 PASS. Seven Python package regressions PASS. Current HAP rebuild/ArkTS/installed native and startup networking proof remain open; old0c5007b4 HAP is historical. See native-offline-check.md.
- Workspace attempt2 passed scoped analysis but timed out at the first-file wait after initial mount/tree gestures; static review confirmed a path-comparison defect. Independently reviewed source c2f4c4d9 normalizes Windows paths and adds actual-state timeout diagnostics; no third runtime run yet. Main235/240 still owns the serial host slot through observed seq253; SQL248 requests explicit retry handoff and does not infer a gap from inventory.
- Exact assigned device127.0.0.1:5555 still returns Empty. SQL has made no device mutation; Python124 remains next after explicit SQL release. Restore-existing-session request218 remains unresolved.
- JSON owner committed family editor/native/artifact follow-ups62fbeb1 (seq246); later current-core JSON cross-root host check is queued253. Its earlier snapshot-bound target evidence is preserved in json-owner-evidence.md and cannot close current shared-core/family gates.

### Superseding host handoff and third-run outcome

C263/main264 explicitly released the old reservation. SQL accepted273 and released274 directly to Go236 after exact PID12368/tool40310 exit1 in9.5s; format/analyze exited0. The actual two cases remain0PASS/2FAIL on fixed archived coree025805b and formatted test8c596648, with all66SQL/265core hashes stable. Case1 fails after drawer reopening before page reconstruction: child restoration is asynchronous after root creation. Case2 reaches its final exception check after the SQLite assertions, then fails because core _diagFocus reads a defunct Element. C adopted source fix/regression282, UNRUN. SQL's fixture correction and corrected-core retry require later named verification, not reuse of the released slot. Native code6999b0d has been pushed/independently matched on all5mirrors; old HAP remains historical, device target unavailable.
