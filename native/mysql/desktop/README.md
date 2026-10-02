# Oracle MySQL Desktop Runtime

Windows and Linux use the actual upstream Oracle server and C client. The
adapter in `lib/mysql_database.dart` starts the private server through
`LocalMySqlRuntime` and invokes `qfli_mysql_bridge` on worker isolates. Explicit
injected channels retain their existing behavior. No TCP service is opened and
no SQLite or cloud fallback is performed.

## Build And Package

Windows x64 input is the official Oracle MySQL 8.4.6 ZIP:

- URL: `https://cdn.mysql.com/archives/mysql-8.4/mysql-8.4.6-winx64.zip`
- SHA256: `b6c152f9f3aaa7294eb47db698e47974d37b261bf3cab4f90dc1243bb5ecd204`

Stage it before the Windows Flutter build:

```powershell
./native/mysql/desktop/stage-windows.ps1 -Archive <path-to-official-zip>
$env:QFLI_MYSQL_SOURCE = '<verified-mysql-8.4.6-source-tree>'
flutter build windows
```

The pinned Oracle source tree supplies its RapidJSON headers; source provenance
and extraction instructions are in `native/mysql/README.md`. The default source
location is `build/mysql-port/mysql-8.4.6`. The official Microsoft Visual C++
runtime required by Oracle must be installed on the target Windows host.

Linux staging uses installed **Oracle** development/server packages. It rejects
MariaDB and copies the server, resources, plugins and resolved native dependency
chain. Host libc and the dynamic loader remain system prerequisites:

```bash
bash native/mysql/desktop/stage-linux.sh
export QFLI_MYSQL_SOURCE=<verified-mysql-8.4.6-source-tree>
flutter build linux
```

`QFLI_ORACLE_HOME` overrides the staged distribution location. Windows/Linux
plugin CMake installs the complete runtime into `qfli_mysql/` beside the app.
Missing runtime inputs fail desktop packaging. Standalone native builds use:

```bash
cmake -S native/mysql/desktop -B native/build/mysql-client \
  -DQFLI_MYSQL_SOURCE=<verified-source> -DQFLI_ORACLE_HOME=<staged-distribution>
cmake --build native/build/mysql-client
cmake --install native/build/mysql-client --prefix <installation-root>
```

The launcher lives in `qfli_mysql/bin`. Windows keeps the bridge and Oracle DLL
dependencies in `bin`; Linux keeps the bridge and shared libraries in `lib`.
The runtime explicitly points mysqld at its bundled resources and plugins.
Retain all upstream LICENSE/docs and source/build provenance in release bundles.

## Lifecycle

The default storage is the user's local application data under `qfli_sql/mysql`.
`QFLI_MYSQL_BUNDLE` overrides runtime discovery. The test constructor can inject
an isolated data directory; it never silently substitutes a system server.

Initialization runs in a private staging directory. Only a successful Oracle
initialization is moved to `data`; `initialized.json` records the exact server
version and a random 256-bit local password. Existing data without a successful
marker or a different version returns unavailable; automatic upgrade is disabled.
`root.sql` installs that credential before accepting queries. Unix storage files
are mode 600, directories/socket parents 700. Windows uses the user's local data
ACL, an unpredictable pipe name and Oracle RSA password exchange over that pipe.

A lifetime file lock and process-local registry prevent a second runtime from
using the same directory. Queries and stop are serialized. Stop invokes Oracle
shutdown, waits, and terminates only the owned launcher on timeout. Linux
PDEATHSIG and the Windows creation-time Job Object terminate the owned server
after application death. `stop()` releases its transport and lock while keeping
database contents. Server diagnostics and failed initialization are reported.

## Verification And Remaining Platforms

Run `native/mysql/desktop/runtime_test.dart` with the bundle, bridge and launcher
paths. It checks real initialization, ownership, exact values, parameter errors,
scripts/transactions, output caps, credentials, persistence, stop, parent death
and recovery. It retains its isolated fixture for diagnostics. Set
`QFLI_MYSQL_TEST_BUNDLE` for `test/mysql_desktop_database_test.dart`; these tests
exercise the typed application adapter using a temporary database.

Windows Oracle 8.4.6 and Linux Oracle 8.0.46 have real-engine evidence. Full
Windows Flutter GUI build remains unverified without MSVC; Linux Flutter GUI
and Apple execution have not been tested. Portable macOS launcher/runtime source
exists, but macOS bundle/signing integration is still required. Android server
build/lifecycle, native iOS hosting and the product's local-MySQL engine selector
remain open requirements. This backend delivery does not establish them.
