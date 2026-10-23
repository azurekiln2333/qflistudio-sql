# Offline audit report collection

Date: 2026-10-22. This tool consumes captured local files only. It performs no device, build, signing, Git or network operation.

## Delivered files and checks

- `tool/ohos/collect_curriculum_audit.py`: Python standard-library CLI and strict report validator.
- `tool/ohos/test_collect_curriculum_audit.py`: **21/21 PASS**, including current shipped asset identity/denominator and negative protocol/outcome fixtures.
- `test/sql_curriculum_report_collection_test.dart`: **1/1 PASS** across the actual `CurriculumAuditStore` emitter and Python CLI. Real Dart store output is collected from prefixed Unicode-chunked logs and from persisted `report.json` + `events.jsonl`; the recovered complete report equals the original field-for-field. Removing one real emitted chunk fails collection.
- `flutter analyze --no-pub test/sql_curriculum_report_collection_test.dart`: PASS, no issues, including Dart type checking.
- `python -m py_compile tool/ohos/collect_curriculum_audit.py tool/ohos/test_collect_curriculum_audit.py`: PASS. Ruff/mypy are not installed; no Python linter/static type-check claim is made.

Test sessions are explicitly synthetic protocol fixtures. Their `platform: ohos` values exercise serialization and matching rules and are **not device acceptance evidence**.

Commands run:

```powershell
python -m unittest discover -s tool/ohos -p test_collect_curriculum_audit.py -v
flutter test --no-pub test/sql_curriculum_report_collection_test.dart --reporter expanded
flutter analyze --no-pub test/sql_curriculum_report_collection_test.dart
python -m py_compile tool/ohos/collect_curriculum_audit.py tool/ohos/test_collect_curriculum_audit.py
python tool/ohos/collect_curriculum_audit.py --help
```

## Use during the coordinated acceptance window

Capture/pull files through the separately coordinated device workflow first. The commands below operate on those local copies. Get the exact run ID from the captured REPORT header/private report path and the exact build ID from the reviewed build metadata; neither is inferred from the newest file.

### Pull the authoritative debug-sandbox files

The installed DevEco SDK `hdc` is 3.2.0f. Its local `-h` explicitly supports
`file recv -b <bundle>` and `shell -b <bundle>` for debug-application sandbox
access. The official OpenHarmony `docs/zh-cn/application-dev/dfx/hdc.md` describes
the same syntax and debug-app restriction. This resolves the collection method;
an actual SQL pull remains unverified until the coordinated device run.

Use the exact `reportPath` and `eventPath` emitted by that run, rather than
guessing a host-visible application data path. After explicit SQL handoff:

```powershell
$sqlAuditHdc = 'D:/ProgramFiles/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe'
& $sqlAuditHdc -t 127.0.0.1:5555 file recv -b com.azurekiln.qfli.sqlab.audit `
  '<exact-reportPath-from-this-run>' build/ohos-audit/pulled-unique-run/report.json
& $sqlAuditHdc -t 127.0.0.1:5555 file recv -b com.azurekiln.qfli.sqlab.audit `
  '<exact-eventPath-from-this-run>' build/ohos-audit/pulled-unique-run/events.jsonl
```

Use this explicit SDK path; the `hdc` found through PATH is an older client.
Keep a fresh host directory per attempt and preserve both original files.
Capture the audit marker live before launch as a second evidence path. Current
device `hilog -h` supports blocking regex-filtered reads:

```powershell
& $sqlAuditHdc -t 127.0.0.1:5555 shell hilog -e QFLI_SQL_CURRICULUM_AUDIT
```

Redirect this stream to a fresh local UTF-8 log. Stopping that owned host reader
must not reset the daemon or clear device logs. Large final REPORT chunks may
be lost to platform log limits, so use the persisted report/events when present;
the collector rejects incomplete logs rather than guessing the missing parts.

The current original shipped denominator is **126 examples / 372 scripts**: SQLite **120 / 360**, MySQL **6 / 12**. Each MySQL example currently has one authored exercise. Counts are derived from the two supplied catalog files and checked against the explicit flags; the collector never reduces the denominator to selected engines or available records.

From a captured hilog:

```powershell
python tool/ohos/collect_curriculum_audit.py `
  --hilog build/ohos-audit/captured-hilog.txt `
  --run-id '<exact-run-id>' `
  --expected-build-id '<exact-QFLI_SQL_CURRICULUM_BUILD_ID>' `
  --expected-platform ohos `
  --catalog-examples assets/content/sql_examples.json `
  --catalog-tutorials assets/content/sql_tutorials.json `
  --expected-examples 126 --expected-scripts 372 `
  --output-dir build/ohos-audit/collected-unique-attempt
```

From pulled files, replace `--hilog ...` with:

```powershell
  --report build/ohos-audit/pulled-unique-run/report.json `
  --events build/ohos-audit/pulled-unique-run/events.jsonl
```

`--events` alone reconstructs its final report and validates the complete event history. `--report` alone validates the full report without claiming event-history coverage. Hilog collection requires the complete selected REPORT payload but does not require older checkpoint logs to remain in the ring buffer. Use `--sequence <integer>` if a selected run has multiple REPORT candidates; without it the tool refuses ambiguity. A bare report does not contain a sequence, so `--sequence` requires hilog or events.

Use a fresh output directory for each attempt. Existing evidence is never overwritten, and output paths cannot overwrite supplied input files. Full catalogs need to be the reviewed catalog shipped in that build; later content promotion requires new explicit counts and the corresponding files.

## Outputs and exit codes

The CLI prints one machine-readable JSON summary to stdout and writes:

- `summary.json`: selected identity, SHA-256 of every input, independent counts/outcome reconciliation, validation failures, gate failures and exit code.
- `report.json`: complete recovered input report, preserving every script source, authored/actual output, native statement/result, reason and unknown future field. If the report is parsed but validation fails, this forensic copy is still retained; its embedded PASS flag does not override the summary's rejection.
- `report-event.json`: complete recovered REPORT envelope when available, including sequence and persistence failure metadata.

| Exit | Meaning |
| --- | --- |
| `0` | Collection validated and the complete recomputed OHOS device gate passed. |
| `1` | Full report validated, but its execution/identity/cleanup/fatal/platform gate failed. All failures and not-executed records remain present. |
| `2` | Malformed, incomplete, ambiguous or mismatched evidence/arguments, or output preservation failed. No device pass is accepted. |

Automation must require exit `0`, `collectionValidated == true` and `deviceGatePassed == true`. This is a report consistency check over the supplied evidence, not cryptographic attestation of a device run.

## What is rejected

- Missing REPORT header/parts, exact duplicate parts or headers, conflicting totals, out-of-range indices, multiple unselected sequences, or a reassembled envelope with the wrong run/sequence/kind/path. Detail parts from another run/sequence cannot fill a missing selected part. Unrelated runs remain selectable through the mandatory explicit run ID.
- Truncated/duplicate-key/non-finite JSON; invalid Unicode; absent final timestamps, required report/engine fields or per-script records; running/setup-only reports; wrong platform/build/run identity or denominator.
- Unknown/duplicate script keys; missing or changed source/authored outputs against the complete supplied lesson/example/exercise mapping.
- A claimed passing script whose native summary or statement is unavailable, failing or truncated; sparse/malformed rows; missing query evidence; authored/native/recorded output disagreement; a NULL row standing in for the `(no rows)` expectation.
- Engine/script/example count conflicts, incompatible verified engine identity, omitted engines or unsuccessful cleanup being presented as a gate pass. A complete internally consistent failed run is preserved with exit `1`.
- A pulled event history with run/path mixing, duplicate/gapped sequence numbers, decreasing timestamps, missing final REPORT, report-copy disagreement, missing/duplicate script lifecycle or contradictory final outcome.
- A final REPORT explicitly marked `logOnly`, or containing `persistError`, being presented as a successful collection. A complete hilog REPORT without these persistence-failure markers remains a supported input.

## Remaining boundary

No actual OHOS report was available to this reviewer and no device operation was attempted. The coordinator still needs to use a real captured/pulled report with the reviewed build/catalog identity during an authorized device window. Product audit, HAP build/sign/stage scripts and existing Dart audit sources were not edited.

## Collection-document review (2026-10-23)

Independent read-only review found two documentation issues: pulled-file paths
did not match the preceding destination, and “log-only REPORT” could be read as
rejecting every hilog input. Both are corrected above, with the rejection tied
to the collector's actual `logOnly`/`persistError` persistence-failure fields.
Commands now select the known DevEco SDK client explicitly. The review found no
private device identifier, key or certificate payload in this document, the
umbrella update or the JSON evidence note. These edits do not establish a
successful target pull or a device pass.
