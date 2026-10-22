# SQL shared-core consumer verification

Verified 2026-10-22, final snapshot at 20:33:37 +08:00. Reviewer owns only this report and `test/sql_shared_core_integration_test.dart`. No product/core code, build configuration, device state, Git index or history was modified by this review.

## Result

- `flutter analyze --no-pub test/sql_shared_core_integration_test.dart`: PASS, no issues (includes Dart type checking).
- `flutter test --no-pub test/sql_shared_core_integration_test.dart --reporter expanded`: PASS, **4/4**, no skipped tests, final run 11 seconds.
- Real Windows bundled SQLite **3.50.0**, DLL SHA-256 `12bb8326b9ab400472d4b95596cb343512a10ab2ac6e40620e09df2da2c59f93`. The editor test uses the actual `sqlProfile` analyzer and normal bundled-library resolution; no fake SQL engine or diagnostic response is injected.
- This is host Flutter widget/engine evidence. It does not establish OHOS layout, OHOS execution, MySQL grammar validation or complete umbrella acceptance.

## Exercised behavior

1. Actual `SqlContentRepository` supplies the entire shipped **126 tutorial / 126 example** catalog to the shared pages at **320 logical px, 2.0 text scale**. Each of the 126 lesson titles and each of the 126 example titles is entered through the actual search control. Every matching lazy row has an SQL language badge. SQL chip selection, final lesson/example detail badge, authored source code and filter reset are asserted. Flutter reports no layout exception. This verifies metadata/UI consumption; these tests do not execute curriculum scripts.
2. Actual SQL profile declares the SQL analyzer, offline policy and `.sql` support. The shared adapter returns all 126 SQL examples. Importing an actual catalog example writes its exact source to `src/imported.sql`, preserving the existing `main.sql` and project configuration bytes.
3. Actual shared `EditorPage` obtains its analyzer from `sqlProfile`. Initially valid saved SQL is clean. Editing an unsaved CRLF/emoji buffer to `SELECT '😀';\r\nSELECT 1, FROM;` produces a real SQLite syntax error at the UTF-16 offset of `FROM`; the saved file remains unchanged.
4. The code view selects the SQL grammar. Actual registered highlighter tokenization preserves source and marks SELECT/string tokens. The editor controller's installed span builder produces wavy decorations while retaining existing token color. Opening the actual Problems panel and tapping the SQLite error selects line 2, column 11. Repairing the unsaved buffer clears the waves/problems and reports a completed clean check.
5. Opening another SQL tab with a different owner root and a MySQL marker updates the same editor scheduler to that root, exposes the honest MySQL lexical-only limitation, and attaches its unmatched-quote diagnostic only to the second file. Switching back to the repaired SQLite tab clears foreign diagnostics and completes the SQLite check. Both saved files retain their original source.

## Exact snapshot

SQL HEAD: `42602e37e75dff348ed4d2a453f7c8af009a4fbb` plus the existing task/baseline working tree. Core was initially `daddce27eed1f9389efed0360a0ca954af422da8`; by the final verification it was `96e6833f46a791949cfa58d36e7ba7a25720d18d`. The consumed source blob hashes below were identical before/after the final run, including the concurrently committed editor-controller change. Thus this evidence is for the recorded working-tree code, not a clean checkout of daddce27.

All values in the tables are `git hash-object` SHA-1 blob identities, not commit IDs.

| SQL file | Verified blob |
| --- | --- |
| `lib/main.dart` | `80875a5535230de427dac664c18b4b396b12fb71` |
| `lib/sql_content_repository.dart` | `f6bc8f2790db3b33bace64df5b6f865248a44895` |
| `lib/sql_code_analyzer.dart` | `ac93c6d6b88e0b11c2b0498d6fb21d20b381a029` |
| `lib/sql_syntax_validator.dart` | `aee70e2bd8eb689be6de9cd21b6b0478589fdf94` |
| `lib/sqlite_ffi.dart` | `902d1640348e2a524fb3db24a56681ea455e8129` |
| `lib/sql_engine_preference.dart` | `cd55e564590390619b193f99daf81f3a341f3fa1` |
| `assets/content/sql_tutorials.json` | `93929a988428ea4bb66fce5f9ae2423f8b74c02b` |
| `assets/content/sql_examples.json` | `2d40b923433e4b0dbb6b1138c9a8be5023fa889b` |
| `test/sql_shared_core_integration_test.dart` | `509e195a32c13248db17b824ec6724d0d886c4d1` |

| Shared core file | Verified blob |
| --- | --- |
| `lib/editor/editor_controller.dart` | `a69fe3db6cd73768518a5bd3f64ea2a669cbc511` |
| `lib/editor/editor_page.dart` | `f36228ffe319b58e18bf73d312c381ad17a80218` |
| `lib/editor/editor_analysis_controller.dart` | `49829c4881d84cfe3f5638f3c5ea25bb596a456e` |
| `lib/editor/editor_diagnostics.dart` | `1bf5520b5b22b024747cb18707dcc11b4e5bb21f` |
| `lib/editor/editor_problems_bar.dart` | `58a1e27375c7f568f4e359da71753329e351389a` |
| `lib/editor/highlight_themes.dart` | `64dc1f6f493881d2a97f0e50394358b61ff1c274` |
| `lib/editor/open_file.dart` | `2974aa8e8f13fe488707ec09d5fd6d88477794db` |
| `lib/pages/local_content_pages.dart` | `240c8ad4522453a2057d3d55b5a6964afc9de8c4` |
| `lib/widgets/language_badge.dart` | `d218068b5b41c53108e8498c5ca3b018c2f1287e` |
| `lib/widgets/code_snippet.dart` | `719270624053760fa9aa012484d93313035d503e` |
| `lib/services/code_import_service.dart` | `3ed3119ef4db5b290cff6ebf77f27a0b7b52667f` |
| `lib/services/go_source_file_name.dart` | `c9f8d43af377b18ee553e98654c72d64e6d04330` |
| `lib/content/local_content_adapter.dart` | `4ee9ecd9b6934fcbeaa0d08cd7e40037642898bf` |
| `lib/services/code_analysis.dart` | `d5b924fed71bb6d1eb34e669dd09b86db55c1cf0` |
| `lib/services/studio_profile.dart` | `c953b7eabdffab00c16df918723a9bc72f2cbe66` |

Core remained dirty after the run: `code_import_service.dart`, `code_snippet.dart`, their Go helper/test, `.trellis/spec/frontend/offline-content.md`, and Python content generation/verification files. Other teams retain ownership; none were changed here. The table identifies the production code relevant to these tests; it is not a hash manifest of the entire core repository.

## Open review boundaries

- No product defect was found in the exercised SQL/core paths. New tests fill a SQL-consumer integration evidence gap; they make no claim about unrelated languages.
- The explicit 126 cardinality is the original-catalog gate. After the original OHOS gate permits content promotion, update this test to the reviewed new shipped denominator and rerun it.
- Sidebar expansion/restart persistence is not retested by this scoped file. Existing core-owner workspace tests remain the authority for that behavior. This SQL test covers owner-root switching and diagnostic isolation within an actual editor session.
- Main coordinator still needs full app analysis/tests, native/OHOS gates and owned-diff review. No install, launch, device reset, HAP build/sign, stage, commit or push occurred here.
- Loaded task specs need coordinator synchronization: `sqlite-native-runtime.md` still describes OHOS SQLite scripts as single-query and platform-selected MySQL fallback; `sql-terminal-offline.md` still describes Oracle as the effective OHOS local implementation. Current task code preserves explicit SQLite transport/engine identity. These cross-file contract updates are outside this reviewer's two-file ownership.
