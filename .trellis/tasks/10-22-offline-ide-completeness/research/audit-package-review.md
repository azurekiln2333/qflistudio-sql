# Independent audit-package review

2026-10-22. Reviewer: `review_audit_package` (`trellis-check`). Static package gate **PASS** for the exact artifact below. **No installation, device startup, SQL execution or phone acceptance was performed by this reviewer.**

## Artifact and reproducible commands

- Signed HAP: `build/ohos-audit/sql-audit-signed.hap`, 416777742 bytes, SHA-256 `831a868056d0747d8e1718e7ed684c603d15221254b97ae445279b456ba8b02f`.
- Unsigned HAP SHA-256: `1cbcbaba48a7a73656d5bdc92974310b897751b3f0212400590812d5d7b6d94d`; build UTC `2026-10-22T12:10:39.182118Z`.
- Inspection UTC: `2026-10-22T13:34:12.311333+00:00`. Machine evidence: [audit-package-inspection.json](./audit-package-inspection.json).
- Bundle: `com.azurekiln.qfli.sqlab.audit`; build target `integration_test/sql_curriculum_ohos_audit.dart`; architecture `ohos-x64`; manifest debug mode `true`; compile SDK `26.0.0.105`.
- Current audit entrypoint source is embedded byte-for-byte (allowing CRLF/LF normalization) in the packaged kernel; the recorded build ID is present. This and recorded target are static evidence, not proof that `main()` ran.

```powershell
python tool/ohos/inspect_audit_hap.py
python -m unittest discover -s tool/ohos -p test_inspect_audit_hap.py -v
python -m py_compile tool/ohos/inspect_audit_hap.py tool/ohos/test_inspect_audit_hap.py
```

The inspector defaults to the original catalog gate, 126 examples / 372 scripts. It writes a fresh `build/ohos-audit/inspection.json`, exits nonzero on any failed invariant, and uses temporary files for ELF transforms and signature verification. No device API is called.

## Actual archive findings

- 124 ZIP entries, all unique and safe relative names. Signing adds the SDK `.pages.info` code-sign metadata; every original unsigned ZIP payload is byte-identical after signing.
- `module.json` and `pack.info` agree on the separate audit bundle. Actual permissions are `ohos.permission.INTERNET` and `ohos.permission.READ_PASTEBOARD`, matching the existing source manifest. This permission inventory does not establish runtime network use.
- Seven x86_64 shared libraries include Flutter, SQLite, C++ runtime and all four real Oracle images. Six additional ARM64 native images have correct AArch64 ELF headers; there is **no ARM64 Flutter image**. This HAP is an x86_64 audit artifact, not a complete phone artifact.
- Both curriculum JSON assets match current shipped files byte-for-byte. Each of 126 examples maps uniquely to one lesson with identical code and authored output. All authored exercise answers/expected outputs are present.
- Correct original denominator: **126 examples + 246 exercises = 372 scripts**. SQLite: 120 examples, 240 exercises, 360 scripts. MySQL: six examples, six exercises, 12 scripts. The prior 378 claim assumed two exercises for each MySQL lesson and was incorrect; the runtime audit already derives its denominator correctly.
- Oracle resources match the staged resource tree byte-for-byte: 70 runtime resources, `runtime.json` (version 8.4.6), and two license files. No resource is missing or extra.
- Fresh SDK `verify-app` passes cryptographic digest, native code-sign and permission verification. Fresh `verify-profile` returns `verifiedPassed: true`; authenticated content matches signing input, audit bundle, debug type, normal APL, single UDID scope and current validity. Public SDK identity trust on the device remains unverified.

### Shipped asset identities

| Asset | SHA-256 |
| --- | --- |
| `assets/content/sql_examples.json` | `cacfbf628a56fc42635764e3767981da14325eb9c8802cda94f5be0270276049` |
| `assets/content/sql_tutorials.json` | `0ea1071c1aa9a6611ebceba7c4b4a832f6f635f4b57e052406f6455c99e5a2e0` |
| `kernel_blob.bin` | `262596b73bbd28265e3d91c3f8e11d864cd0f41da674cb2efb27d05dd9f8404f` |

### Actual x86_64 native identities

Every Oracle row is byte-identical to the result of the installed SDK `llvm-strip --strip-all` applied to the exact candidate hash in `staging.json`; candidate hashes also match the independent x86 port closure report. The inspector records SDK tool hashes, so the transform is reproducible.

| Image | HAP bytes | HAP SHA-256 |
| --- | ---: | --- |
| `libc++_shared.so` | 1294904 | `09b9e3a97d3c01260b5e269e2ce15fe4d3b7c787b99dc4378295d4f35e2fa006` |
| `libflutter.so` | 40298440 | `84f72baf693ee885146bf26ae962a88fd3b81488a54b2a99044fe3ea761bd9a1` |
| `libqfli_mysql.so` | 14381032 | `546d76618e37299e549f830bdd6c0a72dbb347f5499003cd1be98d287d418968` |
| `libqfli_mysql_launcher.so` | 11504 | `5ba04d87f7fe52bd7c322be18c1716c1c7e824310a73f6b79cc07fcda9ffa997` |
| `libqfli_mysql_server.so` | 74266400 | `90a57cc466b4f757b8f0c2c4e8755af93f18fdeb93a72df18e6f8e173a1928d4` |
| `libqfli_mysql_server_proto.so` | 61674232 | `f9e20b20e24cd8adddf619a6af09ebcc7ff5cda6f4ac425bb638efc43087e7c3` |
| `libqfli_sql.so` | 1723736 | `d26bf68a3157e6d493c4bb51b14a8145eb9ae4fbec95941ffbaa08858762128c` |

- All x86_64 `DT_NEEDED` names resolve to packaged libraries or the installed x86_64 SDK. No text relocations detected.
- Strong symbol-name imports resolve against each actual NEEDED dependency graph: client 330, public server 617, launcher 34, private server 408, SQLite 131, C++ runtime 165; **zero unresolved**. SDK stub exports establish the link interface only, not target loader behavior or runtime symbol versions.
- Private Oracle image depends only on `libc.so`; exactly seven required exports remain: `QfliMysqlMain`, `qfli_mysql_child_main`, `qfli_mysql_record_exit`, `qfli_mysql_proto_report`, `qfli_mysql_proto_ready`, `qfli_mysql_proto_enter_child_scope`, `qfli_mysql_proto_child_exit`. No external C++ exception/unwind/guard imports.

## Findings fixed

- `tool/ohos/build_audit_hap.ps1`: the wrapper acquired `.build-lock` before reading metadata and changing location outside its `try/finally`. A missing/unreadable metadata file could leave a stale lock. Moved metadata reads and `Push-Location` inside the protected block and guard `Pop-Location` with `locationPushed`.
- Added `tool/ohos/inspect_audit_hap.py` to enforce real package identity, complete catalog denominator, exact native strip provenance and signature/profile validation. Added `tool/ohos/test_inspect_audit_hap.py` to guard omitted lesson mappings, output drift, exercise omissions, wrong denominator, ambiguous archive paths and the actual PowerShell early-read cleanup path.

## Findings not fixed / boundaries

- Root reported a subsequent narrow native fix for exactly 512 statements followed by comments/empty semicolons. That fix is outside this reviewer ownership and **requires a new HAP build, signing and inspection**. This review cannot be reused as evidence for changed native source or a different HAP hash.
- The inherited generated x86 stub caused a duplicate `ProcessLibs` input before this artifact. Root already preserved and removed that obsolete output after checking Ninja ownership. Current final bytes prove the real engine; a previously built checkout may need the same narrowly scoped cache migration. Do not add `pickFirst` or run broad clean.
- `ohos/entry/build-profile.json5` was dirty at task start. HEAD already supports both native ABIs; the current empty `nativeLib.filter.excludes` is neutral relative to HEAD. No baseline configuration hunk was edited or staged by this reviewer; omit it from this task commit unless separately justified.
- Staging/build/sign scripts and native/Hvigor architecture guards were reviewed. No further actionable local defect found. Fresh complete-build reproducibility from a clean checkout was not executed: the Oracle port still requires its pinned archives, SDK and existing patched Oracle/host-tool inputs. Exact HAP assembly from the audited staged candidate is verified.
- `.trellis/spec/backend/ohos-audit-packaging.md` matches these package/ABI/signature/lock contracts and the corrected 126/372 gate. No spec drift identified.

## Verification

- Actual inspector: **PASS**, exact HAP hash above; fresh native/signature tools, no reused success log.
- Python unittest: **5/5 PASS** (including two actual PowerShell missing-metadata subcases; no skip).
- Python bytecode syntax checks: **PASS**. PowerShell parser: all three packaging scripts **PASS**. No separate Python type checker/linter is configured in this repository; no Dart/ArkTS/C++ changes were made in this review.
- Scoped `git diff --check`: **PASS**. No full Flutter build/test, device action, staging or commit performed by this reviewer.
