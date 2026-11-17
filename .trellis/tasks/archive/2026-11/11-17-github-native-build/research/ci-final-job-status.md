# Research: Native build outcomes for runs 3 and 4

- Query: Report completed target builds and successful artifact links alongside main-branch merge.
- Scope: external execution evidence, internal workflow contract
- Date: 2026-11-17 10:18 CST

## Findings

The GitHub REST jobs and artifact endpoints report all four requested native
targets successful across two runs. Run 3 as a whole failed because its first
iOS attempt failed. Run 4 retried iOS successfully and skipped OHOS/Android.

| Run | Commit | Job | Conclusion |
| --- | --- | --- | --- |
| 43937691966 | 5a83aea2ac85230f870d00b06ace2f34e10f8635 | OHOS arm64 | success |
| 43937691966 | 5a83aea2ac85230f870d00b06ace2f34e10f8635 | Android arm64-v8a | success |
| 43937691966 | 5a83aea2ac85230f870d00b06ace2f34e10f8635 | Android x86_64 | success |
| 43937691966 | 5a83aea2ac85230f870d00b06ace2f34e10f8635 | iOS SQLite | failure, superseded by run 4 |
| 43942332046 | 08a3b41695bdf7d3085b6159850a82dfbf64e3a6 | iOS SQLite | success |
| 43942332046 | 08a3b41695bdf7d3085b6159850a82dfbf64e3a6 | OHOS and Android | skipped |

Source-input jobs succeeded in both runs.

## Successful Runtime Artifacts

| Artifact | Bytes | Download page | Expiry (CST) |
| --- | ---: | --- | --- |
| native-ohos-arm64 | 48,668,593 | https://github.com/azurekiln2333/qflistudio-sql/actions/runs/43937691966/artifacts/14263878450 | 2026-12-01 04:05:24 |
| native-android-arm64-v8a | 32,407,113 | https://github.com/azurekiln2333/qflistudio-sql/actions/runs/43937691966/artifacts/14263552429 | 2026-12-01 03:56:24 |
| native-android-x86_64 | 32,652,998 | https://github.com/azurekiln2333/qflistudio-sql/actions/runs/43937691966/artifacts/14263699238 | 2026-12-01 04:04:38 |
| native-ios-sqlite | 4,701,371 | https://github.com/azurekiln2333/qflistudio-sql/actions/runs/43942332046/artifacts/14265598166 | 2026-12-01 04:15:26 |

API artifact digests:

- OHOS: `sha256:1f78023c51866b193d323e98b86270ddda91037a0719e4fdbd04783297f643ee`
- Android arm64: `sha256:eededcc8538f1dbb73e75eccf2c2d553660514926a7524cc6df311a541d5acfc`
- Android x86_64: `sha256:629ab1bfa4b430f8cbec168ecb2ca3cc54555685a4bda4009b738b7ef134512a`
- iOS SQLite: `sha256:6e18e43cdf07ed01fc8a66c43eac9e6dc1aa2668d37fafe40987dc819edcdc6e`

## Files Found / Code Patterns

- `build/native-ci-observer.py`: ignored GitHub API observation helper. Read-only queries use the existing credential helper.
- `.github/workflows/native-build.yml:121`: Android runtime artifact upload.
- `.github/workflows/native-build.yml:243`: OHOS runtime artifact upload.
- `.github/workflows/native-build.yml:273`: iOS runtime artifact upload.
- `ci-run-3-monitor.md`: earlier queue and iOS-failure evidence, preserved unchanged.

## External References

- https://github.com/azurekiln2333/qflistudio-sql/actions/runs/43937691966
- https://github.com/azurekiln2333/qflistudio-sql/actions/runs/43942332046
- GitHub REST jobs and artifacts endpoints under each run, queried at the date above.

## Related Specs

- `.trellis/spec/backend/native-ci.md`

## Caveats / Not Found

This follow-up checked GitHub job conclusions and artifact existence only. It did
not download the archives or independently validate their internal hashes, ELF
dependencies or XCFramework contents. These are native libraries and runtime
packages, not APK/HAP/IPA applications. A successful cross-build does not establish
device execution. The two successful runs use different source commits.
