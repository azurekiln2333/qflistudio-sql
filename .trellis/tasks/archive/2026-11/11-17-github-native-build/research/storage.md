# Storage and GitHub remote inspection

Inspected on 2026-11-17. Read-only inspection only. No deletion, rebuild,
remote modification, WSL configuration change, or VHD compaction occurred.

## Repository storage

Sizes below sum readable file lengths. They are logical bytes, not allocated
disk blocks. Broken/inaccessible Windows links are skipped. Nested rows must
not be added to their parents.

| Path | MiB | Notes |
| --- | ---: | --- |
| `build/` | 10506.2 | 12 inaccessible entries during initial walk |
| `.dart_tool/` | 2478.4 | Almost entirely `flutter_build/` |
| `ohos/entry/build/` | 2243.7 | 329 inaccessible generated/link entries |
| `ohos/build/` | 766.7 | APP bundles and symbol archive |
| `native/build/` | 205.9 | Includes 195.8 MiB Android runtime staging |
| `build/app/` | 2624.2 | Nested Android build output |
| `build/ohos-audit/` | 2647.2 | Nested audit HAP output |
| `build/ohos-audit/history/` | 1854.9 | Nested historical HAP snapshots |
| `build/mysql-port/` | 3291.3 | Mixed source, packages, tests, DB backups |
| `build/mysql-port/mysql-8.4.6/` | 1078.8 | Prepared Oracle source |
| `build/mysql-port/package/` | 323.5 | Required OHOS runtime staging |
| `build/mysql-port/artifacts/` | 512.2 | Historical HAP snapshots |
| `build/mysql-port/prod-cold-backup-20261009/` | 168.2 | Production DB cold backup |
| `build/mysql-port/prod-backup-UNVERIFIED-live-20261009/` | 168.3 | Unverified live DB backup |
| `ohos/entry/libs/` | 343.8 | Staged native libraries |
| `ohos/entry/src/main/resources/rawfile/mysql/` | 4.9 | Staged MySQL resources |

The two untracked files with Base64-like names are 89 and 90 bytes. Their
contents point to old `_m_true.txt` / `_m_false.txt` research markers.
`research/tmp-status.txt` is an old Git status dump. These three files do not
explain the storage footprint.

There are no project GitHub Actions workflows yet. `.github` folders found
under downloaded MySQL dependencies are upstream source content, not project CI.

## Classification for future cleanup

- Rebuildable caches: `.dart_tool/flutter_build/`, Android Gradle/CMake
  intermediates under `build/app/`, and generated Hvigor outputs under
  `ohos/entry/build/` and `ohos/build/`.
- Historical delivery/test evidence: `build/ohos-audit/history/`, old HAP/APK
  copies, `build/mysql-port/artifacts/`, and audit output directories. Retain
  needed evidence outside disposable caches before removing copies.
- Required local packaging inputs: `build/mysql-port/package/`,
  `native/build/mysql-android/`, and OHOS staged libraries/resources. Existing
  app packaging expects these inputs. Removing them before restoring a verified
  remote build artifact will break native packaging.
- Source/toolchain material: MySQL/OpenSSL archives, prepared source trees,
  host generators, OHOS SDK copies, Android NDK, and native compiler builds.
  Reproducible cloud builds may replace local build trees. Source provenance
  and matching packages still need preservation.
- Database material: production backups and any fixture directories containing
  `data/`, `initialized.json`, or credentials. These are data, not compiler
  caches. Broad deletion of `build/` would delete production backups here.

The workspace `.gitignore` excludes many generated paths. Ignore rules prevent
Git tracking; they do not reclaim storage.

## WSL storage outside this repository

The registered `qfli-java-build` distribution is stopped. Its VHD is:

`D:/MyNewProjects/qfli_java/build/wsl/qfli-java-build/ext4.vhdx`

The host file length is 84,817,215,488 bytes (about 79.0 GiB). Last-write time
reported by Windows was 2026-10-28 14:32:53. This is the whole shared Java/native
build distribution. It cannot be attributed entirely to this SQL project.

Attempting read-only `du -h --max-depth=1 /root` failed before Linux started:

`Wsl/Service/CreateInstance/CreateVm/HCS/HCS_E_HYPERV_NOT_INSTALLED`

The message says the current machine cannot start WSL2 because virtualization
support is not enabled. Therefore current `/root/qfli-mysql*` sizes could not be
measured. No attempt was made to enable components, restart Windows, mount the
VHD elsewhere, or alter the distribution.

Historical repository evidence identifies:

- `/root/qfli-mysql-port`: prepared ARM64 Oracle source, host generators, OHOS
  SDK copy, native build, and packaged runtime.
- `/root/qfli-mysql-ohos-x64-1022`: isolated x86_64 Oracle build/package plus
  an earlier failed `ohos-build-incomplete-source` directory.
- `.trellis/tasks/10-22-offline-ide-completeness/research/runtime-audit.md:100`
  recorded 1.2 G prepared source, 1.2 G ARM64 build tree, and 548 M SDK copy in
  the earlier ARM64 tree. These are historical sizes, not current measurements.
- `.trellis/tasks/10-22-offline-ide-completeness/research/x86-build-check.md:40`
  recorded an approximately 149 MiB x86_64 packaged runtime.

The VHD also hosts tools for other work. Keep the distribution and final runtime
packages until reproducibility and restoration are proven. A future cleanup
must measure inside WSL first and separate build intermediates from user data,
SDKs, source patches, and runtime packages.

## GitHub remote verification

`git ls-remote https://github.com/azurekiln2333/qflistudio-sql.git HEAD refs/heads/main refs/heads/master`
returned:

- GitHub `HEAD` and `refs/heads/main`: `7890d283148daebe1a132979317f1eb161d244a0`
- No `refs/heads/master` result.
- Local `HEAD`: `a841bc77ec91834386b605991c06c254ebd775cd`

`origin` fetches from CNB. Its five configured push URLs target CNB, GitHub,
Gitee, GitCode, and GitLab. `push.default` is `simple`; local `main` tracks
`origin/main`. A generic `git push origin` would target all configured push
URLs. A GitHub-only operation must use the explicit GitHub URL or a dedicated
GitHub remote. This inspection did not change remote configuration or refs.
