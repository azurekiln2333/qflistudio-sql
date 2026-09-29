# Design

## Runtime boundary

The final database engine is a bundled MySQL server for HarmonyOS arm64, started with app-private paths and accessed over a local socket. The runtime manager owns initialization, one-instance startup, readiness, shutdown, and diagnostics. The app never reports the server as ready before a live query succeeds. A packaged, versioned binary and its license notices are release artifacts, not user setup instructions.

The existing SQLite source is a separate engine and an immediate way to make the current SQL runner functional during migration. It does not satisfy the MySQL requirement and must not be labeled as MySQL.

## Application boundary

Keep the database workbench in this app package. Define typed results at the engine boundary: column metadata, nullable values, affected-row counts, errors, and stable row identity. Use the same engine contract for script execution and grid mutations. Build SQL identifiers from validated metadata and bind cell values as parameters. The UI manages selection, loading, and error states; the engine owns SQL dialect and storage details.

The workbench's first screen has an object explorer and data grid, with a SQL editor and result view reachable without leaving the workspace. On narrow screens the object explorer becomes a drawer while the grid remains horizontally scrollable. Existing project/editor navigation remains accessible.

## Data flow

User action -> typed workbench command -> engine/client -> local MySQL server -> typed result -> explorer/grid. Schema or data writes invalidate the affected object and refresh only its visible data. Saved queries and history live in app-private persistent storage, separate from database files.

## Compatibility and risk

The current `SqlProgramRunner` and `SqlQueryService` use SQLite paths and text-only output. Migration needs an explicit engine selection and shared result contract; silently interpreting MySQL SQL as SQLite would produce incorrect behavior. Native MySQL server cross-compilation and on-device process support are the main unverified platform risks. Keep source and build inputs reproducible, then prove the binary on a device before marking the runtime complete.
