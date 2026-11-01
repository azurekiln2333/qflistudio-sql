# Explicit unsigned x64 static inspection

Date: 2026-10-26. Status: source implementation and authored tests only.
The inspector and tests were not imported or executed. No SDK, build,
signing, controller, formatter, analyzer or device command ran for this change.

## Behavior gap and ownership

The builder already publishes sql-audit-unsigned.hap and build.json with
signed:false and unsignedSha256. The inspector previously selected only
sql-audit-signed.hap, required signed:true, and always invoked SDK signature
verification. An unsigned build could not enter the existing static gate.

This change touches only tool/ohos/inspect_audit_hap.py,
tool/ohos/test_inspect_audit_hap.py and this note. Existing five-source kernel
bindings, offline-permission checks and all other working-tree changes remain
intact. Their presence in a Git diff against HEAD is not new ownership here.
The builder, signing helper, product code, shared core and sibling apps remain
outside this change.

## Selection and report contract

- Default inspection still selects the signed HAP and requires signed:true.
  It still binds both archive hashes, compares every unsigned ZIP payload,
  invokes verify-app and verify-profile, and validates the authenticated
  profile identity, input equality, privilege, device scope and validity.
- Explicit --unsigned selects only sql-audit-unsigned.hap. It requires the
  boolean signed:false, deviceExecuted:false and the matching unsigned hash.
  A present signedSha256 or signingIdentity field is contradictory, including
  a null field, and causes rejection before native-tool execution.
- A stale signed sibling is neither selected nor read by unsigned inspection.
  It cannot supply a missing unsigned HAP or satisfy the unsigned hash check.
  Its presence alone does not invalidate a new unsigned build, because the
  existing builder can leave historical signed output in the directory.
- Unsigned archives containing .pages.info are rejected. This is supported
  by the historical actual-archive finding in audit-package-review.md:
  signing added that SDK code-sign entry to the unsigned ZIP. This rule does
  not claim cryptographic detection of every possible signature format.
- Both modes use the same manifest, permissions, catalog-byte comparison,
  catalog reconciliation, five current audit-source bindings, build-ID,
  Oracle resource inventory, ELF/ABI, staging hash/size, SDK strip transform,
  dependency, private-export and strong-symbol closure checks.
- Unsigned mode returns after those shared checks. It does not read the
  signing JAR, Java executable or audit-profile.json. Its signature report
  records verified:false and performed:false. It emits no trust or device
  success and retains entryExecutionVerified:false and deviceExecuted:false.
- Reports identify inspectionMode as signed or unsigned. The unsigned default
  is build/ohos-audit/inspection-unsigned.json, preserving the signed default
  build/ohos-audit/inspection.json. Explicit --report still selects a caller
  path. Callers must avoid deliberately pointing both modes at one report.
- Defaults remain 126 examples and 372 scripts. The build architecture must
  remain ohos-x64. Existing inspection of any packaged ARM64 native images
  does not establish an ARM64 Flutter artifact or phone acceptance.

## Authored regressions: UNRUN

Eight new test methods exercise the actual inspect() or CLI main() branches.
Fixtures contain ZIP payloads, current original-catalog JSON, five source
inputs, a build record, Oracle resources, ELF headers and staging identities.
Only subprocess dispatch is stubbed with inert tool responses and byte-copy
strip output. The successful unsigned fixture resolves one strong import
through its declared libc dependency with the real symbol-closure code.

Coverage includes successful unsigned inspection without a signing JAR or
profile, stale signed siblings, contradictory booleans/signing/device fields,
unsigned hash mismatch and absence without signed fallback, catalog/source/
resource/permission/native/architecture failures, code-sign metadata rejection,
default signed refusal of unsigned metadata, signed hash/payload/entry binding,
mandatory app/profile verification, original CLI denominators and separate
default report paths. Negative cases cover TEXTREL and an unresolved strong
import. CLI failures enter the real inspector, return exit1 and write error
reports to caller paths without replacing the default success reports.
Existing test methods remain present.

These fixtures cannot establish real SDK behavior or native acceptance. In
particular, inert strip responses do not prove the installed SDK transform,
and inert signature responses do not prove cryptographic verification.

## Source-only checks and identities

- ast.parse accepted both Python files. This parsed source without importing
  either target module and did not execute a test definition.
- AST inspection counted 21 test methods in test_inspect_audit_hap.py,
  including the eight new methods. All 21 remain UNRUN for this change.
- JSON reads confirmed 126 current examples and 372 derived scripts.
- git diff --check passed for both Python files before this note was added.
  Git reported its existing LF-to-CRLF conversion warnings.
- Raw working-file SHA256 for inspect_audit_hap.py:
  6d820169a4b37dfa7dde260232e2d48e381e3dd945dd2a80fb50cf2839bb4003.
- Raw working-file SHA256 for test_inspect_audit_hap.py:
  2c8e7a8545226039d1b232b1379d343763fa15d9490762c49779f1df688b1458.

## Independent source review

The dispatched trellis-check reviewer traced artifact selection, metadata
guards, the shared checks, the unsigned return and the signed verification
path. Initial review found no scoped behavior defect. Follow-up review
identified missing negative cases and expanded the existing fixture methods.
The reviewer confirmed both current raw Python hashes above with independent
SHA256 reads. Production inspector bytes remain unchanged by review.

The historical audit-package-review.md records the observed .pages.info
addition after signing. The current signed branch already requires that
entry. The new unsigned rejection matches that observed package format.
Its absence does not prove cryptographic signature absence or device trust.

Independent AST inspection found 21 test definitions: six source-binding,
four catalog/archive/ELF, two permission, eight inspection-mode and one
build-cleanup method. Seven inspection-mode methods enter the real inspector.
The CLI method stubs inspection for success-default argument/report subcases
and enters the real inspector for failure subcases. The successful
unsigned fixture removes the signing JAR and leaves no signing profile.
It also leaves an invalid stale signed sibling to verify selection isolation.

Both Python AST parses, current catalog data reads and scoped
git diff --check passed. No target module was imported. Lint, type-check,
all 21 tests, SDK tools and package/device execution remain UNRUN.
No staging, commit or publication occurred during this review.

## Follow-up regression coverage review

All additions remain inside existing inspection-mode methods. The fixture
tool responses now allow per-library dynamic tables and symbol tables.
The unsigned success case declares a libc dependency and resolves one strong
SDK symbol through it. Its report must show one strong import and no unresolved
symbols. This avoids an exclusively empty symbol-closure success fixture.

The unsigned native-guard method now supplies TEXTREL and an undefined strong
symbol in separate valid-package subcases. Each requires its exact guard
error and no Java call. Signed ZIP subcases add an entry, remove pack.info and
remove .pages.info. Each refreshes the signed hash before inspection, so the
entry-set guard must reject the package rather than the outer hash guard.
No signing call may follow these failures.

CLI failure subcases invoke actual main/inspect paths for signed-mode unsigned
metadata and unsigned-mode hash mismatch. Each requires exit1, FAIL status,
the exact error, correct mode, deviceExecuted:false and matching printed
failure output. Separate nested caller destinations must contain the reports.
Both default success reports must retain their exact bytes. Early metadata/hash
failure must produce no tool calls. The test definition inventory remains21.
AST parses and scoped whitespace checks pass. All regressions remain UNRUN.

## Remaining gates

Independent source review is complete. Fresh authorized execution must
run the authored fixtures and existing regressions before claiming tested
behavior. Current-source x64 build and unsigned inspection remain UNRUN.
Signed package verification, device trust, installed catalog execution,
current workspace/full-product checks and umbrella acceptance remain open.
Historical package reports are not fresh evidence for this source revision.
The tool/test edits invalidate previous frozen tool identities and test-count
bindings. Refresh those bindings during separately authorized preparation.
This note does not request, consume or replay any runtime grant.
