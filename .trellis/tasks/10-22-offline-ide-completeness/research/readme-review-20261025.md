# Trilingual README review — 2026-10-25 (final)

Supersedes the earlier file of the same name. The earlier review said
`README.zh-TW.md` was absent. All three files now exist.

## Status

**NOT PASS.** The three files are close, but two classes of defect remain:

1. `README.zh-TW.md` makes a runtime claim that depends on **uncommitted** code.
2. All three files overstate the platform verification state for Linux and
   Android.

Fixed since the previous review:

- Both Chinese files pass `scripts/ste-lint-zh.py` with 0 findings.
- No dead local links; the old untracked `mysql-workspace.md` link is gone.
- No README cites `scripts/ste-lint-zh.py`.
- No Chinese semicolon violations; clauses are split.
- `README.zh-TW.md` is consistently Traditional.

Owned by: CHECK worker (this file only). The three READMEs belong to their own
writers and were read, never edited.

## Method

Read: the three READMEs, `check.jsonl`, `prd.md`, `implement.md`,
`research/requirements-evidence.md`, and the platform specs
(`mysql-desktop-runtime.md`, `mysql-android-runtime.md`, `mysql-ohos-runtime.md`,
`sqlite-native-runtime.md`, `sql-diagnostics.md`). Facts were checked against
current source and shipped assets. Ran the linter read-only. No Flutter, SDK,
HAP, signing, device or content-generation command ran. No file was staged,
committed or pushed.

## File hashes (SHA-256)

| File | SHA-256 | Bytes |
| --- | --- | --- |
| `README.md` | `CDEC1A49EBC82C737D1DF051022B1A942CE3350F3736614801C182A047B17E40` | 14418 |
| `README.zh-TW.md` | `683A82F6FA6AC5BC9B4D24D55888D8EA272EC954AA3BE354856AB851933B4E85` | 14307 |
| `README.en.md` | `CB25FA97A7DB18B91FB9EC5AADE7E9A0036D10A1FA9D1EA0BE0D1358B733D7D9` | 12054 |
| `HEAD:README.md` (old text) | `2024FC0D249E66E6BAB554F0CAF01F5E8A42B4EE6108602B688C918B2772A9E1` | 2208 |

## Linter results (`scripts/ste-lint-zh.py`)

| Command | `README.md` | `README.zh-TW.md` |
| --- | --- | --- |
| default (40-char limit) | hard 0, baseline 0, 3525 counted chars, exit 0 | hard 0, baseline 0, 3484 counted chars, exit 0 |
| `--json` | `[]` | `[]` |
| `--max-chars 25` | 7 long-sentence findings (all explanation prose) | 31 long-sentence findings (all explanation prose) |
| `--selftest` | `selftest OK` | `selftest OK` |

The linter masks inline code, URLs and link text. English semicolons are not a
Chinese concern: `python scripts/ste-lint-zh.py README.en.md` reports 25 hard
findings, all rule `semicolon`, and the English file is not linter-gated.

## Blocker — claim depends on uncommitted code

### B1 — `README.zh-TW.md:38` claims retained editor file and cursor

```text
開啟專案會進入共用編輯器，編輯器保留檔案與游標。
```

Retained editor state is uncommitted. The other two files say so:

- `README.md:30` — `文档与光标保留、命名工作区入口和已保存的工作区都尚未提交。它们的验收仍待完成。`
- `README.en.md:34-35` — `Retained editor state and named workspaces in the SQL shell are still pending, so this README does not promise them.`

Evidence that the feature is not committed:

- `git status --porcelain lib/sql_projects_page.dart` → ` M` (uncommitted).
- `git show HEAD:lib/sql_projects_page.dart` has no `retained` or
  `saved_workspaces` reference; only the working tree imports
  `qfli_studio_core/editor/retained_editor_host.dart` and
  `qfli_studio_core/workspace/saved_workspaces_tab.dart`.
- `../qfli_studio_core/editor/retained_editor_host.dart` does not exist.
- `../qfli_studio_core/workspace/saved_workspaces_tab.dart` does not exist.

Required: replace line 38 with the pending wording used by the other two files.
Do not promise retained file/cursor in a docs-only commit.

## Findings

### F1 — Linux host run is claimed at 8.4.6

- `README.md:84` — `Windows、Linux | ... 宿主已验证`
- `README.zh-TW.md:108` — `Windows、Linux | ... 宿主已驗證`
- `README.en.md:97` — `Windows, Linux | ... verified on the host`

`.trellis/spec/backend/mysql-desktop-runtime.md:107` records the only available
evidence: `Windows 8.4.6, Linux 8.0.46`. A blanket host pass under the 8.4.6
heading overstates Linux.

Required: state Windows is host-verified at 8.4.6 and the Linux host run used
8.0.46, or split the row.

### F2 — Android evidence is inverted and understated

- `README.md:85` — `仅 64 位，API 28 起。x86_64 设备已验证` (device, no ARM)
- `README.zh-TW.md:109` — `僅 64 位元，API 28 起。x86_64 裝置已驗證`
- `README.en.md:98` — `x86_64 verified on a device, ARM requires its own device run`

`.trellis/spec/backend/mysql-android-runtime.md:87-90` records:

- API 37 **x86_64 emulator** passed both engine integration tests on 2026-10-02.
- Physical **ARM64 OPD2413 (API 36)** passed on 2026-10-15.

So `x86_64 设备已验证` / `x86_64 verified on a device` is wrong (emulator, not a
device), and `ARM requires its own device run` is wrong (the ARM64 device
already passed). The zh-CN and zh-TW rows also drop ARM entirely.

Required: say the x86_64 result was an emulator and the ARM64 OPD2413 result was
a physical device. Keep `64-bit, API 28+` as the build limit.

### F3 — `固件` / `韌體` is not a real content field

- `README.md:46` — `方言信息写在摘要与概念中，不只写在固件里。`
- `README.zh-TW.md:60` — `方言資訊寫在摘要與概念中，不只寫在韌體裡。`

`固件` / `韌體` means firmware. No SQL asset carries firmware. In
`assets/content/sql_examples.json` the engine lives in
`inputFixtures.engine` (`sqlite` 120, `mysql` 6) and the dialect text lives in
`summary` and `concepts`. `README.en.md:57` correctly omits the clause. The
clause looks like a mistranslation of "fixture".

Required: replace the clause with the real field (`inputFixtures.engine`) in
both Chinese files, or drop it.

### F4 — `README.zh-TW.md` merges actions and facts that `README.md` splits

The linter gates `；`, not `，`, so these pass mechanically but violate
one-action-per-sentence. Representative pairs:

| `README.zh-TW.md` | Merged content | `README.md` equivalent |
| --- | --- | --- |
| 65 | `分析讀取…，不重讀…，也不儲存…，分析不執行使用者 SQL。` | 50 (four sentences) |
| 70 | `缺失物件回報為…而不是語法錯誤，引擎失敗回報為…而不是正常結果。` | 54 (four sentences) |
| 112/115 | `Oracle 使用私有通訊端或管線，並開啟 skip-networking。` + `TCP 不能作為後備，應用也不要求 INTERNET 權限。` | 90 (four sentences) |
| 121 | `交易必須寫在一個腳本內，此時連線才真實存在。` | 94 (two sentences) |
| 126 | `請把 … 檢出為同級目錄，然後在本倉庫解析相依性。` | 98 (two instructions) |
| 133 | `不要從本倉庫修改 …，請記錄實際使用的核心版本。` | 103 (two instructions) |
| 151 | `Oracle 資料是獨立建置，請先建置固定的原生產物，再建置應用。` | 120 (three sentences) |
| 167 | `略過不算通過，請把無法使用略過與通過分開記錄。` | 132 (two sentences) |
| 203 | `Oracle 使用私有本機通訊端，不需要網路權限，封存檢查器也拒絕 INTERNET 權限。` | 157 (three sentences) |

Also `README.zh-TW.md:46,48,49,50` merge statements that `README.md:35-38` keeps
separate (worksheet display vs execute; structure/index check; index source),
and `README.zh-TW.md:57,59` merge statements that `README.md:43,45` keep separate.

Required: split to match `README.md`.

### F5 — requirement sentences exceed the 25-char instruction limit

Imperative steps (`请…` / `不要…` / `請…`) are all ≤25 in both files. Three
"must" requirement sentences are not:

- `README.md:198` — 30 chars.
- `README.zh-TW.md:246` — 26 chars (instruction clause joined to an explanation).
- `README.zh-TW.md:259` — 32 chars.

All three sit under the 40-char explanation limit, so the default gate passes.
If these count as instructions, split them.

### F6 — cross-language parity gaps

| Item | zh-CN | zh-TW | en |
| --- | --- | --- | --- |
| Tutorial/example/answer/denominator counts (126 / 126 = 120+6 / 246 / 372) | yes | yes | **missing** |
| Bundle `com.azurekiln.qfli.sqlab` | missing | missing | yes |
| Extra limits only in en: 512 prepare attempts, PRAGMA/ATTACH/DETACH/virtual-table refusal | missing | missing | yes |
| `ohos.permission.READ_PASTEBOARD` named | yes | yes | prose only |
| `private-host fence change` open item | missing | missing | yes (`README.en.md:209`) |

Section order also differs: both Chinese files place `课程与发布资源` before
`当前验收状态` / `已知限制`; `README.en.md` places `Content` after
`Known gaps`. `README.en.md` has no `延伸阅读` section, so the seven tracked
spec links exist only in the Chinese files. Table row counts are equal (10 each)
and all Chinese headings match by order (20 each).

The `private-host fence` item is backed by untracked scripts
(`native/tests/build-with-fence.sh`, `prove-fence-branch.sh`, and others in
`git status`). The Chinese files omitting it is safe, not a defect.

### F7 — audit wrapper attribution is imprecise

- `README.en.md:159` — `wrappers under tool/ohos/, which stage native libraries and runtime data and restore the production signing configuration afterwards`
- `README.zh-TW.md:144` — `鴻蒙封裝用倉庫內建腳本，腳本準備原生程式庫與 Oracle 本機資料，隨後還原正式簽章設定。`

`HEAD:tool/ohos/build_audit_hap.ps1` performs no native or runtime staging; it
only copies the unsigned HAP and restores the mutation byte-for-byte. The
working tree copy is the same on this point. Library staging lives in the
separate tracked `tool/ohos/stage_mysql_x64.ps1`, which stages four x86_64 ELF
libraries and a `staging.json` (`runtimeVerified: false`,
`deviceVerified: false`) and no runtime data. `README.md:113` is accurate
(`脚本构建独立的审计包。脚本随后逐字节恢复原始配置。`).

Required: align en/zh-TW with `README.md`, or name the actual staging script and
drop "runtime data".

### F8 — historical OHOS device probe dropped

The old review (F5) asked that the historical OHOS on-device probe stay
separable. All three files now omit it and state "no current HAP install/run
proof". That is honest. Recorded as informational only, not a defect.

## Constraint check — no claims from uncommitted work

| Surface | Result |
| --- | --- |
| Named workspace / saved workspaces | `README.md:30` and `README.en.md:34-35` say pending. `README.zh-TW.md:38` violates (B1). |
| macOS Oracle helper | All three say pending/unverified (`README.md:86`, `README.zh-TW.md:110`, `README.en.md:99`). `native/mysql/macos/` is untracked. OK. |
| New wrapper parameters | READMEs use only `-Target`, `-Architecture ohos-arm64`, `-DeviceUdid`. All exist in `HEAD`: `build_audit_hap.ps1` param block and unmodified `sign_audit_hap.ps1:2`. The uncommitted new params (`-Flutter`, `-DevEcoHome`, `-Json5Module`) are not mentioned. OK. |

## PASS items

- Linter: 0 hard and 0 advisory findings in both Chinese files.
- Traditional Chinese throughout `README.zh-TW.md`: no strictly-simplified
  characters found; Traditional forms used (`資料庫`, `專案`, `檔案`, `儲存`,
  `網路`, `連線`, `簽章`, `稽核`, `封裝`, `執行`, `函式`, `資訊`).
- No passive `被`, no semicolon, no marketing adjective, no empty phrase, no
  `进行…` nominalization, no synonym rotation. (`用户` and `客户端` are distinct
  concepts; the linter's suffix block is correct.)
- Active voice and named actors in procedures.
- All local Markdown link targets exist and are **tracked**:
  `.trellis/spec/{frontend/sql-workbench,frontend/sql-terminal-offline,frontend/sql-content-repository,backend/sqlite-native-runtime,backend/sql-diagnostics,backend/mysql-ohos-runtime,backend/ohos-audit-packaging}.md`,
  `native/README.md`, `native/mysql/README.md`,
  `native/mysql/desktop/README.md`, `native/mysql/android/README.md`,
  `native/tests/README.md`, `README.md`, `README.en.md`, `README.zh-TW.md`.
- In-page anchors resolve: `#并行检出与依赖` → `README.md:95`,
  `#並行檢出與相依性` → `README.zh-TW.md:123`.
- No README links to `.trellis/tasks/`, `research/`, `scripts/` or
  `scripts/ste-lint-zh.py`.
- Verified facts agree with current source/assets: SQLite `3.50.0`
  (`sqlite3.h:149`), Oracle `8.4.6` (`package-runtime.cmake`), version `1.0.0+1`,
  bundle `com.azurekiln.qfli.sqlab`, product key `sqlab`, five destinations
  (`数据库/项目/功能/教程/示例`), exactly `READ_PASTEBOARD` and no INTERNET,
  five NAPI methods (`qfli_sql_napi.cpp:565-569`), counts 126 / 126 (120+6) /
  246 / 372, x86_64 staging `runtimeVerified: false` / `deviceVerified: false`.
- Modal/hedge words preserved (`可能`, `尚未`, `未驗證`, `未實作`).

## Verdict

NOT PASS. Must fix before the docs-only commit:

1. B1 — `README.zh-TW.md:38` uncommitted retained-state claim (the stated
   constraint).
2. F1 — Linux 8.4.6 host overclaim (all three files).
3. F2 — Android x86_64/ARM evidence inverted (all three files).

Recommended before commit: F3 (`固件/韌體`), F4 (zh-TW sentence merges),
F5, F6 parity gaps, F7 wrapper wording.

The Chinese files are mechanically clean; the residual risk is factual, not
stylistic.

## Final resolution and publication — 2026-10-26

The earlier NOT PASS findings above were resolved before publication. The final three files passed scripts/ste-lint-zh.py with zero findings and no suppressions, Markdown link/anchor review, factual evidence review and staged diff whitespace checks. Chinese instructions and explanations were reviewed against the controlled-language limits.

Commit d99c725cd64a61340b871fc72c350724ed46ad00 (`docs(sql): rewrite README in three languages`) contains only README.md, README.zh-TW.md and README.en.md. All five remote main heads were independently verified at this exact commit after push: CNB, GitHub, Gitee, GitCode and GitLab. Product/test/tooling work remains outside this docs commit. The umbrella task remains in_progress. C616 later produced 0PASS/3ERROR/0SKIP; it does not establish named-workspace acceptance.
