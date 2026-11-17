# Run 3 native artifact verification

Verified on 2026-11-17 (Asia/Shanghai). All three native artifacts below pass
download integrity, package inventory, architecture and dependency checks.
This record covers OHOS and Android. The main session verifies iOS separately.

## Source and remote outcomes

- Run: https://github.com/azurekiln2333/qflistudio-sql/actions/runs/43937691966
- Exact source: `5a83aea2ac85230f870d00b06ace2f34e10f8635`.
- The authenticated GitHub artifact API reports that exact source and run for
  every downloaded package. Each inner manifest matches both values.
- Job `133546524864` (OHOS), `133546525343` (Android arm64), and `133546525295`
  (Android x86_64) completed successfully. Run 3 also contains a failed iOS job.
  the overall run status does not invalidate these three successful jobs.

| Artifact | ID | Download bytes | Package files | Result |
| --- | --- | ---: | ---: | --- |
| native-ohos-arm64 | 14263878450 | 48,668,593 | 83 | Pass |
| native-android-arm64-v8a | 14263552429 | 32,407,113 | 86 | Pass |
| native-android-x86_64 | 14263699238 | 32,652,998 | 86 | Pass |

Package counts include the manifest and inner checksum file. Download pages:

- https://github.com/azurekiln2333/qflistudio-sql/actions/runs/43937691966/artifacts/14263878450
- https://github.com/azurekiln2333/qflistudio-sql/actions/runs/43937691966/artifacts/14263552429
- https://github.com/azurekiln2333/qflistudio-sql/actions/runs/43937691966/artifacts/14263699238

API expiry times are 2026-11-30 20:05:24Z, 19:56:24Z and 20:04:38Z respectively.
These correspond to 2026-12-01 04:05:24, 03:56:24 and 04:04:38 in Asia/Shanghai.

## Integrity and provenance

Verified each downloaded ZIP against its GitHub API SHA256 digest and byte count.
Verified the outer SHA256SUMS against the tar stream. Verified every regular
file against both the inner SHA256SUMS and manifest. The exact file sets match.
there are no unchecked extra files or archive links.

| Target | ZIP SHA256 |
| --- | --- |
| OHOS arm64 | `1f78023c51866b193d323e98b86270ddda91037a0719e4fdbd04783297f643ee` |
| Android arm64-v8a | `eededcc8538f1dbb73e75eccf2c2d553660514926a7524cc6df311a541d5acfc` |
| Android x86_64 | `629ab1bfa4b430f8cbec168ecb2ca3cc54555685a4bda4009b738b7ef134512a` |

All manifests record MySQL 8.4.6, OpenSSL 3.5.3 and SQLite 3.50.0.
CI_PROVENANCE.txt records Clang 18.1.3 and CMake 3.31.6. Source hashes match
the pinned scripts: MySQL `a1e523dc8be96d18a5ade106998661285ca01b6f5b46c08b2654110e40df2fb7`
and OpenSSL `c9489d2abcf943cdc8329a57092331c598a402938054dc3a22218aea8a8ec3bf`.
OHOS metadata records API23/SDK6.1.0.31 and SDK archive SHA256
`b833b75a64ee46bbd7880921abbb49b733ec5c8171b6684c9b524d57f624cee0`.
Android records API28 and NDK27.0.12077973.

## Native checks

OHOS contains five ELF64 AArch64 files under libs/arm64-v8a: the Oracle client
NAPI, server, launcher, private server image and SQLite NAPI. All 70 resource
paths declared by rawfile/mysql/runtime.json exist. Oracle and OpenSSL notices
are present. SQLite exports register_qfli_sql_module and qfli_sql_version.

Executed the current audit_ohos_native.sh embedded dependency checker against
every extracted library using the local OHOS SDK readelf. All dependencies are
allowed platform libraries or packaged libraries. The private image depends
on exactly libc.so. SQLite depends on libc.so, libace_napi.z.so and
libhilog_ndk.z.so. Other Oracle libraries require the app's compatible
libc++_shared.so, as documented by the packaging contract.

Each Android package contains mysqld, the launcher, libqfli_mysql_bridge.so and
libc++_shared.so under mysql/, plus the separate ABI-specific libqfli_sqlite.so.
Resources include charsets, English errors, ICU data and upstream license notices.
Read-only validation applies the production stage.ps1 requirements: required
paths, exact Oracle ELF set, ELF64 little-endian matching ABI, PIE/shared type,
/system/bin/linker64 executable interpreter, allowed dependencies and 16 KiB
LOAD segment alignment/congruence. Every native file passes. Both SQLite
libraries export qfli_sql_execute, qfli_sql_result_free and qfli_sql_version.
their only dependencies are libc.so, libm.so and libdl.so.

The downloaded Android audit logs also confirm the original production stager
ran successfully on GitHub: four native files and 76 resource files per ABI.
Those log ZIPs match their GitHub API digests. Local verification did not run the
stager's output-writing section or overwrite native/build.

## Evidence and limits

- Local raw archives, API metadata, per-target manifests, audit JSON and the
  verification helper are under ignored build/native-ci-runs/3/.
- artifact-verification.json records exact hashes, sizes, ELF dependencies,
  alignment and captured provenance. ohos-current-dependency-audit.txt records
  the output from the current dependency checker.
- Verification streams tar payloads and extracts only ELF files into the new
  verified-elf/ directory. No compiler/source tree was downloaded or built.
  The three ZIPs total 113,728,704 bytes. Extracted ELF files total 359,310,336
  bytes and are disposable verification copies. Existing accepted packages,
  native/build outputs and database backups were untouched.
- These artifacts predate the repository GPL v3 license change. They contain
  upstream notices but no new root LICENSE. Later source commits add that file.
  these exact downloaded archives were not modified to imply otherwise.
- Binary audits and successful hosted compilation establish packaging evidence.
  They do not establish APK/HAP integration, device execution or database
  lifecycle acceptance. No device or application acceptance was attempted here.
