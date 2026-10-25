# QFLISQLab (`qfli_sql`)

English · [简体中文](README.md) · [繁體中文](README.zh-TW.md)

A standalone, offline-first SQL IDE built with Flutter. It bundles its own
SQLite engine, can run a bundled Oracle MySQL server locally, and ships a built-in
SQL curriculum. You do not need an external database server, a cloud account, or a network
connection to use the app.

This repository is one product in a family of standalone language apps that all
consume the shared `qfli_studio_core` package.

## Overview

- Built with Flutter as `qfli_sql` (product key `sqlab`, bundle
  `com.azurekiln.qfli.sqlab`, version `1.0.0`); entry point `lib/main.dart`,
  which installs the offline-only `sqlProfile` for `.sql` files.

- Interface language is Simplified Chinese. The home screen has five swipeable
  destinations: 数据库 (Databases), 项目 (Projects), 功能 (Tools), 教程
  (Tutorials) and 示例 (Examples). A phone shows a bottom navigation bar; a wide
  window shows a navigation rail.

## Capabilities

**数据库 — Databases.** An expandable database → table tree (the phone body, a
desktop side panel) next to a data grid. Row edits use stable hidden row identity
and bound parameters; a SQLite table without an unshadowed `rowid` alias is shown
read-only, and an update that does not affect exactly one row is reported as a
stale row. Saved queries are stored independently of the engine.

**项目 — Projects.** Project list with search, plus add/remove actions. Opening a
project uses the shared editor route, and each project runs against its own
database: `<project>/.qfli/data.sqlite` for SQLite, or the schema named in
`<project>/.qfli/mysql.json` for Oracle. Retained editor state and named
workspaces in the SQL shell are still pending, so this README does not promise
them.

**功能 — Tools.** SQL features are embedded directly here, not behind a
secondary landing page:

- Worksheet with the captured engine and database identity, ordered result sets,
  affected rows and errors, retained across tab switches.

- Query plan: plain `EXPLAIN QUERY PLAN` (SQLite) or `EXPLAIN` (MySQL) for one
  guarded statement. It never runs `EXPLAIN ANALYZE` and never re-executes your
  worksheet statement.

- Structure and indexes: columns with type, nullability, primary-key and
  generated flags, plus index inspection with real names, uniqueness, origin,
  partial and expression markers. Index creation is a previewed `CREATE INDEX`
  that never runs on its own.

- Text and value tools: formatting that preserves literals, quoted identifiers
  and comments; identifier and literal helpers; explicit NULL-versus-empty-string
  handling; CSV copy of captured rows.

**教程 / 示例 — Tutorials and Examples.** The app's own curriculum, loaded from
the SQL assets in this repository. Every example is a self-contained script
(create, insert, query) with an authored expected result, and the dialect
(SQLite 3.50 or MySQL) is stated in the entry.

**Editor diagnostics.** Unsaved SQL buffers are checked through the shared
`CodeAnalyzer` contract. Lexical checks report only provable problems
(unterminated strings, identifiers and block comments; mismatched parentheses).
For SQLite, engine-level checking prepares statements in a private in-memory database and
never steps them, never opens your database, and refuses PRAGMA, ATTACH, DETACH,
external file functions and virtual tables. Ranges are UTF-16 offsets converted
from native byte offsets. A missing object in the empty validation schema is
reported as limited coverage, not as a syntax error.

**Terminal.** One SQL delegate serves both terminals: `sql <file.sql>`,
`sql -e "SQL"`, `sql --execute "SQL"`, `sql --help`. There is no interactive
`mysql`/`sqlite3` client and no SQL cancellation API.

## Engine and platform support

Two independent local engines exist. Selecting one never silently switches to the
other, and tools never relabel a SQLite run as MySQL.

### SQLite (bundled 3.50.0, public domain)

| Platform | Transport |
| --- | --- |
| Android, iOS, Windows, Linux, macOS | Bundled C library through FFI on a worker isolate |
| HarmonyOS | Native NAPI bridge `libqfli_sql.so` on the `qfli_sql/native` channel |
| Web | Not available — the SQL engines are native only |

Limits: 500 complete rows and 1 MiB of cell bytes per grid query; one shared
500-row / 1 MiB budget per script, up to 512 statements; 3000 ms database lock
wait; editor engine input capped at 512 Ki UTF-16 (Dart) and a further 1 MiB
UTF-8 on HarmonyOS; validation stops after 512 prepare attempts, and the FFI
deadline cannot cancel an in-flight prepare. Truncation never returns a partial
row, and reaching a limit or hitting an error keeps completed results while
failing the summary.

### Oracle MySQL 8.4.6 (bundled server)

| Platform | State |
| --- | --- |
| Windows, Linux | Local server started by the app over a private pipe/socket, with TCP disabled |
| Android | 64-bit only, API 28+ |
| macOS | Not integrated here: the helper build and signing wiring are pending, and execution is unverified |
| iOS | Not implemented |
| HarmonyOS | arm64-v8a and x86_64 runtimes are packaged; a phone starts the server as a forked, privately loaded image because the sandbox forbids child-process start |

Historical host checks used MySQL 8.4.6 on Windows and MySQL 8.0.46 on Linux.
Android engine integration tests passed on an API 37 x86_64 emulator on
October 2, 2026, and a physical API 36 ARM64 OPD2413 on October 15, 2026.
These historical results do not establish acceptance of the current source.

Oracle traffic uses a private Unix socket or pipe with `skip-networking`; TCP is
never a fallback and the app does not request network permission. Defaults are
1 MiB of SQL input, 1,000 rows / 1 MiB of displayed results, at most 128 result
sets per script and an 8 MiB packet limit.

**Transactions.** Both engines use per-call connections, so there are no
standalone Begin/Commit/Rollback buttons — a transaction must be written inside
one script, where a single connection is real. Truncation limits output only and
later statements still run, so a script error can leave earlier changes in place.
Much MySQL DDL commits implicitly, and wrapping it in a transaction is not
described as rollback-safe.

## Prerequisites and sibling checkout

`pubspec.yaml` depends on the shared core and the vendored editor by relative
path, so both must sit beside this repository:

```text
checkout-parent/
  qfli_studio_core/
  qfli_sql/
```

The two path dependencies are `qfli_studio_core` at `../qfli_studio_core` and the
`re_editor` override at `../qfli_studio_core/vendor/re_editor`.

You need a Flutter SDK with Dart `^3.11.5`. HarmonyOS builds additionally need the
Flutter OHOS fork, an installed DevEco Studio (SDK, Node/npm, OHPM, Hvigor, Java)
and a build identity. Do not edit `../qfli_studio_core` from here; note the core
revision you built against.

## Build

Run these from this repository root. `flutter pub get` resolves the relative
dependencies above.

```bash
flutter pub get
flutter run -d <device-id>
flutter build windows        # also: linux, macos
```

The Oracle server runtime is a separate native build that must exist before an
application build for a supported ABI. `native/CMakeLists.txt` and Hvigor fail
rather than substitute a stub when a required image or resource is missing:

- [native/README.md](native/README.md) — bundled SQLite bridge and packaging
- [native/mysql/README.md](native/mysql/README.md) — pinned Oracle/OpenSSL inputs
  and the HarmonyOS arm64 port

- [native/mysql/android/README.md](native/mysql/android/README.md) — Android build
- [native/tests/README.md](native/tests/README.md) — Oracle host verification setup

Windows and Linux native preparation is documented in
[native/mysql/desktop/README.md](native/mysql/desktop/README.md). It requires
upstream Oracle distributions. The macOS helper build and signing integration
remain pending, and macOS execution is unverified.

The HarmonyOS audit wrapper builds a separate audit package, then restores the
original configuration byte for byte. Read the
[audit packaging contract](.trellis/spec/backend/ohos-audit-packaging.md) first:

```powershell
& tool/ohos/build_audit_hap.ps1 -Target <entry>.dart -Architecture ohos-arm64
& tool/ohos/sign_audit_hap.ps1 -DeviceUdid <actual-device-udid>
```

A successful package build does not establish installation or runtime acceptance.

## Checks

```bash
flutter analyze --no-pub lib test integration_test
flutter test --no-pub
```

Suites that need a real native library or a device print an explicit skip; a
skip is not a pass. Keep unavailable-engine skips separate from passes.

```powershell
& native/tests/run-sql-validation-test.ps1        # validation core, real SQLite
& native/tests/check-ohos-sql-napi-syntax.ps1     # HarmonyOS bridge, -Werror
```

The compile gate prints `SKIP` when no DevEco SDK is installed. Device suites
under `integration_test/` need an attached target. The offline policy handler
check does not require a device:

```bash
node tool/test_sql_offline_platform.cjs
```

## Offline boundary

- The app profile is offline-only: a persisted cloud engine selection is mapped
  back to local SQLite without opening a connection, saving cloud is refused, and
  cloud code paths check policy before reading a token or calling an API.

- On HarmonyOS, the ability refuses agreement, browser-open and login requests
  with a single `OFFLINE_ONLY` error before reading arguments. The single declared
  permission is `ohos.permission.READ_PASTEBOARD`; the archive inspector rejects
  network permission.

- Tools, diagnostics and content use only bundled engines, app-owned files and
  pure computation. Developer research, Git publication and pushes may use the
  network; that does not change runtime policy.

## Current acceptance limits

This section separates what source and host checks establish from what has
actually run. Nothing here is a release acceptance claim.

**Established:** the bundled SQLite engine and its per-platform packaging; a
consistent Dart/NAPI/ArkTS contract for the native methods, result shapes and
limits; host suites and native harnesses for engines, diagnostics, terminal,
offline policy and content; the bridge compiling for arm64 and x86_64 with
`-Wall -Wextra -Werror`.

**Open — no pass claimed:**

- No current HarmonyOS build, install or normal-app run is attested here. The
  recorded audit package predates the native offline policy change, so it cannot
  prove the current policy. Normal application acceptance is still pending.

- Production signing files are missing. Audit packages use only the installed
  public SDK test identity, and signature verification does not establish install
  trust or ordinary device trust.

- **Packaging is not execution proof for Oracle.** The x86_64 runtime is staged
  and closure-audited, and its own record marks it runtime- and device-unverified:
  it is packaged, not proven to start, persist or shut down. The same distinction
  applies to the packaged arm64 runtime.

- macOS Oracle execution, iOS Oracle hosting and any HarmonyOS UI interaction
  each need their own host and run.

- No SQL debugger, breakpoint/step backend or managed port forwarding exists, so
  none is offered.

## Known gaps

- A file larger than the engine budget is validated lexically only, and the
  limitation is stated in the result.

- MySQL diagnostics are lexical-only; there is no MySQL grammar validation.
- SQLite diagnostics run against an empty schema, so missing objects are reported
  as coverage gaps rather than resolved against your data.

- The SQLite grid advertises no schema-editing or export capability; index
  creation is available for Oracle only, while SQLite index tooling inspects
  existing indexes and previews DDL.

## Content

The shipped catalog has 126 tutorials and 126 examples: 120 SQLite examples
and six MySQL examples. It includes 246 exercise answers, so the full original
audit denominator is 372 scripts. These counts do not establish an OHOS pass.

Curriculum authoring lives in `tool/sql_curriculum/lessons/`, and the shipped
assets under `assets/content/` are generated from it. Checks:

```bash
python tool/sql_curriculum/coverage.py
python tool/sql_curriculum/validate_content.py
python tool/sql_curriculum/validate_assets.py
```

`tool/sql_curriculum/build_content.py` regenerates the shipped assets; it has no
`--help` parser, so passing `--help` still rewrites them. Read its source and run
it deliberately.

## Upstream

Bundled engines: [SQLite](https://www.sqlite.org/) 3.50.0 (public domain),
[Oracle MySQL](https://www.mysql.com/) 8.4.6 community source, and OpenSSL 3.5.3.
Release distributions must ship the corresponding upstream sources, patches,
build scripts and license notices for these native components.
