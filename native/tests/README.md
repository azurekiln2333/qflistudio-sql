# Oracle MySQL host verification

These tests verify the native C API client and Dart repository against a real
Oracle MySQL server. They do not prove that the HarmonyOS server port works.
The initial verified host was Ubuntu's Oracle MySQL 8.0.46 in the
`qfli-java-build` WSL distribution. The target port remains Oracle MySQL 8.4.6.

## Build

Install the host Oracle client development headers, pkg-config, and a C++17
compiler. RapidJSON can be read from the pinned Oracle source archive without
downloading another copy:

```bash
cmake -S native/tests -B build/mysql-host-tests \
  -DRAPIDJSON_INCLUDE_DIR="$PWD/build/mysql-port/mysql-8.4.6/extra/rapidjson/include"
cmake --build build/mysql-host-tests --parallel 1
```

## Run

Use an isolated test data directory and a private socket. Initialize it with
`mysqld --no-defaults --initialize-insecure`; run the server with
`--skip-networking` and explicit data, socket, PID, log, temporary, and
`secure-file-priv` paths. A small buffer pool and disabled performance schema
are sufficient for these tests. Do not point the tests at user databases.

```bash
build/mysql-host-tests/mysql_client_test /path/to/private/mysql.sock
```

The client suite checks exact BIGINT and DECIMAL values, quoted text, NULL,
binary bytes, unchanged updates, large cells, output caps, malformed SQL,
parameter mismatches, single-statement enforcement, and socket errors.

The Dart suite currently invokes the bridge through the `qfli-java-build` WSL
distribution. From PowerShell:

```powershell
$env:QFLI_MYSQL_TEST_BRIDGE='/mnt/d/MyNewProjects/qfli_sql/build/mysql-host-tests/mysql_query_bridge'
$env:QFLI_MYSQL_TEST_SOCKET='/path/to/private/mysql.sock'
flutter test --no-pub native/tests/mysql_workspace_test.dart
```

It checks database/table CRUD, auto-increment keys, composite and binary keys,
Unicode text, BLOB/empty/NULL distinctions, filtering, sorting, paging,
read-only tables without a primary key, and actual Oracle SQL errors. Each
test creates and drops its own uniquely named schema. Shut down the owned
test server after verification.
