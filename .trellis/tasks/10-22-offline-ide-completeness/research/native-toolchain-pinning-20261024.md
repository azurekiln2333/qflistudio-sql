# Native build toolchain selection — 2026-10-24

Status: source implemented and independently reviewed; runtime UNRUN. This work does not
accept or expand SQL570, reserve a host window, rebuild a HAP or use a device.

## Behavior gap and boundary

The audit builder resolves Flutter explicitly but invokes ambient Node for
metadata. Flutter's OHOS TS builder also selects npm, OHPM, Hvigor and Java
through environment or persistent configuration. A capsule alone therefore
does not establish which installed toolchain performs the build.

The smallest implementation boundary is `tool/ohos/build_audit_hap.ps1`, its
actual-wrapper transaction fixture, and the existing early-metadata cleanup
fixture in `test_inspect_audit_hap.py`. Select one explicit DevEco installation,
resolve its inputs before metadata mutation, set only process-local environment,
and restore that environment on both success and failure. Preserve the explicit
Flutter input and current metadata transaction. No application/core/signing
implementation changes belong to this correction.

## Local primary-source evidence

Paths below are beneath
`D:/ProgramFiles/flutter_ohos/packages/flutter_tools/lib/src/` unless stated.
Two independent read-only explorers examined the SDK and fixture seams; no
toolchain executable or regression method was run.

- `ohos/hvigor_utils.dart:191-224` runs bare `npm install` in the TS path even
  with `--no-pub`. Lines67-69 write `NODE_HOME` as `nodejs.dir`.
- `ohos/hvigor.dart:97-109` selects project `ohos/hvigorw.bat`, otherwise bare
  `hvigorw`; lines120-126 run bare `ohpm install --all`. The SQL checkout has no
  project-local Hvigor wrapper. An unexpected local wrapper must be separately
  bound or refused rather than silently overriding the selected installation.
- DevEco `tools/hvigor/bin/hvigorw.bat:43-57` checks `NODE_HOME/node.exe` but
  eventually invokes bare `node.exe`. `NODE_HOME` alone does not select the
  executable; the selected Node directory must lead the child PATH.
- DevEco `tools/ohpm/bin/ohpm.bat:82-108` tries PATH Node before `NODE_HOME`.
- DevEco `tools/node/npm.cmd:13-17` can redirect npm-cli through the global
  prefix returned by `npm-prefix.js:23`. Bind `npm_config_prefix` to the selected
  Node distribution and retain hashes of npm-cli/prefix inputs.
- `ohos/ohos_sdk.dart:129-134,294-360` prefers persistent `ohos-sdk` over SDK
  environment variables. It expects the DevEco `sdk` root and discovers the
  child `default/sdk-pkg.json`; selecting `sdk/default` is not equivalent.
- `base/config.dart:190-209` selects Windows `%APPDATA%/.flutter_settings`.
  An absent file is acceptable. Inspect only `ohos-sdk` and refuse a conflicting
  root before mutation; never rewrite or expose the rest of the settings.
  If APPDATA is absent, Flutter uses `.` in its child working directory. The
  guard must check repository settings and resolve relative APPDATA and SDK
  selectors against that same directory, not the wrapper caller's directory.
- DevEco `tools/hvigor/hvigor-ohos-plugin/src/sdk/info/ohos-sdk-info.js:1`
  checks `JAVA_HOME` before executing bare `java -version`. Set both JAVA_HOME
  and the selected Java bin in PATH. The inspected launchers do not use generic
  OHPM_HOME/HVIGOR_HOME selectors.

## Required assertions

The fake-toolchain regression must prove selection despite poisoned inherited
Node/environment values, observe the actual metadata Node executable, and
verify the child environment. Both a fake Flutter exit17 and a fake successful
artifact must restore exact metadata and release the lock. A same-process
PowerShell harness must verify environment restoration; Python parent values
cannot prove it. Success records selected input paths/hashes, not target proof.
Missing tools and conflicting persistent SDK configuration must fail before
metadata mutation. The early-metadata fixture must still reach metadata reads
and lock acquisition, rather than pass at a new tool preflight error.

Independent check fixed the APPDATA/SDK-selector working-directory gap above.
Authored subcases cover matching relative selection, conflicting absolute,
missing and relative APPDATA, missing tool input, a local Hvigor override and a
fake successful build that mutates npm-cli. That last case must refuse publication
while still restoring metadata/environment. These subcases remain UNRUN.

## Final source checkpoint

| File | SHA256 |
| --- | --- |
| tool/ohos/build_audit_hap.ps1 | a08dd59282cabcaae5fadad5ea17bd158c7bce94a0a3cd2b8b392c3494e17cb8 |
| tool/ohos/test_build_audit_hap.py | f3c7bbfa60edc0a39a414194d3ccd2da41ec969ee32082eec999ec4f8187d059 |
| tool/ohos/test_inspect_audit_hap.py | ff843a352eb7931353b0ea80518ca7df16c21ccf470d1daf31c476715da6b7b4 |

The inspector implementation remains d8193ab0. Builder and generated-harness
PowerShell parsing, Python AST/compile-only and scoped whitespace checks pass.
All selected installed launch paths exist. No fixture method, lint/type-check,
SDK, build, signing or device command was executed. Python definition inventory
is now36:2 builder +21 collector +13 inspector. This is discovery, not36 passes.

The full-host supervisor remains5476622e. Its still-refusing template only
updates the inventory preparation note to36; current template SHA256 is
11ac95f50e7446150d19186c56b38903af9626432613746656a6be77c21c79e6.
The prior template is preserved byte-exactly as
`full-sql-launch.template.checkpoint573.json`, SHA40931177. All prerequisite
evidence/inventories remain null; no full-host execution becomes authorized.
Channel575 publishes these exact source identities and unchanged SQL570 request
without accepting a window or reporting a new runtime handle/exit.

## Remaining acceptance

Static parsing and source review are followed by the actual fixture methods in
a fresh named full-host window. A real bounded capsule build needs the exact
formatted/passed SQL source, this final reviewed tooling, current dependency
setup, owned process cleanup and strict HAP inspection. SDK setup/build and
installed OHOS126/372 acceptance remain separate required gates. The existing
checkpoint573 capsule retains its original hashes; it is not silently updated
or relabeled as tested by this work.
