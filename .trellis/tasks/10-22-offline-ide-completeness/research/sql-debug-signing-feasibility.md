# SQL own-bundle OHOS debug signing — feasibility (read-only)

Task: `.trellis/tasks/10-22-offline-ide-completeness`
Author: read-only signing investigator (Pi). Scope addendum to `research/runtime-audit.md`.
Date: 2026-10-22.

**Boundaries honored:** no keypair/profile created, no config edited, no app installed/started/stopped,
no daemon or device-queue mutation, no product write. Only filesystem/CLI inspection plus
`hdc shell` *read-only* queries (`param get`, `bm dump`, `bm get`, `bm help`, `cat` of world-readable
system files). This was the only file written. All passwords/keys are redacted below.

---

## 1. Bottom line

1. **Yes — a fully offline, own-bundle (`com.azurekiln.qfli.sqlab`) debug signing path exists using only
   material shipped with the installed SDK, and this emulator's trust policy accepts it.**
   The device trusts `C=CN, O=OpenHarmony, OU=OpenHarmony Team, CN=OpenHarmony Application Root CA`
   and lists an `OpenHarmony apps` source whose app/profile/profile-debug certs are exactly the
   certificates inside `sdk\default\openharmony\toolchains\lib\OpenHarmony.p12`. No sibling bundle,
   no AGC account, no network is needed.
2. **Provision inspection of the already-installed app is possible only at metadata level.**
   `bm dump` reports `appProvisionType: debug`, `appDistributionType: none`, `installSource: unknown`,
   `apiCompatibleVersion: 50100018`, `apiTargetVersion: 60101024`. The installed HAP payload
   (and therefore its embedded `.p7b`) is **not readable** without privilege
   (`ls /data/app/el1/bundle/public/com.azurekiln.qfli.sqlab` → `Permission denied` as `shell` uid 2000).
   No secret is extractable, and none is needed.
3. **Minimal unsigned x86 HAP build** is a single `flutter build hap --debug --target-platform ohos-x64`
   invocation; the unsigned HAP is emitted before `SignHap`, so the expected non-zero exit at
   `SignHap` can be tolerated — no `ohos/build-profile.json5` edit required. The ABI gate is
   currently satisfied (see §6.1: a concurrent worker already restored `x86_64` in
   `ohos/entry/build-profile.json5`).

---

## 2. Evidence collected this session

### 2.1 Device trust policy (read-only, `/system/etc/security/*.json`, world-readable)

`trusted_root_ca.json` contains two roots, including:

```
C=CN, O=OpenHarmony, OU=OpenHarmony Team, CN=OpenHarmony Application Root CA
```

`trusted_apps_sources.json` contains an `"OpenHarmony apps"` entry:

| field | value |
| --- | --- |
| app-signing-cert | `C=CN, O=OpenHarmony, OU=OpenHarmony Team, CN=OpenHarmony Application Release` |
| profile-signing-certificate | `... CN=OpenHarmony Application Profile Release` |
| profile-debug-signing-certificate | `... CN=OpenHarmony Application Profile Debug` |
| issuer-ca | `C=CN, O=OpenHarmony, OU=OpenHarmony Team, CN=OpenHarmony Application CA` |
| root-ca | `C=CN, O=OpenHarmony, OU=OpenHarmony Team, CN=OpenHarmony Application Root CA` |
| max-certs-path | 3 |

### 2.2 SDK default material (`sdk\default\openharmony\toolchains\lib`)

`OpenHarmony.p12` (8252 B) — PKCS#12 aliases (listed with the SDK's documented default store password,
**not reproduced here**):

| alias | entry | subject / validity |
| --- | --- | --- |
| `openharmony application release` | PrivateKeyEntry | `CN=OpenHarmony Application Release`, 2021‑02‑02 → **2049‑12‑31** |
| `openharmony application ca` | PrivateKeyEntry | `CN=OpenHarmony Application CA`, 2021‑02‑02 → **2049‑12‑31** |
| `openharmony application root ca` | PrivateKeyEntry | `CN=OpenHarmony Application Root CA`, 2021‑02‑02 → **2049‑12‑31** |
| `openharmony application profile debug` | PrivateKeyEntry | `CN=OpenHarmony Application Profile Debug`, 2021‑02‑02 → **2049‑12‑31** |
| `openharmony application profile release` | PrivateKeyEntry | `CN=OpenHarmony Application Profile Release` |
| `openharmony software signature` | PrivateKeyEntry | `CN=OpenHarmony Software Signature` |
| `cacert`, `rootcacert` | trustedCertEntry | root copies |

`OpenHarmonyProfileDebug.pem` — **3-cert chain**, first cert subject = issuer =
`CN=OpenHarmony Application Root CA`, valid to **2049**. This is the `-profileCertFile` input for a
debug profile.

`UnsgnedDebugProfileTemplate.json` — template for the profile *content*:
`type: debug`, `bundle-info.developer-id: OpenHarmony`, `bundle-name: com.OpenHarmony.app.test`,
`apl: normal`, `app-feature: hos_normal_app`, `debug-info.device-id-type: udid`,
`debug-info.device-ids: [two unrelated UDIDs]`, `issuer: pki_internal`,
**`validity: 1610519532 → 1705127532` (2021‑01‑13 → 2024‑01‑13, EXPIRED)**.

`hap-sign-tool.jar` supports exactly the needed verbs:
`generate-app-cert`, `generate-profile-cert`, `sign-profile -mode localSign`,
`sign-app -mode localSign`, `verify-profile`, `verify-app`.

### 2.3 Device identity (read-only)

```
udid: 454D55057494E058383602DD9C05BCD9E4026BE286E3F6B3CC57700000000000
product: emulator   api: 26   abilist: x86_64   fullname: OpenHarmony-7.0.0.105
software: 7.0.0.107(SP8DEVC00E999R4P11)
```

### 2.4 Repo signing state (unchanged facts from `runtime-audit.md`)

- `ohos/build-profile.json5` (worktree, baseline WIP) references
  `default_ohos_atLN…{cer,p7b,p12}` — **absent**; HEAD references `default_ohos_EyK2s6z…` — also absent.
- No `.p7b` on disk binds `com.azurekiln.qfli.sqlab`; the 6 present profiles belong to
  java / script / dartwing / go / cloudterminal / cpp. **Sibling identity must not be borrowed** —
  all six are bound to different bundle names and would be rejected/mis-identifying.

---

## 3. Exact safe signing commands (root executes; all outputs in a throwaway dir)

Nothing below writes into the repository, `ohos/`, or `~/.ohos`. Placeholders:
`<SDK>` = `D:\ProgramFiles\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\lib`,
`<TOOL>` = `<SDK>\hap-sign-tool.jar`, `<P12>` = `<SDK>\OpenHarmony.p12`,
`<PEMP>` = `<SDK>\OpenHarmonyProfileDebug.pem`, `<TMP>` = a new empty scratch dir
(e.g. `D:\MyNewProjects\qfli_sql\build\sql-sign-scratch`, or `%TEMP%\sql-sign`).
Passwords are **redacted**: `<STORE_PWD>` is the SDK-documented default store password for
`OpenHarmony.p12`; prefer `-pwdInputMode 1` (interactive) so no secret enters shell history.

### Step 1 — write the SQL-bound profile JSON (content only, no signature yet)

Copy `<SDK>\UnsgnedDebugProfileTemplate.json` to `<TMP>\sql-debug-profile.json` and change exactly:

| field | from | to |
| --- | --- | --- |
| `bundle-info.bundle-name` | `com.OpenHarmony.app.test` | `com.azurekiln.qfli.sqlab` |
| `debug-info.device-ids` | the two template UDIDs | `["454D55057494E058383602DD9C05BCD9E4026BE286E3F6B3CC57700000000000"]` |
| `validity.not-before` | 1610519532 (expired) | current epoch (or now − 1 day) |
| `validity.not-after` | 1705127532 (expired) | now + 180 days (any window covering the test run) |
| `uuid` | template value | any fresh UUID (optional but tidy) |

Leave `type: debug`, `apl: normal`, `app-feature: hos_normal_app`,
`bundle-info.developer-id: OpenHarmony`, `issuer: pki_internal`,
`bundle-info.development-certificate` **unchanged** (it must stay the `OpenHarmony Application
Release` cert that the device's trust entry names).

### Step 2 — sign the profile with the SDK's Profile-Debug key

```powershell
java -jar <TOOL> sign-profile -mode localSign `
  -keyAlias "openharmony application profile debug" `
  -keyPwd <STORE_PWD> `
  -profileCertFile <PEMP> `
  -inFile <TMP>\sql-debug-profile.json `
  -signAlg SHA256withECDSA `
  -keystoreFile <P12> -keystorePwd <STORE_PWD> `
  -outFile <TMP>\sql-debug-profile.p7b
```

Verify (writes only into `<TMP>`):

```powershell
java -jar <TOOL> verify-profile -inFile <TMP>\sql-debug-profile.p7b -outFile <TMP>\profile-verify.json
# expect: verified OK, type=debug, bundle=com.azurekiln.qfli.sqlab, device-ids contains the UDID
```

### Step 3 — produce the app certificate chain (3 levels, leaf→CA→root)

The trust entry names `CN=OpenHarmony Application Release` as the app signing cert and allows
`max-certs-path: 3`. Export the shipped chain rather than minting a new identity:

```powershell
$kt = "D:\ProgramFiles\Java\jdk-25\bin\keytool.exe"
& $kt -exportcert -rfc -alias "openharmony application release"    -keystore <P12> -storetype PKCS12 -storepass <STORE_PWD> > <TMP>\leaf.pem
& $kt -exportcert -rfc -alias "openharmony application ca"         -keystore <P12> -storetype PKCS12 -storepass <STORE_PWD> > <TMP>\ca.pem
& $kt -exportcert -rfc -alias "openharmony application root ca"    -keystore <P12> -storetype PKCS12 -storepass <STORE_PWD> > <TMP>\root.pem
Get-Content <TMP>\leaf.pem,<TMP>\ca.pem,<TMP>\root.pem | Set-Content <TMP>\sql-app-chain.cer
```

(Alternative, if a *distinct* app identity is preferred: `generate-app-cert -keyAlias <new alias> -subject
"... CN=<own name>" -issuer "C=CN, O=OpenHarmony, OU=OpenHarmony Team, CN=OpenHarmony Application CA"
-issuerKeyAlias "openharmony application ca" -issuerKeystoreFile <P12> ... -outForm certChain`. This
creates a new key — **not recommended** here: the trust entry pins the release subject, so the exported
chain is the lower-risk option.)

### Step 4 — sign the unsigned HAP (no repo config touched)

```powershell
java -jar <TOOL> sign-app -mode localSign `
  -keyAlias "openharmony application release" -keyPwd <STORE_PWD> `
  -appCertFile <TMP>\sql-app-chain.cer -profileFile <TMP>\sql-debug-profile.p7b `
  -inFile <unsigned.hap> -signAlg SHA256withECDSA `
  -keystoreFile <P12> -keystorePwd <STORE_PWD> `
  -outFile <TMP>\entry-default-signed-x86_64.hap

java -jar <TOOL> verify-app -inFile <TMP>\entry-default-signed-x86_64.hap `
  -outCertChain <TMP>\v-chain.cer -outProfile <TMP>\v-profile.p7b
```

`<unsigned.hap>` = `ohos\entry\build\default\outputs\default\entry-default-unsigned.hap`
(or the x64 build's equivalent, §6).

### Step 5 — install (root-only; this is the one non-reversible-ish step)

```powershell
hdc -t 127.0.0.1:5555 install -r <TMP>\entry-default-signed-x86_64.hap
```

`-r` replaces the existing install. App data is normally preserved by replace-install, but this is the
only step that mutates the device and it must be a root decision, not a worker decision.

---

## 4. Constraints and gotchas (all verified, none speculative)

1. **The bundled template's validity window is expired** (ends 2024‑01‑13) while the device clock is 2026.
   A copied template must get a fresh `validity`; the *certificates* are fine to 2049.
2. **Device UDID must be in `debug-info.device-ids`** — a `debug` profile is device-bound. The template's
   two UDIDs are foreign to this emulator.
3. **Profile signer must be `... CN=OpenHarmony Application Profile Debug`**, i.e. alias
   `openharmony application profile debug` with `<PEMP>` as `-profileCertFile`. Signing the debug profile
   with the *release* key will not match the device's `profile-debug-signing-certificate`.
4. **`bundle-name` must be exactly `com.azurekiln.qfli.sqlab`** (`ohos/AppScope/app.json5`). Any other value
   installs under a different identity — this is the "never borrow sibling identity" line.
5. **Chain order is leaf → CA → root, max 3 links**; `OpenHarmonyProfileDebug.pem` is already a correct
   3-cert chain for the profile, and step 3 builds the app chain the same way.
6. **Nothing in this flow needs network, AGC, or an account.** It also does not need the deleted
   `atLN…`/`EyK2s6z…` material, and does not require editing `ohos/build-profile.json5`.
7. Optional convenience only: `hvigor/hvigor-config.json5 → "properties": { "enableSignTask": false }`
   (verified present in `hvigorw.js`: `PROPERTIES = "properties"`, `defaultProperties.enableSignTask = true`)
   would stop `SignHap` from being scheduled. **Not needed** — see §6 — and it is a config edit, so avoid it.

---

## 5. Inspecting the installed app's provision without extracting secrets

| What | Observable? | How |
| --- | --- | --- |
| provision **type** (debug/release) | yes | `bm dump -n com.azurekiln.qfli.sqlab` → `applicationInfo.appProvisionType` |
| distribution type / install source | yes | same dump → `appDistributionType: none`, `installSource: unknown` |
| SDK compatibility recorded at install | yes | `apiCompatibleVersion: 50100018`, `apiTargetVersion: 60101024` |
| code path / ABI | yes | `codePath`, `cpuAbi: x86_64`, `nativeLibraryPath: libs/x86_64` |
| embedded `.p7b` / signing certs | **no** | installed HAP lives under `/data/app/el1/bundle/public/…`; `shell` (uid 2000) gets `Permission denied`. Extracting it would require root or a signed package you already hold. |

Conclusion: the existing install proves *a* debug-provisioned sqlab build existed at some point; it cannot
tell us which profile, and it yields no reusable secret. The §3 flow does not depend on it.

---

## 6. Minimal unsigned **x86_64** HAP build invocation and architecture constraints

### 6.1 Current ABI state (changed since `runtime-audit.md` — re-verified now)

`ohos/entry/build-profile.json5` in the worktree now reads:

```json5
"abiFilters": ["arm64-v8a", "x86_64"],
"nativeLib": { "filter": { "excludes": [] } }
```

i.e. the earlier arm64-only restriction has already been reverted by another worker, so an x86_64
package is buildable again. `ohos/build-profile.json5` still points at the missing `atLN…` material —
irrelevant for the unsigned path in §6.2, fatal only for `flutter build hap`'s automatic `SignHap`.

### 6.2 Minimal invocation

```powershell
cd D:\MyNewProjects\qfli_sql
flutter build hap --debug --target-platform ohos-x64 --no-pub
# optionally -t integration_test/sql_curriculum_native_test.dart for the curriculum target
```

- Artifact: `ohos\entry\build\default\outputs\default\entry-default-unsigned.hap`.
- **Expect a non-zero exit at `:entry:default@SignHap`** (`00303107 … Invalid storeFile value`). That is the
  known, documented behavior: `PackageHap`/`PackingCheck` complete and the unsigned HAP is written first,
  so the failure is tolerable. Gate on the artifact existing + `zip`-listing containing
  `libs/x86_64/libqfli_sql.so libs/x86_64/libapp.so libs/x86_64/libflutter.so libs/x86_64/libc++_shared.so`.
- Then sign that artifact with §3 steps 1–4. **No repository config change is required at any point.**

### 6.3 Architecture constraints to expect in that package

- `native/CMakeLists.txt` gates the real Oracle MySQL runtime on
  `CMAKE_SYSTEM_PROCESSOR ~= aarch64`; every other ABI (including x86_64) links
  `src/qfli_mysql_unavailable.cpp`, whose query path returns
  `"The bundled Oracle MySQL runtime requires a HarmonyOS arm64 device."` (`error_code 127`).
  So an x86_64 HAP carries **real SQLite 3.50.0 + stub MySQL**.
- Verified in a prior x86_64 OHOS configure tree
  (`ohos/entry/.cxx/default/default/debug/x86_64/CMakeCache.txt`: `OHOS_ARCH=x86_64`,
  `CMAKE_OHOS_ARCH_ABI=x86_64`, toolchain `sdk\default\hms\native\build\cmake\hmos.toolchain.cmake`;
  its `build.ninja` links `libqfli_sql.so` from `sqlite3.c` and `qfli_mysql_unavailable.cpp`).
- Consequence: an emulator run can validate SQLite curriculum/exercise output only. The six MySQL
  lessons stay unproven there, and the package's MySQL strings must never be reported as acceptance.
- Flutter places `libapp.so` under `entry/libs/<arch-of-target-platform>` (`ohos_builder.dart`),
  i.e. `libs/x86_64` for `--target-platform ohos-x64`; the AOT/engine artifacts for `ohos-x64` are
  supported (`build_hap.dart` allows `ohos-arm64|ohos-arm|ohos-x64`).
- Size: the arm64 HAP is ~190 MB because of the 130 MB Oracle server images; the x86_64 build should be
  far smaller (no MySQL server libs) — a useful sanity signal in the zip listing.

---

## 7. Recommended next root step (reversible, no new permission)

**Do §6.2 first: build the unsigned x86_64 HAP and verify its `libs/x86_64/*` listing.**
It touches only `ohos/entry/build/**` (already gitignored build output), requires no signing material,
no config edit, no device interaction, and is fully reversible by deleting the build outputs.
It also immediately answers "does the current tree still compile for x86_64 with the restored ABI list?".

Then, only if the artifact is good, run §3 steps 1–4 in a scratch dir and `verify-app`. Both are
local, offline and disposable (delete `<TMP>`).

Only after a verified signed HAP exists should root consider §3 step 5 (`hdc install -r`) — the single
device-mutating action.

## 8. Open questions / residual uncertainty

- Whether the emulator enforces `app-feature`/`apl` beyond `normal` for a debug provision (expected: no;
  our app declares none).
- Whether debug install additionally validates `bundle-info.developer-id` against the profile-signing
  chain (the template's `OpenHarmony` value matches the shipped chain, so this is consistent either way).
- Whether the device rejects an *exported* `OpenHarmony Application Release` chain in favour of a
  freshly issued cert — unverified, and only observable with one install attempt (root decision).
- No claim is made that a signed+installed x86_64 HAP passes the curriculum target; that is a separate
  execution acceptance with its own evidence requirements.
