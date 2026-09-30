# Local MySQL database workbench

## Goal

Make QFLISQLab a self-contained local database application. A user can create databases and tables, run SQL, browse objects on the left, and edit table data directly on the right without installing or configuring a separate MySQL server.

## Confirmed State

- The Flutter shell delegates project editing to `qfli_studio_core`.
- `SqlProgramRunner` currently defaults to an unavailable engine. The existing HarmonyOS SQLite source and channel do not make the runner usable yet.
- The current SQL tool is a text box with text output. There is no database tree or editable result grid.
- The HarmonyOS build targets arm64. No MySQL server binary is bundled in this repository or available on the development PATH.
- The worktree contains unrelated, pre-existing changes; commits for this task must stage only task-owned files.

## Requirements

1. Bundle and start a real, local Oracle MySQL server on the supported target device. MariaDB or a compatibility layer does not satisfy this requirement, as confirmed by the user on 2026-09-30. The app must own initialization, storage, lifecycle, error reporting, and a clean shutdown. It must not require the user to install or administer a separate server.
2. Execute MySQL SQL statements against the local server, including schema changes and data queries. Report affected rows, columns, result values, and errors accurately.
3. Let users create, rename where supported, and delete databases, tables, columns, and indexes with confirmation for destructive actions.
4. Show databases and tables in a navigable left pane and table rows in an editable grid in the main pane. Support adding, changing, deleting, refreshing, filtering, sorting, and paging rows, with correct NULL and typed values.
5. Provide practical SQL tools: query tabs or history, saved queries, schema inspection, import/export, and a clear execution/result view.
6. Retain access to the existing project/editor workflow. The first useful screen should expose the database workbench. Do not show development-status copy, fake data, or success states for unavailable operations.
7. Commit each coherent change batch with a conventional commit message. Do not stage unrelated pre-existing worktree changes.

## Acceptance Criteria

- [ ] A clean HarmonyOS arm64 install initializes and starts its bundled MySQL runtime with no external server setup.
- [ ] After a restart, a database, table, inserted rows, and saved SQL are still present.
- [ ] `CREATE DATABASE`, `CREATE TABLE`, `INSERT`, `SELECT`, `UPDATE`, and `DELETE` succeed from the SQL editor; malformed SQL yields a useful error.
- [ ] A database and its tables appear in the left pane; selecting a table shows its real rows and columns in the right pane.
- [ ] Grid edits, row insertion, and row deletion round-trip through MySQL and survive a refresh.
- [ ] Schema actions, filtering, sorting, paging, history, saved queries, and import/export work on real local data.
- [ ] Existing project/editor navigation remains reachable and the app contains no development-status or sample-data filler.
- [ ] Platform build, static analysis, automated tests, and on-device runtime smoke checks pass for the delivered features.
