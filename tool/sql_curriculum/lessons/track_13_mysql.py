"""Track 13 — MySQL-specific dialect lessons (lessons 121-126).

These lessons target MySQL 8.0 syntax and are NOT executed by the SQLite
validator. They are marked engine="mysql" so the validation report lists them
under "not executed" instead of falsely claiming execution. Explanations are
real and state the compatibility boundary versus SQLite.
"""

from __future__ import annotations

from lessons.helper import E, L

LESSONS = [
    L(
        121, "mysql-on-duplicate-key", "MySQL：ON DUPLICATE KEY UPDATE", "advanced", "mysql",
        concepts=["ON DUPLICATE KEY UPDATE", "UPSERT", "MySQL 8.0"],
        objective="用 MySQL 的 ON DUPLICATE KEY UPDATE 实现 upsert",
        prerequisites=["了解 UPSERT 概念与唯一约束"],
        explain=(
            "MySQL 8.0 的 upsert 写法是 INSERT ... ON DUPLICATE KEY UPDATE col = new.col（8.0.20 "
            "起推荐用行别名 new.col，替代已弃用的 VALUES(col)）。与 SQLite 的 ON CONFLICT(col) "
            "DO UPDATE 不同：MySQL 依据主键或唯一索引自动判断冲突，无需显式列出冲突列。本课为"
            "MySQL 8.0 专项，SQLite 无法执行，验证报告将其列为“未执行”；对应 SQLite 写法见第 "
            "101 课。"
        ),
        setup=(
            "CREATE TABLE counters (name VARCHAR(32) PRIMARY KEY, v INT NOT NULL);\n"
            "INSERT INTO counters VALUES ('a', 1);"
        ),
        query=(
            "INSERT INTO counters (name, v) VALUES ('a', 2) AS new\n"
            "  ON DUPLICATE KEY UPDATE v = counters.v + new.v;\n"
            "SELECT name, v FROM counters;"
        ),
        expected="a|3",
        pitfalls=[
            "不写行别名时需用已弃用的 VALUES()，注意 MySQL 版本。",
            "该语法在 SQLite 与 PostgreSQL 均不存在，跨库迁移需改写。",
        ],
        exercises=[
            E("按本课逻辑，冲突时应把新值累加还是覆盖？", "看 ON DUPLICATE KEY UPDATE 的表达式。",
              "SELECT v FROM counters;", "", verify_query=False),
        ],
        engine="mysql", version="8.0",
    ),
    L(
        122, "mysql-concat", "MySQL：CONCAT 与字符串长度", "advanced", "mysql",
        concepts=["CONCAT", "LENGTH", "CHAR_LENGTH", "MySQL 8.0"],
        objective="用 MySQL 的 CONCAT/CHAR_LENGTH 处理字符串",
        prerequisites=["了解 SQLite 的 || 拼接"],
        explain=(
            "MySQL 8.0 用 CONCAT(a,b) 拼接（任一参数为 NULL 结果为 NULL），LENGTH 返回字节数、"
            "CHAR_LENGTH 返回字符数；UTF-8 下中文 LENGTH 是 3 字节而 CHAR_LENGTH 是 1 字符。"
            "SQLite 用 || 拼接，length() 按字符计。本课为 MySQL 专项，SQLite 无法执行；跨越两"
            "种方言的说明见第 118 课。"
        ),
        setup=(
            "CREATE TABLE t (id INT PRIMARY KEY, s VARCHAR(64));\n"
            "INSERT INTO t VALUES (1,'Alice');"
        ),
        query=(
            "SELECT id, CONCAT(s, '@example.com') AS email, CHAR_LENGTH(s) AS n FROM t;"
        ),
        expected="1|Alice@example.com|5",
        pitfalls=[
            "CONCAT 遇 NULL 返回 NULL，需 COALESCE 兜底。",
            "LENGTH 对 UTF-8 中文返回字节数，常与直觉不符。",
        ],
        exercises=[
            E("MySQL 中 LENGTH('你好') 与 CHAR_LENGTH('你好') 是否相等？", "UTF-8 下中文 3 字节/字。",
              "SELECT LENGTH('你好'), CHAR_LENGTH('你好');", "", verify_query=False),
        ],
        engine="mysql", version="8.0",
    ),
    L(
        123, "mysql-date-add", "MySQL：DATE_ADD 与日期运算", "advanced", "mysql",
        concepts=["DATE_ADD", "DATEDIFF", "MySQL 8.0"],
        objective="用 MySQL 的 DATE_ADD/DATEDIFF 做日期运算",
        prerequisites=["了解 SQLite 的 date(x,'+1 day')"],
        explain=(
            "MySQL 8.0 用 DATE_ADD(d, INTERVAL 1 DAY) 做日期加法、DATEDIFF(a,b) 计算日期差，"
            "DATE 是一等类型。SQLite 用 date(x,'+1 day') 与 julianday 差。MySQL 的 DATEDIFF 只"
            "比较日期部分，更细粒度需 TIMESTAMPDIFF。本课为 MySQL 专项，SQLite 无法执行。"
        ),
        setup=(
            "CREATE TABLE shipments (id INT PRIMARY KEY, shipped_at DATE);\n"
            "INSERT INTO shipments VALUES (1,'2026-01-01');"
        ),
        query=(
            "SELECT id, DATE_ADD(shipped_at, INTERVAL 1 DAY) AS eta, "
            "DATEDIFF('2026-01-05', shipped_at) AS days FROM shipments;"
        ),
        expected="1|2026-01-02|4",
        pitfalls=[
            "INTERVAL 单位需正确拼写（DAY 而非 DAYS）。",
            "DATEDIFF 忽略时间部分，跨时区场景应改用 TIMESTAMPDIFF。",
        ],
        exercises=[
            E("DATEDIFF('2026-01-05','2026-01-01') 的结果是多少？", "日期差。",
              "SELECT DATEDIFF('2026-01-05','2026-01-01');", "", verify_query=False),
        ],
        engine="mysql", version="8.0",
    ),
    L(
        124, "mysql-isolation", "MySQL：事务隔离级别", "advanced", "mysql",
        concepts=["隔离级别", "REPEATABLE READ", "MySQL 8.0"],
        objective="用 MySQL 查看并设置事务隔离级别",
        prerequisites=["了解隔离级别概念"],
        explain=(
            "MySQL 8.0 默认隔离级别是 REPEATABLE READ，可用 SET SESSION TRANSACTION ISOLATION "
            "LEVEL READ COMMITTED 修改，并用 SELECT @@transaction_isolation 查看。SQLite 无此"
            "语句，采用数据库级写锁。MySQL 的 REPEATABLE READ 基于 MVCC 快照，间隙锁处理特定"
            "幻读场景。本课为 MySQL 专项，SQLite 无法执行。"
        ),
        setup=(
            "CREATE TABLE t (id INT PRIMARY KEY, v INT);\n"
            "INSERT INTO t VALUES (1,10);"
        ),
        query="SELECT @@transaction_isolation AS level;",
        expected="REPEATABLE-READ",
        pitfalls=[
            "会话级设置只影响当前连接；全局需 SET GLOBAL 且有权限。",
            "READ COMMITTED 与 REPEATABLE READ 对同一事务内重复读的可见性不同。",
        ],
        exercises=[
            E("MySQL 8.0 默认隔离级别是哪个？", "查看 @@transaction_isolation。",
              "SELECT @@transaction_isolation;", "", verify_query=False),
        ],
        engine="mysql", version="8.0",
    ),
    L(
        125, "mysql-group-concat", "MySQL：GROUP_CONCAT 与排序", "advanced", "mysql",
        concepts=["GROUP_CONCAT", "SEPARATOR", "MySQL 8.0"],
        objective="用 MySQL 的 GROUP_CONCAT 控制分隔符与排序",
        prerequisites=["了解 SQLite 的 GROUP_CONCAT"],
        explain=(
            "MySQL 8.0 的 GROUP_CONCAT(expr ORDER BY ... SEPARATOR ';') 可在聚合内指定排序与"
            "分隔符；SQLite 的 GROUP_CONCAT(expr, sep) 中分隔符是第二个参数，排序子句自 3.44 "
            "起支持。MySQL 结果受 group_concat_max_len 限制，超长会静默截断。本课为 MySQL 专项，"
            "SQLite 无法执行。"
        ),
        setup=(
            "CREATE TABLE s (id INT PRIMARY KEY, region VARCHAR(16), product VARCHAR(16));\n"
            "INSERT INTO s VALUES (1,'north','pen'),(2,'north','book'),(3,'south','bag');"
        ),
        query=(
            "SELECT region, GROUP_CONCAT(product ORDER BY product ASC SEPARATOR ',') AS products "
            "FROM s GROUP BY region ORDER BY region;"
        ),
        expected="north|book,pen\nsouth|bag",
        pitfalls=[
            "group_concat_max_len 默认 1024，超长截断需调大。",
            "SQLite 与 MySQL 的分隔符参数位置不同，迁移时易错。",
        ],
        exercises=[
            E("GROUP_CONCAT 不写 SEPARATOR 时默认分隔符是什么？", "查 MySQL 文档。",
              "SELECT GROUP_CONCAT(product) FROM s;", "", verify_query=False),
        ],
        engine="mysql", version="8.0",
    ),
    L(
        126, "mysql-full-join", "MySQL：FULL OUTER JOIN 的替代", "advanced", "mysql",
        concepts=["FULL OUTER JOIN", "UNION", "MySQL 8.0"],
        objective="用 LEFT/RIGHT JOIN + UNION 模拟 FULL OUTER JOIN",
        prerequisites=["掌握 JOIN 与 UNION"],
        explain=(
            "MySQL 8.0 不直接支持 FULL OUTER JOIN，标准做法是把 LEFT JOIN 与 RIGHT JOIN 结果做 "
            "UNION（去重）或 UNION ALL（配合去重条件）。SQLite 3.39 起原生支持 RIGHT/FULL JOIN。"
            "注意 UNION 会去除完全重复的行，若需保留应使用 UNION ALL。本课为 MySQL 专项，SQLite "
            "无法按此写法验证；对应 SQLite 的 FULL JOIN 说明见 JOIN track。"
        ),
        setup=(
            "CREATE TABLE a (id INT PRIMARY KEY, v VARCHAR(8));\n"
            "CREATE TABLE b (id INT PRIMARY KEY, v VARCHAR(8));\n"
            "INSERT INTO a VALUES (1,'x'),(2,'y');\n"
            "INSERT INTO b VALUES (2,'p'),(3,'q');"
        ),
        query=(
            "SELECT a.id, a.v, b.v FROM a LEFT JOIN b ON a.id=b.id\n"
            "UNION\n"
            "SELECT b.id, a.v, b.v FROM a RIGHT JOIN b ON a.id=b.id\n"
            "ORDER BY 1;"
        ),
        expected="1|x|\n2|y|p\n3||q",
        pitfalls=[
            "UNION 去重会改变行数，需确认语义。",
            "两分支列类型/顺序必须一致，否则报错或隐式转换。",
        ],
        exercises=[
            E("MySQL 8.0 是否有原生 FULL OUTER JOIN 关键字？", "查 MySQL 文档。",
              "SELECT 1;", "", verify_query=False),
        ],
        engine="mysql", version="8.0",
    ),
]
