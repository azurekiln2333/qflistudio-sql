# Design

## Runtime boundary

The final database engine is a bundled Oracle MySQL server for HarmonyOS arm64, started with app-private paths and accessed over a local socket. MariaDB is excluded by the user's explicit engine choice. Oracle MySQL 8.4.6 is the pinned source used for the initial port experiment. The runtime manager owns initialization, one-instance startup, readiness, shutdown, and diagnostics. The app never reports the server as ready before a live query succeeds. A packaged, versioned binary and its license notices are release artifacts, not user setup instructions.

The existing SQLite source is a separate engine and an immediate way to make the current SQL runner functional during migration. It does not satisfy the MySQL requirement and must not be labeled as MySQL.

## Application boundary

Keep the database workbench in this app package. Define typed results at the engine boundary: column metadata, nullable values, affected-row counts, errors, and stable row identity. Use the same engine contract for script execution and grid mutations. Build SQL identifiers from validated metadata and bind cell values as parameters. The UI manages selection, loading, and error states; the engine owns SQL dialect and storage details.

The workbench's first screen has an object explorer and data grid, with a SQL editor and result view reachable without leaving the workspace. On narrow screens the object explorer becomes a drawer while the grid remains horizontally scrollable. Existing project/editor navigation remains accessible.

## Data flow

User action -> typed workbench command -> engine/client -> local MySQL server -> typed result -> explorer/grid. Schema or data writes invalidate the affected object and refresh only its visible data. Saved queries and history live in app-private persistent storage, separate from database files.

## Compatibility and risk

The current `SqlProgramRunner` and `SqlQueryService` use SQLite paths and text-only output. Migration needs an explicit engine selection and shared result contract; silently interpreting MySQL SQL as SQLite would produce incorrect behavior. Native MySQL server cross-compilation and on-device process support are the main unverified platform risks. Keep source and build inputs reproducible, then prove the binary on a device before marking the runtime complete.

## Phone host investigation (2026-10-09)

On the connected MRT-AL10 phone, both API 26 child-process capability queries
returned false. Direct execution of the installed launcher and execution through
the system musl interpreter both returned EACCES. The PC-only
executableBinaryPaths declaration caused installation rejection. These results
rule out the tested fresh-exec paths on this phone; they do not establish that
every possible native process design is unavailable.

Pi owns implementation and the complete build/install/device-test loop. The
current alternative is an isolated prototype of a privately linked server DSO,
loaded and fully initialized in the parent before each independent fork child
enters it. The parent must never run the server. This preserves separate
initialization/service processes and does not substitute another engine or
change the target to tablets.

Before enabling that host in production, prove private Oracle/OpenSSL/ICU and
C++ runtime binding, audit load-time constructors and process-wide effects,
account for the platform libc fork repair boundary, reset child signals and
descriptors, and cover every child termination path without inherited parent
finalizers. RTLD_LOCAL alone is not a binding guarantee, and a constructor-name
list is not a quiescence audit. Require bounded cleanup with retained and
reachable ownership, parent-death cleanup, and fresh initialization/service
children for every restart. No post-fork library loading, security-policy
changes, or execution from writable app-data files is part of the design.

The prototype uses owned test data and must pass actual Oracle identity, exact
CRUD/error handling, shutdown/restart, persistence, and parent-survival checks.
Compilation, ELF inspection and host tests are separate evidence. The normal
application must be restored and checked before delivery. See
research/option-b-private-preload-design.md and
research/phone-acceptance-main-2026-10-09.md for current evidence.
