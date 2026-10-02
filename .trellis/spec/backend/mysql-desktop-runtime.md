# Oracle Desktop Runtime

## Scope

Windows/Linux local Oracle MySQL backend and packaging. The default product
engine preference currently remains SQLite/cloud; selection of this local
backend is a subsequent integration requirement. macOS bundle/signing, Android
server integration and native iOS hosting remain implementation gaps. Never
report those platforms as delivered based on portable source or desktop tests.

## Interfaces And Transport

- `NativeMySqlDatabase({MethodChannel? channel, LocalMySqlRuntime? runtime})`:
  an explicit channel wins. Otherwise desktop calls use the injected/shared
  runtime; Android/OHOS/iOS retain their existing channel path for now.
- `LocalMySqlRuntime.invoke(method, arguments)` accepts `query` and
  `executeScript`. `schema` is a schema name, including empty server scope;
  `source` is SQL, `params` is nullable strings for prepared queries.
- `MySqlFfi.invoke(libraryPath, request)` runs the real C client on an isolate.
  `qfli_mysql_invoke(const char*, size_t)` returns allocated UTF-8 JSON, freed
  only with `qfli_mysql_free`. Request fields add `method`, `socket`, `password`.
- `query`, `executeScript`, `shutdown` share the existing typed result shape.
  Script summary fields occupy the outer object; `results` are ordered results.
  No double conversion of BIGINT/DECIMAL; binary fields are hex; NULL stays null.
- Default display limits are 1,000 rows/1 MiB; optional `rowLimit` and `byteLimit`
  can only lower them. Scripts drain every Oracle result, retaining at most 128.
- New credentialed C++ overloads retain all existing OHOS signatures and symbols.
  Windows fixes `MYSQL_PROTOCOL_PIPE` and enables
  `MYSQL_OPT_GET_SERVER_PUBLIC_KEY` for Oracle caching_sha2_password RSA exchange.
  Linux/macOS use `MYSQL_PROTOCOL_SOCKET`. Neither can fall back to TCP.

## Lifecycle And Files

Default data is `<local-application-data>/qfli_sql/mysql`; Windows uses
LOCALAPPDATA, Linux XDG_DATA_HOME or ~/.local/share, macOS Application Support.
`QFLI_MYSQL_BUNDLE` overrides installed bundle discovery. The explicit constructor
supports isolated fixtures. Production must not set the test `serverUser=root`.

`runtime.lock` is held for the server lifetime; a canonical directory registry
rejects duplicate owners in the same isolate. Initialization creates a private
staging directory, invokes upstream `--initialize-insecure`, and moves only a
successful datadir to `data`. `initialized.json` stores the exact Oracle version
and random 256-bit credential. `root.sql` sets it before readiness checks.
Missing metadata beside existing data, malformed metadata or a changed version
returns unavailable; `--upgrade=NONE` prevents implicit upgrades. Recovery of
such metadata is a separate explicit operation, never deletion of user data.

Unix directories are 700, credential files 600 and sockets use a short private
temporary parent. Windows storage inherits the user's local application ACL;
pipe names are unpredictable and queries require the stored credential. Server
startup disables TCP, mysqlx, LOCAL INFILE and filesystem import/export. It uses
bundled plugin/message paths and modest embedded-service memory settings.

`invoke` and `stop()` serialize. Graceful stop uses Oracle shutdown, bounded
wait, then owned-process termination. Cleanup releases directory ownership even
if socket cleanup fails. Linux launcher validates the app parent then sets
PDEATHSIG; Windows uses a creation-time Job Object and waits on the app handle.
Normal exit and application death leave data for upstream InnoDB recovery.

## Packaging

`native/mysql/desktop/CMakeLists.txt` builds the client bridge and launcher.
Windows/Linux FFI plugin builds include it and install `qfli_mysql/{bin,lib,share}`
beside the app. Missing server/source inputs fail desktop packaging. Windows
Oracle/OpenSSL DLLs are resolved from bridge directory through LoadLibraryExW;
Linux client uses $ORIGIN RPATH and the child uses its bundled lib directory.

Use the hash-verified 8.4.6 official Windows ZIP and its retained licenses/docs.
Linux staging copies installed Oracle packages, complete dependency resolution,
resources/plugins and license inputs. Keep provenance and host libc prerequisites
explicit. CMake requires verified Oracle source RapidJSON headers; no ad hoc JSON
serializer or replacement SQL engine is allowed.

## Verification

- Standalone lifecycle test: actual upstream initialization/version/private
  transport, ownership, exact prepared values, metadata/NULL/binary, diagnostics,
  transactions/partial scripts, caps/result draining, credentials/no fallback,
  persistence/stop/restart, version rejection, app death and crash recovery.
- Typed adapter tests: set `QFLI_MYSQL_TEST_BUNDLE` to a built bundle; assert exact
  data, script results/errors and missing-runtime behavior. No mock establishes
  real native functionality. Existing explicit-channel tests must keep passing.
- Available evidence: Windows 8.4.6, Linux 8.0.46, complete installed runtime
  bundles, Windows Flutter tests. MSVC/full desktop GUIs and Apple execution
  are not established by these checks.

## Wrong Vs Correct

Wrong: enable TCP when a socket/pipe login fails, split scripts by semicolons,
replace a version-mismatched datadir, or change the old OHOS C++ ABI.

Correct: return the real error, use Oracle's prepared/multi-statement client,
keep persistent data and retain old symbols alongside credentialed overloads.
