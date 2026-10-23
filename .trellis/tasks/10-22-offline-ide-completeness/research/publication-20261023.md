# Reviewed SQL delivery publication — 2026-10-23

All five configured destinations accepted a normal fast-forward of `main` from
`42602e37e75dff348ed4d2a453f7c8af009a4fbb` to the reviewed delivery checkpoint
`3dfb07362015ea378a9526efc64e0423eff7714f`. No force push was used.

| Destination | Push result | Independent `ls-remote` result |
| --- | --- | --- |
| CNB | PASS | `3dfb07362015ea378a9526efc64e0423eff7714f` |
| GitHub | PASS | `3dfb07362015ea378a9526efc64e0423eff7714f` |
| Gitee | PASS | `3dfb07362015ea378a9526efc64e0423eff7714f` |
| GitCode | PASS | `3dfb07362015ea378a9526efc64e0423eff7714f` |
| GitLab | PASS | `3dfb07362015ea378a9526efc64e0423eff7714f` |

The published history contains product `9f92d49`, x64 Oracle recipe `69b428e`,
held curriculum drafts `9c6da05`, evidence `6a5de4c`, and whitespace/evidence
correction `3dfb073`. The last correction passed both staged whitespace review
and the complete task diff against the original base before commit. Original
baseline WIP remains outside the committed history. Local command evidence is
preserved at `build/offline-ide-check/publication-1023.json`.

Source checks remain the isolated272PASS/2OracleSKIP, zero analysis issues and
26 Python passes in `isolated-checkpoint-check.md`. Publication and subsequent
documentation changes do not turn the explicit skips into Oracle execution
passes and do not require rerunning the unchanged application sources.

## Target handoff remains open

Web explicitly released `127.0.0.1:5555` to Lua121 in channel seq163, with SQL122
next. The exact target was disconnected. SQL's subsequent read-only
`hdc list targets` using the running DevEco SDK client also omitted that emulator;
the separate network target was not claimed or used. SQL performed no install,
start, stop, daemon, emulator, security, uninstall or data-clear operation.

At that initial publication checkpoint, the signed HAP was
`0c5007b468e3e525d687b4e52983865b4c84d6ad2a89dd006aaf83bd8df76d78`, build ID
`sql-originals-x64-capfix-20261022`, bundle `com.azurekiln.qfli.sqlab.audit`.
SQL requested explicit Lua-to-SQL handoff and live target availability in seq171. This archive predates native offline enforcement6999b0d and is now historical, pending replacement.
The complete original126/372 OHOS run, later306/912 promotion and target run,
normal target UI acceptance and other products' requirements remain open.

## Shared-source follow-up

Core owner published owner-aware Run `0ec321c`; Web reported its default-preview
regression in seq162. Studio main announced new workspace/editor work in seq166.
SQL retains read-only shared-core access and must capture the exact consumed
source when adding workspace consumer acceptance. Earlier isolated tests cover
the captured `f8edb042` working-tree snapshot, not later unverified changes.

## Native offline follow-up publication

- Reviewed commit `6999b0d2171318129fcd64a82ae9e493d13609e9` (`fix(ohos): enforce native SQL offline policy`) contains nine scoped files. Staged EntryAbility excludes the pre-existing startupProgress block, and staged offline spec excludes the pending workspace-consumer test contract. All original unrelated WIP remains in the worktree.
- `git push origin main` exited0. Five separate `git ls-remote --refs <remote> refs/heads/main` queries each exited0 and returned this exact OID for CNB, GitHub, Gitee, GitCode and GitLab. Local evidence: `build/offline-ide-check/native-offline/publication.json` and `push.log`.
- Host verification and independent mutation review are recorded in `native-offline-check.md`. The historical HAP's actual compiled module permissions were separately fed to the new inspector policy and rejected as expected. This is a negative control, not a new package or device pass.
- New workspace regression initially awaited the serial handoff; the later third run is recorded below and did not pass. Current native HAP rebuild/ArkTS/installed offline and original126/372 curriculum gates remain open. No SQL device mutation has occurred.

## Third workspace run and exact resource release

- Explicit C263/main264 handoff was accepted273. Format PID42516 exit0 (one file reformatted), scoped analyzer PID68416 exit0; tests PID12368 / tool handle40310 exited1 after9.5s, actual0PASS/2FAIL. SQL explicitly released274 to Go236, followed by Rust205/C211; no further heavy process started.
- Formatted test SHA256 `8c5966486fe74d9a06428db9666225b007f11dbaadf9b72d1e60c170d171368f`, isolated SQL3bd36f1/coree025805b. All66SQL/265core captured hashes stable. Evidence: `build/offline-ide-check/workspace/paths-run-summary.json`.
- First case failed immediately after drawer reopening, before explicit page reconstruction: root presence did not fence asynchronously restored child nodes. Second case reached its final exception check after the actual SQLite assertions, but the test failed on core's unsafe focus diagnostic. No partial test pass is claimed.
- C adopted the real focus-context defect282 and authored a mounted-context guard plus focused-disposal regression, not yet run. SQL owns the minimal drawer-child wait; a future retry requires the corrected core checkpoint and a new named slot. Current HAP/device/original-catalog gates remain open.
