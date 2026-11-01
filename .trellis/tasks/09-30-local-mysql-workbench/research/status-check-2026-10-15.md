# Status check 2026-10-15

Read-only health check of `qfli_sql` (no commit, no push, no code changes).

## 1. Tooling

`flutter analyze lib test`:
- Result: **FAIL** (exit 1) — but no errors/warnings; only 1 info-level lint.
- `info - unnecessary_import`: `dart:typed_data` import is redundant in
  `lib/sql_document_service.dart:3:8` (already provided by
  `package:flutter/services.dart`).

`flutter test --no-pub`:
- Result: **PASS** — `+65 ~2` ("All tests passed!"), 65 passed / 2 skipped,
  ~5s. No failures.

## 2. HarmonyOS phone MySQL host — where it is stuck

- The blocker is *not* Oracle itself and *not* the SQL layer: an isolated
  probe PASSED all 12 native checks on the real phone (runId
  `1791542089201247_c1326982907f1eee`) using a **preload + fork** host that
  calls the private server entry directly, bypassing `exec`.
- The original blocker was process hosting: on this phone (MRT-AL10, API 26,
  arm64) both OS child-process APIs report `supported=false` (native=false,
  ark=false), direct `execve` of the packaged launcher is `EACCES` (installed
  mode 0644), the musl interpreter exec is also `EACCES`, and the only
  exec-enabling manifest field (`executableBinaryPaths`) is rejected at install
  (`9568449`). So no supported fresh-process host exists under the current
  bundle/policy.
- The authorized fallback (Option B: private-binding preload + fork, static
  libc++, constructor audit) is now proven at the engineering-gate level
  (Gate 1 static closure, Gate 2/4 mechanism, DATA/STDIO protocols) and has
  produced a 12/12 device PASS.
- Latest device-blocking issue is sequencing/coordination, not native failure:
  the last fresh-launch attempt (`aa start`, 2026-10-09 20:13) returned
  `10106102` because the **phone screen was locked**; no new runId was created.
  Work is held pending a coordinated `CORE_SNAPSHOT_READY` / SDK release.
- Note: the production datadir was cold-backed-up (259/259 files, 168.2 MB,
  verified) and a stale `mysql.pid` (12899) / socket lock was observed; the
  runtime's remove-if-exists startup handles these.

## 3. Next step

1. Fresh phone acceptance re-run of the installed HAP after the user unlocks
   the screen, to revalidate the atomic-fence native delta
   (`libqfli_mysql_server.so` 89004736) with a new START/runId.
2. Respect coordinator sequencing: one Flutter HAP build only after
   `CORE_SNAPSHOT_READY`/grant, then `CORE_RELEASE`/`SDK_FREE`, then continue
   device probes.
3. Then build/install the normal `lib/main.dart` HAP and verify the workbench
   (do not leave only the probe app).

## Notes

- Working tree has ~120 uncommitted changes across lib/, spec/, macos/,
  task docs — pre-existing, untouched by this check.
- The single analyze finding is cosmetic (`unnecessary_import`); no action taken
  per read-only instruction.
