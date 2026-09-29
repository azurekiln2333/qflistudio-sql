# QFLISQLab native SQLite bridge

This directory embeds the official SQLite 3.50.0 amalgamation. The app uses a
project-local database at `.qfli/data.sqlite`; no MySQL server or desktop
`sqlite3` executable is required.

The bridge exposes only two NAPI functions:

- `execute(source, databasePath)` returns `available`, `exitCode`, `output`,
  `error`, and `truncated`.
- `version()` returns SQLite's own `sqlite3_libversion()` value.

The HarmonyOS build compiles `native/CMakeLists.txt` and packages
`libqfli_sql.so` into the HAP. The NAPI entry point lives in
`ohos/entry/src/main/cpp/` because Hvigor enables its CMake task only when
the module's source set contains C++ code. After building, verify the HAP
contains `libs/arm64-v8a/libqfli_sql.so`.

The Dart runner calls the registered `qfli_sql/native` channel and creates
the project database directory before opening it. The device integration test
in `integration_test/sql_native_test.dart` checks write, read, persistence,
and SQL error handling against the packaged engine.

The `query` method is for a single prepared statement. It binds nullable text
parameters and returns column names, nullable rows, affected-row count, and a
truncation flag. Its 500-row / 1 MiB cap is a UI safety limit; callers page
table data rather than relying on unbounded results.

Source: https://www.sqlite.org/
Version: 3.50.0
License: public domain, as declared by the upstream SQLite source.
