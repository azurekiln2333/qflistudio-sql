# Parent Implementation Plan — Coordination

Parent: `.trellis/tasks/10-12-sql-curriculum-and-home`

This parent owns planning, the task map, cross-child acceptance criteria, and the
final integration review. It normally does not implement code itself.

## Checklist

- [ ] 1. Parent PRD/design/implement written and reviewed (this step).
- [ ] 2. Children activated and dispatched:
      - C1 `.trellis/tasks/10-12-sql-home-tree` → `pi-mysql` (UI).
      - C2 `.trellis/tasks/10-12-sql-lesson-curriculum` → curriculum worker.
- [ ] 3. Enforce ownership:
      - All writes stay inside `qfli_sql`; `../qfli_studio_core` is read-only.
      - C2 must not touch `lib/main.dart` / `lib/sql_workbench_page.dart`.
      - C1 must not hard-code lesson content; it injects `SqlContentRepository`.
- [ ] 4. Preserve the pre-existing dirty files; no reset/format/unrelated edits.
- [ ] 5. Collect child `check.md` evidence.
- [ ] 6. Final integration review against cross-child AC1–AC8:
      - AC1/AC2/AC3 via C1 evidence + manual/widget check.
      - AC4/AC5/AC6/AC7 via C2 reports.
      - AC8 via `git status` review.
- [ ] 7. Ordering: C2 content can land independently; verify AC3 end-to-end once
      both are present. If only one child is merged, record which ACs remain
      unverified and keep the parent open.
- [ ] 8. Wrap-up: update spec (home navigation + SQL curriculum conventions) and
      journal after both children are verified.

## Validation Commands

```powershell
cd D:\MyNewProjects\qfli_sql
git status --porcelain            # confirm dirty baseline preserved
flutter analyze
flutter test --no-pub
cd D:\MyNewProjects\qfli_studio_core
flutter analyze
flutter test --no-pub
```

## Risky Points / Rollback

- No shared-package writes are permitted.
- New local assets are schema-checked against the shared parser.
- Rollback is per child; the parent does not revert child work.

## Review Gates

- [x] All cross-child ACs verified (see `check.md`).
- [x] No ownership violations (no writes to `../qfli_studio_core` or unrelated files).
- [x] Dirty baseline preserved.
- [x] Spec/journal updates complete (spec: `frontend/sql-content-repository.md`,
      `frontend/sql-workbench.md`; journal session 2 recorded).
- [x] Peer reviews resolved: content F1–F5; UI U1–U6.
- [x] Final combined check: Python validators green; `flutter analyze` net-pass;
      `flutter test` 65 passed, 2 skipped.
