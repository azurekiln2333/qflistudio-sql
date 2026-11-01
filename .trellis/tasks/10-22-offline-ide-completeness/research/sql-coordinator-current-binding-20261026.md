# Coordinator current-main binding repair (2026-10-26)

Status: SOURCE PREPARED / UNRUN / EXECUTION DISABLED. This note supersedes
only the old observer's four-main-file and fixed-68 capture claims. No launch,
core publication, grant, successful gate or readiness was refreshed here.

## Boundary and identities

Changed only the ignored observer
build/offline-ide-check/workspace/coordinate-bounded-retry.py and this note.
The observer preimage SHA256 was
e61043c1cbc25d6c4a16b050a5cb93d19218f54281bf9513488c81567c499700.
The revised observer SHA256 is
8cf14a2d304f7581335b52598250786f85f59cfe897306212573d8bc6bedd52f.

The immutable run-bounded-retry.py remains SHA256
ec8b29f9399261be5c2af6c3e22a9d32d21a8067c977a05f9f70be18d0964e12.
The unchanged stale bounded-retry-launch.json remains SHA256
71692f4ece9339efa20374c9c94183b3df006fbcd76562d0fe0ebf3dd2041249.
LAUNCH_SHA still requires that exact compiled-in pin. CLI input cannot replace
the pin. EXECUTION_ENABLED is now false. Even a future source edit enabling
entry would encounter the absent new launch schema before any ACK.

The pinned 2f9039a3 core publication remains historical. A later source-only
core publication or diagnostic release does not prove a tested core checkpoint.
This repair selects no replacement checkpoint and makes no current-core claim.

## Required future launch schema

The existing expectedReviewSha256 remains the complete exact runner.capture
map of the prepared review. Add exactly this object to a future reviewed launch:

```json
{
  "currentMainBinding": {
    "schemaVersion": 1,
    "expectedMainCaptureSha256": {"<captured relative path>": "<SHA256>"},
    "expectedMainSupplementalSha256": {"<supplemental relative path>": "<SHA256>"},
    "expectedReviewSupplementalSha256": {"<supplemental relative path>": "<SHA256>"}
  }
}
```

Missing, null, empty, malformed or extra binding fields refuse. Version 1 must
be an integer. Maps contain normalized relative paths and lowercase SHA256.
No preparation field is populated by this turn.

The main capture uses the unchanged runner.capture inventory: all Dart files
under lib, test, integration_test and vendor/re_editor/lib, plus present
pubspec.yaml, pubspec.lock, pubspec_overrides.yaml, analysis_options.yaml,
.dart_tool/package_config.json and native/build/windows/qfli_sqlite.dll.
Complete current main must equal its declared map. Main and review path sets
must match. Both must include pubspec, lock, analysis and package config.
No count such as 68 or 70 defines completeness.

All non-config entries must have byte-identical main/review preformat hashes.
The five named configuration files have independently frozen main and review
hashes. Their path presence must match and both sides remain frozen. Their
bytes may differ for isolated dependency roots. This observer does not perform
the full gate's semantic dependency-parity transformation. Independent review
of the future configuration preparation remains required; full-gate dependency
parity remains an additional acceptance boundary.

The supplemental maps exactly cover all Python files under tool/sql_curriculum
and tool/ohos, both SQL curriculum assets, and tool/ohos/build_audit_hap.ps1.
Discover additions and removals on both sides. Require both maps and actual
bytes to match. This includes the inspector and its tests without adding tools
to the immutable runner's capture map. Future preparation must copy all declared
supplemental inputs before reserving a slot. A partial collector-only review
copy refuses this schema.

## Checks and formatter lineage

freeze verifies complete current-main and supplemental maps before the first
channel read and again before grant consumption and ACK. After the wrapper is
terminal with activeProcesses zero, inspect_immutable_inputs recaptures main,
configs and both supplemental inventories within the existing deadline.
Existing review capture checks remain exact before ACK.

A successful child requires hash-authenticated initial.json, before.json and
after.json from its final evidenceHashes. Initial must equal the frozen complete
review capture. Before and after must match completely, including core. Their
path sets must equal initial. Only the immutable runner's four SOURCES may
change between initial and before. Every other captured file retains its
initial bytes, including all configuration and native inputs. Actual final
review capture must equal before. Main stays preformat. No newline or semantic
normalization exception was added.

Grant author/text/event sequence, exclusive replay claims, deadlines, retained
Job ownership, HOLD behavior and protocol-717 final-sender publication remain
unchanged. Binding maps are retained in pre-ack and validation evidence.

## Source-only verification and next review

Passed AST parsing, JSON data parsing, source whitespace inspection and exact
runner/launch byte hashes. Static assertions confirm disabled execution and the
old launch's absent currentMainBinding. AST comparison against the retained
preimage confirms only freeze, inspect_immutable_inputs, inspect_child and main
changed among existing functions. Grant/replay, channel/publication and terminal
helper ASTs remain identical. The diff adds three binding helpers and config
names. Neither observer, runner nor full gate was imported or invoked.

No SDK, tests, controls, build, native/device operation, channel command, grant
request, commit or push ran. Runtime timing and failure regressions remain
UNRUN. Added complete captures must fit the same bounded reserve; no budget
extension is implied.

Independent review should inspect exactly this observer diff and this note.
Check map inventory completeness, config exclusions, full supplemental parity,
missing/null schema refusal, pre-ACK/post-terminal placement, four-file-only
formatter lineage, evidenceHashes authentication, and unchanged ownership and
publication protocol. Review the unchanged runner solely as the capture and
evidence producer. Do not refreeze launch/core during that review.

After source review, future preparation must bind an explicitly published core
with honest source-only versus tested status, complete current main/review and
supplemental inventories, and exact configuration transformations. Replace the
compiled-in launch/core pins only through a new reviewed source change. Enable
execution only through that explicit future review. Runtime still requires a
new named grant and its accepted command/publication contract. Old C586/C616
grants remain unusable. Focused/full/native/device and umbrella gates stay open.

## Independent source review result

Independent trellis-check review passed the actual current binding, refusal, check placement and formatter-lineage paths. The focused-observer spec bullet matches. Main/review supplemental inventories contain30paths per side with byte parity. Execution remains disabled; the stale launch lacks currentMainBinding. AST/JSON/hash/whitespace checks passed without target imports or runtime.

The independent reviewer could not locate a retained coordinator preimage. Therefore the implementer-reported historical helper-AST equality was not independently reproduced. The reviewer inspected the current grant/replay, retained Job/HOLD and protocol717 publication paths directly. This limitation does not establish runtime behavior; all runtime tests and timing remain UNRUN.
