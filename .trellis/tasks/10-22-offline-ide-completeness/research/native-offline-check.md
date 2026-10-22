# SQL native offline enforcement — 2026-10-23

## Boundary and behavior

JSON's family audit identified a real R11 gap beneath SQL's offline Flutter UI:
EntryAbility could open remote agreements/arbitrary URIs and execute Huawei
authentication. This patch rejects `openAgreement`, `openUrl` and account `login`
with `OFFLINE_ONLY` before argument access, retaining the account channel for
compatible explicit refusal. AccountKit, Want/router dispatch, client metadata
and INTERNET permission are removed. Clipboard permission remains unchanged.

MySQL uses `<filesDir>/mysql/mysql.sock`, `MYSQL_PROTOCOL_SOCKET`, port0 and
`skip-networking`; it does not justify TCP permission. No runtime implementation
or shared-core source is changed. Existing AgreementReader page/route remains
byte-identical as user WIP; platform dispatch no longer enters it.

## Baseline preservation

Ignored `build/offline-ide-check/native-offline/baseline.json` records saved bytes
before this patch. EntryAbility before SHA256 is
`501cf716abb24b9fe4e3babd639bf6b55f0a97d484f67014e523fed86f16b5f7`;
after working-copy SHA256 is
`cf6929e44a7450dd9add82f14a2f1ab8012d65fcfcb58b435d5619d92764c3a3`.
Lifecycle/window/native registrations (1328bytes), startupProgress (453bytes),
share/picker dispatch (1032bytes), clipboard tail and page/route match the saved
baseline exactly. The pre-existing startupProgress block is excluded from the
publishable candidate; its normalized SHA256 is
`66ca013387845784883324f31d80af2216bfc30a14d48020096c2a04ccf07257`.

## Executed host checks

- Actual EntryAbility SDK-TypeScript transpile/interface-double harness:
  default303 assertions PASS; 22 explicit refusals, all six picker routes,
  sharing success/failure, disposal ordering/success/failure and window handling.
  A throwing argument accessor proves the refusals precede argument access.
  Explicit import doubles reject newly introduced or AccountKit imports.
- Working copy `--workspace-startup`:337 assertions PASS, including nine valid/
  invalid progress cases. This verifies preserved WIP, not staged startup work.
- Clean publishable EntryAbility `--entry`:303 assertions PASS, log retained at
  `build/offline-ide-check/native-offline/handler-publishable.log`.
- `python -m unittest discover -s tool/ohos -p test_inspect_audit_hap.py -v`:
  seven tests PASS. The actual inspector now accepts clipboard-only and rejects
  the old clipboard+INTERNET policy, empty/extra/duplicate permissions. Existing
  catalog/ZIP/ELF and build-lock regressions remain covered.
- Parsed the actual source module with the installed JSON5 parser and passed
  its permission list through the inspector's policy; clipboard-only and absent
  client metadata confirmed.
- Independent check found no substantive defect. The publishable control passed
  303 assertions; seven temporary regression variants were all rejected:
  original AccountKit source, restored startAbility, restored router, successful
  login bypass, and argument access before each of the three guards. Node/Python
  syntax and scoped diff checks passed; two permission-class tests passed.

These checks do not establish ArkTS typing, actual picker/share IO, packet
capture, normal-startup network behavior or installed OHOS execution. The
historical signed HAP `0c5007b4…6d78` predates this native patch and cannot prove
it. A fresh source-bound build/sign/inspection and device run remain required;
the exact assigned target still returns `[Empty]`. No device mutation occurred.

## Bug analysis

1. Root cause: cross-layer contract/coverage gap. Flutter policy gates did not
   cover independently callable native platform/account handlers or manifest
   permissions.
2. Earlier checks: cloud-repository call counting correctly covered Dart cloud
   entry points, but could not prove native refusal. A hidden UI was insufficient
   evidence for those handlers. No earlier native repair is claimed here.
3. Prevention: actual handler execution tests exact replies and preserved local
   behavior; archive policy rejects permission drift; frontend offline and
   backend packaging specs now require both layers and separate device proof.
4. Expansion: sibling findings are queued to their existing owners. SQL does
   not edit sibling/shared-core code or infer their runtime state from this fix.
5. Knowledge captured in `sql-terminal-offline.md` and
   `ohos-audit-packaging.md`. This product has no
   `src/templates/markdown/spec` mirror to synchronize.
