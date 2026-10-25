# QFLISQLab（`qfli_sql`）

繁體中文 · [簡體中文](README.md) · [English](README.en.md)

QFLISQLab 是用 Flutter 編寫的離線 SQL 整合開發環境。
應用內建 SQLite 引擎。應用也能在本機啟動內建的 Oracle MySQL 伺服器。
應用內建 SQL 課程。使用應用不需要網路、雲端帳號或外部 SQL 伺服器。
本倉庫是獨立語言應用家族中的 SQL 產品，所有成員共用 `qfli_studio_core` 套件。
建置前請先讀 [並行檢出與相依性](#並行檢出與相依性)。

## 產品簡介

產品標識為 `qfli_sql`，產品鍵為 `sqlab`，版本為 `1.0.0`。
套件名稱為 `com.azurekiln.qfli.sqlab`。
入口檔案是 `lib/main.dart`。入口安裝 `sqlProfile`。入口啟動 `SqlLabApp`。
介面語言為簡體中文（`zh-CN`）。課程資源也使用中文。
主介面有五個可滑動頁面：資料庫、專案、功能、教學、範例。
手機用底部導覽列。寬螢幕用側邊導覽列。
每個頁面擁有獨立工具列。外殼不顯示第二個工具列。

## 應用功能

### 資料庫頁面

`lib/sql_workbench_page.dart` 是資料庫工作區。
手機以可展開的資料庫到資料表樹為主體。桌面把樹放在側欄。
資料庫獨立展開或收合。點選資料列可選取物件。
SQLite 表格用隱藏資料列識別來編輯資料。寫入使用繫結參數。
存在未遮蔽的 `rowid` 別名時，SQLite 表格允許寫入。
SQLite 表格為 `WITHOUT ROWID` 時，介面回報唯讀。
更新或刪除影響的資料列數不等於 1 時，應用回報該資料列已過期。
歷史紀錄上限為 100 條。
已儲存查詢獨立於引擎。儲存失敗不會丟棄有效結果。

### 專案頁面

`lib/sql_projects_page.dart` 列出專案。頁面提供搜尋與「更多」選單。
「更多」選單可以新增現有專案。它也可以刪除失效專案。
開啟專案會進入共用編輯器。
檔案與游標保留、命名工作區入口都尚未提交。
它們的驗收仍待完成。
專案 SQL 在專案自己的資料庫中執行。
SQLite 專案用 `<project>/.qfli/data.sqlite`。Oracle 專案用 `<project>/.qfli/mysql.json` 中的資料庫名。

### 功能頁面

SQL 能力直接放在本頁。本頁沒有通用「專用功能」跳轉頁。
捷徑保留共用工具路由與完整終端。
工作表顯示擷取的引擎與資料庫標識。工作表執行腳本。工作表顯示有序結果。
查詢計畫為一條受保護語句加上 `EXPLAIN QUERY PLAN` 或 `EXPLAIN`。應用不執行 `EXPLAIN ANALYZE`。應用不重跑工作表語句。
結構與索引顯示欄位名、型別、可為空、主鍵與計算欄標記。它檢查索引。
文字與值工具保留字面值與引號識別字的格式化。它區分 NULL 與空字串。
SQLite 索引資料來自 `PRAGMA main.index_list`。Oracle 資料來自 `information_schema`。
索引建立是一條預覽的 `CREATE INDEX` 語句。
引擎無法使用時介面回報無法使用。介面不把 SQLite 結果標為 MySQL。

### 教學與範例頁面

兩個頁面透過 `lib/sql_content_repository.dart` 讀取本應用自己的資源。
`assets/content/sql_tutorials.json` 有 126 個教學。每個課程一節。
`assets/content/sql_examples.json` 有 126 個範例。其中 120 個針對 SQLite。6 個針對 MySQL。共 246 條練習答案。
每個範例都是自足腳本。腳本含建表、插入與查詢。腳本帶人工撰寫的預期結果。
摘要與概念註明 SQL 方言。

### 編輯器診斷

`lib/sql_code_analyzer.dart` 為未儲存的 SQL 緩衝區實作共用 `CodeAnalyzer` 約定。
分析讀取精確的未儲存快照。分析不重讀磁碟檔案。分析不儲存編輯器。分析不執行使用者 SQL。
詞法檢查只回報可證明的問題，例如未結束字串、未結束引號識別字、括號不相符。
引擎語法檢查讓原生層在私有 `:memory:` 資料庫中準備語句。
它從不執行語句。它也從不開啟使用者資料庫。
範圍使用從零開始的 UTF-16 半開位移。原生層會轉換 UTF-8 位元組位移。
缺失物件回報為涵蓋落差。它不是語法錯誤。引擎失敗回報為無法使用。它不是正常結果。
SQLite 引擎檢查最多準備 512 次語句。
它拒絕 PRAGMA、ATTACH、DETACH、外部檔案函式與虛擬資料表。
MySQL 專案只提供詞法診斷。MySQL 沒有完整語法檢查。

### 終端

`lib/sql_runner.dart` 向獨立終端與編輯器終端提供同一個 SQL 委派。

```text
sql <file.sql>
sql -e "SQL"
sql --execute "SQL"
sql --help
```

未知命令回傳 false。共用檔案命令繼續運作。
路徑必須留在終端沙箱內，包括解析後的符號連結。
應用沒有互動式 `mysql` 或 `sqlite3` 用戶端。應用也沒有 SQL 取消介面。

## 引擎與平台限制

應用有兩個本機引擎。引擎可用性不會修改已選擇的引擎。
SQLite 橋接方法：`execute`、`executeScript`、`query`、`validate`、`version`。

| 平台 | SQLite 傳輸方式 |
| --- | --- |
| Android、iOS、Windows、Linux、macOS | `dart:ffi` 呼叫隨應用發佈的 C 程式庫 |
| 鴻蒙（OHOS） | `qfli_sql/native` 通道上的 `libqfli_sql.so` |
| Web | 不支援，SQL 引擎只支援原生平台 |

SQLite 單次查詢上限為 500 完整資料列與 1 MiB 儲存格資料。
腳本顯示預算為 500 資料列與 1 MiB。預算共用整個腳本。語句數上限為 512。
結構化查詢的鎖等待最多 3000 毫秒。
Dart 層輸入上限為 512 Ki UTF-16。原生層再限 1 MiB UTF-8。
截斷不會回傳不完整的資料列。
出現錯誤或達到上限時，引擎保留已完成結果。摘要標記失敗。

### Oracle MySQL 8.4.6（內建伺服器）

| 平台 | 狀態 |
| --- | --- |
| Windows、Linux | 應用啟動本機伺服器。連線使用私有管線或通訊端。伺服器不開放 TCP。 |
| Android | 僅支援 64 位元。最低要求為 API 28。 |
| macOS | 輔助程式建置未完成，執行未驗證 |
| iOS | 未實作 |
| 鴻蒙 | 已封裝 arm64-v8a 與 x86_64。手機透過私有映像分叉宿主啟動伺服器 |

歷史宿主檢查使用 Windows MySQL 8.4.6 與 Linux MySQL 8.0.46。
2026 年 10 月 2 日，API 37 x86_64 模擬器通過引擎整合測試。
2026 年 10 月 15 日，API 36 ARM64 OPD2413 實體裝置通過同類測試。
這些歷史結果不代表目前原始碼已驗收。

Oracle 使用私有通訊端或管線。Oracle 開啟 `skip-networking`。
TCP 不能作為後備。應用也不要求 INTERNET 權限。
MySQL 輸入上限為 1 MiB。預設顯示上限為 1000 資料列或 1 MiB。
每個腳本最多保留 128 個結果集。最大封包為 8 MiB。
截斷只限制輸出。後續語句仍然執行。
MySQL 的許多 DDL 會隱式提交交易。腳本出錯時前面修改可能留在資料庫中。
兩個引擎都為每次呼叫開啟新連線。應用不提供獨立的開始、提交或回滾按鈕。
交易必須寫在一個腳本內。此時連線才真實存在。

## 並行檢出與相依性

`pubspec.yaml` 透過相對路徑相依於共用核心與內建編輯器。
請把 `qfli_studio_core` 檢出為同級目錄。
請在本倉庫解析相依性。

```text
checkout-parent/
  qfli_studio_core/
  qfli_sql/
```

內建編輯器路徑為 `../qfli_studio_core/vendor/re_editor`。

```bash
flutter pub get
```

共用核心由其他負責人維護。它也會同時修改。
需要帶 Dart `^3.11.5` 的 Flutter SDK。
鴻蒙建置還需要 Flutter 鴻蒙分支、已安裝的 DevEco Studio 與簽章身分。
不要從本倉庫修改 `../qfli_studio_core`。請記錄實際使用的核心版本。

## 建置與執行

請先在倉庫根目錄解析相依性。

```bash
flutter pub get
flutter run -d <device-id>
flutter build windows
```

桌面目標還有 `linux` 與 `macos`。
鴻蒙稽核封裝使用倉庫內建腳本。
腳本建置獨立的稽核套件。
腳本隨後逐位元組還原原始設定。
執行前請先讀 [`ohos-audit-packaging.md`](.trellis/spec/backend/ohos-audit-packaging.md)。

```powershell
& tool/ohos/build_audit_hap.ps1 -Target <entry>.dart -Architecture ohos-arm64
& tool/ohos/sign_audit_hap.ps1 -DeviceUdid <actual-device-udid>
```

封裝成功不代表安裝成功。封裝成功也不代表可以執行。
Oracle 資料需要獨立建置。請先建置固定的原生產物。請再建置應用。
`native/CMakeLists.txt` 與 Hvigor 都要求受支援 ABI 的真實封裝。
缺少原生產物時 arm64 建置失敗。
不支援的架構改為建置 `native/src/qfli_mysql_unavailable.cpp`。該檔案回傳顯式無法使用結果。

## 測試與靜態檢查

```bash
flutter analyze --no-pub lib test integration_test
flutter test --no-pub
```

平台允許時測試使用真實引擎，否則測試注入 `MethodChannel`。
`test/sqlite_ffi_test.dart` 驗證真實 SQLite 的持久化、交易、邊界與上限。
`test/sql_code_analyzer_test.dart` 驗證真實 FFI 的 `validate` 路徑。
`test/sql_terminal_commands_test.dart` 與 `test/sql_offline_policy_test.dart` 驗證終端與離線拒絕。
`test/sql_curriculum_test.dart` 與 `test/sql_curriculum_native_coverage_test.dart` 驗證資源涵蓋。
需要真實原生程式庫或裝置的測試會印出顯式略過。
略過不算通過。請把無法使用略過與通過分開記錄。

```powershell
& native/tests/run-sql-validation-test.ps1
& native/tests/check-ohos-sql-napi-syntax.ps1
```

第一個腳本對真實內建 SQLite 執行隔離驗證核心。
第二個腳本為 arm64 與 x86_64 做編譯檢查。檢查選項為 `-Wall -Wextra -Werror`。
缺少 DevEco SDK 時第二個腳本印出 `SKIP`。腳本回傳 0。語法檢查不是執行驗收。
Oracle 宿主驗證與前置條件見 `native/tests/README.md`。
整合測試需要已連線裝置。入口在 `integration_test/`。
平台 ArkTS 離線策略檢查不需要裝置：

```bash
node tool/test_sql_offline_platform.cjs
```

## 原生引擎與文件

`native/third_party/sqlite/` 是未修改的 SQLite 3.50.0 單一檔案，屬於公有領域。
`native/src/qfli_sql_bridge.c` 是 FFI 腳本與結果橋接。它使用定位字元分隔輸出。
`native/src/qfli_mysql_client.cpp` 是 Oracle C API 用戶端。它使用私有通訊端與預備語句。
`ohos/entry/src/main/cpp/qfli_sql_napi.cpp` 是鴻蒙 NAPI 模組。它涵蓋五個方法。
`ohos/entry/src/main/cpp/qfli_sql_validation.cpp` 是隔離準備檢查核心。它絕不執行語句。
`ohos/entry/src/main/ets/plugins/QfliSqlNative.ets` 是 ArkTS 通道 `qfli_sql/native` 派發。
`native/mysql/` 存放 Oracle 伺服器修補、交叉建置腳本、封裝與子行程入口。`native/tests/` 存放驗證工具。
`native/README.md` 仍只描述兩個 NAPI 函式。該說明已過時。實際橋接暴露五個方法。
Oracle 原生文件：[鴻蒙 arm64 伺服器移植](native/mysql/README.md)、[Windows 與 Linux 本機準備](native/mysql/desktop/README.md)、[Android Bionic 建置](native/mysql/android/README.md)。

## 離線邊界

應用依設計離線。`sqlProfile.isOffline` 為 true。
`SqlEnginePreference` 拒絕儲存雲端選擇。
過時的雲端選擇會映射為本機 SQLite。它不開啟連線。
雲端查詢與腳本路徑先檢查策略。離線策略拒絕後續的權杖讀取與 API 存取。
鴻蒙 `EntryAbility` 在讀取參數前拒絕 `openAgreement`、`openUrl` 與 `login`。它只回傳一個 `OFFLINE_ONLY` 錯誤。
帳號通道保留註冊，供已儲存的呼叫方使用。應用不派發 AccountKit、路由或認證操作。
鴻蒙模組只要求 `ohos.permission.READ_PASTEBOARD`。
Oracle 使用私有本機通訊端。Oracle 不需要網路權限。封存檢查器也拒絕 INTERNET 權限。
工具與診斷只使用內建引擎、本機檔案與純計算。
開發者調查、Git 發佈與遠端推送可以使用網路。這不會修改應用的離線策略。

## 課程與發佈資源

課程來源檔位於 `tool/sql_curriculum/lessons/track_*.py`。這些來源檔建立 `assets/content/` 下的 JSON。

```bash
python tool/sql_curriculum/coverage.py
python tool/sql_curriculum/validate_content.py
python tool/sql_curriculum/validate_assets.py
```

本檢出的內容計數：126 個教學、126 個範例（120 SQLite 與 6 MySQL）、246 條練習答案、372 個執行分母中的腳本。
`tool/sql_curriculum/build_content.py` 重建發佈資源。
該腳本沒有 `--help` 解析器。傳入 `--help` 仍會改寫資源。
請先讀原始碼。請按需執行腳本。
原生涵蓋測試拒絕來源與輸出不一致。它也拒絕未知引擎。引擎過濾不會縮小分母。

## 當前驗收狀態

本節區分原始碼說明與實際驗證結果。
當前鴻蒙驗收仍待完成。
原始碼與宿主檢查已成立：SQLite 引擎是內建 3.50.0 單一檔案。它按平台封裝。
Dart、NAPI 與 ArkTS 層對五個原生方法、結果形狀與上限保持一致。
宿主測試與原生工具涵蓋引擎、診斷、終端、離線策略、工具與課程涵蓋。
鴻蒙橋接在 arm64 與 x86_64 上通過 `-Wall -Wextra -Werror` 編譯。
未驗收，本文不作通過聲明：目前沒有新的 HAP 建置、安裝或正常應用執行證據。
已記錄的稽核封裝早於當前的原生離線策略。該策略修改了原始碼與清單。
舊封裝不能證明當前策略。
正式簽章檔案缺失。稽核封裝只使用公開 SDK 測試身分。安裝信任仍未證明。
封裝的 x86_64 Oracle 產物已做建置與閉包稽核。中繼資料為 `runtimeVerified: false` 與 `deviceVerified: false`。
x86_64 只是已封裝，不是在裝置上證明啟動、持久化或關閉。
macOS Oracle 輔助程式建置仍未完成。執行也沒有驗證證據。
iOS Oracle 宿主與鴻蒙介面互動都需要各自可用的宿主。
應用沒有 SQL 除錯器、中斷點或單步後端。介面不提供這些控制項。

## 已知限制

超過引擎預算的 `.sql` 檔案只做詞法檢查。分析結果會註明該限制。
MySQL 診斷只有詞法層級。
SQLite 診斷在空的隔離資料庫上執行。缺失物件回報為涵蓋落差。
SQLite 表格介面不提供結構編輯或匯出。
Oracle 提供索引編輯。SQLite 只提供索引檢查與預覽 DDL。
交易必須寫在一個腳本內。應用沒有長期的手動交易工作階段。

## 延伸閱讀

- [SQL 工作台約定](.trellis/spec/frontend/sql-workbench.md)
- [SQLite 原生引擎約定](.trellis/spec/backend/sqlite-native-runtime.md)
- [SQL 診斷約定](.trellis/spec/backend/sql-diagnostics.md)
- [Oracle 鴻蒙引擎約定](.trellis/spec/backend/mysql-ohos-runtime.md)
- [鴻蒙稽核封裝](.trellis/spec/backend/ohos-audit-packaging.md)
- [SQL 終端與離線約定](.trellis/spec/frontend/sql-terminal-offline.md)
- [SQL 內容倉庫](.trellis/spec/frontend/sql-content-repository.md)

上游引擎：[SQLite](https://www.sqlite.org/) 3.50.0（公有領域）、[Oracle MySQL](https://www.mysql.com/) 8.4.6 社群原始碼、OpenSSL 3.5.3。
發佈套件必須附帶原生元件的配套材料。
材料包含上游原始碼、修補、建置腳本與授權聲明。
