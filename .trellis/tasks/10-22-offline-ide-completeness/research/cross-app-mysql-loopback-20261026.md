# Research: Cross-app MySQL loopback

- Query: Serve sibling OHOS apps at 127.0.0.1:3306, preserving Unix clients.
- Scope: internal, source only.
- Date: 2026-10-26

## Findings

Optional TCP loopback is a plausible extension of the owned Oracle MySQL 8.4.6 server. Other apps use separate clients/accounts. Current code does not implement or prove sharing.

### Files found and code patterns

- ohos/entry/src/main/ets/plugins/QfliMysqlRuntime.ets:138 owns filesDir/mysql and mysql.sock. Lines 194 and 507 queue queries and coalesce lazy startup. No explicit service-start API exists.
- QfliMysqlRuntime.ets:536 rewrites config and manages a version-only initialization marker. Production initialization adds --initialize-insecure at 648; probe path does so at 488.
- QfliMysqlRuntime.ets:573 adopts a server after socket SELECT VERSION. Lines 601-625 check exit/status and socket readiness. This does not prove listener/config identity.
- QfliMysqlRuntime.ets:752 reads startup logs. Configuration at 770 preserves socket, sets skip-networking at 781 and max-connections=16 at 789. No explicit TCP bind/port or X listener option appears.
- native/src/qfli_mysql_client.cpp:111 forces MYSQL_PROTOCOL_SOCKET. Line 113 disables TLS. Line 142 hardcodes root and accepts password. Default query at 159 passes empty password at 164; shutdown at 167-169 and script at 175 do likewise.
- native/src/qfli_mysql_client.h:52 has password-aware query/shutdown/script overloads, without general username parameter.
- ohos/entry/src/main/cpp/qfli_mysql_napi.cpp:136 calls no-password script/shutdown/query overloads at 136-140.
- ohos/entry/src/main/ets/plugins/QfliMysqlNative.ets:9 exposes private Flutter query/executeScript/stop. lib/mysql_database.dart:17 routes OHOS there. Desktop is separate: lib/local_mysql_runtime.dart:216 disables networking and mysqlx at 217.
- ohos/entry/src/main/ets/entryability/EntryAbility.ets:25 disposes on destruction. QfliMysqlRuntime.ets:223 gates queries during stop; :267 attempts socket shutdown before bounded escalation and retains uncertain ownership.
- ohos/entry/src/main/cpp/qfli_mysql_proto_probe.cpp:37 exits child after parent death. Legacy launcher mirrors it at native/mysql/qfli_mysql_launcher.cpp:47.
- ohos/entry/src/main/module.json5:37 requests clipboard only, without INTERNET.

### Proposed minimum architecture

1. Add optional sharing state and explicit start/stop/status to ArkTS runtime/channel. Enabled config proposes bind-address=127.0.0.1 and port=3306, preserving Unix socket and explicitly disabling X protocol. Disabled config keeps skip-networking. Verify bundled options. Never bind LAN as fallback.
2. Provision before TCP exposure. Insecure initialization plus empty root must never become reachable, even briefly. No account/bootstrap SQL exists here. Conservative flow: socket-only start, secure admin and provision sibling accounts, confirmed stop, TCP-enabled restart. Failure retains socket-only mode. Existing data needs idempotent auth migration; version marker alone is insufficient.
3. Reuse password-aware native overloads but extend NAPI jobs/ArkTS interfaces, which omit passwords. Propagate admin secret to query/script/shutdown/readiness after securing root. Keep secrets private and out of logs. Never export root. General-user native access also requires username support.
4. Give each sibling a password-protected account, selected schema/action grants and revoke/rotate. lib/mysql_workspace_repository.dart:101 prefix checks are client conventions, not authorization. Direct clients bypass them. Loopback does not identify app bundles. Verify account host matching and authentication compatibility.
5. Preserve ownership/diagnostics. Port collision must be visible. Socket readiness cannot prove 3306 is ours or authenticates the intended user. Future acceptance must establish TCP/config identity. Never adopt/kill another listener or silently change port. Existing-server adoption requires owned restart/config policy.
6. UI/API exposes endpoint, account management and truthful state. Explicit start must work without an editor query. This app-owned architecture does not inherently need a shared-core rewrite.
7. Determine both apps' OHOS permissions; adjust manifest/archive policy narrowly if required. Preserve cloud/login/browser/download refusals. Permission declaration alone proves no cross-app access.

### Bootstrap / authentication caveats

No init-file mechanism exists. Source inspection did not establish upstream init-file ordering or fail-closed listener behavior. Do not assume init-file protects empty root. Prefer socket-only provisioning and confirmed stop/restart until ordering is proven. Keep SQL/secret files private and absent from diagnostics.

RSA key retrieval exists only for Windows pipes at native/src/qfli_mysql_client.cpp:124-131. Internal Unix TLS settings do not prove TCP sibling authentication. Validate actual caching_sha2_password/TLS/RSA compatibility; do not blindly select obsolete authentication.

### Checks and public claims

- integration_test/mysql_ohos_probe.dart:363 requires skip_networking=1. Separate private-default and opted-in profiles.
- integration_test/support/sql_curriculum_runtime.dart:248 requires no listener. Keep default private. integration_test/mysql_native_test.dart:78 reads network identity; desktop stays separate.
- tool/ohos/inspect_audit_hap.py:48 requires clipboard-only permissions at 50-51. Fixtures: tool/ohos/test_inspect_audit_hap.py:134 and :329.
- tool/test_sql_offline_platform.cjs:330 disclaims device/network coverage. UI refusal checks do not prove TCP.
- Preserve cloud refusal: test/sql_offline_policy_test.dart, lib/sql_engine_preference.dart:29 and lib/cloud_mysql_database.dart:23/:48.
- README.md:110/:202 promises skip-networking/no INTERNET. Revise with real opt-in behavior/evidence; do not claim proven cross-app/background access.

### Lifetime and related specs

Destruction disposes the runtime and parent death ends the child. TCP cannot create a persistent system service. No background contract was found in EntryAbility. App switch, locking, suspension, kill and restart need target acceptance. Preserve watchdog cleanup. Internal and sibling clients share the current 16-connection cap.

Read .trellis/workflow.md and backend/frontend indexes. Relevant specs: backend/mysql-ohos-runtime.md, backend/mysql-workspace.md, frontend/native-startup.md, frontend/sql-terminal-offline.md and backend/ohos-audit-packaging.md:124. Older phone-host prohibition in mysql-workspace.md conflicts with newer runtime spec/source. Task prd.md clarification dated 2026-10-26 records requested sharing and separate acceptance.

### External references / versions

No browsing under source-only dispatch. Oracle version is 8.4.6 at QfliMysqlRuntime.ets:112. Official permission, cross-app loopback, background, init-file, account matching and authentication claims need document review and target proof. Historical socket probes do not prove sharing.

## Caveats / Not Found

- Only this research file was written. No implementation, scripts, tests, SDK, builds, device, hdc or channel actions.
- No sharing UI, account provisioner or NAPI credential path was found.
- Cross-app reachability and background availability remain unproven.
- Preserve data/WIP. Do not reset databases, remove all offline guards or expose passwordless root.
