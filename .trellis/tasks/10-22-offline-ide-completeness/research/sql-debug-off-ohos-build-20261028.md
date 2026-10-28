# SQL debug-off OHOS build — 2026-10-28

The second attempt produced a normal signed ARM64 release HAP.
The build, offline package inspection, and SDK signature verification each returned exit 0.
The delivered local copy was independently hashed after copying.

- Artifact: `build/sql-debug-off-ohos-20261028-02/delivery/QFLISQLab-1.0.0-1000000-ohos-arm64-release-signed.hap`
- Size: 349,011,045 bytes.
- SHA256: `afa0c36aa2bb1a73a913ea2f09d1599e7d9974cf34a12c0599b83c8c796774ef`.
- Checksum: the adjacent `.hap.sha256` file.
- Production bundle: `com.azurekiln.qfli.sqlab`.
- Version: 1.0.0 / 1000000.

## Build and verification

```text
flutter build hap --release --target-platform ohos-arm64 --no-pub --no-codesign --target lib/main.dart --build-number 1000000 --dart-define=QFLI_DIAG_TABBAR=false --dart-define=QFLI_PERF=false
```

The existing `default` development/debug signing configuration signed the HAP through Hvigor.
The Flutter/package build mode is release.
The packaged app debug flag is false.
The bundle remains `com.azurekiln.qfli.sqlab`.
Flutter's `--no-codesign` flag did not disable that configured signing task.
No certificate, profile, keystore, password, or signing identity was replaced.

The DEBUG banner was already disabled in source.
The release build explicitly disables the tab-bar diagnostic and performance defines.
Offline inspection passed production identity/version/mode checks, ARM64 library checks with precisely constrained ELF strip correspondence, and direct authored-resource comparisons.
SDK `verify-app` returned exit 0 and its success marker for the new signed HAP.
These checks establish packaging and signature acceptance.
They do not establish device behavior.

## Source provenance and signing correction

The reviewed runner froze 501 current input files, including authored product/core resources, native package files, build configuration, and selected tools.
Generated Flutter/MySQL staging copies were excluded as source authorities.
The post-build source snapshot matched.
The build includes preserved working-tree changes.
it is not presented as a clean-HEAD or reproducible-build result.

The only product edit for the retry changed `products.default.signingConfig` from `releaseKey` to `default`.
This returns that field to its HEAD baseline and selects the already-configured profile associated with `com.azurekiln.qfli.sqlab`.
All other file bytes and existing dirty changes were preserved.
Exact pre-edit bytes are retained in the ignored retry directory.

The first attempt remains FAIL1 with SignHap error `00303074`: its selected `releaseKey` profile associated with `com.azurekiln.qfli.sql`, which did not match the production bundle.
Its newly generated unsigned HAP and passing offline unsigned inspection remain separate evidence.
The successful second attempt does not rewrite the first attempt's result.

## Process custody and release

Parent observed original tool `425137`, session `59747`, terminate with exit 0 through observation `99fa3b`.
Wrapper root PID was 62768.
All retained phase and final-publisher process/Job handles reached terminal + activeProcesses 0 and were closed.
Actual resource release was published globally as sequence 1068.

| Phase | PID | Creation FILETIME | Process HANDLE | Job HANDLE | Exit / active |
| --- | ---: | --- | ---: | ---: | --- |
| hap | 30276 | 134376288682517803 | 404 | 456 | 0 / 0 |
| inspection | 41436 | 134376288900071366 | 456 | 516 | 0 / 0 |
| signature | 74312 | 134376288918341270 | 568 | 492 | 0 / 0 |
| final-publisher | 78432 | 134376288970531499 | 536 | 608 | 0 / 0 |

The parent outer receipt recorded total elapsed time of 35.697 seconds, within the 600-second window.
AppScope metadata was restored after owned jobs reached active 0.
No foreign process was stopped.

## Delivery scope

This receipt covers the local signed HAP copy and checksum.
No HDC transfer, device installation, device runtime test, WSL operation, or native MySQL rebuild occurred in this receipt step.

Evidence: `build/sql-debug-off-ohos-20261028-02/{final.json,inspection.json,signature.log,independent-signed-review.json,outer-terminal-ready.json,original-terminal-proof.json,final-publisher-terminal.json,delivery-receipt.json}`.
The large native inspection report and signing material contents are intentionally not reproduced here.
