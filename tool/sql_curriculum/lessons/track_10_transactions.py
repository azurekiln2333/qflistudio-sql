"""Track 10 — transactions (lessons 103-108)."""

from __future__ import annotations

from lessons.helper import E, L

LESSONS = [
    L(
        103, "txn-basic", "BEGIN/COMMIT/ROLLBACK", "advanced", "transactions",
        concepts=["BEGIN", "COMMIT", "ROLLBACK", "原子性"],
        objective="用事务把多条语句绑成原子操作",
        prerequisites=["掌握 DML"],
        explain=(
            "BEGIN 开启事务，COMMIT 提交，ROLLBACK 撤销自 BEGIN 以来的所有改动。事务保证原子"
            "性：要么全部生效，要么全部不生效。示例在事务内插入一行后 ROLLBACK，因此表里只有"
            "事务前的一行。SQLite 默认每条语句自动提交，显式事务才能跨语句保证一致性；长事务"
            "会持有写锁，应尽量短小。"
        ),
        setup=(
            "CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT);\n"
            "INSERT INTO t VALUES (1,'kept');\n"
            "BEGIN;\n"
            "INSERT INTO t VALUES (2,'rolled-back');\n"
            "ROLLBACK;"
        ),
        query="SELECT id, v FROM t ORDER BY id;",
        expected="1|kept",
        pitfalls=["忘记 COMMIT 会长时间持锁并在连接关闭时回滚。", "DDL 在部分数据库会隐式提交事务，SQLite 支持事务内 DDL 但需留意版本。"],
        exercises=[
            E("统计表中行数（验证回滚生效）。", "COUNT(*)。",
              "SELECT COUNT(*) FROM t;", "1"),
            E("返回表的所有 v，按 id 排序。", "SELECT v。",
              "SELECT v FROM t ORDER BY id;", "kept"),
        ],
    ),
    L(
        104, "savepoint", "SAVEPOINT 部分回滚", "advanced", "transactions",
        concepts=["SAVEPOINT", "RELEASE", "部分回滚"],
        objective="用保存点只回滚事务中的一部分",
        prerequisites=["掌握事务基础"],
        explain=(
            "SAVEPOINT 名字 建立保存点，ROLLBACK TO 名字 回滚到该点（其后的改动撤销，保存点仍"
            "存在），RELEASE 名字 释放保存点。示例在事务里插入 A、设保存点、插入 B、回滚到保存"
            "点，因此只保留 A；最后 COMMIT 提交 A。适合批量导入时跳过坏批次。"
        ),
        setup=(
            "CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT);\n"
            "BEGIN;\n"
            "INSERT INTO t VALUES (1,'A');\n"
            "SAVEPOINT sp1;\n"
            "INSERT INTO t VALUES (2,'B');\n"
            "ROLLBACK TO sp1;\n"
            "RELEASE sp1;\n"
            "COMMIT;"
        ),
        query="SELECT id, v FROM t ORDER BY id;",
        expected="1|A",
        pitfalls=["ROLLBACK TO 之后不 RELEASE 会保留保存点，嵌套层级需理清。", "保存点名称重复时会覆盖，注意作用域。"],
        exercises=[
            E("统计表行数（验证部分回滚）。", "COUNT(*)。",
              "SELECT COUNT(*) FROM t;", "1"),
            E("返回表中 id 最大的行的 v（单值）。", "ORDER BY id DESC LIMIT 1。",
              "SELECT v FROM t ORDER BY id DESC LIMIT 1;", "A"),
        ],
    ),
    L(
        105, "txn-atomicity", "事务中的错误与原子性", "advanced", "transactions",
        concepts=["原子性", "约束", "回滚"],
        objective="理解语句失败时事务的保留状态",
        prerequisites=["掌握 SAVEPOINT"],
        explain=(
            "事务中一条语句失败时，默认冲突动作 ABORT 只回滚这一条语句，事务中先前成功的语句"
            "仍然有效，直到显式 ROLLBACK。本课用 SAVEPOINT 演示：先写入 A，设保存点后写入一行"
            "NULL（违反 NOT NULL 被拒绝），再把保存点后的改动回滚，但保留保存点之前的 A；最后"
            "COMMIT。结果表只保留 A。若把 NOT NULL 错误改成整事务 ROLLBACK，则 A 也会消失。"
        ),
        setup=(
            "CREATE TABLE t (id INTEGER PRIMARY KEY, u TEXT NOT NULL);\n"
            "BEGIN;\n"
            "INSERT INTO t VALUES (1,'a');\n"
            "SAVEPOINT sp;\n"
            "INSERT OR IGNORE INTO t VALUES (2,NULL);\n"
            "ROLLBACK TO sp;\n"
            "RELEASE sp;\n"
            "COMMIT;"
        ),
        query="SELECT id, u FROM t ORDER BY id;",
        expected="1|a",
        pitfalls=["ABORT 与 ROLLBACK 冲突策略对事务其他语句的影响不同。", "应用层必须检查错误码，不能假设整批都成功。"],
        exercises=[
            E("统计表行数（验证仅失败语句被回滚）。", "COUNT(*)。",
              "SELECT COUNT(*) FROM t;", "1"),
            E("返回表内唯一值的数量（单值）。", "COUNT(DISTINCT u)。",
              "SELECT COUNT(DISTINCT u) FROM t;", "1"),
        ],
    ),
    L(
        106, "isolation", "隔离级别概念", "advanced", "transactions",
        concepts=["隔离级别", "脏读", "可重复读"],
        objective="理解隔离级别与并发异常的关系",
        prerequisites=["掌握事务原子性"],
        explain=(
            "隔离级别描述并发事务之间的可见性：READ UNCOMMITTED 可能脏读，READ COMMITTED 避免"
            "脏读，REPEATABLE READ 避免不可重复读，SERIALIZABLE 最强。SQLite 使用数据库级写锁，"
            "同一时刻只有一个写事务，默认提供可串行化的写；读在 WAL 模式下可与写并发。示例用"
            "单个连接演示提交前后可见性，因为 CLI 层面无法并发注入第二个事务。"
        ),
        setup=(
            "CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER);\n"
            "BEGIN IMMEDIATE;\n"
            "INSERT INTO t VALUES (1,10);\n"
            "COMMIT;"
        ),
        query="SELECT id, v FROM t ORDER BY id;",
        expected="1|10",
        pitfalls=["SQLite 无传统多版本隔离级别，跨进程并发模型与 MySQL 不同。", "MySQL 需 SET TRANSACTION ISOLATION LEVEL，默认 REPEATABLE READ，语义与 SQLite 不同。"],
        exercises=[
            E("返回提交后表中的行数（单值）。", "COUNT(*)。",
              "SELECT COUNT(*) FROM t;", "1"),
            E("返回表中 v 的总和（单值）。", "SUM(v)。",
              "SELECT SUM(v) FROM t;", "10"),
        ],
    ),
    L(
        107, "locking", "并发写与锁（SQLite 行为）", "advanced", "transactions",
        concepts=["写锁", "BUSY", "WAL"],
        objective="理解 SQLite 的写锁与忙等待行为",
        prerequisites=["掌握隔离级别概念"],
        explain=(
            "SQLite 默认 rollback journal 模式下写事务拿排他锁，第二个写者会得到 SQLITE_BUSY；"
            "可用 PRAGMA busy_timeout=5000 让驱动自动重试（本示例省略该语句以免输出回显）。"
            "WAL 模式允许多读一写。BEGIN IMMEDIATE 立即获取保留锁，避免读到中途升级锁导致的 "
            "BUSY。示例在本连接顺序执行两个事务，说明提交后数据可见；跨连接并发的 BUSY 需在"
            "驱动层设置超时处理。"
        ),
        setup=(
            "CREATE TABLE t (id INTEGER PRIMARY KEY, v INTEGER);\n"
            "BEGIN IMMEDIATE;\n"
            "INSERT INTO t VALUES (1,1);\n"
            "COMMIT;\n"
            "BEGIN IMMEDIATE;\n"
            "INSERT INTO t VALUES (2,2);\n"
            "COMMIT;"
        ),
        query="SELECT id, v FROM t ORDER BY id;",
        expected="1|1\n2|2",
        pitfalls=["未设 busy_timeout 时并发写会立刻 BUSY 失败。", "长事务占用写锁会让其他写入者超时，应尽快提交。"],
        exercises=[
            E("返回表中行数（单值）。", "COUNT(*)。",
              "SELECT COUNT(*) FROM t;", "2"),
            E("返回 v 的最大值（单值）。", "MAX(v)。",
              "SELECT MAX(v) FROM t;", "2"),
        ],
    ),
    L(
        108, "txn-capstone", "综合练习：转账原子操作", "advanced", "transactions",
        concepts=["事务", "一致性", "约束"],
        objective="用事务保证转账的借贷一致",
        prerequisites=["掌握本 track"],
        explain=(
            "转账必须在同一事务里完成扣款与入账，任一步失败都要整体回滚，且应校验余额充足与"
            "CHECK 非负。示例把 alice 的 30 转给 bob：一条 UPDATE 扣减、一条 UPDATE 增加，都在"
            "同一事务内，因此总额守恒。真实系统还会加行锁与幂等键防止重复提交。"
        ),
        setup=(
            "CREATE TABLE accounts (id INTEGER PRIMARY KEY, name TEXT UNIQUE, balance INTEGER NOT NULL CHECK (balance >= 0));\n"
            "INSERT INTO accounts VALUES (1,'alice',100),(2,'bob',50);\n"
            "BEGIN IMMEDIATE;\n"
            "UPDATE accounts SET balance = balance - 30 WHERE name = 'alice';\n"
            "UPDATE accounts SET balance = balance + 30 WHERE name = 'bob';\n"
            "COMMIT;"
        ),
        query="SELECT name, balance FROM accounts ORDER BY id;",
        expected="alice|70\nbob|80",
        pitfalls=["未校验余额时可能触发 CHECK 失败并回滚整笔。", "并发下需锁定或重试避免竞态双花。"],
        exercises=[
            E("返回账户余额总和（验证守恒，单值）。", "SUM(balance)。",
              "SELECT SUM(balance) FROM accounts;", "150"),
            E("返回余额最高的账户名（单值）。", "ORDER BY balance DESC LIMIT 1。",
              "SELECT name FROM accounts ORDER BY balance DESC LIMIT 1;", "bob"),
        ],
    ),
]
