# Research: JSON owner evidence and umbrella requirement mapping

- Query: Establish JSON's attributable curriculum, tools, editor, workspace, offline and delivery evidence without taking over its owner.
- Scope: internal; follow C coordinator seq161/172, its read-only audit and the exact referenced JSON artifacts/source. No tests, builds, device, Git, remote or network actions.
- Date: 2026-10-23 (Asia/Shanghai). Target/build evidence below is dated 2026-10-22.
- Ownership: existing JSON task `10-22-offline-json-ide` remains `in_progress`; implementation `6df694e3e695fdb69d7b59232cfc4b833139f3f6`. Shared core remains C-owned. This research writes only this file.

## Findings

Evidence levels are explicit: **source** means inspected implementation; **artifact** means an existing report/log/archive inspected here; **owner** means an attributable claim not rerun. The actual JSON OHOS result is substantive, but snapshot-bound. It does not close later shared-core changes or prove the required original-before-expansion sequence.

### Curriculum and actual OHOS identity

A read-only asset count found **340 unique example IDs and 340 distinct example code strings**, 340 tutorials/lessons, 440 exercise answers and 340 fixtures. [Catalog audit][catalog] records **100 inherited +240 new** examples/tutorials across24 categories. All200 recorded inherited code fingerprints match the current100 example and100 lesson code strings. The audit explicitly records corrections to100 example outputs,100 lesson outputs,200 former prose exercise answers and100 fixtures; original outputs/answers were corrected rather than preserved verbatim.

The current data-document denominator is340 examples +340 lessons +440 answers =1120 documents; only the340 examples run through the normal `RunnerService` route. [Verification source][verifier] parses and compares formatted example/lesson outputs, parses all answers, verifies recognized Pointer exercises, and checks every fixture against its example. Ten specially shaped fixtures execute Patch/Merge Patch expectations. This does not prove independent business-rule/schema semantics for every document.

[Final result][result] is183bytes, SHA256 `ed91cdb87dcd7d1ea1709265654484282396f0c06da9fa0967eebd9fd88927d2`:

```json
{"passed":true,"examples":340,"runnerPasses":340,"tutorials":340,"lessons":340,"exerciseAnswers":440,"fixtures":340,"semanticOperations":10,"tools":16,"platform":"ohos","failures":[]}
```

[Final log line9][hilog] contains the same marker/result from PID5271 at `2026-10-22 20:48:02.595` local time. Its independently computed SHA256 is `b7d3bdf1f4cf423b3fbe81e36f542fe7cb7e08d92c7d8381d4403bb5ccfb7671`. [OHOS report][ohos] attributes installation/start to `127.0.0.1:5555`, API26 x86_64. The aggregate result itself has **no runId, buildId, timestamp, revision, per-document success records or HAP hash**; identity is supplied by adjacent logs, source snapshots and artifact metadata, not self-authenticated by the result.

| Existing artifact | Date / identity | What is established here |
| --- | --- | --- |
| [Final harness metadata][harness] | HAP modified `2026-10-22T20:31:52.935995+08:00`;123852051bytes; SHA256 `e2a945a8687ffa73e8552a5874610ef0d44420320dec5b3297f805e3f3f71268`; kernel `5b6a52a26e6130fc9c34735613558aabef9b84f70b09117bdc125a4f119bc71a` | Metadata, result and process log are mutually consistent; harness archive was superseded by the ordinary build, so its bytes were not independently rehashed here. |
| [Harness source snapshot][harness-snapshot] | Captured `2026-10-22T12:31:35.292431+00:00`;160 recorded files; actual snapshot SHA256 `2c87621c71e0f53ee7abb45dc5f94a6891f90da32d421710578458fcf653f85b` | Snapshot file hash matches harness metadata. It lacks the ordinary snapshot's repository-head fields. |
| [Ordinary metadata][normal] and [source snapshot][normal-snapshot] | HAP modified `2026-10-22T21:07:21.062148+08:00`;123864987bytes; SHA256 `a7b17b33ca7a97ccdbc62ca5addbf31bf8f960ff716146298f9ac2fc48aebfa7`; snapshot SHA256 `e1aeeb18004e73cbadc295220f42d880c73085cb17d04f48f175b2e44f2ae45f` | Existing ordinary HAP and snapshot hashes independently match. Snapshot records app `6df694e3e695fdb69d7b59232cfc4b833139f3f6`, core `96e6833f46a791949cfa58d36e7ba7a25720d18d` plus concurrent captured dirty bytes. |

Read-only inspection of the ordinary HAP found39 unique archive entries, bundle `com.azurekiln.qfli.json`, and only `ohos.permission.READ_PASTEBOARD`. Its three product assets exactly match current source bytes:

| Asset | SHA256 |
| --- | --- |
| `catalog_audit.json` | `6442c06e699d130ee7eec32d2fb80d1226d6810b3537ade9a1ba3972ad92bb4f` |
| `examples.json` | `20a555e3f0671dfc0cafd09adb4895ba57ace25babdca332dd6bc59e33f33675` |
| `tutorials.json` | `8cb0b9e82ba0185d6cf0c988458f7e16ac0ea3c45fea1c541ce22c50c7869ca2` |

Both snapshots have the same160 recorded paths. On2026-10-23 all recorded **app** files still match;13 recorded **core** files differ: `content/local_content_adapter.dart`; `editor/{editor_controller,editor_page,editor_problems_bar,file_explorer,retained_editor_host}.dart`; `pages/{home_page,local_content_pages,points_page,tasks_page}.dart`; `services/{code_import_service,process_supervisor,studio_profile}.dart`. This comparison does not inventory newly added files outside the old manifest. C's earlier audit observed only two differences; that count is now stale. Target acceptance applies to captured core bytes, not the current shared worktree.

### Requirement mapping

IDs below follow the SQL umbrella ledger; JSON's own PRD numbers debugging/offline/highlighting/commits differently.

| Umbrella ID | Supported evidence | Boundary / remaining evidence |
| --- | --- | --- |
| R2 all existing OHOS | **Artifact/source:** final installed340/340 Runner result, full340 lesson/440 answer/340 fixture loop,10 semantic fixtures, log PID/time and snapshot/artifact identities above. | Both initial and final target reports already contain340 expanded examples. No separate pre-expansion100-example OHOS report was found in the referenced artifacts. Original100 are included in340, but mandatory ordering is unproven. Unsigned x64 emulator only; no physical ARM or signed-release acceptance. |
| R3 >100 new | **Artifact:** catalog100 inherited +240 new;340 distinct IDs/code strings;24 categories; all200 inherited example/lesson code fingerprints still match. Expanded catalog is included in target result. | No independent pedagogical review of all340 explanations was performed here. Expansion-before-original-target timing remains an R2 process gap. |
| R4 filters / badges | **Source:** [JSON profile][profile] is JSON-only and injects the product repository. **Owner:** [evidence lines35/49][evidence] attributes shared filters/badges to `ef34591`. | The final aggregate harness does not exercise title badges/filter interactions. No target interaction trace for these was found; current shared content-page bytes also differ from the target snapshot. |
| R5 direct tools | **Source:** [enum lines13-29 and grid line212][tools] map16 operations directly to real operation pages: format/check, minify, key sort, Pointer, diff, Merge Patch, JSON Patch, flatten/unflatten, JSON Lines both ways, string escape/unescape, CSV, local Schema, statistics. Killable isolates have cancellation and a5second deadline. **Artifact:** installed harness completes all16 defaults; [widget test line227][editor-test] covers direct reachability, existing116-test log passes. | Installed tool smoke only requires **nonempty output**, not authored exact results or every UI interaction. Local Schema is an explicit2020-12 subset; external refs/unsupported keywords fail. Query is RFC6901 Pointer, not JSONPath. |
| R6 dirty diagnostics / Problems | **Source:** [analyzer line11][analyzer] processes exact in-memory snapshots in a worker and returns UTF-16 ranges. [Main-editor tests lines45/88][analyzer-test] cover CRLF/astral offsets, wavy decoration, Problems click navigation, correction clearing and unchanged disk. Document page fences generations and explicitly saves. **Artifact:** saved target Problems screenshot visibly shows unsaved syntax error and position; correction screenshot shows unsaved `{}` and no Problems. | Screenshots establish visible states, not the entire intervening action sequence or unchanged disk. Later shared editor/controller changes require fresh consumer/target acceptance. |
| R7 explorer / workspaces | **Source:** [explorer tests lines25/50/78/116/216][explorer-test] cover reconstruction, drawer reopen, fast root switches, multiple roots and independent expansion. **Artifact:** existing workspace27/27 and backup/compatibility83/83 log tails pass. **Owner:** `daddce2` plus owner-backup `96e6833`. Target tree screenshot shows expanded `src` in a one-project workspace. | One screenshot does not establish restart persistence or actual multi-root target behavior. Shared explorer/controller/host/history integration is owner-managed; changed snapshot files and unarchived ordinary-UI evidence remain open. |
| R8 highlighting / headers | **Source:** [JsonSourceController line430][document] colors JSON keys, strings, numbers/literals and overlays exact wavy error spans. **Artifact:** Problems screenshot visibly retains string/literal colors beneath error decoration; existing editor tests cover this path. | JSON cannot establish C/C++ header/toolchain correctness or highlighting for other languages. Main-editor current-core changes are not covered by the old HAP. |
| R10 feasible debug / logs | **Source:** real parse/format Run output, positioned errors, document Problems/Output and read-only `json check/format/minify/sort/stats/get` terminal commands ([runner line78][runner]). Profile supplies no executable debugger adapter. [Owner contract][contracts] explicitly treats JSON as data. | Breakpoint/step execution, Debug Console and network Ports are inapplicable to JSON parsing; no fake backend is claimed. These capabilities in executable-language products remain separate requirements. |
| R11 offline | **Source:** JSON profile `isOffline:true`; [host-policy tests][offline-test] deny HTTP-client creation, reject external refs and inspect native routing/manifest. **Artifact:** ordinary compiled manifest has no INTERNET and only clipboard permission; bundled assets match. | This is offline application evidence, not packet capture or proof for every later shared path. Historical build fetched `@ohos/hypium`1.0.6 via ohpm; disconnected builds were not proven. |
| R12 review / commits / push | **Artifact:** existing final test log ends `+116: All tests passed!`; analyzer log says no issues; source/test behaviors inspected above. **Owner/snapshot:** product `6df694e3e695fdb69d7b59232cfc4b833139f3f6`; shared backup `96e6833` pushed `github/main`, reaffirmed by coordinator172. | Product has no configured remote according to JSON evidence/C audit; no JSON push claimed or destination invented. Test logs are historical, not a rerun against the13 changed core files. Task steps9/11 and ordinary UI/evidence/journal/archive remain existing owner work. |

### App-private report export route

The exact referenced task Markdown/JSON/log artifacts do **not** retain a `hdc file recv`, `run-as`, pull helper or debug file-access command. [OHOS report line5][ohos] says only “exported from the app sandbox.” [Verification page lines29-41][page] writes `json_verification_result.json` beneath `AppPaths.storageDirectory()` and logs the aggregate JSON marker. [AppPaths lines68-86][paths] tries application support, then application documents, then writable fallbacks; the path is not a fixed `/data/...` contract. The complete final marker at [log line9][hilog] can recover the183-byte aggregate, but no proved sandbox-pull command can be transferred to SQL from these artifacts. No device command was executed for this research.

## Files / contracts consulted

- [C read-only audit][c-audit], plus global coordinator161 (`2026-10-22T16:23:34.940Z`) and172 (`2026-10-22T17:14:03.213Z`): ownership and claim provenance.
- JSON PRD/design/implementation/evidence and exact linked source/report files above; existing `%TEMP%/qfli-json-final-review-tests.log`, `qfli-json-final-analyze.log`, `qfli-workspace-acceptance.log`, `qfli-workspace-backup-after.log` were read only.
- Local images inspected: `ohos-ui-problems.png`, `ohos-ui-unsaved-correction.png`, `ohos-ui-tree-reopened.png`. Their visible states are used narrowly; filename alone is not acceptance proof.
- Related contracts: JSON's [research/contracts.md][contracts] and design; SQL `.trellis/spec/backend/ohos-audit-packaging.md` and `.trellis/spec/frontend/sql-content-repository.md` preserve the general package/host/target distinction. JSON frontend/backend spec index paths were absent; no matching JSON-named shared spec was found by the bounded lookup.
- External references: the owner's contracts file records official VS Code/JetBrains JSON docs, RFC6901/6902/7396 and JSON Schema2020-12 choices. They were not fetched again in this network-free refresh.

## Caveats / Not Found

This is a read-only evidence review, not JSON ownership transfer or a new test pass. Strongest supported conclusion: the captured expanded JSON product has real x64 OHOS data-validation/Runner evidence and useful local tools/editor features. Missing or stale evidence comprises original-before-expansion ordering, self-identifying/per-document target report records, the sandbox export command, full ordinary UI/multi-root/restart target coverage, acceptance against later core changes, signed/ARM distribution and product publication without an authoritative remote. Preserve the existing owner's task and dirty evidence; do not archive the umbrella from this review.

[c-audit]: D:/MyNewProjects/qfli_c/.trellis/tasks/10-22-offline-standalone-ide/research/json-owner-audit-20261022.md
[catalog]: D:/MyNewProjects/qfli_json/assets/content/catalog_audit.json:1
[verifier]: D:/MyNewProjects/qfli_json/lib/json/json_catalog_verification.dart:14
[result]: D:/MyNewProjects/qfli_json/.trellis/tasks/10-22-offline-json-ide/research/ohos-harness-final-result.json:1
[hilog]: D:/MyNewProjects/qfli_json/.trellis/tasks/10-22-offline-json-ide/research/ohos-harness-final.log:9
[ohos]: D:/MyNewProjects/qfli_json/.trellis/tasks/10-22-offline-json-ide/research/ohos.md:5
[harness]: D:/MyNewProjects/qfli_json/.trellis/tasks/10-22-offline-json-ide/research/ohos-final-harness-artifact.json:1
[harness-snapshot]: D:/MyNewProjects/qfli_json/.trellis/tasks/10-22-offline-json-ide/research/ohos-final-source-snapshot.json:1
[normal]: D:/MyNewProjects/qfli_json/.trellis/tasks/10-22-offline-json-ide/research/ohos-normal-artifact.json:1
[normal-snapshot]: D:/MyNewProjects/qfli_json/.trellis/tasks/10-22-offline-json-ide/research/ohos-normal-source-snapshot.json:1
[profile]: D:/MyNewProjects/qfli_json/lib/main.dart:26
[evidence]: D:/MyNewProjects/qfli_json/.trellis/tasks/10-22-offline-json-ide/evidence.md:18
[tools]: D:/MyNewProjects/qfli_json/lib/json/json_tools.dart:13
[editor-test]: D:/MyNewProjects/qfli_json/test/json_editor_test.dart:227
[analyzer]: D:/MyNewProjects/qfli_json/lib/json/json_analyzer.dart:11
[analyzer-test]: D:/MyNewProjects/qfli_json/test/json_analyzer_test.dart:45
[explorer-test]: D:/MyNewProjects/qfli_studio_core/test/file_explorer_state_test.dart:25
[document]: D:/MyNewProjects/qfli_json/lib/json/json_document_page.dart:430
[runner]: D:/MyNewProjects/qfli_json/lib/json/json_runner.dart:78
[contracts]: D:/MyNewProjects/qfli_json/.trellis/tasks/10-22-offline-json-ide/research/contracts.md:14
[offline-test]: D:/MyNewProjects/qfli_json/test/json_offline_host_test.dart:9
[page]: D:/MyNewProjects/qfli_json/lib/json/json_verification_page.dart:29
[paths]: D:/MyNewProjects/qfli_studio_core/lib/services/app_paths.dart:68

## Addendum: committed JSON owner handoff — 2026-10-23

Query/scope: bounded read-only follow-up to coordinator seq223 (`2026-10-22T20:21:17.191Z`), which attributes the new durable handoff to JSON commit `8f4d8e3`. Only the two new handoff documents and the evidence newly referenced for changed findings were inspected; no product source audit, Git operation, test/build or device command was repeated. The historical findings above are retained.

New records: [owner final handoff][json-final-handoff] and [family evidence index][json-family-index]. The implementation remains `6df694e`; `8f4d8e3` is the coordinator-reported evidence handoff, not a newly verified product-runtime revision. The owner closes its recorded JSON implementation/acceptance work while explicitly preserving final-core, multi-root target, signed/ARM and family follow-ups.

| Prior boundary | Change established by the new records | Remaining limit |
| --- | --- | --- |
| Ordinary UI previously supported chiefly by visible screenshots | [Typed UI acceptance record][json-ui-acceptance] records2026-10-22/23 direct cards, Pointer `/items/0/id` -> `1`, ordinary import/open, syntax colors, Problems click selecting the offending character, UI unsaved correction with malformed disk retained, validation output, `/values/1` -> `3` at line4/column17, and `src` expansion after drawer reopen **and app-process restart**. All10 referenced screenshot files exist and their SHA256 values match the record. The restored task sample is recorded as123bytes, original hash `70739cda8c82069b2d496ac68ecff4f2c40ee67705e5c9e6a69aeba4e9a6b0ac`. | These are attributable owner observations plus matching saved images, not gestures or disk reads independently re-executed here. Diagnostic setup explicitly used an hdc-seeded task fixture rather than UI typing. Target multi-root gestures remain untested; the report itself restricts scope to the recorded paths. The earlier assertion that no explicit ordinary correction/restart interaction record was available is superseded. |
| Host116 evidence previously depended on historical TEMP logs | New task-local `host-20261023-serial-tests.log` ends `+116: All tests passed!`; `host-20261023-analyze.log` says no issues. The owner retains the earlier transient type-error/OOM history and describes the controlled serial rerun. | These are saved execution logs read here, not fresh runs. Final handoff explicitly reports concurrent shared edits during the host run: compatibility evidence, not a frozen source assertion. |
| Initial100-before-expansion chronology | No new100-only pre-expansion target report is supplied. New handoff again references the expanded340-runner harness and preserved original code identities. | **Not resolved.** Inclusion of the original100 in340 and preserved code hashes do not establish the required order. The family index restates baseline-first as a family requirement but supplies no missing JSON chronology. |
| Exact sandbox export command | New UI record mentions hdc fixture setup, but neither new handoff nor its typed UI report supplies `hdc file recv`, `run-as`, a report-export helper or an exact debug-sandbox pull command. | **Not resolved.** Earlier source/log recovery findings remain unchanged. Do not treat a fixture-seeding claim as a proved app-private report-pull route. |
| Binding to current final shared core | UI record points to the existing `ohos-normal-artifact.json` and `ohos-normal-source-snapshot.json`. Final handoff says both device archives bind the same160 captured files and later core edits were **not installed**. It asks for ordinary JSON rebuild/affected UI after common editor/debug/workspace freeze. | **Not resolved.** No new current-core target artifact/run is supplied. The earlier13-file mismatch count remains a dated observation, not a fresh count in this addendum. Serial host compatibility does not bind final core bytes to the installed HAP. |
| Remote / publication and ownership | Final handoff explicitly repeats **no product remote, no guessed destination, no JSON push**. Core owner-backup `96e6833` remains the previously reported `github/main` push. Coordinator223 now confirms durable JSON handoff `8f4d8e3`; the owner identity is established. | No product remote publication is claimed; no live Git/remote verification was attempted. JSON's released temporary UI usage does not grant SQL or another product a device window. |

The new family index is a dated secondary owner review, not fresh sibling execution. Its SQL row still cites the initial five-commit `3dfb073` publication checkpoint; the SQL root supplied the later published `3bd36f1` checkpoint to this assignment. Do not replace current product ledgers with that historical row. No other sibling paths were followed for this addendum.

Frozen inputs (SHA256 computed from the referenced local files):

| Record | SHA256 |
| --- | --- |
| `final-handoff.md` | `9b4861cb90d8cefb26f807dcd8bb15eabc8e017d9f1b55370b780f500afe1e60` |
| `family-audit-20261023.md` | `6677742b827a0c45f48a789695007ea57054db0510e10ac29ec226a11537d334` |
| `ohos-ui-acceptance.json` | `6f6883ec35ea19f36da21df58dd6b121ce4c1764af8c12161d0817141edad2f7` |
| `host-20261023-serial-tests.log` | `60e96422a7d36f59df8ca7d1eb060d737ccc73d7069b6aec8c5a7e10ae7e55d3` |
| `host-20261023-analyze.log` | `dfc204ca3b2923fb4c37d6a1832e2e34193da11f7ecc2bbf6f389e3fa3cc60cc` |

Caveat: owner reports and typed UI observations now narrow several ordinary-UI evidence gaps, but do not resolve baseline chronology, current-core target binding or remote publication. No new device acceptance is claimed by this reviewer. Related source/packaging contracts and external-reference limits remain those recorded above.

[json-final-handoff]: D:/MyNewProjects/qfli_json/.trellis/tasks/10-22-offline-json-ide/research/final-handoff.md:14
[json-family-index]: D:/MyNewProjects/qfli_json/.trellis/tasks/10-22-offline-json-ide/research/family-audit-20261023.md:33
[json-ui-acceptance]: D:/MyNewProjects/qfli_json/.trellis/tasks/10-22-offline-json-ide/research/ohos-ui-acceptance.json:1
