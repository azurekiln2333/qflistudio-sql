# Parent Design — SQL Curriculum and Home

Child tasks own their own `design.md`. This parent records the cross-child
integration design and ownership split.

## 1. Integration Boundaries

```
qfli_sql (Flutter app, all writes happen HERE)
  lib/main.dart (sqlProfile)
  lib/sql_app.dart
  lib/sql_workbench_page.dart      ← C1 (UI home tree + entry actions)
  lib/sql_projects_page.dart       ← C1 (projects page)
  lib/sql_content_repository.dart  ← C2 (SqlContentRepository)
  assets/content/sql_tutorials.json  ← C2 (data)
  assets/content/sql_examples.json   ← C2 (data)
  tool/sql_curriculum/**             ← C2 (authoring/validation)
  test/sql_curriculum_test.dart      ← C2

../qfli_studio_core (READ-ONLY reference)
  lib/content/content_repository.dart   (ContentRepository, ContentCatalog)
  lib/pages/local_content_pages.dart    (tabs already take a `repository:`)
  lib/widgets/code_snippet.dart         (copy + import)
```

- **Hard constraint**: no file outside `qfli_sql` may be written. No edits to
  `../qfli_studio_core/**` at all (other-language workers edit it in parallel).
- C1 changes the SQL app UI layer only.
- C2 adds local assets, `SqlContentRepository`, `tool/`, and a test, and owns the
  `pubspec.yaml` asset registration.
- Interface handshake: C1 constructs `SqlContentRepository()` and injects it via
  the existing `repository:` parameter of `LocalTutorialsTab` / `ExampleCodeTab`.
  The shared tabs need no change; any would-be shared edit is forbidden and must
  be handled locally instead.

## 2. Cross-Layer Data Flow

1. `AssetContentRepository.load()` reads `packages/qfli_studio_core/assets/content/*.json`.
2. `ContentCatalog.fromJson` parses into typed `TutorialContent` / `ExampleContent`.
3. `ContentFilter.forProduct('sqlab')` restricts to `type == "sql"`.
4. `LocalContentAdapter` maps to page models (one tutorial entry → one chapter,
   one lesson).
5. `LocalTutorialsTab` / `ExampleCodeTab` render; details use `CodeSnippet` for
   copy + editor/project import.
6. C1 hosts these tabs behind home entry actions.

For the SQL app the repository is swapped: C2's `SqlContentRepository` loads the
local `assets/content/sql_*.json` and performs the same `ContentCatalog.fromJson`
+ `ContentFilter` steps 2–3. Steps 4–5 are unchanged shared code. Step 6 is C1
only.

## 3. Ownership Matrix

| Path | C1 | C2 | Notes |
| --- | --- | --- | --- |
| `lib/main.dart` | – | – | Frozen this iteration |
| `lib/sql_workbench_page.dart` | ✅ (layered on dirty state) | 🚫 | UI home |
| `lib/sql_projects_page.dart` (new) | ✅ | 🚫 | Projects page |
| `lib/sql_content_repository.dart` (new) | 🚫 (consume) | ✅ | C2 owns |
| `lib/*.dart` repositories/runner | 🚫 | 🚫 | Consume only |
| `assets/content/sql_tutorials.json`, `sql_examples.json` (new) | 🚫 | ✅ | Data |
| `tool/sql_curriculum/**` (new) | 🚫 | ✅ | Tooling |
| `test/sql_curriculum_test.dart` (new) | 🚫 | ✅ | Tests |
| `pubspec.yaml` (assets list only) | 🚫 | ✅ | C2 registers assets |
| `../qfli_studio_core/**` | 🚫 | 🚫 | **Read-only, no writes** |

## 4. Compatibility and Risk

- Preserve all pre-existing dirty files in `qfli_sql`; write nothing outside it.
- No dependency changes; Python tooling uses system Python; execution validation
  uses the already-present `sqlite3` CLI and the repo's local MySQL test
  facilities.
- The local assets are new, so there is no risk of corrupting other-language
  content.

## 5. Rollback

Each child is independently revertible: C1 reverts UI files; C2 reverts the two
assets (scoped) plus its new tool/test files. Parent is planning-only and needs
no code rollback.

## 6. Final Integration Review (parent)

After both children report done, the parent verifies:
- Home is the tree; projects on its own page; tutorials/examples reachable.
- The `sql` catalog is real (counts, uniqueness, execution report).
- No ownership violations or shared-interface changes landed without escalation.
- Existing tests still pass and the dirty baseline is preserved.
