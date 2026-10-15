"""Track 8 — DDL and constraints (lessons 83-94)."""

from __future__ import annotations

from lessons.helper import E, L

LESSONS = [
    L(
        83, "create-table", "CREATE TABLE 与列类型", "intermediate", "ddl",
        concepts=["CREATE TABLE", "类型", "NOT NULL"],
        objective="用 CREATE TABLE 定义表和列并选择合适类型",
        prerequisites=["掌握 SELECT 与表达式"],
        explain=(
            "CREATE TABLE 定义列名、类型与约束。SQLite 3.50 使用类型亲和（类型名中带 INT/"
            "CHAR/CLOB/TEXT/BLOB/REAL/FLOA/DOUB 时映射到对应亲和），而不是严格类型；列仍可"
            "存其他类型，但亲和会影响比较与 CAST。示例建一张 books 表，用 TEXT/INTEGER/REAL "
            "表达书名、数量与价格，这是可读性与约束兼得的最小定义。"
        ),
        setup=(
            "CREATE TABLE books (id INTEGER PRIMARY KEY, title TEXT NOT NULL, qty INTEGER, price REAL);\n"
            "INSERT INTO books VALUES (1,'SQL 入门',3,59.9),(2,'数据库原理',NULL,79.0);"
        ),
        query="SELECT id, title, qty, price FROM books ORDER BY id;",
        expected="1|SQL 入门|3|59.9\n2|数据库原理||79.0",
        pitfalls=["把 TEXT 强塞数字会导致比较按文本进行，排序与聚合结果异常。", "SQLite 不强制列类型，写入错误类型不会报错。"],
        exercises=[
            E("返回 title 以 'SQL' 开头的书 id，按 id 排序。", "title LIKE 'SQL%'。",
              "SELECT id FROM books WHERE title LIKE 'SQL%' ORDER BY id;", "1"),
            E("返回数量为 NULL 的书 id，按 id 排序。", "qty IS NULL。",
              "SELECT id FROM books WHERE qty IS NULL ORDER BY id;", "2"),
        ],
    ),
    L(
        84, "primary-key-autoincrement", "PRIMARY KEY 与自增", "intermediate", "ddl",
        concepts=["PRIMARY KEY", "AUTOINCREMENT", "rowid"],
        objective="用主键唯一标识行并理解自增行为",
        prerequisites=["掌握 CREATE TABLE"],
        explain=(
            "INTEGER PRIMARY KEY 是 rowid 的别名，插入 NULL 或省略时自动分配递增整数，且"
            "复用被删除的最大值；加 AUTOINCREMENT 则保证单调递增、不复用历史值，代价是额外"
            "维护 sqlite_sequence。示例显式插入 id=10 后再插入两行，自增从 11 继续。"
        ),
        setup=(
            "CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT);\n"
            "INSERT INTO t (id, v) VALUES (10,'a');\n"
            "INSERT INTO t (v) VALUES ('b'),('c');"
        ),
        query="SELECT id, v FROM t ORDER BY id;",
        expected="10|a\n11|b\n12|c",
        pitfalls=["复合主键不能使用 INTEGER PRIMARY KEY 的自增别名行为。", "AUTOINCREMENT 影响删除后重用，非必要不启用。"],
        exercises=[
            E("返回最大 id（单值）。", "MAX(id)。",
              "SELECT MAX(id) FROM t;", "12"),
            E("统计行数（单值）。", "COUNT(*)。",
              "SELECT COUNT(*) FROM t;", "3"),
        ],
    ),
    L(
        85, "not-null-default", "NOT NULL 与 DEFAULT", "intermediate", "ddl",
        concepts=["NOT NULL", "DEFAULT"],
        objective="用 NOT NULL 禁止缺失并用 DEFAULT 提供默认值",
        prerequisites=["掌握 CREATE TABLE"],
        explain=(
            "NOT NULL 拒绝写入 NULL；DEFAULT 在未提供该列值时生效（显式写 NULL 仍会写入 NULL，"
            "除非违反 NOT NULL）。示例 status 默认 'new'，插入时不写 status 的行会得到 'new'，"
            "而显式写 NULL 的行会因 NOT NULL 约束被拒绝——本课数据都合法，故 status 均非空。"
        ),
        setup=(
            "CREATE TABLE tasks (id INTEGER PRIMARY KEY, title TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'new');\n"
            "INSERT INTO tasks (id, title) VALUES (1,'写文档');\n"
            "INSERT INTO tasks (id, title, status) VALUES (2,'评审','doing');"
        ),
        query="SELECT id, title, status FROM tasks ORDER BY id;",
        expected="1|写文档|new\n2|评审|doing",
        pitfalls=["DEFAULT 只在列被省略时生效，显式 NULL 不会触发默认值。", "NOT NULL 与 DEFAULT 组合时，DEFAULT 值必须非 NULL。"],
        exercises=[
            E("返回 status 为 'new' 的任务 id，按 id 排序。", "WHERE status='new'。",
              "SELECT id FROM tasks WHERE status = 'new' ORDER BY id;", "1"),
            E("统计 doing 状态的任务数（单值）。", "COUNT(*) 配 WHERE。",
              "SELECT COUNT(*) FROM tasks WHERE status = 'doing';", "1"),
        ],
    ),
    L(
        86, "unique-constraint", "UNIQUE 约束", "intermediate", "ddl",
        concepts=["UNIQUE", "唯一性"],
        objective="用 UNIQUE 保证列值（或组合）唯一",
        prerequisites=["掌握主键"],
        explain=(
            "UNIQUE 建立唯一索引，重复插入会被拒绝；SQLite 中多个 NULL 不违反 UNIQUE（NULL 互"
            "不相等）。示例 username 唯一，插入 alice 两次会失败，因此下面的数据只含不同用户。"
            "唯一约束是业务去重的最后防线，不能只依赖应用层检查。"
        ),
        setup=(
            "CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT UNIQUE NOT NULL, email TEXT);\n"
            "INSERT INTO users VALUES (1,'alice','a@x.com'),(2,'bob',NULL);"
        ),
        query="SELECT id, username, COALESCE(email,'-') AS email FROM users ORDER BY id;",
        expected="1|alice|a@x.com\n2|bob|-",
        pitfalls=["UNIQUE 允许重复 NULL，需要 NOT NULL 才能真正唯一。", "冲突时默认中止语句，可用 ON CONFLICT 指定替代动作。"],
        exercises=[
            E("返回 username 为 'bob' 的用户 id（单值）。", "WHERE username='bob'。",
              "SELECT id FROM users WHERE username = 'bob';", "2"),
            E("统计不同 username 的数量（单值）。", "COUNT(DISTINCT username)。",
              "SELECT COUNT(DISTINCT username) FROM users;", "2"),
        ],
    ),
    L(
        87, "check-constraint", "CHECK 约束", "intermediate", "ddl",
        concepts=["CHECK", "域约束"],
        objective="用 CHECK 在写入时校验取值范围",
        prerequisites=["掌握 UNIQUE"],
        explain=(
            "CHECK(expr) 在插入或更新时求值，为假（0）则拒绝，NULL 视为通过（因为未知）。示例"
            "限制 qty >= 0，插入负数量会被拒绝。CHECK 是数据库层的域约束，能拦住绕过应用层"
            "的写入路径，但表达式应尽量简单以保证可预测。"
        ),
        setup=(
            "CREATE TABLE stock (id INTEGER PRIMARY KEY, name TEXT, qty INTEGER CHECK (qty >= 0));\n"
            "INSERT INTO stock VALUES (1,'pen',10),(2,'book',0);"
        ),
        query="SELECT id, name, qty FROM stock ORDER BY id;",
        expected="1|pen|10\n2|book|0",
        pitfalls=["CHECK 对 NULL 求值为 NULL，不会拒绝 NULL，需配合 NOT NULL。", "复杂 CHECK 在每次写入都求值，有轻微开销。"],
        exercises=[
            E("返回 qty 为 0 的商品 id，按 id 排序。", "WHERE qty=0。",
              "SELECT id FROM stock WHERE qty = 0 ORDER BY id;", "2"),
            E("返回 qty 大于 5 的商品名，按 id 排序。", "WHERE qty>5。",
              "SELECT name FROM stock WHERE qty > 5 ORDER BY id;", "pen"),
        ],
    ),
    L(
        88, "foreign-key", "FOREIGN KEY 与外键动作", "intermediate", "ddl",
        concepts=["FOREIGN KEY", "ON DELETE", "引用完整性"],
        objective="用外键维护引用完整性并选择删除动作",
        prerequisites=["掌握主键与 UNIQUE"],
        explain=(
            "外键要求子表引用父表存在的键。SQLite 默认关闭外键强制，需要 PRAGMA "
            "foreign_keys=ON。示例 orders.customer_id 引用 customers.id，并用 JOIN 取回客户名。"
            "ON DELETE CASCADE 会在父行删除时级联删除子行，RESTRICT 则拒绝删除被引用的父行。"
        ),
        setup=(
            "PRAGMA foreign_keys = ON;\n"
            "CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT);\n"
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER REFERENCES customers(id), amount INTEGER);\n"
            "INSERT INTO customers VALUES (1,'alice'),(2,'bob');\n"
            "INSERT INTO orders VALUES (1,1,100),(2,2,200);"
        ),
        query=(
            "SELECT o.id, c.name, o.amount FROM orders AS o "
            "JOIN customers AS c ON c.id = o.customer_id ORDER BY o.id;"
        ),
        expected="1|alice|100\n2|bob|200",
        pitfalls=["忘记 PRAGMA foreign_keys=ON 时外键不生效。", "删除被引用父行若未定义动作会报错，需明确 CASCADE/SET NULL/RESTRICT。"],
        exercises=[
            E("返回 alice 的订单总额（单值）。",
              "JOIN 后 WHERE c.name='alice' 再 SUM。",
              "SELECT SUM(o.amount) FROM orders AS o JOIN customers AS c ON c.id = o.customer_id WHERE c.name = 'alice';",
              "100"),
            E("返回 bob 的订单 id（单值）。",
              "JOIN 后 WHERE c.name='bob'。",
              "SELECT o.id FROM orders AS o JOIN customers AS c ON c.id = o.customer_id WHERE c.name = 'bob';",
              "2"),
        ],
    ),
    L(
        89, "generated-columns", "生成列（GENERATED）", "intermediate", "ddl",
        concepts=["GENERATED", "虚拟列", "STORED"],
        objective="用生成列表达派生值避免重复计算",
        prerequisites=["掌握 CHECK 与表达式"],
        explain=(
            "SQLite 3.31 起支持生成列：VIRTUAL（默认，读取时计算）与 STORED（写入时计算并"
            "存储）。生成列不能直接写入。示例 total 由 price*qty 生成，查询时无需重复表达式，"
            "适合放稳定的派生字段；但生成列不能引用其他生成列以外的非确定性函数。"
        ),
        setup=(
            "CREATE TABLE items (id INTEGER PRIMARY KEY, price REAL, qty INTEGER, "
            "total REAL GENERATED ALWAYS AS (price * qty) STORED);\n"
            "INSERT INTO items (id, price, qty) VALUES (1, 10.0, 3), (2, 5.0, 4);"
        ),
        query="SELECT id, price, qty, total FROM items ORDER BY id;",
        expected="1|10.0|3|30.0\n2|5.0|4|20.0",
        pitfalls=["生成列不可 INSERT/UPDATE，写出错会报错。", "VIRTUAL 不占存储但每次读取计算，热点查询可考虑 STORED。"],
        exercises=[
            E("返回 total 大于 25 的 item id，按 id 排序。", "WHERE total>25。",
              "SELECT id FROM items WHERE total > 25 ORDER BY id;", "1"),
            E("返回 total 的总和（单值）。", "SUM(total)。",
              "SELECT SUM(total) FROM items;", "50.0"),
        ],
    ),
    L(
        90, "alter-table", "ALTER TABLE 加列改列", "intermediate", "ddl",
        concepts=["ALTER TABLE", "迁移"],
        objective="用 ALTER TABLE 增加列并了解删改限制",
        prerequisites=["掌握 CREATE TABLE"],
        explain=(
            "SQLite 的 ALTER TABLE 能力有限：支持 RENAME TO、RENAME COLUMN、ADD COLUMN，"
            "不支持直接 DROP COLUMN（3.35 起支持 DROP COLUMN 但有约束）或修改列类型；改类型"
            "需建新表、搬迁数据再替换。示例先建表再加一列 note 并回填，演示无损加列。"
        ),
        setup=(
            "CREATE TABLE logs (id INTEGER PRIMARY KEY, msg TEXT);\n"
            "INSERT INTO logs VALUES (1,'start'),(2,'stop');\n"
            "ALTER TABLE logs ADD COLUMN level TEXT DEFAULT 'info';\n"
            "UPDATE logs SET level = 'warn' WHERE id = 2;"
        ),
        query="SELECT id, msg, level FROM logs ORDER BY id;",
        expected="1|start|info\n2|stop|warn",
        pitfalls=["ADD COLUMN 若带非常量默认值会失败。", "改列类型/删除列要建新表迁移，注意事务包裹。"],
        exercises=[
            E("返回 level 为 'warn' 的日志 id，按 id 排序。", "WHERE level='warn'。",
              "SELECT id FROM logs WHERE level = 'warn' ORDER BY id;", "2"),
            E("返回 level 为 'info' 的日志数量（单值）。", "COUNT(*) 配 WHERE。",
              "SELECT COUNT(*) FROM logs WHERE level = 'info';", "1"),
        ],
    ),
    L(
        91, "drop-table", "DROP TABLE 与 IF EXISTS", "intermediate", "ddl",
        concepts=["DROP TABLE", "IF EXISTS", "清理"],
        objective="安全地删除表并避免不存在时出错",
        prerequisites=["掌握 ALTER TABLE"],
        explain=(
            "DROP TABLE t 删除表及其数据与索引；表不存在会报错，DROP TABLE IF EXISTS t 则"
            "静默通过。示例先建临时表 tmp 再删除，随后用查询证明它已不在 sqlite_master 中。"
            "生产环境删除表的脚本应写 IF EXISTS 以便可重复执行。"
        ),
        setup=(
            "CREATE TABLE keep (id INTEGER PRIMARY KEY);\n"
            "CREATE TABLE tmp (id INTEGER PRIMARY KEY);\n"
            "INSERT INTO keep VALUES (1);\n"
            "DROP TABLE IF EXISTS tmp;"
        ),
        query="SELECT name FROM sqlite_master WHERE type = 'table' AND name IN ('keep','tmp') ORDER BY name;",
        expected="keep",
        pitfalls=["DROP TABLE 不可回滚到删除前状态（除非在事务内且未提交）。", "删除表不会自动清理视图/触发器对它的依赖。"],
        exercises=[
            E("tmp 已被删除后，返回 keep 表里的 id（验证删除没有误伤其它表）。",
              "直接查 keep。",
              "SELECT id FROM keep ORDER BY id;", "1"),
            E("统计 sqlite_master 中名为 keep 的表数量（单值）。", "COUNT(*) 配 WHERE。",
              "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='keep';", "1"),
        ],
    ),
    L(
        92, "temp-tables", "临时表与内存表", "intermediate", "ddl",
        concepts=["TEMP", "临时表", "会话"],
        objective="用临时表存放会话级中间结果",
        prerequisites=["掌握 CREATE TABLE"],
        explain=(
            "CREATE TEMP TABLE 建在当前连接可见的 temp 数据库中，连接关闭即消失，不污染主库。"
            "适合分步计算、导入暂存。SQLite 3.50 中示例在同一连接内建临时表 stage、写入三行"
            "再聚合。注意：临时表是连接作用域，本课练习必须与 setup 在同一连接（同一 sqlite3"
            "会话）内执行才能看到 stage；跨连接会报 no such table。临时表也可建索引提升中间"
            "步骤性能。"
        ),
        setup=(
            "CREATE TEMP TABLE stage (id INTEGER, amount INTEGER);\n"
            "INSERT INTO stage VALUES (1,10),(2,20),(3,30);"
        ),
        query="SELECT COUNT(*) AS n, SUM(amount) AS total FROM stage;",
        expected="3|60",
        pitfalls=["临时表对其他连接不可见，练习/验证必须与建表在同一连接内执行，否则 no such table。", "大量临时数据占内存或临时目录，注意清理。"],
        exercises=[
            E("返回 stage 中 amount 最大的行 id（单值）。",
              "子查询或 ORDER BY LIMIT。",
              "SELECT id FROM stage ORDER BY amount DESC LIMIT 1;", "3"),
            E("返回 stage 的金额平均值（单值）。", "AVG(amount)。",
              "SELECT AVG(amount) FROM stage;", "20.0"),
        ],
    ),
    L(
        93, "constraint-conflicts", "约束冲突与错误处理", "intermediate", "ddl",
        concepts=["ON CONFLICT", "ROLLBACK", "ABORT"],
        objective="理解约束冲突策略并选择合适动作",
        prerequisites=["掌握 UNIQUE 与 CHECK"],
        explain=(
            "约束冲突时可指定 ON CONFLICT 动作：ABORT（默认，回滚当前语句）、ROLLBACK（回滚"
            "整个事务）、FAIL（停止但保留已改行）、IGNORE（跳过该行）、REPLACE（删除冲突行再"
            "插入）。示例用 OR IGNORE 跳过重复 username，因此只保留首次出现的行。"
        ),
        setup=(
            "CREATE TABLE t (id INTEGER PRIMARY KEY, u TEXT UNIQUE);\n"
            "INSERT INTO t VALUES (1,'a');\n"
            "INSERT OR IGNORE INTO t VALUES (2,'a');\n"
            "INSERT OR IGNORE INTO t VALUES (3,'b');"
        ),
        query="SELECT id, u FROM t ORDER BY id;",
        expected="1|a\n3|b",
        pitfalls=["OR REPLACE 会删除旧行再插入，可能触发外键级联删除。", "ABORT 与 FAIL 在事务内的保留行行为不同，需分清。"],
        exercises=[
            E("返回 u 为 'a' 的行 id（单值）。", "WHERE u='a'。",
              "SELECT id FROM t WHERE u = 'a';", "1"),
            E("统计表 t 的行数（单值）。", "COUNT(*)。",
              "SELECT COUNT(*) FROM t;", "2"),
        ],
    ),
    L(
        94, "ddl-capstone", "综合练习：设计规范表结构", "intermediate", "ddl",
        concepts=["DDL", "约束", "外键", "默认值"],
        objective="综合运用约束设计一个订单明细表结构",
        prerequisites=["掌握本 track"],
        explain=(
            "本课用 DDL 建 orders 与 order_items 两表：主键自增、外键引用、CHECK 保证数量为"
            "正、NOT NULL 保证关键字段、生成列计算小计。随后插入两行并 JOIN 汇总，得到每单"
            "总额。这是订单域最常见的结构，约束把数据质量前置到写入时刻。"
        ),
        setup=(
            "PRAGMA foreign_keys = ON;\n"
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer TEXT NOT NULL);\n"
            "CREATE TABLE order_items (id INTEGER PRIMARY KEY, order_id INTEGER NOT NULL REFERENCES orders(id), "
            "price REAL NOT NULL CHECK (price >= 0), qty INTEGER NOT NULL CHECK (qty > 0), "
            "subtotal REAL GENERATED ALWAYS AS (price * qty) STORED);\n"
            "INSERT INTO orders VALUES (1,'alice'),(2,'bob');\n"
            "INSERT INTO order_items (order_id, price, qty) VALUES (1,10.0,2),(1,5.0,3),(2,20.0,1);"
        ),
        query=(
            "SELECT o.id, o.customer, SUM(i.subtotal) AS total FROM orders AS o "
            "JOIN order_items AS i ON i.order_id = o.id GROUP BY o.id, o.customer ORDER BY o.id;"
        ),
        expected="1|alice|35.0\n2|bob|20.0",
        pitfalls=["外键需 PRAGMA 开启；复合约束顺序影响错误信息可读性。", "生成列用于聚合前要确认其表达式稳定、无副作用。"],
        exercises=[
            E("返回订单 1 的明细行数（单值）。", "COUNT(*) 配 WHERE。",
              "SELECT COUNT(*) FROM order_items WHERE order_id = 1;", "2"),
            E("返回所有明细 subtotal 的总和（单值）。", "SUM(subtotal)。",
              "SELECT SUM(subtotal) FROM order_items;", "55.0"),
        ],
    ),
]
