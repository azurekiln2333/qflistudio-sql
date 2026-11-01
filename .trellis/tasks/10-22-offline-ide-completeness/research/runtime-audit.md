# Read-only runtime / quality audit (bounded)

Task: `.trellis/tasks/10-22-offline-ide-completeness`
Author: read-only runtime reviewer (Pi). Date: 2026-10-22.
Scope per `research/pi-runtime-review-brief.md`. This document is the only file written.

**Audit is bounded here.** Everything below was observed in this session. No product
source, core, assets, git state, build output, device lifecycle, or signing material was
created or modified. Values copied from older reports are labelled `HISTORICAL`.

---

## 0. What was NOT done (and must stay a root decision)

- No `flutter build`/`hvigorw`, no `flutter test`, no CMake/ninja invocation, no install,
  no app start/stop, no `hdc` daemon restart, no uninstall, no signing-key generation.
- No writes to `ohos/build-profile.json5`, `ohos/entry/build-profile.json5`,
  `native/**`, `tool/**`, `assets/**`, `integration_test/**`, `lib/**`.
- No credentials printed. `build-profile.json5` password fields were never read out;
  only filenames/hashes and p7b bundle names were inspected.

---

## 1. Current environment (verified this session)

| Fact | Value | How observed |
| --- | --- | --- |
| Flutter | `3.27.5-ohos-1.0.1`, Dart 3.11.5 | `flutter --version` |
| Device target | `127.0.0.1:5555`, `ohos-x64`, `Ohos OpenHarmony-7.0.0.105 (API 26)` | `flutter devices` |
| Device model / ABI | `emulator`, `const.product.cpu.abilist = x86_64` | `hdc shell param get` |
| Device UDID | `454D55057494E058383602DD9C05BCD9E4026BE286E3F6B3CC57700000000000` | `hdc shell bm get -u` |
| Device software | `7.0.0.107(SP8DEVC00E999R4P11)` | `param get const.product.software.version` |
| SDK (DevEco) | HarmonyOS `26.0.0.105` / API 26 (`sdk\default\{hms,openharmony}`) | `sdk-pkg.json` |
| SDK (standalone) | `OpenHarmony\Sdk\20`, `OpenHarmony\Sdk\23\native` (clang resource 15.0.4) | dir listing |
| Apple/x86 sysroots | `aarch64-linux-ohos`, `arm-linux-ohos`, `x86_64-linux-ohos` in **both** SDKs | dir listing |
| MySQL local port root | `build\mysql-port\{mysql-8.4.6, openssl-ohos, host-build, ohos-build, package}`; `package\libs\` = **arm64-v8a only** | dir listing |
| SQLite version in tree | `SQLITE_VERSION "3.50.0"` (`native/third_party/sqlite/sqlite3.h`) | file read |
| Existing HAP | `ohos\entry\build\default\outputs\default\entry-default-unsigned.hap`, 189,845,889 B, 2026-10-17, entries **only** `libs/arm64-v8a/*` (+ `module.json`, `pack.info`) | zip entry listing |
| ADB devices | none attached | `adb devices -l` |
| Host MySQL | no `mysql` CLI, no `mysqld` binary, no 3306 listener, no MySQL service | PATH/service/port check |
| Installed SQL app on emulator | `com.azurekiln.qfli.sqlab` present, `appProvisionType: debug`, `cpuAbi: x86_64`, `nativeLibraryPath: libs/x86_64`, versionCode 1 | `hdc shell bm dump -n ...` |

### 1.1 Baseline dirty state (must be preserved, not "fixed")

`.trellis/tasks/10-22-offline-ide-completeness/research/baseline-git-status.txt` already
lists — before any worker started — both:

- `M ohos/build-profile.json5` — signing material repointed `EyK2s6z…` (HEAD) → `atLN…` (worktree).
- `M ohos/entry/build-profile.json5` — `abiFilters: ["arm64-v8a","x86_64"]` (HEAD) →
  `["arm64-v8a"]` **plus** `nativeLib.filter.excludes: ["**/x86_64/**"]` (worktree).

Consequence: the current worktree **cannot build a runnable HAP for the x86_64 emulator**
even if signing worked. HEAD's committed value is the emulator-capable one. This is a
baseline-WIP conflict, not a new worker regression, and not mine to change.

### 1.2 Signing — current facts, no SQL profile exists

`~/.ohos/config` holds 6 profile sets; `hap-sign-tool verify-profile` bundle names:

| Profile | bundle-name | type |
| --- | --- | --- |
| `Gu8zVby…` | `com.azurekiln.qfli.java` | debug |
| `GxYLofwt…` | `com.azurekiln.qfli.script` | debug |
| `H2qDWxiv…` | `com.azurekiln.qfli.dartwing` | debug |
| `PCM4VcSp…` | `com.azurekiln.qfli.go` | debug |
| `udwsx4sz…` | `com.azurekiln.cloudterminal` | debug |
| `weTSdRQh…` | `com.azurekiln.qfli.cpp` | debug |

- The worktree references `default_ohos_atLN…{cer,p7b,p12}` — **absent**.
- HEAD references `default_ohos_EyK2s6z…` — **also absent** (and that name is the one used
  by `qfli_note`/`qfli_rust` too, both missing).
- **No profile on disk binds `com.azurekiln.qfli.sqlab`.** Any sibling profile reuse would
  bind the wrong bundle name and is excluded by the brief.
- Therefore: signed HAP install on the emulator is **blocked at present**, and the
  already-installed x86_64 debug build cannot be reproduced from this tree.

Offline candidate (investigated only, **not generated, not installed**):
`OpenHarmony\Sdk\23\native\toolchains\lib` (and the same folder in the DevEco SDK) ships
`OpenHarmony.p12`, `OpenHarmonyProfileDebug.pem`, `UnsgnedDebugProfileTemplate.json`.
A locally signed debug profile can be produced with `hap-sign-tool sign-profile` by
setting `bundle-info.bundle-name = com.azurekiln.qfli.sqlab` and
`debug-info.device-ids = [<UDID above>]`. Whether this emulator trusts the OpenHarmony
root CA is **unverified**; establishing it requires one install attempt, which is root
lifecycle. Do not treat as PASS.

---

## 2. Narrow question: can the WSL MySQL port build **Oracle 8.4.6 for x86_64 OHOS**
into a **new isolated build dir** without touching arm64 outputs?

**Answer: yes, architecturally — but not with the current scripts unmodified.** The
compiler/triple/config model is portable; five concrete files encode aarch64 assumptions
and must be given x86_64 variants. Nothing in the patch set is aarch64-only, and the one
arch-sensitive InnoDB code path is already neutralized for any `__OHOS__` target.

### 2.1 Verified reusable pieces (already on disk)

| Piece | Location | State |
| --- | --- | --- |
| Patched Oracle source | `build/mysql-port/mysql-8.4.6` (D:, 1.2 G) and `/root/qfli-mysql-port/mysql-8.4.6` (ext4, 1.2 G) | present; `patches/0001-ohos-platform.patch` already applied (no `.git`) |
| Host generator tools | `/root/qfli-mysql-port/host-tools/{comp_err,comp_client_err,comp_sql,uca9dump,gen_lex*,protoc}`, also `build/mysql-port/host-build/runtime_output_directory` | present → `QFLI_MYSQL_HOST_TOOLS` reuse avoids rebuilding host tools |
| Full prior aarch64 build tree | `/root/qfli-mysql-port/ohos-build` (1.2 G) + `qfli-runtime/lib/{libqfli_mysql,libqfli_mysql_server,libqfli_mysql_server_proto,libqfli_mysql_launcher}.so` | present, 177 M of runtime libs |
| SDK partial copy on ext4 | `/root/qfli-mysql-port/ohos-sdk` (548 M) | has `sysroot/usr/lib/{aarch64,arm,x86_64}-linux-ohos` **including** `libace_napi.z.so` for x86_64; **missing** `llvm/lib/x86_64-linux-ohos/c++/libc++_static.a` and `libunwind.a` (both exist in `/mnt/d/...OpenHarmony/Sdk/23/native` and the DevEco SDK) |
| Dependency coverage | `libsasl2.so, libldap.so, liblber.so, libncursesw.so, libz.so, libcrypto.so, libssl.so, libicuuc.so, libace_napi.z.so, libhilog_ndk.z.so` | **present for both arm and x86** in the SDK sysroot |
| Toolchain binaries | WSL distro `qfli-java-build`: `/usr/bin/clang-18`, `clang++-18`, `llvm-ar-18` etc. | present |
| Disk | ext4 `/`: 884 G free; `D:` only 35 G free | `df -h` |
| CPU/RAM | 24 cores, 15 G | `nproc`, `free` |

### 2.2 The patch is already x86_64-OHOS safe

`patches/0001-ohos-platform.patch` on `storage/innobase/include/ut0crc32.h` inserts

```c
#if defined(__OHOS__)
#define CRC32_DEFAULT
#elif defined(__GNUC__) && defined(__x86_64__) || defined(_WIN32)
#define CRC32_x86_64
```

verified this session: `/usr/bin/clang-18 --target=x86_64-linux-ohos -dM -E -x c /dev/null`
defines **both** `__OHOS__ 1` and `__x86_64__ 1`. So an x86_64 OHOS build takes
`CRC32_DEFAULT` (portable software CRC) and does **not** enter the x86 hardware-CRC/SSE4.2
path — no new cpuid/intrinsic risk. Other hunks (editline bypass, host-tool import,
`QFLI_MYSQL_WITHOUT_ZSTD_DICT_BUILDER`, `HAVE_FALLOC_FL_ZERO_RANGE`, boost `__OHOS__`)
are architecture-neutral.

### 2.3 What must differ for x86_64 (exact deltas, not applied)

1. **`native/mysql/ohos-toolchain.cmake`** — currently hardcodes
   `CMAKE_SYSTEM_PROCESSOR aarch64`, `*_COMPILER_TARGET aarch64-linux-ohos`,
   `CMAKE_LIBRARY_PATH .../aarch64-linux-ohos`, and `-L.../aarch64-linux-ohos`.
   Needs an x86_64 sibling (e.g. `ohos-toolchain-x86_64.cmake`) with:
   ```
   set(CMAKE_SYSTEM_NAME Linux)
   set(CMAKE_SYSTEM_PROCESSOR x86_64)
   set(CMAKE_C_COMPILER_TARGET   x86_64-linux-ohos)
   set(CMAKE_CXX_COMPILER_TARGET x86_64-linux-ohos)
   set(CMAKE_SYSROOT $SDK/sysroot)
   # C_FLAGS_INIT: -resource-dir=$SDK/llvm/lib/clang/15.0.4
   # CXX_FLAGS_INIT: ... -stdlib=libc++ -nostdinc++ -isystem $SDK/llvm/include/libcxx-ohos/include/c++/v1
   # EXE/SHARED_LINKER_FLAGS_INIT: -fuse-ld=lld -L$SDK/llvm/lib/x86_64-linux-ohos
   # CMAKE_LIBRARY_PATH: $SDK/sysroot/usr/lib/x86_64-linux-ohos ; $SDK/llvm/lib/x86_64-linux-ohos
   ```
   (`llvm/include/libcxx-ohos` exists in the same SDK layout the arm64 build used.)

2. **`native/mysql/ohos-targets.cmake`** — hard-fails unless processor is `aarch64`, and
   links `${QFLI_OHOS_SDK}/llvm/lib/aarch64-linux-ohos/{c++/libc++_static.a,libunwind.a}`.
   An x86_64 variant needs the same two inputs from `.../x86_64-linux-ohos/...`
   (both files exist in the D: SDKs; they are simply absent from the earlier ext4 copy).
   Everything else (`-Bsymbolic-functions`, `--version-script`, `-nostdlib++`,
   `--no-undefined`, `-rpath,$ORIGIN`) is arch-neutral.

3. **`native/mysql/build-openssl-ohos.sh`** — hardcodes `--target=aarch64-linux-ohos`,
   `perl Configure linux-aarch64`, `-L.../aarch64-linux-ohos`, and the aarch64 smoke
   object. x86_64 needs `--target=x86_64-linux-ohos` and
   `perl Configure linux-x86_64 no-shared no-tests no-docs no-apps --prefix=<x86 prefix>`.
   The **existing `build/mysql-port/openssl-ohos/{libssl.a,libcrypto.a}` are aarch64** and
   cannot be reused — this is the only genuinely expensive extra compile step
   (`make -j1 build_libs install_dev`; prior run left a 36 M build dir).
   Note `linux-x86_64` pulls x86_64 asm; OHOS is ELF/musl and the toolchain supplies lld,
   so this is expected to work but is the highest-risk unknown of the whole plan.

4. **`native/mysql/package-runtime.cmake`** — hardcodes
   `QFLI_MYSQL_PACKAGE_LIBS .../package/libs/arm64-v8a` and rejects any ELF whose
   `FileSummary.Arch` is not `aarch64`. An x86_64 run must use a **separate port root**
   (so this file's outputs land elsewhere) or an arch-parameterized copy; otherwise it
   would write x86_64 libs into the shared `package/libs/arm64-v8a` and abort on the arch
   check anyway.

5. **`native/CMakeLists.txt` (HAP side)** — the ARM64 branch consumes
   `build/mysql-port/package/libs/arm64-v8a`; every other ABI compiles
   `src/qfli_mysql_unavailable.cpp` (confirmed in the OHOS x86_64 ninja file:
   `CMakeFiles/qfli_mysql.dir/src/qfli_mysql_unavailable.cpp.o`). To ship a real x86_64
   engine the HAP build needs a second staging path and an arch-aware branch. Until then the
   emulator stub returns
   `"The bundled Oracle MySQL runtime requires a HarmonyOS arm64 device."` (`error_code 127`).

### 2.4 Minimal flag set for an isolated x86_64 configure (for review, not run)

Reuse of the arm64 command line in `build-mysql-ohos.sh` is valid; only these change:

```
-DCMAKE_TOOLCHAIN_FILE=<repo>/native/mysql/ohos-toolchain-x86_64.cmake
-DQFLI_OHOS_SDK=/mnt/d/ProgramFiles/Huawei/OpenHarmony/Sdk/23/native   # or fixed ext4 copy + 2 missing libc++ files
-DQFLI_CLANG=/usr/bin/clang-18 -DQFLI_CLANGXX=/usr/bin/clang++-18
-DQFLI_MYSQL_PLATFORM_CMAKE=<repo>/native/mysql/ohos-targets-x86_64.cmake
-DQFLI_MYSQL_HOST_TOOLS=/root/qfli-mysql-port/host-tools        # reuse; skip host build
-DWITH_PROTOC=/root/qfli-mysql-port/host-tools/protoc
-DWITH_SSL=system -DOPENSSL_ROOT_DIR=<x86_64 openssl prefix>
-DOPENSSL_INCLUDE_DIR=<...>/include
-DOPENSSL_SSL_LIBRARY=<...>/lib/libssl.a -DOPENSSL_CRYPTO_LIBRARY=<...>/lib/libcrypto.a
-DWITH_EDITLINE=system -DWITH_SASL=system -DWITH_LDAP=system
-DWITH_TIRPC=bundled -Dprotobuf_BUILD_SHARED_LIBS=OFF -Dprotobuf_BUILD_LIBPROTOC=ON
-DWITH_ROUTER=OFF -DWITH_MYSQLX=OFF -DWITH_NDB=OFF -DWITH_NDBCLUSTER_STORAGE_ENGINE=OFF
-DWITH_GROUP_REPLICATION=OFF -DWITH_UNIT_TESTS=OFF
-DWITH_AUTHENTICATION_{CLIENT_PLUGINS,LDAP,KERBEROS,WEBAUTHN}=OFF
-DWITH_NUMA=OFF -DWITH_SYSTEMD=OFF -DWITH_KERBEROS=none -DWITH_FIDO=none -DWITH_CURL=none
-DWITH_EXT_BACKTRACE=OFF -DUSE_BISON_RESULTS_FROM_MAKE_DIST=ON
-DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS_RELEASE="-O1 -DNDEBUG"
-DCMAKE_CXX_FLAGS_RELEASE="-O1 -DNDEBUG"
-DHAVE_SETNS=FALSE -DHAVE_CLOCK_GETTIME=FALSE -DHAVE_CLOCK_REALTIME=FALSE
-DHAVE_FALLOC_PUNCH_HOLE_AND_KEEP_SIZE=FALSE -DHAVE___BUILTIN_FFS=FALSE
-DHAVE_IB_GCC_ATOMIC_THREAD_FENCE=TRUE
```

Isolation requirements (so arm64 artifacts are untouched):
- `QFLI_MYSQL_PORT_ROOT` **must** point at a new root, because `build-mysql-ohos.sh` derives
  `host-build`, `openssl-ohos`, `ohos-build`, `package` from it. `TARGET_BUILD` is not
  independently overridable; a *copied* script (new file, e.g.
  `research/x86-build-mysql-ohos.sh`) with `TARGET_BUILD="$PORT_ROOT/ohos-build-x86_64"`
  and a new port root is the safe shape. The verified arm64 tree
  (`/root/qfli-mysql-port`, `build/mysql-port/package`, `ohos/entry/libs/arm64-v8a`) must not
  be a target of any of those variables.
- `prepare-source.sh` needs `$PORT_ROOT/mysql-8.4.6.tar.gz` for its SHA-256 gate; that
  archive is **not present** (only `openssl-3.5.3.tar.gz` is). A new port root therefore
  either needs the MySQL source archive (~450 MB, network) or the gate bypassed by pointing
  at the existing, already-patched source tree (acceptable because the patch set is pinned
  and `git apply --reverse --check`-idempotent).
- Estimated new-tree footprint: source copy/re-extract ≈1.2 G + build ≈1.2 G + OpenSSL
  ≈40 M + runtime libs ≈180 M + staging ≈180 M ⇒ **~2.8–3 G**. Put it on ext4 (884 G free),
  **not** `D:` (35 G free).
- Build cost: the arm64 build ran single-target, `-j1` steps; expect a long serial build
  (hours) — not something to start inside this task without root scheduling.

### 2.5 Residual risk on the emulator specifically

- Everything above makes a real Oracle 8.4.6 **x86_64 OHOS** image *buildable*; it does not
  prove it **runs** on the emulator. The private preload host (fork + `dlopen` of a
  symbolically bound image) is arch-neutral in principle, but the API-26 sandbox results in
  `spec/backend/mysql-ohos-runtime.md` were measured on an arm64 phone, not this emulator.
- The emulator is API 26 / OpenHarmony 7.0; the SDK is API 23/26. Same as the arm64 path.
- Therefore: even after a successful x86_64 build, the six MySQL lessons would be a *new*
  runtime acceptance case requiring a live run — not a substitute for the arm64 phone
  evidence the spec demands.

---

## 3. Real-Oracle options for the six MySQL lessons (IDs 121–126)

Current state: `validate_content.py` / `validate_assets.py` execute 120 SQLite lessons and
240 exercises against `D:\ProgramFiles\platform-tools\sqlite3.exe` and print
`mysql not executed: 6` (SKIP for 121–126). That is the honest current state; the six
lessons have **no** fresh Oracle evidence anywhere today.

| Option | Status today | Notes |
| --- | --- | --- |
| arm64 HarmonyOS phone (MRT-AL10, preload host) | Not connected | Only path that satisfies `mysql-ohos-runtime.md`; needs root + signing |
| Android arm64 phone (OPD2413 / integrationtest package) | Not connected (`adb devices` empty) | `HISTORICAL`: 6 lessons + 6 exercises passed at `30ee9cb` (Android) — not OHOS proof |
| Android **x86_64** emulator | Not running; no x86_64 Android MySQL staging in tree | `native/mysql/android/README.md` documents x86_64 support and a 2026-10-02 x86_64 API 37 pass (`HISTORICAL`); would need `configure.sh`/`stage.ps1 -Abi x86_64` |
| OHOS x86_64 emulator (this device) | Stub only (`error_code 127`) | Requires §2 work; then unproven runtime |
| Host mysqld | None installed | `host-build` contains only generators; no server binary |

Recommendation for the ledger: keep R2/R3 MySQL rows **open/unproven** until an arm64 run
(with IDENTITY showing `8.4.6`, `@@skip_networking=1`, private socket) is captured.

---

## 4. OHOS SQLite native test path — what is usable, what blocks

Usable today in principle (no MySQL needed):

- `qfli_sql/native` NAPI registers `execute`, `executeScript`, `query`
  (`ohos/entry/src/main/cpp/qfli_sql_napi.cpp:439-442`), and `executeScript` returns a
  structured `results[]` with `columns/rows/affectedRows/truncated/exitCode` — enough for
  authored-output comparison of multi-statement curriculum scripts.
- `NativeSqliteDatabase.executeScript` routes multi-statement scripts to that entry point
  and explicitly skips `Directory.create` for `:memory:` (`lib/sql_database.dart`), so a
  curriculum pass needs **no device storage** and mutates no user database.
- `native/CMakeLists.txt` compiles real `sqlite3.c` for **any** ABI; only `qfli_mysql` is
  stubbed. So an x86_64 HAP would carry a real SQLite 3.50.0 and a stub MySQL.

Blocking, in order:

1. **Signing** (§1.2) — no sqlab profile ⇒ cannot install anything.
2. **ABI** (§1.1) — worktree `abiFilters`/`nativeLib.filter` excludes x86_64 ⇒ the package
   would contain only arm64 libs and be uninstallable on `libs/x86_64`.
3. **MySQL test separation** — the current catalog-driven target registers **one** test per
   engine (`for (final engine in ['sqlite','mysql'])`), so on the emulator the `mysql` case
   must fail by design (stub). That is honest, but it means an emulator run can never be a
   green suite, and a single early SQLite failure aborts the remaining ~360 scripts because
   they share one `testWidgets`.

---

## 5. Review of the native coverage design (`integration_test/sql_curriculum_native_test.dart`
+ `integration_test/support/sql_curriculum_support.dart`, work in progress)

Verified as good:

- Coverage is **derived from the shipped catalog**, not hardcoded: `curriculumCases(catalog)`
  iterates `catalog.examples`, joins `sourceLessonId` → lesson, and asserts
  `allCases.length == content.examples.length`. The old hardcoded `[121..126]` list is gone.
- Drift is rejected **before** execution: duplicate/missing example or lesson ids,
  `example.code != lesson.code`, `example.expectedOutput != lesson.output`, unknown
  `engine`, missing `exerciseSetup`, missing/short/blank `exerciseExpectedOutputs`.
  `coveredLessons.length != lessons.length` catches an unpaired lesson.
- Both script families are covered per example: `lesson` (`example.code` vs
  `example.expectedOutput`) and each `exercise` (`setup + answer` vs authored expectation),
  each in a **fresh** schema (`CREATE DATABASE` with no `IF NOT EXISTS`) or fresh
  `:memory:` connection.
- `verifyCurriculumOutput` refuses to count unavailable/truncated/partial/error results as a
  pass, requires at least one query result, and makes `(no rows)` mean *exactly* zero rows
  (a NULL row cannot pass) — mirrored by the host test
  `test/sql_curriculum_native_coverage_test.dart`.
- `QFLI_SQL_CURRICULUM_NATIVE IDENTITY/PASS/EXAMPLE_PASS/ENGINE_COMPLETE/CATALOG` markers give
  per-entry evidence, and the identity gates are honest (`sqlite_version() LIKE '3.50.%'`,
  MySQL `VERSION()='8.4.6'`, no MariaDB, `@@skip_networking=1`, socket/PID inside the owned
  root).
- Isolation is sound: owned `createTemp` root, `<runId>`-qualified schemas, PID-file check
  before deletion, `RETAINED` on timeout (never deletes a root whose native SQL may still be
  running).

Findings / risks to review before acceptance:

1. **Failure isolation regressed vs the previous design.** Six separate `testWidgets`
   registrations became **one test per engine**. One mismatch in example 001 skips ~40
   further examples inside `sqlite`, and the same for `mysql`. Either re-register per example
   (`for (final entry in cases) testWidgets(...)`) or accept and document that a failure
   truncates coverage. The `CATALOG`/`ENGINE_COMPLETE` markers do **not** substitute for
   "every id produced a PASS" because the log simply ends early.
   *Review gate:* require `PASS` count == `engineScripts` from `CATALOG`, computed
   independently, before any green claim.
2. **Duplicate output-comparison logic.** MySQL goes through `_OwnedRuntime.verify` +
   private `_normalize`; SQLite goes through `verifyCurriculumOutput`. Two comparators can
   drift (e.g. `(no rows)` handling is identical today, but `_normalize` does not reject a
   NULL row where `verifyCurriculumOutput` does). Prefer one comparator fed by a
   `SqlScriptResult`.
3. **Script naming is positional.** `name: 'lesson_$number'` uses the array index, and the
   MySQL schema is `qfli_curr_<runId>_<name>`. Fine for MySQL's 64-char identifier limit, but
   the marker/schema does not name the example id in the schema. Logs do carry `exampleId`,
   so this is cosmetic — do not "fix" it into >64-char MySQL identifiers.
4. **Timeouts.** Per native call 4 min; whole engine test 30 min for ~120 examples × 3
   scripts. On the emulator with a stub MySQL this is fine; on a phone a slow first `CREATE
   DATABASE` could consume the budget — worth measuring rather than raising.
5. **`native/CMakeLists.txt` still has no x86_64 real-engine path** (§2.3 item 5); the HAP on
   any non-ARM64 target will always report the stub string. Ensure no acceptance text claims
   MySQL for the emulator.
6. Content side (other worker's scope, for the later review): drafts for IDs 127+ live only in
   `research/curriculum-drafts/track_{14..17}_*.py` with a valid isolated verifier
   (`verify_drafts.py`: real sqlite3 CLI, duplicate title/explain/code checks, normalized
   query fingerprint, asset-hash immutability guard). Promotion into
   `tool/sql_curriculum/lessons/` is auto-discovered by `build_content.load_lessons()`
   (`import_module("lessons.<name>")`), so a stale `__pycache__` or an out-of-range `number`
   is the main promotion hazard; `coverage.py` minima and `audit()` must be re-run after
   promotion.

---

## 6. Safe, precise command set for the next phases

Read-only / diagnostic (safe any time; no product writes):

```powershell
hdc list targets
hdc -t 127.0.0.1:5555 shell param get const.product.cpu.abilist
hdc -t 127.0.0.1:5555 shell param get const.ohos.apiversion
hdc -t 127.0.0.1:5555 shell bm get -u
hdc -t 127.0.0.1:5555 shell bm dump -n com.azurekiln.qfli.sqlab   # installed identity only
flutter devices
python tool/sql_curriculum/validate_content.py       # executed now: 120/120 sqlite, 240/240 exercises, 6 mysql SKIP
python tool/sql_curriculum/validate_assets.py        # executed now: same shape on packaged JSON
java -jar "<sdk>\default\openharmony\toolchains\lib\hap-sign-tool.jar" verify-profile -inFile <p7b>
```

Root-gated (lifecycle/signing/build — not run here):

```powershell
# 1. restore emulator-capable ABI for the SQL module (baseline WIP decision, HEAD value)
#    ohos/entry/build-profile.json5: abiFilters ["arm64-v8a","x86_64"], drop the x86_64 exclude
# 2. provide a sqlab-bound debug profile, then build
flutter build hap --debug -t integration_test/sql_curriculum_native_test.dart --target-platform ohos-x64 --no-pub
hdc -t 127.0.0.1:5555 install -r <hap>     # only with a valid signature and root approval
# 3. capture a per-entry log and require: CATALOG engineScripts == PASS count, ENGINE_COMPLETE,
#    IDENTITY sqlite 3.50.x, and for mysql (arm64 only) 8.4.6 + skip_networking=1
```

Never: sign with a sibling bundle's profile, fabricate a profile, install over the production
bundle without an isolated root, or claim OHOS acceptance from packaging.

---

## 7. Checklist for the later review of this delivery

- [ ] R2: every shipped example executed on current target/toolchain, per-entry markers,
      artifact hash recorded; host-only and skipped runs recorded separately.
- [ ] R2/R3: MySQL 121–126 have a real Oracle run (identity markers), never the stub string.
- [ ] R3: total ≥ 306 unique ids, source ↔ shipped JSON byte-identical, all exercises have
      authored expectations, `coverage.py` + `audit()` + draft verifier green.
- [ ] Coverage test: `PASS` count equals independently computed script count; failure
      isolation decision documented; single comparator after refactor.
- [ ] R5/R6/R11: tools/diagnostics route to real engines, no network, no user-data writes,
      unavailable states honest.
- [ ] R12: scoped diffs reviewed, baseline WIP (including both `build-profile.json5` edits)
      untouched by commits, remote compare done.
- [ ] Any emulator claim states SQLite-only, and that MySQL is unproven there.

---

## 8. Open items for root

1. Signing: regenerate a `com.azurekiln.qfli.sqlab` debug profile in DevEco (network/account)
   **or** approve the offline SDK-material path (§1.2) with one trial install.
2. ABI: decide whether the worktree's arm64-only restriction stays (then the emulator can
   never run the app) or reverts to HEAD's `["arm64-v8a","x86_64"]`.
3. Whether to schedule the x86_64 real-Oracle build (§2) at all, given that the spec's phone
   acceptance is arm64-only and the emulator run would still be unproven.
4. Who owns the promotion of draft tracks 14–17 (ids 127+) into the shipped catalog, and
   when the native coverage target is re-run against the enlarged catalog.
