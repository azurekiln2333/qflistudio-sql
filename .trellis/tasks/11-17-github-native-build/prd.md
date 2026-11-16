# GitHub Mobile Native Builds

## Goal
Move expensive mobile native compilation to GitHub-hosted runners and provide
verified downloadable packages that replace local compiler intermediates.

## User-approved Scope
The user corrected the prior proposal on 2026-11-17 and explicitly requested
immediate implementation. Exclude Linux/Windows builds. Prioritize OHOS and
Android. Include the existing iOS native implementation. Reuse official macOS
MySQL binaries if available; source-build macOS only if there is no usable package.
This correction is approval to implement the revised scope, not a request for
another planning round.

## Requirements
- R1: Report measured local storage and protect existing data/backups.
- R2: Build real OHOS ARM64 Oracle runtime and Android ARM64/x86_64 Oracle
  runtimes on clean hosted Linux runners using pinned inputs and existing ports.
- R3: Include SQLite and its project bridge for the mobile targets. Build the
  existing iOS SQLite implementation with Xcode; do not claim a missing iOS
  MySQL server/lifecycle exists or silently replace MySQL with SQLite.
- R4: Verify official macOS MySQL availability. Reuse official distributions
  rather than compiling an engine that is already distributed upstream.
- R5: Push a dedicated GitHub CI branch and actually run the workflows.
  Fix scoped CI failures and report each target's observed outcome.
- R6: Upload complete native packages, source provenance, hashes and logs.
  Document download locations, retention and local staging commands.
- R7: Preserve unrelated changes, databases, historical packages and non-GitHub mirrors.

## Acceptance Criteria
- [ ] R1/R7: Storage audit separates caches, runtime packages and database backups.
- [ ] R2/R3: OHOS/Android jobs run with their real target toolchains, with
  architecture/dependency checks before successful artifact upload.
- [ ] R3: iOS device/simulator SQLite bridge package builds remotely and is inspected.
- [ ] R4: macOS official package links and the current integration boundary are documented.
- [ ] R5: Real GitHub run URLs and per-job results are recorded. Any unresolved
  resource/toolchain/implementation blocker is explicit, never a false pass.
- [ ] R6: Successful downloadable artifacts match manifests/checksums and documented layouts.
- [ ] R2/R6: Static checks and independent review pass for workflow/helper changes.

## Confirmed Facts
Local HEAD started at a841bc77, six commits ahead of GitHub main. No project
workflow existed. origin has five push URLs; use the explicit GitHub URL.
OHOS uses MySQL8.4.6/OpenSSL3.5.3, SDK23/6.1.0.32 and Clang18. Android uses NDK27.
The Flutter application depends on sibling qfli_studio_core; standalone native
builds avoid that dependency. Existing native iOS packaging is SQLite only.

## Out of Scope
Complete application builds/signing/store publishing/device acceptance;
new iOS MySQL hosting architecture; Linux/Windows compilation; blanket local
cleanup; non-GitHub publication. OHOS x86_64 research is not a portable production
build entrypoint and remains deferred unless a narrow reuse is demonstrated.
