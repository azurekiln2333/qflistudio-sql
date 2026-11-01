# Release HAP → 14u (MRT-AL10, 192.168.68.207:46551) push attempt

Date: 2026-10-15 ~22:27.

## What was done

1. Built release HAP:
   `flutter build hap --release --target-platform ohos-arm64 --no-pub`
   → ArkTS/CMake/PackageHap/PackingCheck OK; **`SignHap` failed** (unsigned
   artifact emitted).
   log: `build-ohos-push-14u.log`
2. Artifact: `entry-default-unsigned.hap` — 193,021,465 B, SHA256
   `362345B90A11D53ABC2972816B40B1F1CA0485953B26DE5B6E47E6A99B9E2566`,
   md5 `71b0e48177ac6c177aa3f715474013ce`, built 2026-10-15 22:24.
3. Pushed to the device via `hdc file send` (absolute local path):
   `192.168.68.207:46551:/data/local/tmp/qfli_sqlab_release_unsigned.hap`
   — on-device size **193,021,465 B**, md5 **matches local** ✅.

## Install result — BLOCKED (unsigned)

```
hdc install (local)          → code:9568320 error: no signature file
hdc shell bm install -p ...  → code:9568320 error: no signature file
```

## Root cause

The release HAP cannot be signed: `ohos/build-profile.json5` references
`default_ohos_atLNRYMqojeWBzAE5Xsd0aBTQux6Ptm1YtuqBYW5IQg=.p12`, which does not
exist. Re-scanned **all** `~/.ohos` `*.p7b` via `hap-sign-tool.jar
verify-profile`:

| Profile | bundle-name |
| --- | --- |
| `Gu8zVby…` | `com.azurekiln.qfli.jvmx` |
| `H2qDWx…` (new) | `com.azurekiln.qfli.dartwing` |
| `udwsx4…` | `com.azurekiln.cloudterminal` |
| `weTSdR…` | `com.azurekiln.qfli.forge` |

**No `com.azurekiln.qfli.sqlab` provisioning profile exists.** Per instruction,
no other project's profile was used and no credentials were generated, so no
signed HAP was produced.

## Device / data safety

- Device `MRT-AL10` (the "14u"), HarmonyOS 7.0.0.109, API 26.
- The prod app `com.azurekiln.qfli.sqlab` (debug-provisioned, v1.0.0) is
  installed; it was NOT uninstalled and its data was NOT touched.
- Only a HAP copy was placed in `/data/local/tmp/` (harmless scratch).

## To actually install

A valid `com.azurekiln.qfli.sqlab` signing profile must be generated (DevEco
"Automatically generate signature" for this bundleName), or `build-profile.json5`
repointed to a valid sqlab profile. After that the HAP can be signed and
`hdc install` will work. Until then the pushed unsigned HAP cannot be installed
on the phone.
