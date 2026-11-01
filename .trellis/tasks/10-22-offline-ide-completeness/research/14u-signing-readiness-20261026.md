# Research: 14u OHOS signing and delivery readiness

- Query: Build the current OHOS SQL application and deliver the HAP to 14u at 192.168.68.207:46551.
- Scope: internal, read-only source/file-existence inspection. No SDK, signer, build, device, ADB or HDC command executed.
- Date: 2026-10-26

## Findings

### Current delivery authority

The parent first relayed global Python924 as ADB delivery, then explicitly corrected that direction: Python933 WITHDREW the ADB claim after the user rejected ADB for this OHOS target. Fresh Rust/Note reports identify the connected target as MRT-AL10/aarch64/API26. HDC is the current delivery protocol. The research did not perform discovery, connection, push or remote verification. Root owns fresh discovery and exact target selection.

`D:/ProgramFiles/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe` exists. The parent owns its invocation. `D:/ProgramFiles/platform-tools/adb.exe` also exists but is not the tool for this OHOS delivery and must not be invoked merely because Python924 had proposed it.

Current delivery shape, only after root verifies the exact fresh target, is:

```powershell
& 'D:/ProgramFiles/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/hdc.exe' -t '192.168.68.207:46551' file send '<absolute-new-HAP>' '/data/local/tmp/<new-HAP-name>'
```

The destination shown follows the historical non-installing OHOS transfer. Root must retain the current explicit delivery scope and verify target/path before sending. Do not uninstall or clear installed application data. A copied unsigned HAP is a file-delivery result and does not establish installability or execution.

### Signing material: configured SQL identity is absent

`ohos/AppScope/app.json5:3` declares `com.azurekiln.qfli.sqlab`.
`ohos/build-profile.json5:22`, `:25`, and `:27` reference this common stem beneath `C:/Users/lichengyu/.ohos/config/`:

`default_ohos_atLNRYMqojeWBzAE5Xsd0aBTQux6Ptm1YtuqBYW5IQg=`

All three configured paths are absent:

- `.cer`: absent.
- `.p7b`: absent.
- `.p12`: absent.

`ohos/build-profile.json5:35` explicitly selects `signingConfig: default`; therefore a build can reach a real signing failure rather than merely skip a missing product selector. Its leading comments claim valid SQL-bound generated material, but the current path-existence facts contradict that claim.

The eight current `.p7b` files in `.ohos/config` contain these embedded bundle-name strings: `com.azurekiln.qfli.java`, `com.azurekiln.qfli.script`, `com.azurekiln.qfli.dartwing`, `com.azurekiln.qflistudio`, `com.azurekiln.qfli.go`, `com.azurekiln.cloudterminal`, `com.azurekiln.qfli.note`, and `com.azurekiln.qfli.cpp`. No embedded `com.azurekiln.qfli.sqlab` was found. This was byte-level JSON-field inspection only; none of those profiles was cryptographically verified. Do not reuse them, change the SQL bundle, or generate a replacement identity as part of this delivery.

No password values or private-key contents are stored in this research file.

### Exact installed tools and normal build command

These files exist:

- Flutter: `D:/ProgramFiles/flutter_ohos/bin/flutter.bat`.
- DevEco Java: `D:/ProgramFiles/Huawei/DevEco Studio/jbr/bin/java.exe`.
- DevEco bundled Node: `D:/ProgramFiles/Huawei/DevEco Studio/tools/node/node.exe`.
- General Node: `D:/ProgramFiles/nodejs/node.exe`.
- OHPM: `D:/ProgramFiles/Huawei/DevEco Studio/tools/ohpm/bin/ohpm.bat`.
- Hvigor: `D:/ProgramFiles/Huawei/DevEco Studio/tools/hvigor/bin/hvigorw.bat`.
- Signer JAR: `D:/ProgramFiles/Huawei/DevEco Studio/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar`.
- Native compiler: `D:/ProgramFiles/Huawei/DevEco Studio/sdk/default/openharmony/native/llvm/bin/clang++.exe`.

The persistent Flutter `ohos-sdk` selector is `D:/ProgramFiles/Huawei/DevEco Studio/sdk`, matching the installed DevEco SDK root. No selector was changed.

The historically used normal application command, with the current explicit SDK path, is:

```powershell
& 'D:/ProgramFiles/flutter_ohos/bin/flutter.bat' build hap --release --target-platform ohos-arm64 --no-pub
```

Expected unsigned output path: `ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`. A signing failure is still a nonzero build result; if its new unsigned HAP is complete and verified, root may report successful unsigned artifact creation/delivery separately from failed signing. Do not call the overall signed build successful. Do not reuse an old output merely because that path exists.

### Critical native freshness issue

`ohos/entry/build-profile.json5:5-9` selects `../../native/CMakeLists.txt` and lists arm64-v8a/x86_64. In `native/CMakeLists.txt:40-54`, a real OHOS ABI selects prebuilt libraries under `build/mysql-port/package/libs/<ABI>` and checks their existence. The `add_library(qfli_mysql ... qfli_mysql_napi.cpp)` branch at `native/CMakeLists.txt:57-65` runs only for the fallback ABI branch.

Consequently a normal arm64 Flutter HAP build alone does not rebuild the changed MySQL NAPI bridge. The current sharing feature needs its new exports in the real prebuilt `libqfli_mysql.so`; rebuilding/staging that bridge is required before claiming that the new HAP contains working sharing controls. The build worker must verify the packaged library against the rebuilt input and new export strings, rather than package historical native images.

`native/tests/rebuild-ohos-package.sh:4-12` records the historical WSL build root `/root/qfli-mysql-port/ohos-build`, serial `cmake --build . --target qfli_mysql -j1`, server and launcher targets, followed by `native/mysql/package-runtime.cmake`. This script is evidence of prior commands, not permission to execute every server rebuild; a narrowly scoped current bridge rebuild and correct package staging should be selected by the build implementer.

### Historical result and references

`.trellis/tasks/10-15-sql-release-readiness/research/ohos-push-14u.md` records an October 15 unsigned release HAP and HDC transfer to `/data/local/tmp`, plus `9568320 no signature file` on attempted installation. That result is historical; current HDC delivery still requires fresh target selection and a newly built artifact. Python933 has withdrawn the intervening ADB direction.

`tool/ohos/sign_audit_hap.ps1` signs an independent audit bundle with public SDK test identity. It is not a production sqlab signer and is not an appropriate substitute for the missing normal-app identity.

Relevant specs: `.trellis/spec/backend/ohos-audit-packaging.md`, `.trellis/spec/backend/mysql-ohos-runtime.md`; relevant toolchain notes: `research/native-toolchain-pinning-20261024.md`. The latter documents that `--no-pub` does not suppress Flutter OHOS TS-builder npm/OHPM setup, and that Node/npm/Hvigor/Java selections and SDK persistent selectors need explicit binding.

## Caveats / Not Found

- Current SQL-bound cert/profile/store are absent. No current signed normal-app artifact is established.
- Embedded profile bundle strings were read, not verified with a signer.
- No SDK/build/sign/device/runtime action occurred in this research.
- This researcher has established no target reachability, file transfer, size/hash match, installation or launch. HDC delivery belongs to root; the withdrawn ADB direction must not be used.
- New output freshness, actual native-library rebuilding, and final archive contents remain the build/check workers' responsibility.
