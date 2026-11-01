# Isolated native source checkpoint573 — 2026-10-24

The capsule and hashes below preserve checkpoint573. The later explicit DevEco
builder/fixture candidate is documented in `native-toolchain-pinning-20261024.md`;
it changes three tool files without overwriting this capsule. A future candidate
must bind the final reviewed tooling and actual passed/formatted SQL sources.
This checkpoint remains source-only and does not establish current tool/runtime
acceptance.

The last goal turn made concrete progress: explicit DEFER567 reconciled the
consumed old263/264 handoff, and request570 froze the current four-file SQL
consumer gate. This turn reread the complete attachment and inspected current
source/queue. Latest raw read through572 still has no new SQL grant. No host
reservation or SDK/test/build/native process is retained.

## Product/tool corrections

- `build_audit_hap.ps1` accepts explicit `-Flutter`, resolves it against caller
  CWD before changing directories, clears/checks the native exit code, and
  records `flutter` plus `flutterSha256` in build.json. Default executable is
  the actual compatible `D:/ProgramFiles/flutter_ohos/bin/flutter.bat`.
- New `test_build_audit_hap.py` runs the actual wrapper in a private fixture
  with a relative failing batch executable and a different caller CWD. It must
  reach the invocation marker/build failure, preserve exact metadata bytes,
  release the lock and emit no unsigned HAP/build record. Its JSON-subset parser
  is a local control; no real SDK is invoked by the fixture.
- The existing early-metadata cleanup regression now supplies an inert explicit
  executable and proves it reached metadata reading/lock acquisition. A missing
  default SDK cannot make the cleanup regression falsely pass.
- The inspector binds all five actual current audit sources in the debug kernel;
  six new pure methods cover control/newlines/stale or missing helper/path/body.
  Clipboard-only, full126/372, native ELF/strip/signature and entry/buildId checks
  remain required. See `audit-source-binding-refresh.md`.

Independent source review fixed the relative-path and early-cleanup fixture
issues. Final production/tool SHA256 values:

| File | SHA256 |
| --- | --- |
| build_audit_hap.ps1 | a622239a34638126f7bf1518a7ae5074278f29fd984ff8ed5edec925d0723f84 |
| test_build_audit_hap.py | 38a1d6d8943e8b0a1a7e82ff967c6c4f1e01b4109cebbb58cb36564ab186e0b9 |
| inspect_audit_hap.py | d8193ab0f65a4310ea28fc630cbc40a08f1267e3872a0778b7c35be0b36511af |
| test_inspect_audit_hap.py | 0530ae60cd5f63a635ef82cb9694062b643c23bec179f71d5fb65e61cb4eef59 |

PowerShell parsing, Python AST/compile-only and scoped whitespace checks PASS.
Actual regression methods, native typing, HAP build/sign/inspection and device
execution remain UNRUN. No commit or push of these new changes has occurred.

## Created source capsule

File/Git-only preparation completed in3.391s, tool chunk5723b2 / exit0:

- Directory: `D:/MyNewProjects/qfli_sql_hap_src_20261024_1610`.
- Explicit status: `SOURCE_CAPSULE_ONLY_ENVIRONMENT_AND_RUNTIME_UNVERIFIED`.
- SQL base commit55c7252d8daeb79bba9dc9b4efa68c01e19b9801;
  tree3bc89381c772298cbbf42184f546d518518e0797,468Git blobs verified.
- Archive SHA256 e2f822a48bec483036dc874a8d3ef75a4955122b858efe46bbdb756ba7447141.
- All68 frozen SQL source/config/native files match the isolated consumer
  review, including the four UNRUN current integration/test files. The current
  four tool files above are separately overlaid.
- Both configured MySQL ABI sets and all resources copied:82 regular files,
  340,518,821bytes. All copies verify hashes; x64 four-library staging size/hash
  identities and both ABI ELF headers pass. This is input provenance, not native
  execution or renewed ELF symbol/SDK closure acceptance.
- Core2f9039a3 remains immutable, with288 captured source/config hashes and
  archive61f4975a. Capsule source report SHA256
  832c1b558a239e2feee75648312884f95a9c4c8de2e8db9de83f91f41d38c64a.
- Plugin metadata paths are rebased from the actual capsule package config;
  metadata SHA25639be13c3b015f5cdcfa1d5d3135703ce0f5e69fadd0a6356c2cab2bb40e7f324.
  No stale live/e025 core binding is inherited into that bootstrap file.

The helper is ignored
`build/offline-ide-check/workspace/prepare-hap-source-capsule.py`. It only uses a
new owned sibling destination, verifies the Git archive against every blob,
rejects private signing containers before archive creation, and rejects linked
native inputs. Main metadata, signing material, baseline WIP and historical HAPs
were not changed by preparation. It performs no SDK/build/sign/device operation.

## Remaining gates and environment

- Three-case request570 remains READY/UNRUN, with original focused wrapper
  ec8b29f9 and launch03db04f2 unchanged. Old263/264 and527 remain consumed/deferred.
- A separate full-host supervisor/template is source-prepared and independently
  reviewed. It requires real focused three-case PASS, its unchanged
  after-snapshot and root-observed outer-tool terminal/final-release receipt
  before full analysis, full serial suite, both original content validators and
  current Python regressions. AST inventory currently totals35 methods. Its
  template refuses execution until those actual prerequisites and current
  tooling/source hashes are filled. This is not a new runtime pass or grant.
- After formatting, future focused/full evidence must bind the exact source
  used by the native capsule. Refresh a new capsule if formatted source hashes
  change; do not call this preformat capsule tested.
- Npm/OHPM locks and local-properties files are setup inputs. No `.cxx`, `.hvigor`,
  build/module caches, entry/libs or generated Flutter assets were copied.
  Rebase/regenerate dependency setup in a separate named bounded build window.
  Pin SDK Node/npm/OHPM/Hvigor/Java as well as Flutter: `--no-pub` does not prevent
  the SDK TS builder from running npm/OHPM. All descendants need the owned Job.
- Signing requires an explicitly verified assigned UDID. Old unavailable device
  identifiers are not reused. Device122 remains separate/unavailable/deferred
  to Python124 then Rust128; no install/lifecycle/data/daemon action occurred.
- Historical signed0c5007b4/unsigned64df2478 plus four metadata records remain
  preserved under main's pre-native-offline history. Do not promote a failed
  capsule candidate or claim audit-entrypoint packaging proves normal SQL UI.

Original OHOS126/372, normal UI/process restart/offline behavior,180draft promotion,
expanded306/912 and all sibling/umbrella requirements remain open. Goal is active.

## Full-host supervisor review completed

Independent review fixed missing final checks for the isolated collector/assets,
failed pending-publication propagation, numeric-prefix validator count matching,
and strict terminal-receipt integer fields. Nested Flutter collector tests inherit
the already hash-verified Python interpreter. The current source inventory is35
Python methods (1transaction +21collector +13package/source guards); runtime
discovery must match the reviewed inventory with zero skips. The full Flutter
gate requires at least275 passing visible cases, all three focused cases, and
only the two named unavailable-Oracle skips, or zero skips when configured.

Full supervisor SHA256:
`5476622e388a5bf2aa6d8d2df02f71609dacd876c596b786094ee07688fcefb5`.
Refusing launch template SHA256:
`409311774979d8563bcf143351168b0c042e968a1086ecc629bdb61fd3fa7807`.
Both are ignored files under `build/offline-ide-check/workspace`. AST/compile-only,
JSON/hash binding and scoped whitespace checks pass. These supersede the first
authored full-supervisor hashes. No actual gate/controls/SDK process ran; focused
request570 and the original four-file hashes remain unchanged. Channel573 records
the source-only checkpoint without accepting or expanding any host grant.
