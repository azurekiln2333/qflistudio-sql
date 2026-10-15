# Design

The shared StudioProfile.isOffline policy remains authoritative. Audit the shared surfaces read-only and fix only qfli_sql bypasses. Any common-core defect is documented as a coordinated follow-up rather than editing another workspace.

The SQL app owns a five-page home shell. Reuse shared public tab widgets and the existing local SQL workbench/projects/content repository. Add embedding contracts to local widgets where necessary so one shell owns the top-level navigation; retain standalone page behavior for pushed routes and tests. Preserve SQL native lifecycle and database state.

Use current substantive local curriculum as the candidate release source. Validate content structure, uniqueness, dialect labeling, runnable examples and exercise answers before deciding whether regeneration is necessary. No user data cleanup is authorized by the curriculum instruction.

Parallel ownership: UI implementation owns main.dart/sql_app.dart/home shell/workbench embedding/projects embedding and UI tests; terminal/offline audit owns runner, engine preference and its tests only after communicating needed files; curriculum worker owns assets/content, tool/sql_curriculum and curriculum tests; platform worker owns Android/OHOS build investigation and validation reports (no native source edits until coordinated). Main coordinator owns task artifacts/spec updates, integration checks and Git commits.

The initial tree contains 121 existing changes. Capture baseline status and scoped diffs before writing. Never reset/clean, broadly stage, upgrade SDKs, or uninstall a user app. Shared core is concurrently used by other products and can change externally; record its revision for final validation.
