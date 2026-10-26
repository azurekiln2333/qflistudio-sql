# Research: Independent unsigned HAP file-delivery review

- Query: May the existing unsigned HAP receive separate file-delivery acceptance without rewriting its failed build-wrapper or original inspector result?
- Scope: internal; independent Python standard-library reads only.
- Date: 2026-10-26

## Findings

Verdict: **PASS_WITH_EXPLICIT_PROVENANCE_LIMITS**, for copying this exact unsigned artifact only. This verdict does not promote the original build or frozen inspector to PASS.

Artifact: `ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`, 345,947,746 bytes. SHA-256: `6b5e615086c8c5d38b5433cebb3165327e8866f7eadc495c388abf54089b16bf`.

Independent evidence is recorded in `14u-unsigned-artifact-independent-review-20261026.json` beside this note. Its input report SHA-256 values bind the reviewed root metadata, asset, and final ELF reports. The final ELF report SHA-256 was checked again after root's owner-final notice and remains `480108c7106cb1134ca02ecda50344d87cafb65b6617a01f57105db37ba6fa93`.

### Asset coverage and independent recomputation

I independently enumerated the current authored product asset tree, current authored core asset tree, and authoritative MySQL package rawfile tree. I did not execute or import the asset auditor. I compared each source file's bytes directly with the corresponding ZIP member and checked the reported source/archive inventory against this independently generated mapping.

All 90 comparisons are byte-exact: 3 product assets, 14 core assets, and 73 MySQL package resources. The MySQL runtime manifest lists 70 unique resources; all are covered. The extra three are runtime.json and the Oracle/OpenSSL license files. No product/core/MySQL extra or missing packaged assets were found. The ZIP name inventory has no duplicates. Thus there is no unreviewed tail beyond the 70 runtime entries and no skipped catalog/product/core asset family within these current source trees.

I also recomputed all 485 paths in the root current-source snapshot. All 485 still match that inspection snapshot. The HAP hash, size and mtime remained unchanged across my checks. These observations bind the current read-only inspection window; they do not establish missing prebuild provenance.

### Metadata recomputation

The actual HAP module.json identifies com.azurekiln.qfli.sqlab, versionCode 1000000, versionName 1.0.0, release/debug=false, phone entry module, and EntryAbility. Its app object matches the root metadata report and the identity/version match current AppScope source. The permission-name list is exactly INTERNET and READ_PASTEBOARD, without duplicates or additional permissions.

### ELF methodology and independent recomputation

I reviewed elf-independent.py and separately implemented an ELF64 little-endian parser rather than importing that auditor. I independently read all eight packaged ARM64 images and their reported reference sources: qfli_mysql, server, private server, launcher, SQL bridge, AOT app, Flutter engine and libc++ runtime. Reference and packaged hashes match the report.

For every image I checked all program-header table bytes, all PT_LOAD segment metadata, all normalized PT_LOAD bytes, the ELF header after permitted normalization, all allocated section names/metadata/content hashes and GNU build-id. All eight passed. Dynamic-section/string-table content is allocated and remains byte-exact. The owner's report also explicitly parses and compares DT_NEEDED/SONAME/search paths. Its SDK dependency inventory is a source-presence check, not a phone-loader proof.

The only ELF-header normalization is e_shoff bytes40..47, e_shnum bytes60..61 and e_shstrndx bytes62..63. No program-header permission or loadable bytes are ignored. Allocated section sh_name offsets may change as a consequence of nonallocated .shstrtab rewriting; decoded names and the allocated metadata/content remain identical. Those offset changes are explicitly listed. This is narrower than dropping section metadata indiscriminately.

The nonallocated transformation check permits only removed .comment/.symtab/.strtab and an explicit debug-section list, plus a changed .shstrtab. Unknown added/removed sections fail. In particular there is no blanket permission to remove an unknown .permission section. No disallowed transformation was observed in any of the eight images. This correspondence does not establish the identity or version of the strip tool.

### Original results preserved

The original final.json retains wrapper status BUILD_INPUT_DRIFT_OR_INSPECTION_FAILED with artifactAccepted=false and wrapper exit1. post-original-artifact-inspection.json remains FAILED because libqfli_mysql.so does not match the original raw-byte comparison. The supplementary ELF evidence explains that byte difference through constrained stripping correspondence; it does not change the original predicate or edit the failed record.

Relevant files: build/ohos-14u-20261026/diagnosis-readonly/{root-metadata-source-snapshot.json,asset-report.json,asset-audit.py,elf-independent-report.json,elf-independent.py}; build/ohos-14u-20261026/{final.json,post-original-artifact-inspection.json,frozen.json}. Relevant specs: .trellis/spec/backend/ohos-audit-packaging.md and mysql-ohos-runtime.md.

## Caveats / Not Found

- Core authored assets were not frozen before the build. Exact current-source equality cannot recover that prebuild provenance. The four expected generated-copy changes remain documented drift, not a repaired original freeze.
- libc++_shared.so matches the current selected SDK file, which was not frozen as an original build input.
- libqfli_sql.so and libapp.so match current CMake/AOT outputs. This proves correspondence to those outputs, not reproducible source-to-binary semantics.
- Build-id agreement and constrained strip correspondence are not cryptographic source provenance or proof of a particular strip tool.
- Unsigned file delivery does not establish signing, installability, device loader availability, MySQL startup, cross-app TCP, background survival or installed execution.
- No SDK/native/LLVM/Node/WSL/build/retry/HDC operation was performed for this review. All output writes stayed under the active task research directory, as required by the researcher role. Root may copy these review receipts into diagnosis-readonly if desired.

## Root acceptance proposal review

The independent review also read artifact-acceptance-proposal.json after its publication. Both proposed HAP paths independently hash to the stated exact artifact. All three report bindings match the reports reviewed here. Its proposed separate unsigned file-only scope, immutable original failures, provenance limits and fresh named transfer-grant requirement are accepted. This is conditional artifact disposition, not a host/device grant. The ELF allocated-section claim denotes contents and decoded metadata, with the explicitly listed sh_name offset changes; raw section-header byte equality is not asserted.
