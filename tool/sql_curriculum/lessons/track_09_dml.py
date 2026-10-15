"""Track 9 — DML and upsert (lessons 95-102)."""

from __future__ import annotations

from lessons.helper import E, L

LESSONS = [
    L(
        95, "insert-multi", "INSERT 多行插入", "intermediate", "dml",
        concepts=["INSERT", "多行", "rowid"],
        objective="用一条 INSERT 插入多行并理解返回值",
        prerequisites=["掌握 CREATE TABLE"],
        explain=(
            "INSERT INTO t (cols) VALUES (...), (...), ... 一次插入多行，比多次单行插入更高效"
            "（单语句单事务）。省略主键时自动分配 rowid。SQLite 3.50 中 changes() 返回最近一次"
            "修改语句影响的行数。示例用一条语句插入三行，因此紧随其后的 changes() 返回 3。"
        ),
        setup=(
            "CREATE TABLE t (id INTEGER PRIMARY KEY, v TEXT);\n"
            "INSERT INTO t (v) VALUES ('a'),('b'),('c');"
        ),
        query="SELECT changes() AS last_changes, (SELECT COUNT(*) FROM t) AS total;",
        expected="3|3",
        pitfalls=["列顺序与 VALUES 顺序必须一致，否则错位写入。", "大量插入应放入事务以降低提交开销。"],
        exercises=[
            E("返回 t 的所有 v，按 id 升序。", "SELECT v。",
              "SELECT v FROM t ORDER BY id;", "a\nb\nc"),
            E("返回 id 为 2 的行 v（单值）。", "WHERE id=2。",
              "SELECT v FROM t WHERE id = 2;", "b"),
        ],
    ),
    L(
        96, "insert-select", "INSERT ... SELECT", "intermediate", "dml",
        concepts=["INSERT SELECT", "复制数据"],
        objective="用查询结果批量写入另一张表",
        prerequisites=["掌握多行插入与 JOIN"],
        explain=(
            "INSERT INTO dest (cols) SELECT ... 把查询结果写入目标表，适合归档、汇总、表间"
            "搬迁。示例把 orders 中金额大于等于 100 的行复制到 big_orders 归档表。SELECT 的"
            "列必须与目标列一一对应。"
        ),
        setup=(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, amount INTEGER);\n"
            "CREATE TABLE big_orders (id INTEGER PRIMARY KEY, amount INTEGER);\n"
            "INSERT INTO orders VALUES (1,50),(2,150),(3,200);\n"
            "INSERT INTO big_orders (id, amount) SELECT id, amount FROM orders WHERE amount >= 100;"
        ),
        query="SELECT id, amount FROM big_orders ORDER BY id;",
        expected="2|150\n3|200",
        pitfalls=["目标表已有相同主键会冲突；需处理冲突策略。", "写成 SELECT * 时列顺序/数量必须与目标完全匹配。"],
        exercises=[
            E("返回归档表中金额最大的行 id（单值）。", "MAX(amount) 再定位或 ORDER BY LIMIT。",
              "SELECT id FROM big_orders ORDER BY amount DESC LIMIT 1;", "3"),
            E("统计归档表行数（单值）。", "COUNT(*)。",
              "SELECT COUNT(*) FROM big_orders;", "2"),
        ],
    ),
    L(
        97, "update-basic", "UPDATE 基础与 WHERE 安全", "intermediate", "dml",
        concepts=["UPDATE", "WHERE"],
        objective="用 UPDATE 修改行并避免全表误更新",
        prerequisites=["掌握 INSERT"],
        explain=(
            "UPDATE t SET col = expr WHERE cond 修改匹配行。省略 WHERE 会更新整表，是最常见的"
            "生产事故来源；应先 SELECT 验证条件。示例把 price 低于 100 的商品统一加价 10%，"
            "只影响命中行。changes() 报告受影响行数，便于校验。"
        ),
        setup=(
            "CREATE TABLE products (id INTEGER PRIMARY KEY, price REAL);\n"
            "INSERT INTO products VALUES (1,50.0),(2,100.0),(3,80.0);\n"
            "UPDATE products SET price = price * 1.1 WHERE price < 100;"
        ),
        query="SELECT id, price FROM products ORDER BY id;",
        expected="1|55.0\n2|100.0\n3|88.0",
        pitfalls=["漏写 WHERE 会更新整表，务必先 SELECT 验证。", "SET 中的表达式基于更新前的行值，同一语句内不会看到自己的中间结果。"],
        exercises=[
            E("返回价格低于 100 的商品 id，按 id 排序（在更新后的数据上）。", "WHERE price<100。",
              "SELECT id FROM products WHERE price < 100 ORDER BY id;", "1\n3"),
            E("返回价格恰好为 100.0 的行 id（单值）。", "WHERE price=100.0。",
              "SELECT id FROM products WHERE price = 100.0;", "2"),
        ],
    ),
    L(
        98, "update-join", "UPDATE 关联更新", "intermediate", "dml",
        concepts=["UPDATE", "关联", "子查询"],
        objective="依据另一张表的值更新目标表",
        prerequisites=["掌握子查询"],
        explain=(
            "关联更新常写成 UPDATE t SET col = (SELECT ... FROM other WHERE other.key=t.key) "
            "WHERE EXISTS (...)；SQLite 不支持 UPDATE ... FROM 的旧版本，3.33 起支持 UPDATE "
            "... FROM。示例依据 prices 表把 products 的价格刷新为最新值，未匹配的行保持原值。"
        ),
        setup=(
            "CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, price REAL);\n"
            "CREATE TABLE prices (product_id INTEGER PRIMARY KEY, price REAL);\n"
            "INSERT INTO products VALUES (1,'pen',10.0),(2,'book',20.0);\n"
            "INSERT INTO prices VALUES (1,12.0);\n"
            "UPDATE products SET price = (SELECT price FROM prices WHERE prices.product_id = products.id) "
            "WHERE EXISTS (SELECT 1 FROM prices WHERE prices.product_id = products.id);"
        ),
        query="SELECT id, name, price FROM products ORDER BY id;",
        expected="1|pen|12.0\n2|book|20.0",
        pitfalls=["未加 WHERE EXISTS 时未匹配行会被子查询的 NULL 覆盖。", "关联子查询在大表上可能较慢，需索引支撑。"],
        exercises=[
            E("返回价格已从 prices 刷新的商品 id（单值）。", "与 prices 中 product_id 相同的商品。",
              "SELECT id FROM products WHERE price = 12.0;", "1"),
            E("返回未在 prices 中出现的商品 id（单值）。", "NOT EXISTS。",
              "SELECT p.id FROM products AS p WHERE NOT EXISTS (SELECT 1 FROM prices AS x WHERE x.product_id = p.id);",
              "2"),
        ],
    ),
    L(
        99, "delete-basic", "DELETE 与条件删除", "intermediate", "dml",
        concepts=["DELETE", "WHERE", "TRUNCATE 替代"],
        objective="用 DELETE 删除匹配行并了解整表清空",
        prerequisites=["掌握 UPDATE"],
        explain=(
            "DELETE FROM t WHERE cond 删除匹配行；省略 WHERE 清空整表（SQLite 无 TRUNCATE，"
            "可用 DELETE 或 DROP+CREATE）。示例删除库存为 0 的商品，保留有货行。删除前建议在"
            "事务中确认影响行数，必要时回滚。"
        ),
        setup=(
            "CREATE TABLE stock (id INTEGER PRIMARY KEY, name TEXT, qty INTEGER);\n"
            "INSERT INTO stock VALUES (1,'pen',0),(2,'book',5),(3,'bag',0);\n"
            "DELETE FROM stock WHERE qty = 0;"
        ),
        query="SELECT id, name, qty FROM stock ORDER BY id;",
        expected="2|book|5",
        pitfalls=["漏写 WHERE 会清空整表。", "大量删除后可用 VACUUM 回收空间，但会重写数据库文件。"],
        exercises=[
            E("返回剩余商品数量（单值）。", "COUNT(*)。",
              "SELECT COUNT(*) FROM stock;", "1"),
            E("返回 qty 大于 0 的商品名，按 id 排序。", "WHERE qty>0。",
              "SELECT name FROM stock WHERE qty > 0 ORDER BY id;", "book"),
        ],
    ),
    L(
        100, "upsert-replace", "UPSERT：INSERT OR REPLACE", "intermediate", "dml",
        concepts=["INSERT OR REPLACE", "UPSERT", "冲突"],
        objective="用 INSERT OR REPLACE 实现简单幂等写入",
        prerequisites=["掌握 UNIQUE 与 ON CONFLICT"],
        explain=(
            "INSERT OR REPLACE 在唯一冲突时删除旧行并插入新行，等价于 upsert 的简单形式，但会"
            "改变 rowid 并触发级联删除（因为它先删后插）。示例以 u 为唯一键，第二次写 'b' "
            "把旧值替换为 2，最终只有一行 'b'。"
        ),
        setup=(
            "CREATE TABLE kv (u TEXT PRIMARY KEY, v INTEGER);\n"
            "INSERT INTO kv VALUES ('a',1);\n"
            "INSERT OR REPLACE INTO kv VALUES ('b',1);\n"
            "INSERT OR REPLACE INTO kv VALUES ('b',2);"
        ),
        query="SELECT u, v FROM kv ORDER BY u;",
        expected="a|1\nb|2",
        pitfalls=["INSERT OR REPLACE 会先删后插，可能触发外键级联，且 rowid 变化。", "只想更新部分列时 REPLACE 会丢字段，应用 ON CONFLICT DO UPDATE。"],
        exercises=[
            E("返回 u='b' 的 v（单值）。", "WHERE u='b'。",
              "SELECT v FROM kv WHERE u = 'b';", "2"),
            E("统计表 kv 行数（单值）。", "COUNT(*)。",
              "SELECT COUNT(*) FROM kv;", "2"),
        ],
    ),
    L(
        101, "upsert-do-update", "UPSERT：ON CONFLICT DO UPDATE", "intermediate", "dml",
        concepts=["ON CONFLICT", "DO UPDATE", "excluded"],
        objective="用 ON CONFLICT DO UPDATE 精确控制冲突时的更新",
        prerequisites=["掌握 INSERT OR REPLACE"],
        explain=(
            "INSERT ... ON CONFLICT(col) DO UPDATE SET v = excluded.v 在冲突时更新而非替换，"
            "保留原 rowid 且可只改部分列；excluded 前缀引用本次想插入的值。示例把计数累加："
            "冲突时 v = v + excluded.v，因此 'a' 从 1 变 3。这是计数器/幂等写入的标准写法。"
        ),
        setup=(
            "CREATE TABLE counters (name TEXT PRIMARY KEY, v INTEGER);\n"
            "INSERT INTO counters VALUES ('a',1)\n"
            "ON CONFLICT(name) DO UPDATE SET v = v + excluded.v;\n"
            "INSERT INTO counters VALUES ('a',2)\n"
            "ON CONFLICT(name) DO UPDATE SET v = v + excluded.v;"
        ),
        query="SELECT name, v FROM counters ORDER BY name;",
        expected="a|3",
        pitfalls=["DO UPDATE 中引用目标列不加前缀，引用新值必须写 excluded.。", "冲突目标列需要唯一约束或主键支撑。"],
        exercises=[
            E("返回 counters 中 v 的值（单值）。", "SELECT v。",
              "SELECT v FROM counters WHERE name='a';", "3"),
            E("统计 counters 行数（单值）。", "COUNT(*)。",
              "SELECT COUNT(*) FROM counters;", "1"),
        ],
    ),
    L(
        102, "dml-capstone", "综合练习：幂等写入流水", "intermediate", "dml",
        concepts=["INSERT", "UPSERT", "UPDATE", "DELETE"],
        objective="组合 DML 完成一次幂等对账写入",
        prerequisites=["掌握本 track"],
        explain=(
            "本课模拟对账：先把新流水批量 UPSERT 进 ledger（按 id 幂等），再把金额为 0 的流水"
            "清理掉，最后按账户汇总。这样即使重复执行同一批数据，结果也稳定。SQLite 3.50 下"
            "示例账户 A 累计 150（100+50），账户 B 的 20 与 50 合计 70（金额为 0 的那行已被"
            "DELETE 删除）。"
        ),
        setup=(
            "CREATE TABLE ledger (id INTEGER PRIMARY KEY, account TEXT, amount INTEGER);\n"
            "INSERT INTO ledger VALUES (1,'A',100),(2,'A',50),(3,'B',20),(4,'B',0),(5,'B',50)\n"
            "ON CONFLICT(id) DO UPDATE SET account=excluded.account, amount=excluded.amount;\n"
            "DELETE FROM ledger WHERE amount = 0;"
        ),
        query="SELECT account, SUM(amount) AS total FROM ledger GROUP BY account ORDER BY account;",
        expected="A|150\nB|70",
        pitfalls=["UPSERT 的目标冲突键要与业务唯一键一致。", "先删后聚合的顺序影响结果，注意事务边界。"],
        exercises=[
            E("返回 ledger 的行数（验证零金额行已被删除）。", "COUNT(*)。",
              "SELECT COUNT(*) FROM ledger;", "4"),
            E("返回账户 A 的流水条数（单值）。", "COUNT(*) 配 WHERE。",
              "SELECT COUNT(*) FROM ledger WHERE account = 'A';", "2"),
        ],
    ),
]
