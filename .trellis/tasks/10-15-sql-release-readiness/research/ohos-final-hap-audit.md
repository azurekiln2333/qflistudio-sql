# OHOS final unsigned HAP + native audit (ASSETS_STABLE)

Date: 2026-10-15. Platform worker. SDK_FREE for Flutter tool (see platform-report).

> **Core-revision note (2026-10-15 20:11):** this HAP was built against the
> **frozen, clean shared core `8b33443`** (`fix(settings): show active product
> identity in About dialog`). It supersedes the earlier pre-core 19:16 HAP
> (`24F7024B…`), which predated `8b33443`.

## 1. Final unsigned release HAP

**Built against frozen shared core `8b33443`** (`fix(settings): show active
product identity in About dialog`; core working tree clean).

| Field | Value |
| --- | --- |
| Path | `ohos/entry/build/default/outputs/default/entry-default-unsigned.hap` |
| Size | **193,021,465 bytes** |
| SHA256 | `25FD3C1944A077061B98FE120F5CA0F894A2E44499A3BF701005AAA28C9A27BE` |
| Built | 2026-10-15 20:11:23 |
| Source | sqlab tree + shared core `8b33443` |
| Command | `flutter build hap --release --target-platform ohos-arm64 --no-pub` |
| Outcome | ArkTS Ok, CMake Ok, PackageHap Ok, PackingCheck Ok — **only `SignHap` fails** |

Core-fix confirmation: `libapp.so` in this HAP is `29dcf244…` vs the pre-core
19:16 build `ed6d8ddd…` → the `8b33443` Dart change is compiled in.

## 2. Native audit — HAP inputs == final ext4 build outputs (MATCH)

hvigor's `DoNativeStrip` uses `llvm-strip --strip-all` (NOT `--strip-unneeded`).
Reproducing that exact strip on the final ext4 `ohos-build/qfli-runtime/lib`
outputs yields **byte-identical** results to the HAP entries for all four libs:

| HAP entry | HAP size | HAP SHA256 | matches `--strip-all` of final ext4 |
| --- | ---: | --- | --- |
| `libs/arm64-v8a/libqfli_mysql.so` | 13655272 | `dee3b4662e15632eaa79e6079acca7e8d8bb91835ed1b6b7f61f442f565ba573` | **YES** |
| `libs/arm64-v8a/libqfli_mysql_server.so` | 71584712 | `7a8142bb3cc926c63a084b376dfcafe641172be61ae1c189653fbe5659fd1212` | **YES** |
| `libs/arm64-v8a/libqfli_mysql_server_proto.so` | 59211040 | `02b0ad695a733293274d5093434a11fc8f8585e7aa860eb5a354ddbd91c15e0a` | **YES** |
| `libs/arm64-v8a/libqfli_mysql_launcher.so` | 11640 | `2bdf8ad46da2fed32c0990f678e6bcbb1f54f71b202002b30b5f3e772c706f4a` | **YES** |

Final ext4 (unstripped) inputs the HAP is derived from:

| ext4 lib | size | SHA256 |
| --- | ---: | --- |
| `libqfli_mysql.so` | 15005632 | `55230487682a5733d0772dcb58c2baa591fed9523ed97a9c1a614a4c659a0ccd` |
| `libqfli_mysql_server.so` | 89004736 | `05fbfbb0dc55da94d56c11f995e8d95426cc19511aa3e193797c9e41cff0d6a2` |
| `libqfli_mysql_server_proto.so` | 81011056 | `f216e6def30a0c761af6c13dd5a1c6dcd2dc90280605db8d0ebd342b668a2446` |
| `libqfli_mysql_launcher.so` | 22560 | `ef54810dfeff3260e8563dd1c19cccc7c09ecd1e0ea569de09ca700d6f9ed76c` |

### Fence verified in the packaged server image
`llvm-objdump -d` on the HAP-extracted `libqfli_mysql_server_proto.so` →
**397 `dmb`** instructions. The new `HAVE_IB_GCC_ATOMIC_THREAD_FENCE` fence is
present in the shipped server image.

### NAPI fixes verified in the shipped client lib
`libqfli_mysql.so` is derived from the final build of
`ohos/entry/src/main/cpp/qfli_mysql_proto_probe.cpp` (bounded `poll()` handshake,
`child_reset_signals_and_fds` real FD close, checked `watch_parent`
`pthread_create`). No stale Oct-9 lib is packaged (that older lib would strip to
a different hash).

## 3. Assets audit — HAP == repo (MATCH)

| Asset | HAP size | HAP SHA256 | repo `assets/content/` | match |
| --- | ---: | --- | --- | --- |
| `sql_tutorials.json` | 343909 | `0EA1071C1AA9A661…` | same | **YES** |
| `sql_examples.json` | 192421 | `CACFBF628A56FC42…` | same | **YES** |
| `mysql/runtime.json` | 2811 | present | — | — |
| `mysql/share/charsets/Index.xml` | 19525 | present | — | — |
| `mysql/share/english/errmsg.sys` | 410386 | present | — | — |

This is the ASSETS_STABLE curriculum (with author setup/expected metadata) frozen
into the HAP.

## 4. Signing — BLOCKED (missing SQL material, not fabrication)

`SignHap` fails:
```
00303107 Configuration Error
Invalid storeFile value ... must be included in
'C:\Users\lichengyu\.ohos\config\default_ohos_atLNRYMqojeWBzAE5Xsd0aBTQux6Ptm1YtuqBYW5IQg=.p12'
```
- `ohos/build-profile.json5` points at that `.p12/.p7b/.cer` — **none exist**.
- `~/.ohos/config` currently holds only `Gu8zVby…` (jvmx), `udwsx4…`
  (cloudterminal), `weTSdR…` (forge). Exhaustive scan of `~/.ohos` found **no
  file referencing `qfli.sqlab`**.
- Verified with `hap-sign-tool.jar verify-profile` per profile.
- **No other project's profile was reused and no credentials were generated.**
- ⇒ signed HAP / OHOS device acceptance is **blocked on missing
  `com.azurekiln.qfli.sqlab` signing material** (regenerate in DevEco, or repoint
  `build-profile.json5` to a valid sqlab profile — an owner decision).
- Even once signed, the auto-generated cert is a **debug** profile → sideload/
  test only, not store-eligible.

## 5. Race note (staging)

`ohos/entry/libs/arm64-v8a/` and `build/mysql-port/package/libs/arm64-v8a/` are
gitignored generated staging. They were observed reverting to the Oct-9 libs
between builds (a concurrent staging step). The final HAP was produced after
re-staging the final ext4 libs, and **was verified by hash** against the final
ext4 outputs, so the packaged result is correct regardless.

## 6. Rebuild — COMPLETE (frozen core `8b33443`)

Executed 2026-10-15 20:11 against clean core `8b33443`:
`flutter build hap --release --target-platform ohos-arm64 --no-pub` → unsigned
HAP `25FD3C19…` (see §1). Only `SignHap` fails (no signed package). The
unsigned-only hvigor `properties.enableSignTask:false` path was **not needed**
(the wrapper already emits the unsigned HAP before `SignHap`). Nothing to
restore; `build-profile.json5` and `hvigor-config.json5` untouched.

Re-audit after build: native libs == final ext4 (`--strip-all`); curriculum
JSONs == `assets/content/`; `dmb`=397 in the server image; `libapp.so` reflects
core `8b33443`. No OHOS install (no valid profile), no user-data touch, no
borrowed certs.
