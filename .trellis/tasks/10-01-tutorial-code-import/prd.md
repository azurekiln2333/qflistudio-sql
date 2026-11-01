# Tutorial and Example Code Import

## Goal

Simplify the tutorial and example outer pages using Material Design 3. Show
code inside detail pages, where users can import it into the editor or a project,
customize the filename, and immediately open the project and imported file.

## Requirements

- Tutorial and example outer lists show titles and concise summaries without code.
- Use the application's existing MD3 theme, list tiles, dialogs, and icon controls.
- Both lesson details and example details offer code copy, editor import, and
  project import next to the code block.
- Editor import creates a real example project and opens the imported file.
- Project import supports existing projects and creating a new project.
- Both import paths support custom filenames and open the destination project
  with the imported file active, even when an older editor session exists.
- Invalid names, existing-file collisions, write failures, and cancelled dialogs
  must not report success or silently overwrite existing user files. Confirmed
  replacement must back up the previous content first.
- Preserve existing navigation, tutorial content, example customization, and all
  unrelated worktree changes in both repositories.

## Acceptance

- [x] Neither outer page renders source code.
- [x] Lesson and example detail code blocks expose both working import commands.
- [x] New and existing projects receive the exact selected code and custom name.
- [x] Successful import opens the correct project and activates the imported file.
- [x] Dialog validation, cancellation, duplicate names, and errors behave correctly.
- [x] MD3 layouts fit narrow and wide viewports without overflowing.
- [x] Focused flow verification and application compilation pass.

Evidence: `check.md` records the 38 passing checks, shared-package analysis,
successful signed HAP build, and verification limits.
