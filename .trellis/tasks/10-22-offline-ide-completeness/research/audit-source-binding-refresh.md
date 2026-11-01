# Current audit-source binding refresh — 2026-10-24

The HAP inspector previously required the current standalone audit entrypoint's
path and full source in the debug kernel. Four support source matches were
recorded separately for an older HAP, so that historical record could not prove
the helpers in a freshly rebuilt package were current.

The inspector now uses a pure `check_audit_sources` check for the exact five
current audit files: the standalone entrypoint and its audit, runtime, store and
support helpers. Each requires both its path marker and complete source after
CRLF-to-LF normalization. Empty/missing inputs, stale helpers, path-only payloads
and source-only payloads fail. `kernel.sources` records every raw current source
SHA256, path match and embedded-source match. The entrypoint and recorded build
ID requirements remain enforced, as do the existing catalog, clipboard-only
permissions, ELF/Oracle provenance and SDK signature checks.

Six pure regression methods cover the complete control, line-ending handling,
each stale support helper, every missing path marker, each path without source,
and missing/empty source inputs. They do not scan a historical HAP or invoke the
SDK. Source/AST/compile-only checks are allowed in this preparation; tests and
fresh HAP inspection remain **UNRUN** until the coordinator obtains the relevant
new named host window. No installed or device execution result is claimed.

Preparation verification: both Python files pass AST parsing and compile-only
checks; the scoped `git diff --check` passes. Runtime regression methods and
fresh HAP inspection remain **UNRUN**. Source SHA256 values:

- Inspector: `d8193ab0f65a4310ea28fc630cbc40a08f1267e3872a0778b7c35be0b36511af`.
- Regression file: `5e4f635e3b4e4726202b7b73a9debf5bfc12e49b6e8e3b0c474edb9159f1e513`.

Independent tool review then corrected the pre-existing early-metadata cleanup
regression: the new explicit Flutter preflight could otherwise let that test
pass without acquiring the build lock when the default SDK was absent. It now
supplies an inert executable and requires the missing-metadata diagnostic,
created output directory and absent lock/build log. This supersedes the test
file hash above with
`0530ae60cd5f63a635ef82cb9694062b643c23bec179f71d5fb65e61cb4eef59`;
the inspector hash is unchanged. Parser/AST/compile-only checks pass. These
actual regression methods remain UNRUN.
