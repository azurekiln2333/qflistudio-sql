# Mobile Native CI

## 1. Scope / Trigger
Applies to .github/workflows/native-build.yml and tool/ci orchestration.
Build OHOS arm64, Android arm64-v8a/x86_64 and iOS SQLite on hosted runners.
Do not build desktop engines when official upstream binaries are available.

## 2. Signatures
- bash tool/ci/build_android_native.sh
- bash tool/ci/build-ios-sqlite.sh <fresh-output-directory>
- bash tool/ci/audit_android_native.sh <package> <abi>
- bash tool/ci/audit_ohos_native.sh <package>
- python3 tool/ci/package_native.py package <root> <destination> <target>
- QFLI_BUILD_JOBS defaults to 1 in native scripts; CI sets 2.
- workflow_dispatch input target is all (default), android, ohos or ios.
  Pushes build every platform. Manual runs build the selected platform and
  corresponding source inputs, so retries need not repeat other long builds.

## 3. Contracts
Reuse pinned MySQL8.4.6/OpenSSL3.5.3 archives and existing target patches.
Verify hashes before extraction. OHOS SDK API23/6.1.0.31 for Linux (the local Windows SDK is 6.1.0.32) is checked separately
from mirror archive provenance. Preserve SDK/compiler overrides in CMake
try-compile contexts. Android uses NDK27/API28 and validates 16 KiB ELF loads.
Android package/mysql is the exact Oracle stager input; SQLite stays separate.
OHOS exports libs/arm64-v8a plus rawfile/mysql. iOS exports a static XCFramework
with one device and one universal simulator library. It is SQLite only.
Runtime artifacts contain manifests/checksums and use tar for Unix modes.
New packages include the repository LICENSE unchanged alongside upstream notices.
The manifest and SHA256SUMS cover that license, as they cover other packaged files.
Logs upload on failures; incomplete runtimes never upload as successful packages.

## 4. Validation / Errors
Bad source hash, SDK metadata, ABI, dependency or missing required file fails.
Existing iOS output directory fails without deleting it. Failed tee pipelines
must fail the workflow (explicit bash pipefail). Artifacts expire after 14 days.
Audit every packaged OHOS shared library after adding SQLite NAPI. Each dependency
must be packaged or be an allowed platform library. The private Oracle image must
depend only on libc.so. An earlier Oracle-only export check does not cover SQLite.

## 5. Good / Base / Bad
Good: download verified Oracle native output and stage through production scripts.
Base: compilation and ABI checks pass, device execution remains unverified.
Bad: claim iOS MySQL support from a SQLite XCFramework or delete all build/ data.

## 6. Tests Required
Actionlint, shell syntax, Python compilation, package hash/archive inspection,
real GitHub cross-build results, and production ELF/staging audits. Check iOS
platform triples and XCFramework slices, not architecture alone.
Record each Mach-O slice's actual minimum OS. Xcode 16.4 emits an iOS 14.0
minimum for the arm64 simulator slice even when the requested target is 13.0;
the device arm64 and simulator x86_64 slices retain 13.0. The requested compiler
target alone does not establish the minimum encoded in every object.
Pass the input file before lipo -verify_arch. That option consumes following
arguments as architecture names, so a trailing filename is rejected by Apple lipo.

## 7. Wrong vs Correct
Wrong: push origin when it has multiple mirror push URLs.
Correct: use the explicit intended GitHub URL for a GitHub-only trial.
Wrong: delete build/mysql-port wholesale as a cache.
Correct: preserve runtime packages and production database backups there.
Wrong: lipo -verify_arch arm64 path/to/lib.a.
Correct: lipo path/to/lib.a -verify_arch arm64.
