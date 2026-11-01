# SQL terminal coordinator readiness — 2026-10-26

Status: **SOURCE REVIEWED / PROTOCOL 717 / FROZEN SNAPSHOT ONLY / UNRUN / NO SLOT GRANT**.
This preparation grants no host slot. Current host ownership stays with its named owner.
The main workspace dependency audit remains separate. This review makes no
claim that the 68-file snapshot represents every current production dependency.

The missing artifact was the saved outer observer used for C616. The new ignored
`build/offline-ide-check/workspace/coordinate-bounded-retry.py` supplies that
control plane. It imports the frozen runner's `run_phase` and `batch_command`.
`run_phase` uses the existing `OwnedJob` implementation. No runner edits,
product edits, source copying, dependency resolution, or extra test cases belong
to this change.

## Frozen identities

| Artifact | SHA256 |
| --- | --- |
| Coordinator source | `e61043c1cbc25d6c4a16b050a5cb93d19218f54281bf9513488c81567c499700` |
| Immutable child runner | `ec8b29f9399261be5c2af6c3e22a9d32d21a8067c977a05f9f70be18d0964e12` |
| Revised launch | `71692f4ece9339efa20374c9c94183b3df006fbcd76562d0fe0ebf3dd2041249` |
| Core manifest | `14ddd7e4936ae1544bbae06012ca0e582debd31bbcf398a80ebcca6022ee1071` |

The coordinator checks both copies of all four SQL sources, the full 68-file
review snapshot, both package bindings, the immutable core file set, and its
published archive. Identity drift returns `DEFER_NO_ACK_NO_SDK` before ACK.
The existing runner, launch, and core manifest remain unchanged.

## New grant contract

Obtain a fresh global `qfli-core-release-sync` message through the channel CLI.
The new event must have `by=c-coordinator`, `kind=message`, and an explicit
`to=sql-offline-1022` recipient. A one-element recipient array also qualifies.
The exact complete slot name must appear as a complete token in the text.
The event's actual `seq` supplies `--grant-seq`. A number inside a slot name
never supplies the event sequence.

Before supplying `--expected-grant-text-sha`, independently review the complete
event text. It must authorize only the frozen three focused SQL cases and
their existing controls/format/analyze/test/cleanup/publication phases. It must
allow at most 110 seconds total and name `c-coordinator` as successor. It must
exclude additional suites, build/native/device/WSL work and preparation inside
the accepted window. Hash the event's exact UTF-8 `text` value, with no added
newline. The text hash is the explicit scope attestation. The program pins that
attestation instead of guessing the meaning of free-form grant prose.
Supply the exact reviewed budget through required `--total-seconds` (30–110).

The program reads actual global channel events through
`D:/AppData/Roaming/npm/trellis.cmd channel messages ... --scope global --raw`.
It rejects duplicate/missing sequence identities, wrong author or recipient,
changed text, consumed slot names, consumed structured grant sequences, later
coordinator instructions naming the slot, and historical C586/C616 grants.
It creates exclusive persistent claims for both the slot and event sequence.
Partial claims remain consumed. Never remove claims to authorize a retry.

Command template, **not executed during source review**:

The authoritative global protocol acknowledgement is event717. Source review
now enables entry through `EXECUTION_ENABLED = True`. This enables no slot by
itself. A fresh named grant, its actual event sequence and reviewed exact text
SHA256 remain mandatory. This command records the current reviewed source.

```powershell
python build/offline-ide-check/workspace/coordinate-bounded-retry.py `
  --slot-id NEW_FULL_NAMED_SLOT `
  --grant-seq NEW_ACTUAL_EVENT_SEQUENCE `
  --total-seconds 110 `
  --expected-grant-text-sha NEW_REVIEWED_EXACT_TEXT_SHA256 `
  --expected-self-sha e61043c1cbc25d6c4a16b050a5cb93d19218f54281bf9513488c81567c499700 `
  --expected-launch-sha 71692f4ece9339efa20374c9c94183b3df006fbcd76562d0fe0ebf3dd2041249 `
  --execute-slot
```

## Terminal and publication contract

The budget starts immediately before ACK. ACK and child launch occur within
one invocation. For a 110-second grant, the outer wrapper deadline is at most
97 seconds from that start. Shorter grants reserve the same 13 seconds.
The child retains its existing inner 110-second deadline. The parent Job can
terminate its complete owned tree at the earlier outer deadline.

The inherited helper creates the wrapper suspended, assigns it to the outer
Job, and resumes it afterward. It retains the exact process HANDLE, PID and
creation FILETIME. Its cleanup loop keeps those same handles until the root is
terminal and the Job reports active0. It continues holding them if the budget
expires. Nested child Jobs cannot escape the outer Job. No PID-absence check
establishes terminal state.

After terminal observation, the observer finds the unique evidence directory
ending in the retained wrapper PID. It binds that directory to the current
wrapper's hash-verified stdout summary. It reads its actual `final.json`. It checks
the wrapper PID, slot, successor, launch/core/source identities, initial review
snapshot, and every control/validation/pending-publisher terminal active0 record.
It hashes and parses the actual `tests.log`, preserving full group-prefixed
names. Exactly three distinct visible `testDone` events must map one-to-one to
the frozen cases. Hidden events never increase the count. Failures, errors and
skips remain actual outcomes. Report/log size limits and inspection deadline
checks protect the publication reserve.

Before child acceptance, the observer rechecks the coordinator, runner, launch,
core manifest, main sources, core files and archive. A passing child also needs
the actual review snapshot to match `before.json`, written after formatting.
The main source hashes retain their preformat values. The review may retain
legitimate formatter changes. Drift refuses child acceptance and prevents a
passing final publication.

The protocol717 publication path scopes RELEASE to validation ownership. That
scope covers the wrapper and every descendant, including controls and the
child pending publisher. The final sender belongs to the control plane.
`controlPlanePublisherSelfTerminalClaimed=false` explicitly excludes its own
terminal state. The message never grants another product's execution.
The observer may remain alive to coordinate after child validation. Its code
runs no further SDK operation after the wrapper. The next SDK grant requires
the separate final sender's terminal/result evidence as well.

The observer seals `gateStatus` before final publication. Missing or incomplete
child evidence produces `FAILED_INCOMPLETE`. The retained outer wrapper HANDLE
and Job active0 must still prove all validation descendants terminal. A complete
unsuccessful run produces `HOST_GATE_FAILED`. Validation completion beyond the
deadline cannot seal a passing gate.

Before publishing PASS, the observer persists `validation-checkpoint.json`.
It flushes and fsyncs the temporary file, then uses Windows `MoveFileExW` with
REPLACE_EXISTING and WRITE_THROUGH for atomic replacement. The checkpoint stores
the exact gate result, result list, source/evidence hashes, ownership proof,
canonical validation-record hash and exact final message hash. The final
message binds the checkpoint path and validation-record hash. Failed checkpoint
persistence can publish only `FAILED_INCOMPLETE` with `checkpointDurable=false`,
and only after validation ownership has actually been proved terminal.

Final delivery, sender cleanup and final metadata persistence have separate
statuses. An exact receipt records the actual channel sequence. Missing exact
receipt records `DELIVERY_UNKNOWN` without inventing a sequence or retracting a
possibly delivered RELEASE. Unknown sender ownership remains `HOLD` for the
control plane. The observer then atomically persists `final-sender-result.json`
with the exact receipt, actual channel sequence, sender HANDLE/PID/FILETIME/Job
proof, immutable gate result and publication timing. Only a successful durable
write and hash, exact receipt and sender terminal active0 can set both
`controlReturnedToCoordinator` and `successorGrantAllowed` to true. Those flags
permit the coordinator to consider a fresh grant. The observer never launches
a successor SDK operation automatically. Unknown receipt, cleanup or sender
evidence leaves both flags false.

The observer records the publication attempt boundary, receipt-observation
time and cleanup-observation time separately. Publication budget overrun stays
explicit and never rewrites the sealed `gateStatus`. The message always states
`boundedPassClaimed=false`, because its own delivery and cleanup have not yet
been observed while it is sent. Final metadata-write failure records
`CONTROL_PLANE_METADATA_FAILED`; it does not revoke or downgrade the gate.
If the separate sender-result evidence already persisted, failure of the later
coordinator summary does not erase that evidence or revoke the observed return.

## Checks and review concerns

- AST parse passed without importing or executing either coordinator or runner.
- File-only SHA256 checks matched the unchanged runner, launch and core manifest.
- No channel command, synthetic process control, SDK, formatter, analyzer, test,
  build, native operation, device operation or WSL command ran for this work.
- Independent source review must verify the exact grant-text attestation and
  explicit recipient requirement before requesting a grant.
- Nested Job behavior, real publication timing, and actual results remain
  unverified until the fresh named grant. Source readiness is not host acceptance.
- The coordinator lives under ignored `build/`; preserve its bytes and exact
  SHA256 with the reviewed command before any future execution.

## Independent source review and local corrections

The review changed only the coordinator and this note. The frozen runner,
launch, core manifest and test sources were not edited.

- The publication receipt check accepted only a string recipient. The retained
  C616 `publish-pending.log` uses an array. ACK and final receipt checks now
  accept the exact successor string or a one-element successor array.
- Child evidence previously used the PID directory and report alone. The
  observer now verifies the current wrapper log hash and requires one summary
  binding that directory, wrapper PID, final exit and pending-publication flag.
  Missing current summary leaves the outcome `FAILED_INCOMPLETE`.
- Inputs were frozen only before ACK. The observer now rechecks immutable
  inputs and main source hashes before child acceptance. It checks the actual
  post-format review snapshot before accepting a passing result.
- A successful test-stream completion previously needed any successful `done`
  event. It now requires exactly one `done` event with `success=true`.
- Source AST and whitespace checks passed. File-only SHA256 checks matched
  the unchanged runner, launch and core manifest. No coordinator or runner was
  imported or executed. Lint, type-check and runtime tests remain UNRUN under
  the explicit source-only boundary.
- The protocol follow-up separates immutable `gateStatus`, `ownershipTerminal`,
  delivery, sender cleanup and metadata status. It adds the atomic durable
  validation checkpoint and explicit final-message binding. Event717 resolves
  the observer/sender distinction. A second durable sender-result record now
  gates both control-return flags. Source entry is enabled after this review.

The following protocol limits require coordinator decisions or actual runtime
evidence. This review leaves their design unchanged:

- The frozen cleanup loop may retain unknown/live handles beyond the granted
  deadline. This correctly prevents release without terminal proof, but cannot
  guarantee a hard 110-second wall-clock return under Windows API failure.
  The existing five-second control-plane publication attempt can also follow
  an overrun. Its immutable gate keeps the validation result, while explicit
  publication overrun prevents any timely host acceptance claim.
- A RELEASE message reaches the channel before its own publisher terminates.
  It therefore attests validation ownership only. The independent publication
  and metadata statuses may fail after a valid gate result was delivered.
  Event717 requires final sender terminal/result evidence before the next SDK
  grant. No message-only self-terminal or successor execution claim is made.
- File reads, fsync and console writes have no hard OS timeout. Deadline
  checks bound normal processing, not stalled filesystem operations. Actual
  nested Job containment and publication latency remain unverified.

No named grant was consumed during review. The corrected coordinator remains
UNRUN and has no execution slot. This source review establishes no formatter, analyzer, test, full-suite,
native, build, device or WSL acceptance.

## Current-source freeze invalidation after complete-main repair

The existing observer remains a source-reviewed candidate, not executable current readiness. Its pinned launch SHA71692f4e and fixed68 review bindings refer to the retired snapshot. Source preparation copied all64 current Dart files and current declarations/assets/tools. The separate analysis-config-alignment.json records exact main/review configuration parity and preserved old bytes. No launch was refrozen and no SDK was invoked.

Before a new request, obtain the C-owned tested core checkpoint, prepare its immutable archive/config bindings, freeze the complete current-main and review inventories, replace the observer fixed68 requirement with exact complete-map validation, pin the new launch/core identities and obtain independent review. The full gate now requires authenticated focused initial/before/after evidence; keep main preformat bytes unchanged through that gate. All13 template preparation/success fields remain null.

The explicit unsigned static-inspection mode is now a separate source-only repair candidate because the builder produces unsigned output while the inspector currently requires signed metadata/artifact. Future tool hashes and Python test-definition inventory must be recaptured after that repair; existing36definitions are historical authored inventory, not test passes. Do not freeze or request runtime against intermediate source. No device grant is held.
