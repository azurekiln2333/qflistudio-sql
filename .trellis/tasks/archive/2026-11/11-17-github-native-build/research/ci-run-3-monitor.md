# Research: GitHub native run 3 monitoring

- Query: Observe the actual remote build outcomes while the license change proceeds.
- Scope: mixed
- Date: 2026-11-17 (Asia/Shanghai)
- Run: https://github.com/azurekiln2333/qflistudio-sql/actions/runs/43937691966
- Source commit: 5a83aea2ac85230f870d00b06ace2f34e10f8635

## Files Found

- `.github/workflows/native-build.yml`: native build jobs and artifact contracts.
- `build/native-ci-observer.py`: ignored credential-safe GitHub API observation helper.
- `.trellis/spec/backend/native-ci.md`: target, artifact and evidence constraints.
- `tool/ci/build-ios-sqlite.sh`: iOS slice compilation and lipo verification.
- `research/ci-run-3-ios.log` in this task: ignored local download of the completed
  iOS job log. The remote job is 133546525273 in the linked run.

## Code Patterns

- `.github/workflows/native-build.yml:53`: Android allows up to 360 minutes.
- `.github/workflows/native-build.yml:129`: OHOS allows up to 360 minutes.
- `.github/workflows/native-build.yml:248`: iOS requires a macOS 15 runner.
- `.github/workflows/native-build.yml:249`: iOS has a 45-minute execution limit.
- `.github/workflows/native-build.yml:116`: artifacts are retained for 14 days.

## Findings

At 03:26 CST, the authenticated GitHub jobs endpoint reported:

| Job ID | Target | Observed result |
| --- | --- | --- |
| 133546524864 | OHOS arm64 | Build OHOS Oracle and SQLite in progress |
| 133546525295 | Android x86_64 | Build Oracle and SQLite in progress |
| 133546525343 | Android arm64-v8a | Build Oracle and SQLite in progress |
| 133546525273 | iOS SQLite | Queued; no steps have started |
| 133546525377 | Corresponding source inputs | Success |

At 03:28 CST, target job states were unchanged. The artifact endpoint listed only
`native-source-inputs`, ID `14261791796`, size `543634118` bytes, SHA256
`0b9a6c88d82130eb888352fe650f4b2bf5abbcddd3741a04bfbce8895c7c8b33`.
Its API expiry is `2026-11-30T19:17:51Z` (2026-12-01 03:17:51 CST).
Download page:
https://github.com/azurekiln2333/qflistudio-sql/actions/runs/43937691966/artifacts/14261791796

### iOS failure at 03:31 CST

The iOS runner started at `2026-11-16T19:30:36Z` and completed with failure at
`2026-11-16T19:31:08Z`. Its `macos-15` label resolved to a working hosted runner
with Xcode 16.4. GitHub annotations report macOS arm64 capacity constraints,
which explain the prior queue delay but are not the build failure.

SQLite device compilation reached static-library verification. At raw log line
142, lipo rejected the input archive path as an architecture name. The invocation
at `tool/ci/build-ios-sqlite.sh:42` places its input after the variable-length
architecture list:

```bash
"$LIPO" -verify_arch "$arch" "$dir/libqfli_sqlite.a"
```

The emitted usage is `lipo <input_file> <command> [<options> ...]`. The narrow fix
is to put the input first:

```bash
"$LIPO" "$dir/libqfli_sqlite.a" -verify_arch "$arch"
"$LIPO" "$OUTPUT/build/iphonesimulator/libqfli_sqlite.a" -verify_arch arm64 x86_64
```

The second command fixes the same issue at script line 59 before it becomes the
next failure. The `gethostuuid()` warning is not fatal. The failed run uploaded
only its iOS log artifact, ID `14260988507`, not an XCFramework runtime artifact.

At the 03:31 snapshot, OHOS and both Android targets were still compiling.

## External References

- GitHub REST jobs endpoint: `/repos/azurekiln2333/qflistudio-sql/actions/runs/43937691966/jobs`.
- GitHub Actions run linked above is the source of current execution state.

## Related Specs

- `.trellis/spec/backend/native-ci.md`
- `.trellis/spec/backend/mysql-ohos-runtime.md`
- `.trellis/spec/backend/mysql-android-runtime.md`
- `.trellis/spec/backend/sqlite-native-runtime.md`

## Caveats / Not Found

No successful runtime artifact is established by these snapshots. A source upload
is not proof of native compilation. iOS requires a corrected rerun; no remaining
XCFramework phases were verified after its first lipo failure. Device execution
remains outside the build result.
