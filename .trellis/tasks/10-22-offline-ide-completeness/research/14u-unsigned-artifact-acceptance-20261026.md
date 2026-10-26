# SQL 14u unsigned artifact acceptance recommendation

Recommendation: **accept this exact unsigned archive for file delivery only**, with the provenance limits below. C must issue its own artifact disposition and a fresh named HDC file-only grant. This report grants no device or heavy-resource window.

The independent reviewer returned **PASS_WITH_EXPLICIT_PROVENANCE_LIMITS**. The reviewer separately reimplemented resource enumeration and ELF parsing, rather than importing either audit helper. It recomputed all 90 resource pairs, all eight ARM64 images, all 485 current snapshot paths and both HAP copies.

## Exact artifact

- Canonical transfer source: `D:/MyNewProjects/qfli_sql/build/ohos/hap/entry-default-unsigned.hap`.
- Entry output contains the same bytes: `ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`.
- Size: **345,947,746 bytes**.
- SHA-256: `6b5e615086c8c5d38b5433cebb3165327e8866f7eadc495c388abf54089b16bf`.
- Production identity: `com.azurekiln.qfli.sqlab`, release, debug=false, versionCode=1000000, versionName=1.0.0.
- Permissions: exactly INTERNET and READ_PASTEBOARD. EntryAbility, phone module and clipboard usage scope match current authored metadata.

## Direct resource correspondence

| Authoritative source | Exact pairs | Coverage |
| --- | ---: | --- |
| Product assets | 3 | Icon and both SQL catalogs |
| Core assets | 14 | All authored content/tutorials, four fonts and font license |
| MySQL package resources | 73 | All 70 runtime entries, runtime.json and both licenses |

The audit compares package members directly with authored product/core files and `build/mysql-port/package/rawfile/mysql`. Generated copies are not source authority. No missing, additional or duplicate resources were found. Source inventories and hashes stayed stable during inspection.

## Constrained ELF correspondence

All eight ARM64 images passed independent comparison. Complete program-header table bytes, GNU Build IDs, allocated-section contents and decoded metadata, and dynamic dependency metadata match their reported references. The reports bind original, merged, stripped and package files by hash. All stripped intermediates equal their package members.

Only the ELF64 header fields `e_shoff` (bytes40..47), `e_shnum` (bytes60..61) and `e_shstrndx` (bytes62..63) may be normalized. Every PT_LOAD byte then matches. No program-header permissions or arbitrary code/data bytes are ignored. Allocated-section `sh_name` offsets can move within the rewritten nonallocated name table; decoded names remain exact. The report does not claim raw section-header equality.

Observed nonallocated changes are explicitly enumerated per image: removal of comment/debug/static-symbol metadata and name-table rewriting. Unknown section removal or addition fails, including an unknown permission section. This is evidence for this artifact, not a blanket raw-hash exception. The Flutter engine exactly matches its frozen release HAR. The dependency inventory finds packaged libc++ and 22 selected-SDK platform libraries; it does not prove phone-loader availability.

## Preserved failures and provenance limits

Original SQL1017 wrapper **FAIL1**, four generated asset differences, and `artifactAccepted=false` remain unchanged. Its inspector phase was UNRUN. The subsequent frozen inspector remains **FAILED** on the native raw-byte comparison. This separate recommendation does not recolor either result. C accepted resource release in global1032.

The original freeze omitted all 14 core asset source files. Current package/source equality cannot reconstruct their prebuild history. Current libc++ was not individually frozen before build. SQL bridge and AOT comparisons reach current compiler outputs, not reproducible builds or source-semantics proof. Byte relationships do not establish the specific strip executable identity.

Signature verification, installation, device loading, symbol-version binding, API availability, lifecycle behavior and cross-application MySQL access remain unverified. No SDK, native, LLVM, Node, WSL, build, retry or HDC operation occurred in this diagnosis. Frozen scripts and original receipts were not modified.

`artifact-acceptance-final.json` binds the reviewed proposal and independent review receipts by SHA-256. Detailed per-file and per-image evidence remains in the asset, ELF and current-source snapshot reports. A future transfer must rehash the exact archive under its fresh named grant and label it unsigned.
