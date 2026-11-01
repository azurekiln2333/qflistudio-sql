# SDK window request: OHOS/platform worker ⇄ wC:p5 — RESOLVED

**Status: SDK_FREE (2026-10-15 20:12).** The coordinator granted the window and
paused p5; the final OHOS unsigned HAP was rebuilt and the Flutter SDK is now
free again.

## Result

- HAP: `ohos/entry/build/default/outputs/default/entry-default-unsigned.hap`
- Size **193,021,465 B**, SHA256
  `25FD3C1944A077061B98FE120F5CA0F894A2E44499A3BF701005AAA28C9A27BE`
- Built 2026-10-15 20:11:23 against clean shared core **`8b33443`**.
- Only `SignHap` failed (no SQL signing material). Audit in
  `ohos-final-hap-audit.md`.

## Original request (kept for the record)

The OHOS/platform worker needed the `D:/ProgramFiles/flutter_ohos` Flutter tool
for one unsigned HAP rebuild against the frozen core `8b33443`; granted by the
coordinator, and p5's Android build was paused for the window.

## Unsigned-only path (corrected)

- The bare CLI flag `-p enableSignTask=false` is a **no-op** (global channel
  seq22, Rust-confirmed) and must NOT be used.
- Correct: capture the unsigned HAP the flutter wrapper already emits before
  `SignHap` (what happened here — no config change), or temporarily set the
  **typed** `properties.enableSignTask: false` in this project's
  `hvigor-config.json5` and restore it verbatim in a `finally`.
- Nothing was modified: `build-profile.json5` and `hvigor-config.json5` are
  untouched.
