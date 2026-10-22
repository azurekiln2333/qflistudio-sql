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

The current ready signed HAP remains
`0c5007b468e3e525d687b4e52983865b4c84d6ad2a89dd006aaf83bd8df76d78`, build ID
`sql-originals-x64-capfix-20261022`, bundle `com.azurekiln.qfli.sqlab.audit`.
SQL requested explicit Lua-to-SQL handoff and live target availability in seq171.
The complete original126/372 OHOS run, later306/912 promotion and target run,
normal target UI acceptance and other products' requirements remain open.

## Shared-source follow-up

Core owner published owner-aware Run `0ec321c`; Web reported its default-preview
regression in seq162. Studio main announced new workspace/editor work in seq166.
SQL retains read-only shared-core access and must capture the exact consumed
source when adding workspace consumer acceptance. Earlier isolated tests cover
the captured `f8edb042` working-tree snapshot, not later unverified changes.
