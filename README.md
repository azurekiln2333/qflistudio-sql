# qfli_sql

This Flutter app is an independent Git repository. Check out `qfli_studio_core` next to it before resolving dependencies.

```text
checkout-parent/
  qfli_studio_core/
  qfli_sql/
```

Run `flutter pub get` here. The shared editor patch is provided by
`../qfli_studio_core/vendor/re_editor`.

## Local Oracle MySQL

The workbench and project SQL runner select the bundled Oracle MySQL 8.4.6 runtime.
The arm64 server and client compile and are included in the signed HAP.
Build the pinned native runtime first using the instructions
in [native/mysql/README.md](native/mysql/README.md), then build the Flutter HAP.
The Hvigor entry script stages the native libraries, versioned runtime data,
and upstream license notices automatically from `build/mysql-port/package`.
An arm64 build fails when the native runtime package is missing.

The runtime manager implements server initialization, a private Unix socket, and shutdown. It
disables TCP networking and keeps database files in app-private storage. Project
SQL files run in a persistent project database, with its schema name recorded
in `.qfli/mysql.json`. The workbench can browse these databases as well.
Existing SQLite files are not automatically migrated to MySQL.

Oracle handles complete SQL scripts over one connection, including `USE`,
transactions, and multiple result sets. Bound queries are used for grid writes.
SQL input is limited to 1 MiB, and displayed results to 1,000 rows and 1 MiB
across a script. Truncation limits output; subsequent statements still execute.
A script error can leave changes from earlier statements in place. MySQL DDL
statements may commit transactions implicitly.

x86_64 builds provide an explicit unavailable result for Oracle MySQL; the
bundled server currently targets arm64 only. HarmonyOS native-child APIs support
PC/2-in-1 devices and, from API14, tablets. They do not support phones. This
project currently declares a phone target, so local Oracle startup is blocked;
the runtime reports that restriction before attempting initialization. No
supported phone hosting path has been established. Device startup/persistence
remain unverified, and further tests are deferred at the user's request.
