# OHOS audit packaging and native provenance

## 1. Scope / trigger

Use this contract when staging real Oracle runtimes or building the separate
SQL curriculum audit application. Native libraries, HAP metadata and signatures
cross the WSL, Windows, Hvigor and application boundaries. A successful package
build does not establish installation, runtime execution or phone acceptance.

## 2. Signatures

```powershell
& tool/ohos/stage_mysql_x64.ps1 -Distribution qfli-java-build -PortRoot /root/qfli-mysql-ohos-x64-1022
& tool/ohos/build_audit_hap.ps1 -Target integration_test/sql_curriculum_ohos_audit.dart -Architecture ohos-x64 -Flutter 'D:/ProgramFiles/flutter_ohos/bin/flutter.bat' -DevEcoHome 'D:/ProgramFiles/Huawei/DevEco Studio' -DartDefines @('QFLI_SQL_CURRICULUM_BUILD_ID=<unique-build>')
& tool/ohos/sign_audit_hap.ps1 -DeviceUdid <actual-device-udid>
```

Static inspection defaults to the signed artifact. Explicit unsigned inspection
uses `python tool/ohos/inspect_audit_hap.py --unsigned` and defaults to
`build/ohos-audit/inspection-unsigned.json`; the signed default report remains
`build/ohos-audit/inspection.json`. Both modes remain x64 package checks.

The build wrapper also accepts `-BundleName`, restricted to a separate
`com.azurekiln.qfli.sqlab.<suffix>` bundle, and `-Architecture ohos-arm64`.
`-DevEcoHome` selects one installed toolchain; optional `-Json5Module` defaults
to that installation's Hvigor JSON5 package. Resolve `-DevEcoHome`,
`-Json5Module` and `-Flutter` from the caller's directory before changing directories.
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
  and unsigned SHA256, plus resolved `flutter` path and `flutterSha256`. Resolve
  `-Flutter` before changing directories; a relative executable path belongs to
  the caller's directory. Clear/check the native exit code around invocation.
  Signing adds signed SHA256 and the public SDK test identity.
  Neither helper operates the device or claims `deviceExecuted=true`.
- The builder resolves/hashes selected Node, npm wrapper/CLI/prefix, OHPM
  wrapper/CLI, Hvigor wrapper/CLI, Java, SDK package descriptor and JSON5 parser
  inputs before metadata mutation, and rechecks those hashes before publishing
  a successful build. Invoke metadata Node by its literal selected path and
  require an actual zero native exit code. `build.json.toolchain` records
  `devEcoHome`, `sdkRoot`, `json5Module`, `pathPrefix`, `inputs` (name to
  `{path, sha256}`), selected `environment` and `clearedEnvironment`. These are
  launch-input identities; they do not replace final native/SDK graph inspection.
- For builder descendants set `NODE_HOME=<DevEco>/tools/node`,
  `JAVA_HOME=<DevEco>/jbr`, `DEVECO_SDK_HOME=HOS_SDK_HOME=<DevEco>/sdk`, and
  `npm_config_prefix=<DevEco>/tools/node`. Prepend that Node directory,
  `tools/ohpm/bin`, `tools/hvigor/bin`, `jbr/bin` and
  `sdk/default/openharmony/toolchains` to the process PATH. Clear process-local
  OHOS_HOME/OHOS_SDK_HOME. Restore every changed environment value in `finally`
  on success and failure; never change machine/user environment or SDK settings.
- Flutter prefers `%APPDATA%/.flutter_settings`'s `ohos-sdk` over SDK environment.
  An absent settings file is valid; a conflicting selector must fail before
  acquiring the metadata lock. Read only that selector for this decision and
  never print other settings. When APPDATA is absent, check the repository's
  `.flutter_settings`; resolve relative APPDATA and SDK selectors against the
  repository, matching the Flutter child's working directory. Refuse an unbound
  project `ohos/hvigorw.bat`, which
  otherwise overrides the selected Hvigor. SDK root means `<DevEco>/sdk`, whose
  `default/sdk-pkg.json` is discovered by Flutter; `sdk/default` is not equivalent.
- A bounded build should use a fresh isolated source capsule: exact SQL source,
  configs and assets from the successful host checkpoint, immutable exported
  core/re_editor bindings, and hash-checked real native inputs for every ABI in
  `abiFilters`. A killed child cannot strand main's metadata when the build runs
  in that capsule. Preserve main's historical artifacts; failed candidate output
  stays in its capsule until reviewed. Source copying is not a test/build pass.
- A host checkpoint must bind the complete current main Dart path/hash set
  under `lib`, `test` and `integration_test`, not only the focused files.
  Full-launch fields `expectedCurrentMainDartSha256`,
  `expectedMainConfigSha256`, `expectedReviewConfigSha256` and
  `expectedPathRebindings` bind exact file sets/config bytes. Authenticate
  focused `initial.json`, `before.json` and `after.json` through the successful
  focused final evidence; only the four declared formatter inputs may differ
  from preformat main. Keep main preformat bytes until full acceptance.
  Allow only named core/editor path relocations in dependency declarations
  and lock. Resolved package configuration also permits SQL/native checkout
  relocation. Require equal package sets and non-root package metadata.
  Align analysis options byte-exact
  and preserve prior review bytes. New/missing files or postrun drift fail
  acceptance; null prerequisites refuse before execution. The current contract
  and field shapes live in the task research/full-main-source-binding-20261026.md.
- The focused observer separately requires `currentMainBinding` version1 with
  `expectedMainCaptureSha256`, `expectedMainSupplementalSha256` and
  `expectedReviewSupplementalSha256`. Main/review capture inventories must
  match the complete unchanged child capture contract; each side freezes its
  own config bytes. Supplemental maps exactly cover discovered Python tools
  under `tool/sql_curriculum` and `tool/ohos`, both curriculum assets and
  `tool/ohos/build_audit_hap.ps1`, with byte parity on both sides. Missing/null
  schema refuses before ACK. Authenticate initial/before/after snapshots and
  allow only the four declared formatter inputs to change in review. Main
  remains preformat. Config semantic parity additionally requires preparation
  review and the full-gate checks above. Source-only versus tested core status
  must stay explicit. Refreezing does not replace the compiled-in reviewed
  launch/core pins or enable execution; those need a separate reviewed change
  before any fresh named grant. Current field shapes are documented in task
  research/sql-coordinator-current-binding-20261026.md.
- Bootstrap capsule-local plugin paths from the actual package configuration.
  Do not copy stale `.cxx`, `.hvigor`, build output, entry/libs, module caches or
  mutable junctions from another checkout. Npm/OHPM locks may contain relative
  paths that require rebasing or regeneration. `--no-pub` does not suppress the
  SDK TS builder's npm/OHPM setup: pin Flutter, Node/npm, OHPM, Hvigor and Java
  and contain all descendants in the owned bounded build process tree.
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
- Explicit unsigned inspection selects only `sql-audit-unsigned.hap`, requires
  boolean `signed:false` and `deviceExecuted:false`, binds `unsignedSha256`,
  and rejects present `signedSha256`/`signingIdentity` fields. A stale signed
  sibling cannot supply a missing unsigned artifact or satisfy its hash.
  Reject the known SDK code-sign ZIP entry `.pages.info`; its absence is not
  cryptographic proof of unsigned content. Preserve all shared manifest,
  permission, catalog, five-source kernel, resource, ELF, staging/strip and
  symbol-closure checks. Skip Java signature/profile verification only after
  those checks pass. Report `inspectionMode:unsigned` and
  `signature:{verified:false, performed:false}` without device/trust success.
  Signed default inspection still requires signed metadata and all SDK/profile
  verification. An explicit caller report path can override either default;
  separate report paths prevent accidental signed-result replacement.
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
| Explicit Flutter path is relative | Resolve from caller CWD before Push-Location; record that exact executable. |
| Selected DevEco/tool/parser input is absent | Fail preflight before metadata lock or output creation. |
| Persistent ohos-sdk differs, or local Hvigor wrapper overrides selection | Refuse before mutation; do not rewrite settings or invoke another toolchain. |
| Selected launch input changes during a successful child build | Refuse artifact/record publication. |
| Build succeeds or fails after environment selection | Restore all original process environment values as well as metadata. |
| Old module/plugin path or unverified capsule setup | Keep environment UNVERIFIED until bounded setup and exact bindings succeed. |
| One audit helper's path/source is absent or stale | Reject the HAP even when the entrypoint and catalog match. |
| Manifest permissions are not exactly `INTERNET` plus `READ_PASTEBOARD`, or contain extra/duplicate/missing entries | Reject the HAP. The check binds the permission set only; it does not prove loopback-only use. |
| Unexpected concurrent metadata edit | Preserve exact recovery backups; fail for review. |
| Stale generated stub duplicates the real client | Confirm current Ninja ownership, preserve and remove only that obsolete output, then rebuild. |
| Final native bytes differ from both original and recorded strip transform | Fail package provenance. |
| Unsigned mode sees signed metadata, contradictory signing fields, bad/missing unsigned HAP or `.pages.info` | Fail unsigned inspection; never fall back to a signed sibling. |
| Unsigned shared checks pass | Write unsigned static-package PASS with signature verification false; no signing tool/profile or device claim. |
| Signed default receives unsigned metadata | Refuse before signature verification; explicit unsigned mode is required. |
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
- Bad: only NODE_HOME is set while Hvigor executes ambient `node.exe`, or an
  existing persistent `ohos-sdk` silently overrides the selected SDK root.
- Bad: claiming a background service or cross-application device acceptance
  from a host permission fixture; loopback permission is not device evidence.

## 6. Tests required

- Verify actual archive names are unique; inspect manifest bundle/debug fields,
  the exact two-permission set and every packaged native ABI, including
  Flutter. Permission fixtures must accept only `INTERNET` plus
  `READ_PASTEBOARD` in any input order, assert the normalized report
  permissions, and reject an omitted `requestPermissions` key, missing-both,
  missing-either, extra and duplicate entries; they remain UNRUN until a
  runtime grant.
- Compare shipped tutorial/example JSON bytes to current assets and reconcile
  the complete example/exercise inventory. The initial gate is126/372 (SQLite
  120/360, MySQL6/12); derive exercise counts per item instead of assuming two.
- `check_audit_sources(kernel, sources)` requires exactly the standalone
  `integration_test/sql_curriculum_ohos_audit.dart` and four
  `integration_test/support/sql_curriculum_{audit,runtime,store,support}.dart`
  inputs. Require each relative path marker and complete current source in the
  debug kernel, normalizing only CRLF to LF. Record raw source SHA256 and both
  matches in `kernel.sources`; `entryExecutionVerified` remains false. Exercise
  stale helpers, missing path/body, missing/empty inputs and both newline forms.
- Reproduce native byte transforms using the pinned SDK; verify the private
  Oracle image depends only on `libc.so` and retains the required host entries.
- Verify metadata restoration and lock release on success and failure. Do not
  use a broad clean: `build/mysql-port` contains important native inputs.
- Cleanup regressions must reach lock acquisition/metadata reads with an explicit
  inert executable, so a missing SDK cannot satisfy the check. Execute the
  actual wrapper with a failed explicit Flutter fixture from a different caller
  directory; assert the expected build failure, invocation marker, exact restored
  metadata bytes, no unsigned/build record and released lock.
- Use a private fake DevEco layout and copied Node executable to check both fake
  Flutter success and exit17 without executing real Flutter/OHPM/Hvigor/Java.
  Poison inherited Node/environment, observe the actual metadata Node path and
  child PATH/env, and verify the recorded selected paths/hashes. Observe restored
  environment from the same PowerShell process after both outcomes. Missing
  input, SDK-selector conflict and local-wrapper negatives must preserve metadata
  and fail before creating build output. Hash/parse checks alone are not these
  actual transaction regressions.
- Include missing/relative APPDATA and matching relative SDK-selector fixtures.
  A fake successful build that changes one selected launch input must be refused
  before artifact/record publication while metadata and environment still restore.
- Run the installed catalog audit and retain durable report/events, exact HAP
  identity, actual target/toolchain, all per-script outcomes and owned cleanup.
  Expansion remains gated by the complete original OHOS pass.

## 7. Wrong vs correct

Wrong: add `pickFirst` to hide duplicate `libqfli_mysql.so`, or accept an ELF
because its name looks correct. This can package the old unavailable stub.

Correct: inspect the current Ninja graph and both candidate images, preserve
only the obsolete generated output in build history, rebuild, then bind all
final Oracle images to the audited real package through the exact SDK transform.

Wrong: rely on NODE_HOME alone, or edit global Flutter configuration to make a
capsule build find a different SDK. Correct: select DevEco explicitly, bind the
launcher inputs, pin the inherited process environment and refuse conflicting
persistent selection before any metadata transaction.

Wrong: freeze only the isolated review and compare four main files. Correct:
bind all current main Dart paths before and after the gate, authenticate the
focused formatting lineage, and reject unapproved config/package drift. Required
negative cases include a new/missing main file, non-focused review mutation,
missing focused initial proof, a changed direct-dev declaration and postrun drift.

Wrong: treat unsigned static-package PASS as signing or installed acceptance.
Correct: record the explicit mode and unperformed signature verification, retain
strict signed-default checks, and require separate installed execution evidence.
Unsigned-mode fixtures must enter actual inspect/main branches and assert no
signing calls, stale-sibling isolation, bad metadata/hash rejection, retained
catalog/source/native failures and distinct default report paths. Authored tests
remain UNRUN until a fresh runtime grant permits execution.
