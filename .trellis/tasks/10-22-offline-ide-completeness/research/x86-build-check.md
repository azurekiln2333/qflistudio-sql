# Isolated real Oracle 8.4.6 x86_64 OHOS build

Date: 2026-10-22. Owner: SQL native worker. Build and ELF closure **PASS**. Device/runtime acceptance **unverified**.

## Isolation and inputs

- WSL distribution: `qfli-java-build`; sole new writable port root: `/root/qfli-mysql-ohos-x64-1022`.
- Copied already-patched Oracle source from `/root/qfli-mysql-port/mysql-8.4.6`; a complete `diff -qr` proved equality before the successful configure.
- Reused `/root/qfli-mysql-port/host-tools` read-only, including Oracle generators and protoc.
- Copied prior ext4 SDK into the new root and supplied the full missing x86_64 compiler/runtime archive directory from installed `/mnt/d/ProgramFiles/Huawei/OpenHarmony/Sdk/23/native/llvm/lib/x86_64-linux-ohos`. Copy contents were compared, including sysroot x86 libraries.
- Built existing local OpenSSL 3.5.3 archive; verified pinned SHA-256 `c9489d2abcf943cdc8329a57092331c598a402938054dc3a22218aea8a8ec3bf`. Static x86_64 OpenSSL and its real OHOS smoke ELF link passed; smoke NEEDED only `libc.so`.
- Clang/Clang++/LLVM18 in WSL; x86_64-linux-ohos target; SDK Clang15 resource headers/libc++ ABI; `-O1 -DNDEBUG`; at most three compiler jobs.
- No writes to original ARM64 tree, existing `native/mysql` scripts, production package staging, signing, device or Git history.

## New task-local scripts

`research/x86-port/` contains `build-x86_64.sh`, `ohos-toolchain-x86_64.cmake`, `ohos-targets-x86_64.cmake`, `package-runtime-x86_64.cmake`, and `audit-runtime.py`.

Targets/package variants derive the existing reviewed production source/link contracts, changing architecture and paths only. They reject build/package paths outside the new owned root. The production source and existing ARM64 scripts remain unchanged. This is an experiment-ready variant, not yet a replacement production build interface.

## Exact commands and results

From PowerShell at `D:/MyNewProjects/qfli_sql`:

```powershell
wsl.exe -d qfli-java-build -- bash /mnt/d/MyNewProjects/qfli_sql/.trellis/tasks/10-22-offline-ide-completeness/research/x86-port/build-x86_64.sh
# Successful build session 71498, CMake PID 5464; terminal exit 0.
# COMPLETE isolated x86_64 port 2026-10-22T17:50:27+08:00
wsl.exe -d qfli-java-build -- python3 /mnt/d/MyNewProjects/qfli_sql/.trellis/tasks/10-22-offline-ide-completeness/research/x86-port/audit-runtime.py
# PASS; actual-ELF audit also writes /root/qfli-mysql-ohos-x64-1022/closure-report.json
wsl.exe -d qfli-java-build -- diff -qr /root/qfli-mysql-port/package/rawfile/mysql /root/qfli-mysql-ohos-x64-1022/package/rawfile/mysql
# PASS, no differences: 70 resource files, actual Oracle 8.4.6 manifest.
```

Detailed build output: `/root/qfli-mysql-ohos-x64-1022/build.log`. Earlier failed source-copy/configure attempts are retained in that log and the old failed build directory `ohos-build-incomplete-source`; the successful clean configure/build is the final run ending status 0. The first default `cp -a` left zero-length copied files, including `zlib.h`; complete re-copy with `--reflink=never --sparse=never`, source comparison, and a fresh build directory fixed the input. The reusable script now enforces that copy/compare procedure and never accepts a partial-copy marker.

## Actual outputs and closure evidence

Unstripped real engine artifacts: `/root/qfli-mysql-ohos-x64-1022/ohos-build/qfli-runtime/lib`.
Stripped isolated package: `/root/qfli-mysql-ohos-x64-1022/package/libs/x86_64` (four libraries; entire package about 149 MiB).

| Artifact | Packaged bytes | Packaged SHA-256 |
| --- | ---: | --- |
| libqfli_mysql.so | 14381264 | 77afd4d90565ff5524aa98dea2bc7d5019e73ef8e5be797b86a5469c8266c511 |
| libqfli_mysql_server.so | 74266624 | 22c7146d77d5df7342c1d4242c9650f2b11dbd78672fd226d60480d5b9b49190 |
| libqfli_mysql_launcher.so | 11728 | d0140f4b6d64192a54d030529b22af86e87d464ec9cb3c599ca5b198e204a1b8 |
| libqfli_mysql_server_proto.so | 61674464 | 77875c38b99b1fdd39f760a1ad3757d47a85eda0fa785217b8b2f3cd7e40c230 |

The auditor inspects real compiled ELF metadata for every built and packaged library, fails unresolved nonplatform NEEDED entries, checks that private server NEEDED is exactly `libc.so`, and rejects external C++/unwind state. Private exports are the seven allowed entries from the existing production map. Actual unstripped symbols prove presence of `mysqld_main(int, char**)`, `ha_innobase::open(...)`, and client `mysql_real_connect`, so this is the real Oracle server/client graph rather than the unavailable stub. Full raw/packaged hashes and NEEDED arrays are in `closure-report.json`.

## Remaining coordinator gates

1. Review the isolated variants/artifacts before any production native CMake or package-staging change.
2. Add an architecture-aware real x86_64 runtime path and preserve ARM64 packaging; current non-ARM64 production branch still builds the unavailable stub.
3. Build a current SQL HAP with the correct x86_64 artifacts and valid SQL signing, then run actual emulator identity/start/CRUD/stop/cleanup and every MySQL curriculum script. No such run was performed by this worker.
4. Keep phone acceptance distinct: x86_64 ELF closure cannot establish arm64 phone behavior, sandbox fork viability, signing trust, or runtime curriculum PASS.

## Coordinator integration update — 2026-10-22

The worker's production-integration TODOs above are now superseded by these
observed results; its original build provenance remains unchanged:

- `tool/ohos/stage_mysql_x64.ps1` copied the exact audited four images to
  `build/mysql-port/package/libs/x86_64` with size/hash/ELF checks before and
  after copying. ARM64 and shared70 resources were preserved.
- Native CMake now requires real ARM64/x86_64 packages. Hvigor stages the
  available ABI directories after validating all required ELF architectures.
- The first integrated package found an obsolete generated x86 client stub.
  Current Ninja no longer referenced that output. The single stale file was
  preserved under `build/ohos-audit/history/stale-x86-stub` and the rebuild
  succeeded. No broad clean or duplicate-library masking was used.
- The complete original-catalog standalone audit built and passed public SDK
  test signature verification. Signed artifact:
  `build/ohos-audit/sql-audit-signed.hap`, SHA256
  `831a868056d0747d8e1718e7ed684c603d15221254b97ae445279b456ba8b02f`.
- Independent inspection reproduced the exact SDK `llvm-strip --strip-all`
  transform for all four x64 Oracle images and matched final HAP bytes. Full
  package review is recorded separately in `audit-package-review.md` when done.
  Flutter is x64-only in this audit HAP even though ARM64 native extras exist.
- The actual initial catalog denominator is126 topics/372 scripts, including
  MySQL6/12. The earlier378 estimate incorrectly assumed two MySQL exercises
  per topic. Runtime coverage already derives the real complete inventory.

Installation trust, actual current OHOS execution and owned runtime cleanup
remain unproven. SQL has not taken the device window; Web/Lua predecessors
retain their coordinated order. This update is build/package evidence only.
