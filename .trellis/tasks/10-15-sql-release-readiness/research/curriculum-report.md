# SQL Curriculum Content Audit Report

- Task: `.trellis/tasks/10-15-sql-release-readiness` (SQL curriculum integrity)
- Date: 2026-10-15
- Workspace: `D:/MyNewProjects/qfli_sql`
- Report location: `.trellis/tasks/10-15-sql-release-readiness/research/`
- Owner files (exclusive): `assets/content/sql_tutorials.json`,
  `assets/content/sql_examples.json`, `tool/sql_curriculum/**`,
  `lib/sql_content_repository.dart`, `test/sql_curriculum_test.dart`
- Prior evidence reviewed: `.trellis/tasks/10-12-sql-curriculum-and-home`,
  `.trellis/tasks/10-01-tutorial-code-import`,
  `tool/sql_curriculum/lessons/_collab_status-2.md`

## Summary

The existing curriculum is **substantive and complete**. All 126 tutorials / 126
examples were audited item-by-item. No placeholders were found; no regeneration
was required. The existing content is preserved unchanged, and the committed
source (`tool/sql_curriculum/lessons/track_*.py`) renders **exactly** the shipped
assets (verified both byte-identical and structurally-equal to an in-memory
render).

- Tutorials: **126**
- Examples: **126**
- SQLite lessons verified by executing the **Python authoring source**: **120/120**
- SQLite lessons verified by executing the **packaged JSON** (drift guard): **120/120**
- Exercise answers verified from source: **240/240**
- Exercise answers executed from packaged JSON: **240/240**
- MySQL-specific lessons: **6**, cannot be executed on this host (no bundled
  Windows/Linux MySQL server; Android-only runtime artifacts) — recorded as
  NOT EXECUTED, never counted as passing.

## Commands executed

```powershell
python tool\sql_curriculum\coverage.py
python tool\sql_curriculum\validate_content.py     # runs the Python authoring modules
python tool\sql_curriculum\validate_assets.py      # runs the packaged JSON assets
python tool\sql_curriculum\build_content.py
flutter test --no-pub test\sql_curriculum_test.dart
```

Logs (this directory): `curriculum-coverage.txt`,
`curriculum-validation.txt` (source), `curriculum-asset-validation.txt`
(packaged JSON), `curriculum-drift-proof.txt`.

## Results

### `coverage.py` — PASS
```
total lessons: 126
  aggregation: 10   basics: 14   cte: 8   ddl: 12   dml: 8
  functions: 16   indexes: 8   joins: 12   modeling: 4   mysql: 6
  subqueries: 10   transactions: 6   windows: 12
sqlite: 120  mysql: 6
coverage checks passed
```
Every track meets or exceeds its planned minimum; no duplicated `explain`/`code`.
Counts exceed the R4 / AC4 "more than 100" requirement.

### `validate_content.py` (authoring source) — PASS (SQLite) / 6 SKIPPED (MySQL)
```
sqlite examples passed: 120/120
exercise answers passed: 240/240
mysql not executed: 6
all authored expectations matched execution
```

### `validate_assets.py` (packaged JSON — drift guard, NEW) — PASS
The existing validator executes the **Python track modules via `load_lessons()`**,
not the shipped JSON. To close the asset-drift gap called out in review, the new
`tool/sql_curriculum/validate_assets.py` reads
`assets/content/sql_tutorials.json` / `sql_examples.json` directly (exactly what
`SqlContentRepository` loads) and re-executes every lesson and exercise answer:
```
packaged-JSON sqlite examples passed: 120
packaged-JSON exercise answers executed cleanly: 240/240
mysql not executed: 6
all packaged-JSON script executions matched the authored lesson output
```

### Asset ↔ source equality — PASS
Rendering the source in-memory and comparing to the on-disk JSON:
```
tutorials asset == source render: True
examples  asset == source render: True
```
`build_content.py` additionally regenerated both assets byte-identical to the
working tree (no diff). There is **no drift** between `track_*.py` and the assets.

### `flutter test test/sql_curriculum_test.dart` — PASS (8/8)
Asset parses via the shared `ContentCatalog.fromJson`; complete lesson fields;
no placeholder tokens; no duplicated `explain`/`code`; dialect/version visible in
display fields; examples carry runnable DDL; repository load/filter/memoize and
missing-asset error path all pass.

### Per-item structural audit (independent script) — PASS
For all 126 tutorials: non-empty `title`, `summary`, `objective`, `explain`,
`code`, `output`; ≥1 pitfall and ≥1 exercise, each with non-empty
`prompt`/`hint`/`answer`; dialect (`SQLite`/`MySQL`) present in
`summary`/`concepts` display fields; no placeholder tokens
(`TODO`/`FIXME`/`占位符`/`待补充`/`placeholder`).
For all 126 examples: non-empty `code` and `expectedOutput`; every script
contains `CREATE` setup; **every example ends in a query** (SELECT/WITH), i.e. is
a complete runnable/importable script, not a fragment.

## Findings

- **No placeholders / no regeneration needed.** The bundled curriculum already
  satisfies R4/AC4. Content was preserved unchanged.
- Two lessons (`sql-tutorial-025`, `sql-tutorial-039`) have slightly shorter
  `explain` text (86–97 chars) but are complete, factual, dialect-labelled
  sentences — not placeholder/stub content. Left as-is.
- The 6 MySQL lessons (`sql-tutorial-121`…`126`) carry exactly one exercise each
  versus two for SQLite lessons. This is an intentional MySQL-track scope limit;
  content is otherwise complete, with dialect differences and the SQLite
  equivalent explicitly referenced.

## MySQL-only 6 lessons: attempted local execution, still NOT EXECUTED

Attempted as requested, using only local, non-device resources:

- `Get-Command mysql/mysqld`, service scan, and a repo-wide `mysqld*.exe` search
  found **no Windows MySQL server binary**. Windows search found only source
  files under `build/mysql-port/` (e.g. `sql/mysqld.cc`), never a linked binary.
- The host MySQL build (`build/mysql-port/host-build/`) is **incomplete**: its
  `runtime_output_directory/` contains only generators (`comp_err`,
  `gen_lex_hash`, `uca9dump`, …) — no `mysqld`.
- `native/build/mysql-android/assets/mysql-*.zip` are **Android** runtime bundles
  (`share/`, licenses) with the binaries shipped as ARM/x86 **ELF `.so`** in
  `jniLibs/`; they cannot run on Windows.
- The Dart FFI runtime (`lib/local_mysql_runtime.dart` + `lib/mysql_ffi.dart`)
  is present and the Windows bridge builds (`native/build/mysql-client-windows/
  qfli_mysql_bridge.dll`, `qfli_mysql_launcher.exe`), but it requires a staged
  Oracle server bundle (`bin/mysqld.exe`, `share/`, `lib/`). No such bundle
  exists and no pinned Oracle archive
  (`mysql-8.4.6-winx64.zip`, SHA256 `b6c152…d204`) is cached; no `QFLI_MYSQL_*`
  env vars are set.
- `native/mysql/desktop/README.md` confirms a Windows run needs the official
  Oracle ZIP staged via `stage-windows.ps1` plus the pinned MySQL source tree;
  building that server is a heavy, network-dependent operation outside safe
  non-contending scope.

Per task instructions, **no device was touched and no platform build was
hijacked.** The 6 MySQL lessons remain execution-**unverified**. Their authored
outputs (e.g. `a|3` for 121; the three-row union for 126) follow documented
MySQL 8.0 semantics but were not machine-verified here. They are always reported
"requires MySQL" and never counted as passing.

## Change boundary / files touched

- **No source or asset changes** were made to the curriculum; content preserved.
  `build_content.py` rewrote the two assets with identical bytes (no diff).
- New file (owned scope): `tool/sql_curriculum/validate_assets.py`
  (packaged-JSON drift guard requested in review).
- New evidence/report files in this directory only. No shared-core,
  other-language, home-shell, or `pubspec.yaml` files were modified. No user
  database/project data was touched.

## Suggested commit batch (main control to stage serially — do not `git add .`)

Files (all currently untracked, exclusive to this worker):
- `assets/content/sql_tutorials.json`
- `assets/content/sql_examples.json`
- `lib/sql_content_repository.dart`
- `test/sql_curriculum_test.dart`
- `tool/sql_curriculum/**` (incl. new `validate_assets.py`)
- `.trellis/tasks/10-15-sql-release-readiness/research/curriculum-report.md`
  and `curriculum-*.txt` logs

Conventional commit message:
```
test(sql): verify 126-lesson curriculum against packaged assets

Audit the bundled SQL curriculum item-by-item and add a packaged-JSON
validator (tool/sql_curriculum/validate_assets.py) so the shipped assets,
not just the authoring modules, are re-executed. 120 SQLite lessons and
240 exercise answers pass from both the source and the JSON; coverage,
placeholder and dialect checks pass; the source renders byte-identically
to the assets. Record the 6 MySQL-only lessons as unverified: no local
MySQL server binary or staged Oracle bundle is available.
```

## Remaining release blockers (this scope)

- MySQL lessons 121–126 remain execution-unverified until a real MySQL 8.x
  runtime is available (staged Windows Oracle bundle or a device/container).
  Re-run the equivalent of `validate_assets.py` on those six lessons then.
