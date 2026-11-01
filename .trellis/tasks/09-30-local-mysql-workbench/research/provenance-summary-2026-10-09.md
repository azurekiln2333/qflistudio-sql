# Provenance summary — MySQL production host (2026-10-09)

## Source -> native -> HAP identity

Source frozen at 2026-10-09 18:40; native staged 19:22; both HAPs built from that
frozen source and the fence native set.

### Source files (SHA256)
- `ohos/entry/src/main/ets/plugins/QfliMysqlRuntime.ets` aaa1bb341c432a89f2ba339456399daf4562b2458f1664de66812dcffb82dec1
- `ohos/entry/src/main/ets/plugins/QfliMysqlNative.ets` 8bdcb97132a319b9f7e520d037a2c2597103bbb45afa4c5456770ac9d17a33f3
- `ohos/entry/src/main/cpp/qfli_mysql_napi.cpp` e64b17cbde08278ce1d3073693a04232495bdae0900bbf61dd4fa140166108c5
- `ohos/entry/src/main/cpp/qfli_mysql_proto_probe.cpp` bf6cfbaac520653f6c4e9292999962e397285a532e521460ba3950575642786c
- `ohos/entry/src/main/cpp/qfli_mysql_proto_probe.h` 009e1ecd8e25876f04768b2ada11a5d9bc08dec5f5f91d5eea3428e37ab57f19
- `native/mysql/qfli_mysql_host.cpp` 934d1d372a1adf38bf747dbc6065aa939cb7d6d4a6e6dc5cbde25afeec5a1ac2
- `native/mysql/qfli_mysql_host.h` 9eb940a0540e73783171a8d0c8c90695fcab13fee40730f12aa2d41a15c5d9b8
- `native/mysql/qfli_mysql_stdio_protocol.h` b03c55d465d43e1f560647b7ba33f15da0fa78c05243b90228bb35553499082f
- `native/mysql/qfli_mysql_server_proto.cpp` a75178792b78ff27e7e9f06360afaf69a644d04678a70fb8a86fc0c462311842
- `native/mysql/qfli_mysql_server_proto.map` 0e63de411aa8f4c802f1e2d7dee9062c9079605fb7e6e33201ea93f1cefdc9a8
- `native/mysql/qfli_mysql_server.map` c284f18372c7e2c17458192152d977fa3b497551fdb159306b8f4fa7b6c23f51
- `native/mysql/ohos-targets.cmake` d5a398360d25dfb36c2665a598a363792eb01ba7bee7626dfce0c125004f5127
- `native/mysql/build-mysql-ohos.sh` cf48ac0db36a4c967f6d3c2d7ec22b599b335c53122cbc74e3632fbaa05d68f8
- `native/mysql/package-runtime.cmake` 482aaed17f220eb3f65e2add685977ea9ae1089fabea56b69594cbe9013e4ea6
- `native/mysql/qfli_mysql_server.cpp` 99b67d14a2cfac9728b8dd67cb4433b9cd6c369270b628bfae0b1c3aa3fb32ea
- `ohos/entry/hvigorfile.ts` 867f20b09a60f2cfae093d97d2772b3003b0e4c41f3103217eba36dd630c18a3
- `native/CMakeLists.txt` 1a2b96e085314bdc63b0f603f25cda9d7815a031dc04c7df12eaaf6a01e0c977
- `integration_test/mysql_ohos_probe.dart` d5c3203132faefb9210c7606569e94eca05f493eabe08704abcf1a2e6a8ab786

### Native artifacts (staged 19:22)
`build/mysql-port/native-artifact-manifest.txt`:
- libqfli_mysql.so 15004600 e812c680f5cdb172d92b2cf78c31eddda8bce48d5c1d5be85d3a0bab1a8355d2
- libqfli_mysql_server.so 89004736 05fbfbb0dc55da94d56c11f995e8d95426cc19511aa3e193797c9e41cff0d6a2
- libqfli_mysql_server_proto.so 81011056 f216e6def30a0c761af6c13dd5a1c6dcd2dc90280605db8d0ebd342b668a2446
- libqfli_mysql_launcher.so 22560 ef54810dfeff3260e8563dd1c19cccc7c09ecd1e0ea569de09ca700d6f9ed76c

### HAP artifacts (`build/mysql-port/artifacts/`)
- `entry-fence-probe-20261009.hap` 263008835 e19c319d79df50e731e561e45baad18ac7f98167e657e809f3a0a79820047bc7
  built 19:59; installed on device; fence-delta probe run **pending unlock**.
- `entry-normal-main-20261009.hap` 274055738 5f70e8f3a2ead1b34d3b0e1f680aa38cad771409ee303494d8b4f17158236480
  built 20:05 from the held core checkpoint; **retained, not installed**.

## Progressed acceptance results (distinguish clearly)

- Run `1791542089201247_c1326982907f1eee` — **12/12 PASS** (pre-fence native set,
  exec->preload host transition). `build/mysql-port/preload-attempt4/`.
- Run `1791543204596329_6d7175e0ff852321` — **12/12 PASS** (production host config,
  pre-fence). `build/mysql-port/prod-revalidation/`.
- **Fence-delta revalidation — PENDING** (requires fresh START/runId after phone
  unlock; the 19:59 install succeeded but `aa start` returned 10106102 screen-lock).
- **Normal-app (main.dart) acceptance — PENDING** (HAP retained, not installed).

## Changed-file summary within task ownership

Native/host (new): `qfli_mysql_host.{h,cpp}`, `qfli_mysql_launcher.cpp`,
`qfli_mysql_server_proto.cpp`, `qfli_mysql_server{,_proto}.map`,
`qfli_mysql_stdio_protocol.h`, `qfli_mysql_proto_probe.{h,cpp}`.
Native (changed): `qfli_mysql_server.cpp`, `ohos-targets.cmake`,
`build-mysql-ohos.sh` (fence), `package-runtime.cmake`, `native/CMakeLists.txt`.
ArkTS (changed): `QfliMysqlRuntime.ets`, `QfliMysqlNative.ets`,
`qfli_mysql_napi.cpp`, `EntryAbility.ets`, `hvigorfile.ts`.
Tests/tools (new): `native/tests/*` (host stdio/fork tests, ctor/binding probes,
cold-backup scripts) and `integration_test/mysql_ohos_probe.dart`.
