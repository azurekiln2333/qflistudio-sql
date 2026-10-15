# MySQL-hosted curriculum verification (Linux MySQL 8.0.46)

- Task: `.trellis/tasks/10-15-sql-release-readiness`
- Date: 2026-10-15
- Host: WSL distro `qfli-java-build`, real Oracle server
  `/usr/sbin/mysqld` **8.0.46-0ubuntu0.24.04.4 for Linux on x86_64 ((Ubuntu))**
  and `/usr/bin/mysql` **8.0.46**. Confirmed by `mysqld --version` /
  `mysql --version` in the run log.
- Source of truth: the **shipped assets**
  `assets/content/sql_examples.json` + `assets/content/sql_tutorials.json`
  (loaded exactly as the app's `SqlContentRepository` does).
- Isolation: a private `mktemp -d /tmp/qfli-mysql-review.XXXXXX` root containing
  its own `datadir/`, `tmp/`, `socket`, `pid-file` and `mysqld.log`; started with
  `--no-defaults --skip-networking --mysqlx=0 --skip-log-bin`. No system service,
  no user datadir, no other workspace was touched. `SKIP_NETWORKING=1`,
  mysqlx disabled, TCP port 0 (no listener).
- Constraint respected: only Python (inside WSL) + the MySQL server were used.
  **No Flutter/pub/platform build or device operation.** No source file was
  modified. Nothing was committed.

## Method

1. Extracted the 6 MySQL-only cases from the shipped assets
   (`engine == "mysql"`): `sql-example-121`…`126`. For each, the lesson `code`
   (full CREATE+INSERT+query script), `expectedOutput`, `exerciseSetup`, the
   authored `exerciseExpectedOutputs`, and each exercise `answer`.
2. Started an owned `mysqld` 8.0.46 on a private socket and validated identity
   (`VERSION`, `@@version_comment`, `@@skip_networking`, mysqlx disabled).
3. For each case: created a dedicated schema, executed the lesson `code`, and
   compared the result to the **authored** `expectedOutput`. For each exercise:
   created a **separate** schema, ran `exerciseSetup` + `answer`, and compared to
   the **authored** `exerciseExpectedOutputs[i]`.
4. Expectations come only from the assets — never generated from execution.
   Comparison follows the app/native-test normalization
   (`integration_test/sql_curriculum_native_test.dart`): columns joined with
   `|`, SQL NULL rendered as empty. (`mysql --batch` uses tab separators and
   prints `NULL` literally, so the harness maps those to the app's format.)
5. Each schema is dropped after use; the private server is shut down and all
   owned `/tmp/qfli-mysql-review.*` directories removed.

Evidence retained in this directory: `mysql-host-curriculum-review.log` (full
stdout). The run used a temporary Bash/Python harness and extracted case JSON;
these diagnostic files were removed after review. The versioned repeatable
shipping-runtime acceptance target is
`integration_test/sql_curriculum_native_test.dart`, with all six cases loaded
directly from the current packaged assets.

## Results — PASS

```
VERSION=8.0.46-0ubuntu0.24.04.4
COMMENT=(Ubuntu)
SKIP_NETWORKING=1
MYSQLX_PORT='<disabled>'
TCP_PORT=0

sql-example-121: EXAMPLE 'a|3' + EXERCISE '1'
sql-example-122: EXAMPLE '1|Alice@example.com|5' + EXERCISE '6|2'   (UTF-8 LENGTH/CHAR_LENGTH)
sql-example-123: EXAMPLE '1|2026-01-02|4' + EXERCISE '4'
sql-example-124: EXAMPLE 'REPEATABLE-READ' + EXERCISE 'REPEATABLE-READ'
sql-example-125: EXAMPLE 'north|book,pen\nsouth|bag' + EXERCISE 'pen,book,bag'
sql-example-126: EXAMPLE '1|x|\n2|y|p\n3||q' + EXERCISE '1'

mysql examples passed: 6/6
mysql exercise answers passed: 6/6
all authored MySQL expectations matched execution
```

Every authored MySQL expectation — the 6 lesson outputs and the 6 exercise
outputs — matched real execution. Notable confirmations:
- `ON DUPLICATE KEY UPDATE` upsert produced `a|3` (accumulate, not overwrite).
- `CONCAT`/`CHAR_LENGTH` and `LENGTH('你好')=6` / `CHAR_LENGTH('你好')=2`
  under utf8mb4.
- `DATE_ADD`/`DATEDIFF` date arithmetic.
- `@@transaction_isolation = REPEATABLE-READ`.
- Deterministic `GROUP_CONCAT(... ORDER BY ... SEPARATOR ',')`.
- `LEFT JOIN ∪ RIGHT JOIN` emulation of FULL OUTER JOIN with correct NULL
  rendering in the empty cells (`1|x|`, `3||q`).

## Explicit limitation (does not replace device acceptance)

**This Linux MySQL 8.0.46 host result does NOT substitute for Android/OHOS
`8.4.6` device acceptance.** Differences that remain:

- The shipping mobile runtime bundles **Oracle MySQL 8.4.6** (Android `.so` via
  `jniLibs`, OHOS `libqfli_mysql_server.so`); this run is desktop Linux **8.0.46**
  from the Ubuntu package, a different major-line build.
- This validates only the **SQL semantics and asset expectations** of the 6
  lessons, not the app's private-server lifecycle, FFI/NAPI transport, packaging,
  or schema isolation on a real device.
- Device acceptance remains `integration_test/sql_curriculum_native_test.dart`
  (requires a real Android/OHOS app, asserts `VERSION() == 8.4.6`,
  `@@skip_networking == 1`, and per-run schema isolation). It was **not** run
  here — Android is still occupied and device operations were out of scope.

## Safety / cleanup

- No system MySQL service started, stopped, or reconfigured.
- No user datadir, no other workspace, and no shared core touched.
- Only the run's own `mysqld` process and its `/tmp/qfli-mysql-review.*` root were
  used; the process exited and the owned temp directories were removed
  (`ls /tmp/qfli-mysql-review.*` → none remain), verified after the run.
