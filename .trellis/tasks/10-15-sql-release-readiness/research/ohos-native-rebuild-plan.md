# OHOS native rebuild + HAP final status (platform worker)

Date: 2026-10-15. SOURCE_STABLE confirmed received; final NAPI rebuild done.

## 1. Final native rebuild (SOURCE_STABLE) — DONE

Sources touched (drvfs mtime gotcha), then rebuilt in `qfli-java-build`:

- `qfli_mysql` (NAPI) — recompiled `qfli_mysql_proto_probe.cpp`,
  `qfli_mysql_napi.cpp`, `qfli_mysql_host.cpp`; relinked.
- `qfli_mysql_server_proto` — relinked (deterministic).

Final fixes verified present in `ohos/entry/src/main/cpp/qfli_mysql_proto_probe.cpp`:
- `child_reset_signals_and_fds(keep_descriptor, descriptor_count)` closes every
  descriptor except the kept one (line 112: `if (descriptor != keep_descriptor)
  close(descriptor);`), called at line 202 with the handshake write end.
- `watch_parent()` return is now checked; on `pthread_create` failure the child
  `_exit(125)` (lines 205–209) instead of continuing without a watchdog.
- Bounded `poll()` handshake (`await_handshake`) with PID-tracked failed-start
  cleanup.

### Final staged OHOS libs (`ohos/entry/libs/arm64-v8a/`)

| Library | Size | SHA256 |
| --- | ---: | --- |
| `libqfli_mysql.so` (NAPI, WITH fixes) | 15005632 | `55230487682a5733d0772dcb58c2baa591fed9523ed97a9c1a614a4c659a0ccd` |
| `libqfli_mysql_server_proto.so` | 81011056 | `f216e6def30a0c761af6c13dd5a1c6dcd2dc90280605db8d0ebd342b668a2446` |
| `libqfli_mysql_server.so` | 89004736 | `05fbfbb0dc55da94d56c11f995e8d95426cc19511aa3e193797c9e41cff0d6a2` |
| `libqfli_mysql_launcher.so` | 22560 | `ef54810dfeff3260e8563dd1c19cccc7c09ecd1e0ea569de09ca700d6f9ed76c` |
| `libapp.so` (AOT) | 12305328 | `26ed00fa31463fa49632b7e522ed9205a38e31aba9f9b439f6273b68d7681e49` |

### New fence verified (server image)

- `-DHAVE_IB_GCC_ATOMIC_THREAD_FENCE=1` present in innobase `flags.make`.
- Post-relink disassembly of `storage/innobase/.../lock0lock.cc.o` contains
  **28 `dmb`** instructions → `os_rmb`/`os_wmb` compile to real ARM barriers.
- Proto image `NEEDED` = **`libc.so` only**; dynamic exports = exactly
  `qfli_mysql_child_main@@QFLI_MYSQL_SERVER_1.0`, `QfliMysqlMain@@…`,
  `qfli_mysql_record_exit@@…`, no others.

`package-runtime.cmake` ran and emits all 4 libs (incl. proto). `rawfile/mysql/`
unchanged (73 files, 5,139,034 bytes).

## 2. OHOS release HAP — COMPILES + PACKAGES; signing blocked (unchanged root cause)

- `flutter build hap --release --target-platform ohos-arm64` → ArkTS Ok,
  CMake Ok, PackageHap Ok, `PackingCheck` Ok; **fails only at
  `:entry:default@SignHap`**.
- Direct `hvigorw assembleHap -p product=default -p buildMode=release --no-daemon`
  (per user suggestion, using Flutter-generated assets) reproduces the **same
  single failure** — not a Flutter-tool crash, a genuine signing config error:
  ```
  ERROR: Failed :entry:default@SignHap
  00303107 Configuration Error
  Invalid storeFile value. Make sure it is not null or empty. The file must be
  included in
  'C:\Users\lichengyu\.ohos\config\default_ohos_atLNRYMqojeWBzAE5Xsd0aBTQux6Ptm1YtuqBYW5IQg=.p12'
  At file: D:\MyNewProjects\qfli_sql\ohos\build-profile.json5
  ```
- Flutter crash stack head/tail saved (`flutter_09.log`): the exception is just
  `ProcessException` wrapping `hvigorw` exit 1; the substantive error is the
  `SignHap` configuration error above. No other exception.

### Fresh unsigned HAP (final)

`ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`
— **192,985,687 bytes**, SHA256
`AAEBBDA701041BDBD78A07AB199EB2CD4A669976E907D8C16F0B48EFB6B2BBD8`,
2026-10-15 18:55.

### Signing-material audit (exhaustive)

Ran `hap-sign-tool.jar verify-profile` on **every** `*.p7b` under `~/.ohos`:

| Profile | bundle-name |
| --- | --- |
| `default_ohos_Gu8zVby71b0t4gfRa-4NpIdkL2QGfz2fVEJ7JnRdkBg=` | `com.azurekiln.qfli.jvmx` |
| `default_ohos_udwsx4szjsVYdfsIlGUHNWjABzLiV5jMmp6fUlekYQM=` | `com.azurekiln.cloudterminal` |
| `default_ohos_weTSdRQhDd0CYsbdTNnMl7u-9OyyrAJo7t072jC8Yw4=` | `com.azurekiln.qfli.forge` |

**No `com.azurekiln.qfli.sqlab` provisioning profile exists on disk.** The one
referenced by `ohos/build-profile.json5` was deleted. Cannot sign or install the
HAP until a sqlab-bound profile is (re)generated in DevEco, or
`build-profile.json5` is repointed to a valid sqlab profile. No signing material
was fabricated; `build-profile.json5` was not edited.

Note: even when signed, the auto-generated profile is a **debug** profile →
sideload/test only, not store-eligible.
