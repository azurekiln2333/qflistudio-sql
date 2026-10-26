# OHOS audit packaging and native provenance

## 1. Scope / trigger

Use this contract when staging real Oracle runtimes or building the separate
SQL curriculum audit application. Native libraries, HAP metadata and signatures
cross the WSL, Windows, Hvigor and application boundaries. A successful package
build does not establish installation, runtime execution or phone acceptance.

## 2. Signatures

```powershell
& tool/ohos/stage_mysql_x64.ps1 -Distribution qfli-java-build -PortRoot /root/qfli-mysql-ohos-x64-1022
& tool/ohos/build_audit_hap.ps1 -Target integration_test/sql_curriculum_ohos_audit.dart -Architecture ohos-x64 -DartDefines @('QFLI_SQL_CURRICULUM_BUILD_ID=<unique-build>')
& tool/ohos/sign_audit_hap.ps1 -DeviceUdid <actual-device-udid>
```

The build wrapper also accepts `-BundleName`, restricted to a separate
`com.azurekiln.qfli.sqlab.<suffix>` bundle, and `-Architecture ohos-arm64`.
The signing wrapper uses the same bundle and verifies its identity against
`build/ohos-audit/build.json` before signing.

## 3. Contracts

- The audited WSL package contains `closure-report.json`, exactly the four
  required `libqfli_mysql{,_server,_launcher,_server_proto}.so` images under
  `package/libs/x86_64`, and the Oracle resource tree. The closure report records
  packaged byte counts, SHA256 identities, ELF dependencies and 70 resources.
- Staging validates every source before copying, then verifies each destination
  against the same size/hash and little-endian ELF64 machine 62 contract.
  It writes only `build/mysql-port/package/libs/x86_64` and its staging record;
  ARM64 and shared resources retain their independent provenance.
- `native/CMakeLists.txt` requires real packages for ARM64 and x86_64. For those
  architectures missing resources or any required image are fatal. The legacy
  unavailable implementation is reserved for other unsupported architectures.
- Hvigor validates machine 183 for ARM64 and 62 for x86_64 before staging all
  four images and the shared resources. A package supporting two native ABIs
  does not imply its Flutter engine supports both: inspect the final archive.
- The build wrapper acquires `build/ohos-audit/.build-lock`, snapshots metadata
  bytes, temporarily removes production signing and changes the bundle, runs
  Flutter, and restores metadata in `finally`. Unexpected concurrent metadata
  edits retain recovery backups and fail instead of overwriting those edits.
  The lock is released even when an early metadata read fails.
- The build record stores target, architecture, bundle, Dart defines, timestamp
  and unsigned SHA256. Signing adds signed SHA256 and the public SDK test identity.
  Neither helper operates the device or claims `deviceExecuted=true`.
- Current audit packages request exactly two permissions:
  `ohos.permission.INTERNET` and `ohos.permission.READ_PASTEBOARD`. The
  inspector sorts the requested names and rejects any other set, including
  extra, missing or duplicate entries. `INTERNET` serves only the explicitly
  requested same-device loopback TCP path to `127.0.0.1:3306` for sibling
  applications. It does not authorize remote, cloud or LAN access. The
  inspector enforces only this permission set and cannot prove that runtime
  traffic stays on loopback. No background service is claimed. Device cross-application acceptance on the
  selected target remains open. The Oracle staging Unix socket alone does not
  justify network permission. A prior HAP inspected before native offline
  enforcement remains historical, even when its catalog/ELF/signature checks
  passed; rebuild and inspect current inputs.
- Test signing uses only the installed public OpenHarmony SDK identity. The
  template's CA-issued `development-certificate` is the app leaf; append exported
  public Application CA/root certificates. The release alias's exported
  self-signed certificate is not a substitute for that leaf. Do not export keys,
  copy another application's identity or alter device trust settings.
- Verify the signed archive with SDK `verify-app`; `-outCertChain` requires a
  `.cer` path. Write the profile as UTF-8 without BOM. Signature success remains
  separate from ordinary installation trust on the actual selected target.
- Hvigor may strip SOs. Bind final library bytes either directly to the audited
  staging hash or to the exact recorded SDK `llvm-strip --strip-all` transform.
  Inspect actual ELF architecture, dependencies and required exports as well.

## 4. Validation and error matrix

| Condition | Required behavior |
| --- | --- |
| Missing/changed closure report, size or hash | Stop staging; never label candidate audited. |
| ELF class/endian/machine differs | Stop before staging the incompatible ABI. |
| Supported ABI lacks one real Oracle image | Fail CMake/Hvigor; do not substitute a stub. |
| Existing build lock | Refuse concurrent metadata mutation. |
| Build failure | Preserve logs and restore exact original metadata. |
| Unexpected concurrent metadata edit | Preserve exact recovery backups; fail for review. |
| Stale generated stub duplicates the real client | Confirm current Ninja ownership, preserve and remove only that obsolete output, then rebuild. |
| Final native bytes differ from both original and recorded strip transform | Fail package provenance. |
| SDK signature verification passes | Record package evidence only; installed execution remains open. |
| Missing device handoff | Continue host work; do not install/start/stop/reset the shared target. |

## 5. Good / base / bad cases

- Good: a complete x64 audit HAP contains the pinned real Oracle graph, exact
  shipped catalog bytes, matching debug bundle/profile and x64 Flutter engine;
  its reviewed hash is the artifact installed in the explicitly assigned window.
- Base: build/signature checks pass while the device is occupied. Keep the
  artifact and report ready; retain the full original catalog denominator.
- Bad: a dual-native-ABI archive with only x64 Flutter is called a phone build,
  a stale stub wins duplicate selection, or a host pass is reported as OHOS.

## 6. Tests required

- Verify actual archive names are unique; inspect manifest bundle/debug fields,
  permissions and every packaged native ABI, including Flutter.
- Compare shipped tutorial/example JSON bytes to current assets and reconcile
  the complete example/exercise inventory. The initial gate is126/372 (SQLite
  120/360, MySQL6/12); derive exercise counts per item instead of assuming two.
- Reproduce native byte transforms using the pinned SDK; verify the private
  Oracle image depends only on `libc.so` and retains the required host entries.
- Verify metadata restoration and lock release on success and failure. Do not
  use a broad clean: `build/mysql-port` contains important native inputs.
- Run the installed catalog audit and retain durable report/events, exact HAP
  identity, actual target/toolchain, all per-script outcomes and owned cleanup.
  Expansion remains gated by the complete original OHOS pass.

## 7. Wrong vs correct

Wrong: add `pickFirst` to hide duplicate `libqfli_mysql.so`, or accept an ELF
because its name looks correct. This can package the old unavailable stub.

Correct: inspect the current Ninja graph and both candidate images, preserve
only the obsolete generated output in build history, rebuild, then bind all
final Oracle images to the audited real package through the exact SDK transform.
