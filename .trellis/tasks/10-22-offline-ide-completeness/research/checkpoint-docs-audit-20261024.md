# Research: checkpoint documentation consistency

- Query: Do the latest native-capsule, source-binding and host-gate documents match their actual scripts, launch manifests and capsule report?
- Scope: internal; read-only source/document audit, with this research record as the only write
- Date: 2026-10-24

## Findings

No material hash, count or runtime-acceptance mismatch was found in the requested checkpoint. No SDK, test, build, native or device command was executed by this audit.

- `research/current-native-capsule-20261024.md:33` records the four current tool hashes accurately: builder `a622239a`, transaction regression `38a1d6d8`, inspector `d8193ab0`, inspector regression `0530ae60`. All four actual capsule tool copies match main byte-for-byte. `research/audit-source-binding-refresh.md:29` retains an older test hash but explicitly supersedes it with the current hash at line37; this is chronological evidence, not a stale current hash.
- `research/current-native-capsule-20261024.md:74` accurately binds focused wrapper `ec8b29f9` and launch `03db04f2`. The launch's four source hashes and complete68-file source/config/native map match the source-capsule report. All68 actual capsule files match the report hashes. The focused launch remains `SOURCE_FROZEN_UNRUN_REQUIRES_NEW_NAMED_SQL_SLOT`.
- `research/current-native-capsule-20261024.md:113` and line115 accurately bind full supervisor `5476622e` and template `40931177`. The template still has null focused evidence, root terminal receipt and source inventories; its refusing status matches the documented UNRUN prerequisite. The script requires actual three-case focused success and integer exit/release receipt fields (`run-full-sql-gate.py:138`, `:166`).
- `research/current-native-capsule-20261024.md:106` accurately states35 Python test methods. AST-only counting found1 in `tool/ohos/test_build_audit_hap.py`,21 in `tool/ohos/test_collect_curriculum_audit.py`,13 in `tool/ohos/test_inspect_audit_hap.py`. This counted definitions without importing modules or executing methods.
- `research/current-native-capsule-20261024.md:49` through line62 agree with the actual capsule report:468 base Git blobs recorded,68 SQL entries,82 native inputs totaling340,518,821bytes, report SHA `832c1b55`, plugin metadata SHA `39be13c3`, and environment/runtime explicitly unverified. The report sets SDK/test/sign/device execution flags false. This audit rechecked68 actual capsule hashes, the four overlay hashes and native file sizes; it did not re-run Git blob verification or native acceptance.
- The current spec accurately describes explicit Flutter resolution before directory changes (`tool/ohos/build_audit_hap.ps1:15`–`:16`, directory change`:32`), recorded executable/hash (`:66`–`:67`), and unpinned native setup as remaining work. `ohos-audit-packaging.md:60` requires pinning Node/npm/OHPM/Hvigor/Java; the existing builder still invokes ambient `node` at line50, which is a documented future environment prerequisite, not a claimed completed pin.
- `implement.md:67`–`:69` and `research/requirements-evidence.md:29`–`:32` correctly keep the new transaction/source regressions, focused/full host gates and native capsule runtime UNRUN. They do not promote historical HAP/host checks to new offline-policy or installed acceptance.

Two minor wording ambiguities remain; neither changes the gate result:

1. `research/requirements-evidence.md:21` says independent source review remains required, while its later superseding checkpoint at line29 correctly says the four current files are independently reviewed. Suggested maintenance: make line21 explicitly historical or state only runtime gates remain required.
2. `research/current-native-capsule-20261024.md:76`–`:77` says the full supervisor is under independent review, while the appended section at line101 correctly records completed independent source review and final hashes. Suggested maintenance: update the earlier sentence to say reviewed/prepared, with runtime still UNRUN.

## Files found

- `.trellis/spec/backend/ohos-audit-packaging.md`: current packaging and source-binding contracts.
- `.trellis/tasks/10-22-offline-ide-completeness/implement.md`: implementation boundary and remaining runtime gates.
- `research/current-native-capsule-20261024.md`: current capsule identities, counts and source-only supervisor preparation.
- `research/audit-source-binding-refresh.md`: inspector behavior and chronological regression hash correction.
- `research/requirements-evidence.md`: requirement ledger and superseding checkpoint573.
- `build/offline-ide-check/workspace/bounded-retry-launch.json`: focused UNRUN source/config freeze.
- `build/offline-ide-check/workspace/run-bounded-retry.py`: focused bounded supervisor.
- `build/offline-ide-check/workspace/full-sql-launch.template.json`: intentionally refusing full-gate template.
- `build/offline-ide-check/workspace/run-full-sql-gate.py`: prerequisite and complete-suite validators.
- `D:/MyNewProjects/qfli_sql_hap_src_20261024_1610/build/capsule-source/source-capsule.json`: actual created source-capsule report.

## Related specs

- `.trellis/workflow.md`: persistent research artifacts and evidence-based progress.
- `.trellis/spec/backend/ohos-audit-packaging.md`: source provenance, explicit tools, isolated capsule and runtime distinction.

## External references

None. This audit uses only current repository files and the local capsule; no external product or version claim was needed.

## Caveats / Not Found

- SQL DEFER574 remains a queue action, not a test result. This audit claims no runtime handle, exit code or new release.
- No format/analyze, unittest, Flutter, HAP inspection, SDK, native execution, signing, target query or Git operation was performed.
- Hash agreement establishes exact source identity only. It does not establish that the current code compiles, passes tests, builds, installs or behaves correctly on OHOS.
- Source/spec files were left unchanged. The two wording observations above are recommendations for the parent session.
