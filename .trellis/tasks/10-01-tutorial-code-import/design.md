# Design

## Ownership

The pages live in the sibling shared package `../qfli_studio_core`, which contains
pre-existing user changes. Prepare edits against exact current snapshots under
`build/tutorial-code-import/`, then apply a scoped patch to the shared package
using an approved filesystem operation. Do not replace its dirty files wholesale.

## Data and Navigation

HomePage passes its existing ProjectStore, AuthStore, and SettingsStore to both
local content tabs. Both detail pages use a shared code block/import workflow.
The filename and project choice dialog owns its controllers and in-flight state.

The editor requires a Project. Direct editor import therefore creates and
registers a snippet project under app storage using the selected code and
filename. Project import allows an existing local project or a new named project.
New example projects replace the default template entry with the selected code;
companion template resources are preserved.

The existing CodeImportService owns filename validation, default names, relative
paths, and collision checks. Existing-file replacement requires an explicit
confirmation and a successful backup before replacement. ProjectStore
creates/registers new example projects only after writing source and metadata.
Failed snippet or new-project imports clean up their newly created directory.
Successful imports mark the project opened and navigate to EditorPage with the
imported absolute path.

EditorPage restores existing tabs and then activates an explicitly supplied
initial file. Navigation without an initial file restores the previous active tab.

## Boundaries

Changes cover local_content_pages, HomePage dependency wiring, the reusable
code/import widget, import service, ProjectStore's existing example operation,
localized command/dialog labels, and EditorPage's initial-file option. The
Oracle process-hosting task remains separate and incomplete.
