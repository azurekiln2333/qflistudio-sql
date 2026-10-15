# Platform acceptance report — 10-15 SQL release readiness

Platform worker (Android/OHOS build, native package, device evidence).
Repo: `D:/MyNewProjects/qfli_sql`. Only this workspace was written.

> ## SDK_FREE (2026-10-15 20:12)
> The final OHOS unsigned HAP rebuild against frozen core `8b33443` is **done**.
> This worker has stopped all Flutter / dart / Gradle / pub / hvigorw / ohpm
> usage. **The Flutter SDK is free** — Android work (wC:p5) may proceed.
>
> ## Final OHOS artifact (core `8b33443`)
> `entry-default-unsigned.hap` — **193,021,465 B**, SHA256
> `25FD3C1944A077061B98FE120F5CA0F894A2E44499A3BF701005AAA28C9A27BE`, built
> 2026-10-15 20:11:23. Only `SignHap` fails (no SQL signing material). Full audit
> in `ohos-final-hap-audit.md`. No temporary config; `build-profile.json5` /
> `hvigor-config.json5` untouched; no OHOS install.

---

## 1. Android release APK — built, verified (final result owned by wC:p5)

| Field | Value |
| --- | --- |
| Path | `build/app/outputs/flutter-apk/app-release.apk` |
| Size | 45,742,375 B |
| SHA256 | `B2CD9E22943DFD0093DA66786EEF6FB2E21036F275C40F122A485F2DFAD3F3ED` |
| Built | 2026-10-15 18:50 |
| Command | `flutter build apk --release --target-platform android-arm64` |

- Native inputs in the APK matched staging: `libqfli_mysqld_exec.so` 84504248
  `AE707A42…`, `libqfli_mysql_launcher_exec.so` 46944 `B8634965…`,
  `libqfli_mysql_bridge.so` 13968832 `A2B5D7C0…`, `assets/mysql-arm64-v8a.*`.
- Signing (`apksigner`): `CN=Android Debug` (v2) → **sideload/test only, not
  store-eligible** (release signing TODO open at `android/app/build.gradle.kts`).
- Installed + launched on `adb-d361e7a0-gqqQSM (2)._adb-tls-connect._tcp`
  (OPD2413/OP615EL1, arm64-v8a, API 36): install Success, process alive, no
  crash (fresh install; `com.azurekiln.qfli.sqlab` was not previously present).
- **The final Android APK build/install and the native integration test are being
  redone by wC:p5; p5's result supersedes this.** p5 uses the isolated
  `.integrationtest` applicationId (uninstalls only the temp test package).

Key build-config fact for p5: build **without `--no-pub`** so `flutter pub get`
regenerates the gitignored release `GeneratedPluginRegistrant.java` (drops the
`integration_test` dev plugin). No repo source edit was used. Detail:
`android-handoff-p5.md`.

---

## 2. OHOS final unsigned release HAP — compiled, audited

| Field | Value |
| --- | --- |
| Path | `ohos/entry/build/default/outputs/default/entry-default-unsigned.hap` |
| Size | **193,021,465 B** |
| SHA256 | `25FD3C1944A077061B98FE120F5CA0F894A2E44499A3BF701005AAA28C9A27BE` |
| Built | 2026-10-15 20:11:23 |
| Source | sqlab tree + frozen shared core `8b33443` |
| Command | `flutter build hap --release --target-platform ohos-arm64 --no-pub` |
| Result | ArkTS / CMake / PackageHap / PackingCheck OK → **only `SignHap` fails** |

### Native libs in the HAP == final ext4 build outputs (MATCH)

hvigor strips with `llvm-strip --strip-all`; reproducing that on the final
`ohos-build/qfli-runtime/lib` outputs gives byte-identical results to the HAP:

| HAP entry | HAP size | HAP SHA256 |
| --- | ---: | --- |
| `libs/arm64-v8a/libqfli_mysql.so` | 13655272 | `dee3b4662e15632eaa79e6079acca7e8d8bb91835ed1b6b7f61f442f565ba573` |
| `libs/arm64-v8a/libqfli_mysql_server.so` | 71584712 | `7a8142bb3cc926c63a084b376dfcafe641172be61ae1c189653fbe5659fd1212` |
| `libs/arm64-v8a/libqfli_mysql_server_proto.so` | 59211040 | `02b0ad695a733293274d5093434a11fc8f8585e7aa860eb5a354ddbd91c15e0a` |
| `libs/arm64-v8a/libqfli_mysql_launcher.so` | 11640 | `2bdf8ad46da2fed32c0990f678e6bcbb1f54f71b202002b30b5f3e772c706f4a` |

Final ext4 (unstripped) sources:

| Lib | Size | SHA256 |
| --- | ---: | --- |
| `libqfli_mysql.so` (with FD-close + watchdog fixes) | 15005632 | `55230487682a5733d0772dcb58c2baa591fed9523ed97a9c1a614a4c659a0ccd` |
| `libqfli_mysql_server.so` | 89004736 | `05fbfbb0dc55da94d56c11f995e8d95426cc19511aa3e193797c9e41cff0d6a2` |
| `libqfli_mysql_server_proto.so` | 81011056 | `f216e6def30a0c761af6c13dd5a1c6dcd2dc90280605db8d0ebd342b668a2446` |
| `libqfli_mysql_launcher.so` | 22560 | `ef54810dfeff3260e8563dd1c19cccc7c09ecd1e0ea569de09ca700d6f9ed76c` |

- **New fence present in the shipped server image**: `llvm-objdump -d` on the
  HAP-extracted `libqfli_mysql_server_proto.so` → **397 `dmb`** instructions.
- Proto image exports exactly `qfli_mysql_child_main`, `QfliMysqlMain`,
  `qfli_mysql_record_exit` (version script); `NEEDED` = `libc.so` only.

### Assets in the HAP == repo (MATCH)

| Asset | Size | SHA256 | vs repo `assets/content/` |
| --- | ---: | --- | --- |
| `.../flutter_assets/assets/content/sql_tutorials.json` | 343909 | `0EA1071C1AA9A661…` | match |
| `.../flutter_assets/assets/content/sql_examples.json` | 192421 | `CACFBF628A56FC42…` | match |
| `.../rawfile/mysql/runtime.json` | 2811 | present | — |
| `.../rawfile/mysql/share/charsets/Index.xml` | 19525 | present | — |
| `.../rawfile/mysql/share/english/errmsg.sys` | 410386 | present | — |

(Reflects the frozen ASSETS_STABLE curriculum.)

---

## 3. OHOS signing — BLOCKED (missing SQL material; not fabricated)

`SignHap` fails with `00303107 Configuration Error`:
```
Invalid storeFile value ... must be included in
'C:\Users\lichengyu\.ohos\config\default_ohos_atLNRYMqojeWBzAE5Xsd0aBTQux6Ptm1YtuqBYW5IQg=.p12'
At file: D:\MyNewProjects\qfli_sql\ohos\build-profile.json5
```

- `ohos/build-profile.json5` references `atLN…{cer,p7b,p12}` — **none exist**.
- `~/.ohos/config` holds only `Gu8zVby…` (jvmx), `udwsx4…` (cloudterminal),
  `weTSdR…` (forge). Exhaustive scan found **no file referencing `qfli.sqlab`**
  (verified per-profile with `hap-sign-tool.jar verify-profile`).
- **No other project's profile was reused; no credentials generated;
  `build-profile.json5` and real certs were NOT modified.**
- ⇒ Signed HAP and OHOS device acceptance are **blocked on missing
  `com.azurekiln.qfli.sqlab` signing material**. Even once signed, the
  auto-generated cert is a **debug** profile → sideload/test only, not
  store-eligible.

---

## 4. Toolchain (for reference)

| Tool | Version | Path |
| --- | --- | --- |
| Flutter (OHOS) | 3.27.5-ohos-1.0.1 / Dart 3.11.5 | `D:\ProgramFiles\flutter_ohos\bin\flutter.bat` |
| Android SDK | `D:\ProgramData\Android\Sdk` | NDK 27.0.12077973; build-tools 35/36.1/37 |
| hvigorw / ohpm / hdc | DevEco Studio / OHOS SDK 23 | on PATH |
| WSL native build | `qfli-java-build` (clang 18.1.3, cmake 3.28.3, bison 3.8.2) | `/root/qfli-mysql-port` |

Not used (broken / Dart < 3.11.5 / auto-download), left untouched:
`D:\ProgramFiles\flutter`, `D:\ProgramData\flutter`.

---

## 5. Boundary / scope statement

- Only `D:/MyNewProjects/qfli_sql` was written. No other workspace/product, no
  shared `qfli_studio_core`, no other SDK, no `build-profile.json5`, and no real
  certificates were modified.
- Native staging dirs (`ohos/entry/libs/`, `build/mysql-port/package/libs/`) are
  gitignored generated artifacts; they were observed reverting to Oct-9 copies
  between builds (a concurrent staging step). The final HAP was produced after
  re-staging the final ext4 libs and was **verified by hash**, so the packaged
  result is correct.

---

## 6. Owned artifact / log inventory (for the coordinator's commit)

Mine (platform worker) under
`.trellis/tasks/10-15-sql-release-readiness/research/`:

- **Reports**: `platform-report.md` (this file), `ohos-final-hap-audit.md`,
  `ohos-native-rebuild-plan.md`, `android-handoff-p5.md`,
  `android-release-result.md`, `blocker-report.md`,
  `platform-coordination-note.md`, `baseline-git-status.txt`
- **Logs**: `build-android-release.log`, `build-android-release-2.log`,
  `build-ohos-release.log`, `build-ohos-release-2.log`,
  `build-ohos-final-unsigned.log`, `ohos-native-rebuild.log`,
  `ohos-native-rebuild-final.log`, `hvigor-direct.log`
- **Evidence**: `android-release-run.png`

Not authored by me (other workers; coordinate with their owners before staging):
`android-fix-plan.md`, `curriculum-*`, `native-review.md`,
`native-integration-review.md`, `native-lifecycle.patch`,
`runtime-plugin.patch`, `terminal-offline-*`, `ui-*`, `device-window-request.txt`,
`full-repository-analyze*.log`, `curriculum-native-*`.

No source files (`lib/`, `android/`, gradle, `ohos/`, `native/`) were modified by
the platform worker.
