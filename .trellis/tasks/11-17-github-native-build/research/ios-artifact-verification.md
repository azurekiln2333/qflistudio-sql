# iOS artifact verification

Verified on 2026-11-17 against the downloaded artifact, not only the workflow log.

- Run: https://github.com/azurekiln2333/qflistudio-sql/actions/runs/43942332046
- Successful job: 133562851558, completed 2026-11-16T20:15:38Z.
- Artifact: native-ios-sqlite, ID 14265598166, 4,701,371 bytes.
- Download: https://github.com/azurekiln2333/qflistudio-sql/actions/runs/43942332046/artifacts/14265598166
- Artifact expiry: 2026-11-30T20:15:26Z, or 2026-12-01 04:15:26 Asia/Shanghai.
- Source commit: 08a3b41695bdf7d3085b6159850a82dfbf64e3a6.

## Integrity and contents

The ZIP SHA256 matches the GitHub artifact API digest:
`6e18e43cdf07ed01fc8a66c43eac9e6dc1aa2668d37fafe40987dc819edcdc6e`.

The ZIP contains native-ios-sqlite.tar.gz. Its locally computed SHA256 is
`988a9174b35f7a604739a78f258a1f688b11c9d1dd44bca526d8b61b2021effc`.
The inner SHA256SUMS verifies all 12 payload files and covers the complete
regular-file inventory except itself. No tar links or special files were present.

Contents include the static QfliSqlite.xcframework, bridge and SQLite headers,
SQLite source with its upstream notice, bridge source, root GPL v3 LICENSE,
PROVENANCE.txt, slices.txt and SHA256SUMS.

The packaged LICENSE is byte-identical to LICENSE in commit 08a3b416. Its SHA256
is `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`.
The Windows working copy currently has CRLF line endings; normalizing those to
LF also matches exactly. This is not a license-text difference.

PROVENANCE.txt records the expected source commit, Xcode 16.4 (16F6), Apple
Clang 17.0.0 and iPhoneOS/iPhoneSimulator SDK 18.5. slices.txt matches all three
architectures. Info.plist declares exactly one arm64 iOS device library and one
universal arm64/x86_64 iOS simulator library.

## Binary verification

Local OpenHarmony SDK LLVM tools can inspect these Mach-O static archives.
llvm-readobj --file-headers --macho-version-min verified both sqlite3.o and
qfli_sql_bridge.o in each slice:

| Slice | Architecture | Mach-O platform | Actual minimum OS |
| --- | --- | --- | --- |
| Device | arm64 | ios | 13.0 |
| Simulator | x86_64 | iossimulator | 13.0 |
| Simulator | arm64 | iossimulator | 14.0 |

llvm-nm --arch=all --defined-only --extern-only verified defined symbols
_qfli_sql_execute, _qfli_sql_result_free, _qfli_sql_version and
_sqlite3_libversion in every slice. Plain llvm-nm selects one universal slice
by default, so --arch=all is required for this inspection.

## Evidence and limits

Raw API metadata, archives, extracted package, binary reports and verification
JSON are retained under ignored build/native-ci-runs/4/ios*.

The reported deployment target 13.0 is the requested compiler target. The actual
arm64 simulator objects require 14.0. Consumers must use the per-slice minimum
versions above. No source edits were made during verification.

This proves the downloaded native package's integrity, contents, architecture,
platform and symbol presence. It does not prove application linking or execution
on a device/simulator. This package contains SQLite and the project bridge only;
it does not provide iOS MySQL or an IPA.
