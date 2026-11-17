# Execution Plan

## Approved Gate
- [x] Task creation approved.
- [x] User reviewed the first plan, corrected scope to mobile targets, and ordered implementation.
- [x] PRD/design/context updated to match that instruction.
- [x] Start the Trellis task and create the dedicated CI branch.

## Ordered Work
1. Dispatch native CI implementer for workflow, OHOS/Android orchestration,
   shared host generators, package checks and native/CI.md.
2. Dispatch Apple implementer for iOS SQLite packaging and macOS package research.
   Keep file ownership distinct and integrate their job through the main workflow.
3. Main agent prepares GitHub-only push/authentication and source provenance.
4. Run actionlint, shell/Python syntax and focused packaging checks; avoid local
   large Oracle builds. Review edited Chinese with scripts/ste-lint-zh.py.
5. Dispatch trellis-check and resolve concrete findings.
6. Commit only owned changes and push explicitly to the GitHub CI branch.
7. Observe actual jobs, fix CI defects, and retry until success or a concrete
   external/platform blocker remains. Do not call a queued build complete.
8. Download successful artifacts and verify hashes/inventory/ABI and staging paths.
9. Update native CI spec, task evidence and finish-work. Report exact run/artifact URLs.

## Validation
YAML/actionlint, shell syntax, Python checks, actual runner compile/package audits,
iOS XCFramework slice inspection and artifact manifest/hash verification.
Compilation is not application/device execution. Preserve logs and every platform's
actual outcome. Do not replace unavailable iOS MySQL with a mock or claim support.

## Completion Checkpoint
All implementation and validation steps passed on 2026-11-17. OHOS/Android
passed in run 43937691966 at 5a83aea; iOS passed in targeted run 43942332046
at 08a3b41. Downloaded archives passed independent hash, architecture, symbol
and platform/dependency checks. The user-requested main merge was a fast-forward
to 08a3b41, followed by an explicit GitHub push and remote ref verification.
Final evidence records each package's source commit and its verification limits.
