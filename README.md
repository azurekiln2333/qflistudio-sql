# QFLISQLab（`qfli_sql`）

简体中文 · [繁體中文](README.zh-TW.md) · [English](README.en.md)

QFLISQLab 是用 Flutter 编写的离线 SQL 集成开发环境。
应用自带 SQLite 引擎。
应用也可在本机启动内置的 Oracle MySQL 服务端。
应用自带 SQL 课程。
使用应用不需要网络、云账号或外部 SQL 服务端。
本仓库是独立语言应用家族中的 SQL 产品，所有成员共用 `qfli_studio_core` 包。构建前请先读 [并行检出与依赖](#并行检出与依赖)。

## 产品简介

产品标识为 `qfli_sql`，产品键为 `sqlab`，版本为 `1.0.0`。包名为 `com.azurekiln.qfli.sqlab`。入口文件是 `lib/main.dart`。入口安装 `sqlProfile`。入口启动 `SqlLabApp`。
界面语言为简体中文（`zh-CN`）。课程资源也使用中文。
主界面有五个可滑动页面：数据库、项目、功能、教程、示例。手机用底部导航栏。宽屏用侧边导航栏。
每个页面拥有独立工具栏。外壳不显示第二个工具栏。

## 应用功能

### 数据库页面

`lib/sql_workbench_page.dart` 是数据库工作区。手机以可展开的库到表树为主体。桌面把树放在侧栏。
数据库独立展开或收起。点击行选中对象。SQLite 表格用隐藏行标识编辑数据。写入使用绑定参数。
存在未屏蔽的 `rowid` 别名时，SQLite 表格允许写入。
SQLite 表格为 `WITHOUT ROWID` 时，界面报告只读。
更新或删除影响的行数不等于 1 时，应用报告该行已过期。
历史记录上限为 100 条。已保存查询独立于引擎。保存失败不会丢弃有效结果。

### 项目页面

`lib/sql_projects_page.dart` 列出项目。页面提供搜索与「更多」菜单。
「更多」菜单可以添加现有项目。它也可以删除失效项目。
打开项目会进入编辑器。
文档与光标保留、命名工作区入口和已保存的工作区都尚未提交。它们的验收仍待完成。
项目 SQL 在项目自己的库中执行。SQLite 项目用 `<project>/.qfli/data.sqlite`。Oracle 项目用 `<project>/.qfli/mysql.json` 中的数据库名。

### 功能页面

SQL 能力直接放在本页。本页没有通用「专用功能」跳转页。
快捷入口保留共享工具路由与完整终端。工作表显示抓取的引擎与数据库标识。工作表执行脚本。工作表显示有序结果。
查询计划为一条受保护语句添加 `EXPLAIN QUERY PLAN` 或 `EXPLAIN`。应用不执行 `EXPLAIN ANALYZE`。应用不重跑工作表语句。结构与索引显示列名、类型、可空、主键与计算列标记。它检查索引。
文本与值工具保留字面量与引号标识符的格式化。它区分 NULL 与空串。
SQLite 索引数据来自 `PRAGMA main.index_list`。Oracle 数据来自 `information_schema`。索引创建是一条预览的 `CREATE INDEX` 语句。
引擎不可用时界面报告不可用。界面不把 SQLite 结果标注为 MySQL。

### 教程与示例页面

两个页面通过 `lib/sql_content_repository.dart` 读取本应用自己的资源。
`assets/content/sql_tutorials.json` 有 126 个教程。每个课程一节。
`assets/content/sql_examples.json` 有 126 个示例。其中 120 个针对 SQLite。6 个针对 MySQL。共 246 条练习答案。
每个示例都是自包含脚本。脚本含建表、插入与查询。脚本带人工编写的期望结果。
摘要与概念注明 SQL 方言。

### 编辑器诊断

`lib/sql_code_analyzer.dart` 为未保存的 SQL 缓冲实现共享 `CodeAnalyzer` 约定。
分析读取精确的未保存快照。分析不重读磁盘文件。分析不保存编辑器。分析不执行用户 SQL。
词法检查只报告可证明的问题。例如未结束字符串、未结束引号标识符、括号不匹配。
引擎语法检查让原生层在私有 `:memory:` 数据库中准备语句。它从不执行语句。它也从不打开用户数据库。
范围使用从零开始的 UTF-16 半开偏移。原生层会转换 UTF-8 字节偏移。
缺失对象报告为覆盖缺口。它不是语法错误。引擎失败报告为不可用。它不是干净结果。
SQLite 引擎检查最多准备 512 次语句。
它拒绝 PRAGMA、ATTACH、DETACH、外部文件函数与虚拟表。
MySQL 项目只提供词法诊断。MySQL 没有完整语法检查。

### 终端

`lib/sql_runner.dart` 向独立终端与编辑器终端提供同一个 SQL 委托。

```text
sql <file.sql>
sql -e "SQL"
sql --execute "SQL"
sql --help
```

未知命令返回 false。共享文件命令继续工作。路径必须留在终端沙箱内。路径也包括解析后的符号链接。
应用没有交互式 `mysql` 或 `sqlite3` 客户端。应用也没有 SQL 取消接口。

## 引擎与平台限制

应用有两个本地引擎。引擎可用性不会改变已选择的引擎。SQLite 桥接方法：`execute`、`executeScript`、`query`、`validate`、`version`。

| 平台 | SQLite 传输方式 |
| --- | --- |
| Android、iOS、Windows、Linux、macOS | `dart:ffi` 调用随应用发布的 C 库 |
| 鸿蒙（OHOS） | `qfli_sql/native` 通道上的 `libqfli_sql.so` |
| Web | 不支持，SQL 引擎只支持原生平台 |

SQLite 单次查询上限为 500 完整行与 1 MiB 单元格数据。
脚本显示预算为 500 行与 1 MiB。预算共用整个脚本。语句数上限为 512。结构化查询的锁等待最多 3000 毫秒。Dart 层输入上限为 512 Ki UTF-16。原生层再限 1 MiB UTF-8。
截断不会返回不完整的行。出现错误或达到上限时，已完成结果保留。摘要标记失败。

### Oracle MySQL 8.4.6（内置服务端）

| 平台 | 状态 |
| --- | --- |
| Windows、Linux | 应用启动本机服务端。连接使用私有管道或套接字。服务端不开放 TCP。 |
| Android | 仅支持 64 位。最低要求为 API 28。 |
| macOS | 辅助程序构建与签名的脚本仍未提交，执行也未验证 |
| iOS | 未实现 |
| 鸿蒙 | 已打包 arm64-v8a 与 x86_64。手机通过私有镜像分叉宿主启动服务端 |

历史宿主检查使用 Windows MySQL 8.4.6 与 Linux MySQL 8.0.46。
2026 年 10 月 2 日，API 37 x86_64 模拟器通过引擎集成测试。
2026 年 10 月 15 日，API 36 ARM64 OPD2413 真机通过同类测试。
这些历史结果不代表当前源码已验收。

Oracle 使用私有套接字或管道。Oracle 开启 `skip-networking`。TCP 不能作为回退。应用也不申请 INTERNET 权限。
MySQL 输入上限为 1 MiB。默认显示上限为 1000 行或 1 MiB。
每个脚本最多保留 128 个结果集。最大数据包为 8 MiB。截断只限制输出。后续语句仍然执行。
MySQL 的许多 DDL 会隐式提交事务。脚本出错时前面改动可能留在库中。两个引擎都为每次调用打开新连接。应用不提供独立的开始、提交或回滚按钮。
事务必须写在一次脚本内。此时连接才真实存在。

## 并行检出与依赖

`pubspec.yaml` 通过相对路径依赖共享核心与内置编辑器。
请把 `qfli_studio_core` 检出为同级目录。
请在本仓库解析依赖。

```text
checkout-parent/
  qfli_studio_core/
  qfli_sql/
```

内置编辑器路径为 `../qfli_studio_core/vendor/re_editor`。

```bash
flutter pub get
```

共享核心由其他负责人维护。它也会同时改动。需要带 Dart `^3.11.5` 的 Flutter SDK。鸿蒙构建还需要 Flutter 鸿蒙分支、已安装的 DevEco Studio 与签名身份。
不要从本仓库修改 `../qfli_studio_core`。请记录实际使用的核心版本。

## 构建与执行

请先在仓库根目录解析依赖。

```bash
flutter pub get
flutter run -d <device-id>
flutter build windows
```

桌面目标还有 `linux` 与 `macos`。
鸿蒙审计打包用仓库自带脚本。脚本构建独立的审计包。脚本随后逐字节恢复原始配置。
执行前请先读 [`ohos-audit-packaging.md`](.trellis/spec/backend/ohos-audit-packaging.md)。

```powershell
& tool/ohos/build_audit_hap.ps1 -Target <entry>.dart -Architecture ohos-arm64
& tool/ohos/sign_audit_hap.ps1 -DeviceUdid <actual-device-udid>
```

打包成功不代表安装成功。打包成功也不代表可以执行。
Oracle 数据是独立构建。请先构建固定的原生产物。请再构建应用。`native/CMakeLists.txt` 与 Hvigor 都要求受支持 ABI 的真实包。缺少原生产物时 arm64 构建失败。
不支持的架构改为构建 `native/src/qfli_mysql_unavailable.cpp`。该文件返回显式不可用结果。它不使用替代引擎。

## 测试与静态检查

```bash
flutter analyze --no-pub lib test integration_test
flutter test --no-pub
```

聚焦测试位于 `test/`。平台允许时测试使用真实引擎。平台不允许时测试注入 `MethodChannel`。
`test/sqlite_ffi_test.dart` 验证真实 SQLite 的持久化、事务、边界与上限。
`test/sql_code_analyzer_test.dart` 验证真实 FFI 的 `validate` 路径。
`test/sql_terminal_commands_test.dart` 与 `test/sql_offline_policy_test.dart` 验证终端与离线拒绝。
`test/sql_curriculum_test.dart` 与 `test/sql_curriculum_native_coverage_test.dart` 验证资源覆盖。
需要真实原生库或设备的测试会打印显式跳过。跳过不算通过。请把不可用跳过与通过分开记录。

```powershell
& native/tests/run-sql-validation-test.ps1
& native/tests/check-ohos-sql-napi-syntax.ps1
```

第一个脚本对真实内置 SQLite 执行隔离验证核心。
第二个脚本为 arm64 与 x86_64 做编译检查。检查选项为 `-Wall -Wextra -Werror`。
缺少 DevEco SDK 时第二个脚本打印 `SKIP` 并返回 0。语法检查不是执行验收。Oracle 宿主验证与前置条件见 `native/tests/README.md`。集成测试需要已连接设备。入口在 `integration_test/`。
平台 ArkTS 离线策略检查不需要设备：

```bash
node tool/test_sql_offline_platform.cjs
```

## 原生引擎与文档

`native/third_party/sqlite/` 是未修改的 SQLite 3.50.0 单文件。它属于公有领域。`native/src/qfli_sql_bridge.c` 是 FFI 脚本与结果桥。它使用制表符分隔输出。
`native/src/qfli_mysql_client.cpp` 是 Oracle C API 客户端。它使用私有套接字与预编译语句。`ohos/entry/src/main/cpp/qfli_sql_napi.cpp` 是鸿蒙 NAPI 模块。它覆盖五个方法。
`ohos/entry/src/main/cpp/qfli_sql_validation.cpp` 是隔离准备检查核心。它绝不执行语句。`ohos/entry/src/main/ets/plugins/QfliSqlNative.ets` 是 ArkTS 通道 `qfli_sql/native` 派发。
`native/mysql/` 存放 Oracle 服务端补丁、交叉构建脚本、打包与子进程入口。`native/tests/` 存放验证工具。
`native/README.md` 仍只描述两个 NAPI 函数。该说明已过期。实际桥接暴露五个方法。
Oracle 原生文档：[鸿蒙 arm64 服务端移植](native/mysql/README.md)、[Windows 与 Linux 本机准备](native/mysql/desktop/README.md)、[Android Bionic 构建](native/mysql/android/README.md)。

## 离线边界

应用按设计离线。`sqlProfile.isOffline` 为 true。
`SqlEnginePreference` 拒绝保存云选择。陈旧的云选择会映射为本地 SQLite。它不会打开连接。
云查询与脚本路径先检查策略。离线策略阻止令牌读取。离线策略阻止云 API 调用。鸿蒙 `EntryAbility` 在读取参数前拒绝 `openAgreement`、`openUrl` 与 `login`。它只返回一个 `OFFLINE_ONLY` 错误。
账号通道保留注册，供已保存的调用方使用。应用不派发 AccountKit、路由或认证操作。鸿蒙模块只申请 `ohos.permission.READ_PASTEBOARD`。Oracle 使用私有本地套接字。Oracle 不需要网络权限。归档检查器也拒绝 INTERNET 权限。
工具与诊断只使用内置引擎、本机文件与纯计算。开发者调研、Git 发布与远程推送可以使用网络。这不会改变应用的离线策略。

## 课程与发布资源

课程源文件位于 `tool/sql_curriculum/lessons/track_*.py`。`assets/content/` 下的 JSON 由这些源文件创建。

```bash
python tool/sql_curriculum/coverage.py
python tool/sql_curriculum/validate_content.py
python tool/sql_curriculum/validate_assets.py
```

本检出的内容计数：126 个教程、126 个示例（120 SQLite 与 6 MySQL）、246 条练习答案、372 个执行分母中的脚本。
`tool/sql_curriculum/build_content.py` 重新创建发布资源。
该脚本没有 `--help` 解析器。传入 `--help` 仍会重写资源。请先读源码。请按需执行脚本。原生覆盖测试拒绝源与输出漂移。它也拒绝未知引擎。引擎过滤不会缩小分母。

## 当前验收状态

本节区分源码说明与实际验证结果。当前鸿蒙验收仍待完成。
源码与宿主检查已成立：SQLite 引擎是内置 3.50.0 单文件。它按平台打包。
Dart、NAPI 与 ArkTS 层对五个原生方法、结果形状与上限保持一致。
宿主测试与原生工具覆盖引擎、诊断、终端、离线策略、工具与课程覆盖。
鸿蒙桥接在 arm64 与 x86_64 上通过 `-Wall -Wextra -Werror` 编译。
未验收。本文不作通过声明。当前没有新的 HAP 构建、安装或正常应用执行证据。
已记录的审计包早于当前的原生离线策略。该策略改动了源码与清单。
旧包不能证明当前策略。生产签名文件缺失。审计包只使用公开 SDK 测试身份。安装信任仍未证明。打包的 x86_64 Oracle 产物已做构建与闭包审计。它的元数据为 `runtimeVerified: false` 与 `deviceVerified: false`。
x86_64 只是已打包。它不是在设备上证明启动、持久化或关闭。macOS Oracle 辅助程序构建与签名的脚本仍未提交。macOS 执行仍未验证。iOS Oracle 宿主与鸿蒙界面交互都需要各自的可用宿主。应用没有 SQL 调试器、断点或单步后端。界面不提供这些控件。

## 已知限制

超过引擎预算的 `.sql` 文件只做词法检查，该限制会写在分析结果中。
MySQL 诊断只有词法级别。SQLite 诊断在空的隔离库上执行。缺失对象报告为覆盖缺口。
SQLite 表格界面不提供结构编辑或导出。Oracle 提供索引编辑。SQLite 只提供索引检查与预览 DDL。
事务必须写在一次脚本内。应用没有长期的手动事务会话。

## 延伸阅读

- [SQL 工作台约定](.trellis/spec/frontend/sql-workbench.md)
- [SQLite 原生引擎约定](.trellis/spec/backend/sqlite-native-runtime.md)
- [SQL 诊断约定](.trellis/spec/backend/sql-diagnostics.md)
- [Oracle 鸿蒙引擎约定](.trellis/spec/backend/mysql-ohos-runtime.md)
- [鸿蒙审计打包](.trellis/spec/backend/ohos-audit-packaging.md)
- [SQL 终端与离线约定](.trellis/spec/frontend/sql-terminal-offline.md)
- [SQL 内容仓库](.trellis/spec/frontend/sql-content-repository.md)

上游引擎：[SQLite](https://www.sqlite.org/) 3.50.0（公有领域）、[Oracle MySQL](https://www.mysql.com/) 8.4.6 社区源码、OpenSSL 3.5.3。
发布包必须附带原生组件的配套材料。
材料包含上游源码、补丁、构建脚本与许可声明。
