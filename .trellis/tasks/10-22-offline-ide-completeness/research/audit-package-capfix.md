# Current full-audit package after statement-cap correction

Built and inspected2026-10-22; actual device execution remains open.

- Target: `integration_test/sql_curriculum_ohos_audit.dart`.
- Build ID: `sql-originals-x64-capfix-20261022`.
- Bundle: `com.azurekiln.qfli.sqlab.audit`; x64 Flutter/native target.
- Signed HAP: `build/ohos-audit/sql-audit-signed.hap`, SHA256
  `0c5007b468e3e525d687b4e52983865b4c84d6ad2a89dd006aaf83bd8df76d78`.
- Unsigned SHA256:
  `64df2478cbdf916ec581abc3ed7afef6a5aa2685db7f37ad68d25bbcd9a1ee64`.
- Build UTC:2026-10-22T13:52:22.6950164Z.
- Fresh build, sign-app/verify-app and independent package inspector: PASS.
- Exact catalog remains126 examples/246 exercises/372 scripts. Actual Oracle
  x64 strip binding, ELF closure, asset/resource bytes and profile checks pass.
- The complete audit entrypoint and all four support Dart sources match the
  source embedded in the packaged kernel (CRLF/LF normalization allowed),
  including the new statement-cap smoke. Local source-binding identities are
  retained in `build/ohos-audit/audit-source-binding.json`.
- Durable machine summary: `audit-package-capfix-inspection.json`. Complete
  raw local evidence is `build/ohos-audit/inspection-capfix.json`; the versioned
  summary retains signature verdicts while omitting the device identifier and
  certificate/profile payload. No private key was exported or copied.

The package includes the fixed native script limit:512 actual statements plus
trailing trivia succeed; a real513th statement is finalized/refused before
stepping. The SQLite identity check executes both cases and records the
retained-result counts. Host8/8 real SQLite tests and both ABI SDK compile checks
pass; the identity smoke itself also passes on the actual host SQLite engine.

The earlier831a8680 package, logs, build/sign/inspection records are preserved
under `build/ohos-audit/history/pre-cap-831a8680`. The previous independent review
remains evidence for that artifact; this report records the fresh invocation
against the new hash. Production build metadata was restored by the reviewed
wrapper. No device operation occurred; Web/Lua precede the SQL122 window.
