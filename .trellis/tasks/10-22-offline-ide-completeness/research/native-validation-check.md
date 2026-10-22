# OHOS SQLite prepare-only validation check

Date: 2026-10-22. Scope: this SQL native implementation only. No HAP/device acceptance claimed.

## Changed files

- `ohos/entry/src/main/cpp/qfli_sql_validation.{h,cpp}`: production testable core; private `:memory:` only, prepare/finalize without stepping, authorizer, resource/deadline bounds, exact UTF-8-byte to UTF-16 error positions.
- `ohos/entry/src/main/cpp/qfli_sql_napi.cpp`: asynchronous worker/promise `validate(source)` and structured result serialization. Existing executeScript changes preserved.
- `ohos/entry/src/main/ets/plugins/QfliSqlNative.ets`: typed async validate channel route; user database paths rejected. Existing script route preserved.
- `native/CMakeLists.txt`: add validation core to the real OHOS library.
- `native/tests/check-ohos-sql-napi-syntax.{ps1,sh}`: check NAPI/core for both architectures with `-Wall -Wextra -Werror`; removed source-text assertion pseudo-tests.
- `native/tests/qfli_sql_validation_test.cpp`, `native/tests/sql_validation/CMakeLists.txt`, `native/tests/run-sql-validation-test.{ps1,sh}`: independent actual-engine behavior tests using production core and bundled SQLite 3.50.0.

## Commands and results

From `D:/MyNewProjects/qfli_sql` in PowerShell:

```powershell
& native/tests/check-ohos-sql-napi-syntax.ps1
# PASS aarch64-linux-ohos and x86_64-linux-ohos, NAPI + validation core, -Werror
& native/tests/run-sql-validation-test.ps1 -BuildDirectory D:/AppData/Local/Temp/qfli-sql-validation-20261022-native-worker2
# CMake/GNU 4.9.2; production C++ compiled with -Wall -Wextra -Werror.
# Actual bundled SQLite 3.50.0; CTest sql_validation_real_engine 1/1 PASS (0.35 s).
git diff --check -- native/CMakeLists.txt ohos/entry/src/main/cpp/qfli_sql_napi.cpp ohos/entry/src/main/ets/plugins/QfliSqlNative.ets
# PASS (only existing Git LF/CRLF conversion notices).
```

SDK: `D:/ProgramFiles/Huawei/DevEco Studio/sdk/default/openharmony/native`.

Real-engine tests intercept `sqlite3_step` (self-tested against actual execution) and SQLite VFS `xOpen` (self-tested against fixture DB creation). Every validation reports zero calls to either. Tests cover SELECT/literal-semicolon boundaries, DDL never applied even to isolated schema, DML/schema gaps, saved fixture bytes unchanged, PRAGMA/EXPLAIN PRAGMA/ATTACH/DETACH safety, unknown/external functions, ordinary built-in scalar/aggregate functions, virtual tables, VACUUM INTO no file creation, Unicode/supplementary characters/CRLF offsets, no-offset incomplete syntax, NUL/1 MiB/512-statement/expression-depth bounds, and stopped/unvalidated tails.

## Contract and limits

- Input is exact SQL text; native accepts no database argument. `available` means backend ran, not that every statement could be validated.
- `statements` counts discovered/attempted statements. `checked` counts actual prepare attempts, including schema/authorizer failures. At the 512/deadline cap one discovered unknown remaining coverage segment is added; these are lower-bound counts when truncated.
- First preparation failure stops parsing. Its range through end of source is in `skipped` with an explicit reason and `truncated=true`; no failure tail is treated as a complete statement boundary. Syntax failures retain their real issue, schema gaps are never syntax errors, other semantic/resource failures report limited coverage.
- Private fresh connection registers no application/custom functions; extensions are compiled out and disabled. Ordinary bundled functions remain usable. Authorizer rejects PRAGMA, ATTACH, DETACH, virtual tables, and external/file helpers including `edit`, `eval`, `fts3_tokenizer`, `load_extension`, `readfile`, and `writefile`.
- Work runs on NAPI async worker; source <=1 MiB, <=512 attempts, expression/column/compound/variable/opcode bounds, and a 250 ms prepare progress deadline. No user statement is stepped.
- ArkTS/HAP compilation and on-device channel behavior still require the coordinator's current package/device acceptance. Host-engine tests and SDK syntax gates do not prove those results.
