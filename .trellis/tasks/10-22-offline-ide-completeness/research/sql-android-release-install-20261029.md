# Android release build and installation — 2026-10-29

The third attempt produced a fresh ARM64 release APK.
The wrapper returned exit 0.
Independent APK inspection passed.
ADB installed and launched the exact delivered APK on the selected device.

## Artifact

- File: `build/sql-android-release-20261029-03/delivery/QFLISQLab-1.0.0-1000000-android-arm64-release.apk`.
- Size: 46,614,367 bytes.
- SHA256: `592bc38ac642c39156958ee155dd935b74d130dbe5e2423bb21eeb5116469f90`.
- Checksum: the adjacent `.apk.sha256` file.
- Application ID: `com.azurekiln.qfli.sqlab`.
- Version: 1.0.0 / 1000000.

The delivery copy was hashed separately after copying the actual build output.
Android release uses the project's existing development/debug signing configuration.
This signing choice is distinct from Flutter release compilation and the application's debug flag.

## Build

```text
flutter build apk --release --target-platform android-arm64 --target lib/main.dart --pub --no-android-gradle-daemon --extra-gen-snapshot-options=--old_gen_heap_size=512 --build-number 1000000 --dart-define=QFLI_DIAG_TABBAR=false --dart-define=QFLI_PERF=false
```

The child environment limited Gradle heap to 768 MiB and Gradle workers to one.
Kotlin compilation ran in process.
The exact bundled snapshot generator documents the old-generation heap limit in MB.
The application debug banner was already disabled in source.
No foreign JVM was stopped.

## Attempts and corrections

1. Attempt one failed with `zone.cc:96: Out of memory` during AOT generation.
   The generator exited `-1073740791` and the wrapper exited 1.
2. Attempt two passed AOT after memory became available and the snapshot heap was bounded.
   Java compilation failed because the stale generated registrant referenced the excluded development plugin `integration_test`.
3. Attempt three enabled the normal Flutter pub/tooling path.
   Flutter regenerated release plugin registration and the build returned exit 0.

The SDK's `regeneratePlatformSpecificToolingIfApplicable` returns early when `--no-pub` is set.
The standard release generator filters development dependencies before writing Android registration.
A standalone pub-get command generates non-release tooling and would not establish this correction alone.
No SDK source or generated Java registration was patched manually.
Both prior failed attempts and their consumed runners remain preserved.

## Source provenance and process custody

The third runner froze 305 current inputs.
The post-build input comparison matched all 305 files.
Generated Java registration is recorded as generated output rather than authored source authority.
The build includes existing working-tree changes and is not presented as a clean-HEAD build.
The four staged Android MySQL libraries and their resource package were reused from the existing October 2 staging.
This build does not establish correspondence between those historical native binaries and current native source.
No MySQL native rebuild occurred.

The parent observed original tool `9c79a6`, session `52851`, terminate with exit 0 through observation `7e1695`.
The build record reports terminal, Job activeProcesses 0, and closed process/Job handles.
The runner restored `android/local.properties` after confirming the owned Job was empty.
Elapsed build time was 60.367 seconds within the 1200-second budget.

## APK inspection and installation

Independent inspection passed package identity, version, ARM64-only native ABI, and `debuggable=false` checks.
The signature verified against the existing development certificate.
All four staged MySQL libraries matched the packaged bytes directly.
All seven packaged native images passed ARM64 ELF checks.
The independent inspection bound 266 selected inputs and compared 19 asset files directly.
This inspection set is separate from the build wrapper's 305-input snapshot.

ADB targeted `192.168.68.236:39643`, serial `d361e7a0`, model `OPD2413`.
The remote staging file's hash matched the local APK.
`pm install -r` returned `Success` and preserved application data.
No uninstall or data-clear command was used.
The installed package reported versionCode `1000000`.
The installed base APK hash also matched `592bc38ac642c39156958ee155dd935b74d130dbe5e2423bb21eeb5116469f90`.
`am start -W` reported `Status: ok`, a cold launch, and `TotalTime: 917` milliseconds.
Application PID `24718` remained present after the three-second observation.
The scoped AndroidRuntime error log contained no fatal exception during that observation.
The temporary remote staging file was removed.
The complete ADB wrapper returned exit 0.

These results establish package installation and a short launch smoke check.
They do not establish complete feature behavior, MySQL execution, or long-running stability.

## Local evidence

- `build/sql-android-release-20261029-03/final.json`.
- `build/sql-android-release-20261029-03/frozen.json`.
- `build/sql-android-release-20261029-03/registry-diagnosis.json`.
- `build/sql-android-release-20261029-03/delivery-receipt.json`.
- `build/sql-android-release-20261029/independent-inspection.json`.
- `build/sql-android-release-20261029-03/adb-install-receipt.json`.
- Exact ADB step logs are adjacent to the installation receipt.
- The first and second attempt directories retain their original build logs and final receipts.
