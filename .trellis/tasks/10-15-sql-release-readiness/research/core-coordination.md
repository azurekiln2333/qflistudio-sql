# Shared offline release coordination

SQL coordinator works only in D:/MyNewProjects/qfli_sql. Shared core source is read-only for all SQL workers. User explicitly requested coordination with qfli_studio_core for offline store release; home navigation consolidation remains app-local.

At core revision ad17f35ac728e19670de1df305bc3e55c3b5172c, SQL audit confirms EditorPage Git popup and GitPage push/pull/remote actions lack offlineOnly guards. StudioProfile has no local hide-Git switch and EditorPage has no menu override. SQL-specific stale cloud engine/adapters are being guarded locally; both terminal surfaces now receive an app-local SQL command delegate.

Global channel qfli-core-release-sync already records Rust/Go findings and an active core-owned task .trellis/tasks/10-15-offline-editor-gates. Please keep shared mutations serialized under that owner; SQL will not duplicate edits. Additional profile refresh/task activity/settings AI gates reported by Go should be checked centrally. Core Pi wF:p2 has a missing runtime module on incoming turns, so its apparent done status is not evidence a fix landed.

Please post the owning coordinator, final core commit and regression evidence to the existing global channel. SQL final acceptance needs the shared offline fixes, and will re-run product tests against the resulting pinned revision. Do not change SQL navigation or other language products as part of the core fix.

## Final coordinated snapshot

Shared core source is clean at `8b33443`. External owners delivered offline
editor gates (`54a58ca`), background/network shortcuts (`b7b2d2e`), retained
editor animation (`665febb`), generic large-text tools layout (`7b8b7f2`), exact
non-Java import names (`a838c25`) and product About identity (`8b33443`). SQL
remained read-only in core; its five-page home and natural-height tools list
were implemented only in this product.

Final SQL validation against this snapshot: full tests **92 passed / 2 explicit
desktop Oracle skips**; scoped Flutter analysis and root repository Dart
analysis both report **No issues found**. Evidence:
`final-core8b33443-tests.log`, `final-core8b33443-analyze.log`,
`final-core8b33443-repository-analyze.log`. The final unsigned OHOS HAP was also
rebuilt against this source; see `ohos-final-hap-audit.md`.

Correction to the initial audit: direct inspection confirms shared sandbox
`help` and unsupported-command messages already use generic wording. The
earlier Java-copy claim was incorrect and is withdrawn. `sql --help` documents
the local SQL command syntax.

Desktop `createSandboxShell` retains its host-shell fallback, which can run
manually typed host Git/curl commands. Mobile has no host-shell fallback.
Reachable offline UI gates must not be described as strict desktop network
isolation or universal service-level authorization. SQL does not modify this
common behavior without its owner's coordinated review.
