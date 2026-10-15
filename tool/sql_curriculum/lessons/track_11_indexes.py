"""Track 11 — indexes and execution plans (lessons 109-116)."""

from __future__ import annotations

from lessons.helper import E, L

LESSONS = [
    L(
        109, "index-concept", "索引原理与 B-Tree", "advanced", "indexes",
        concepts=["索引", "B-Tree", "查找"],
        objective="理解索引是额外的有序结构及其代价",
        prerequisites=["掌握 CREATE TABLE 与查询"],
        explain=(
            "索引是独立于表的有序 B-Tree 结构，键为被索引列，叶子指向行。查找从 O(n) 降为 "
            "O(log n)，代价是额外存储和写入时需要同步维护索引。示例为 name 建索引后，等值"
            "查询可用索引定位；是否真正使用要看查询计划（EXPLAIN QUERY PLAN）。选择性低的列"
            "（如性别）建索引收益有限。"
        ),
        setup=(
            "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, city TEXT);\n"
            "INSERT INTO users VALUES (1,'alice','beijing'),(2,'bob','shanghai'),(3,'carol','beijing');\n"
            "CREATE INDEX idx_users_name ON users(name);"
        ),
        query="SELECT id, name FROM users WHERE name = 'bob' ORDER BY id;",
        expected="2|bob",
        pitfalls=["索引不是越多越好，写多读少时维护成本会超过收益。", "对函数的列（WHERE lower(name)=...）通常无法用普通索引。"],
        exercises=[
            E("返回 city 为 beijing 的用户 id，按 id 排序。", "WHERE city='beijing'。",
              "SELECT id FROM users WHERE city = 'beijing' ORDER BY id;", "1\n3"),
            E("统计 users 的行数（单值）。", "COUNT(*)。",
              "SELECT COUNT(*) FROM users;", "3"),
        ],
    ),
    L(
        110, "single-column-index", "单列索引与查询加速", "advanced", "indexes",
        concepts=["单列索引", "等值查询"],
        objective="用单列索引加速等值与范围查询",
        prerequisites=["掌握索引原理"],
        explain=(
            "单列索引对等值（=）和范围（<、BETWEEN）查询都有帮助，因为 B-Tree 有序。示例在 "
            "amount 上建索引，范围查询 amount > 100 可以按索引区间扫描。但若查询需要回表取"
            "大量列，优化器可能选择全表扫描，实际是否用索引由计划决定。"
        ),
        setup=(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, amount INTEGER);\n"
            "INSERT INTO orders VALUES (1,50),(2,150),(3,200),(4,80);\n"
            "CREATE INDEX idx_orders_amount ON orders(amount);"
        ),
        query="SELECT id, amount FROM orders WHERE amount > 100 ORDER BY id;",
        expected="2|150\n3|200",
        pitfalls=["对每行都命中的低选择性条件，优化器宁愿全表扫描。", "索引列参与运算（amount+1>100）会使索引失效。"],
        exercises=[
            E("返回 amount 在 80 到 150 之间的订单 id，按 id 排序。", "BETWEEN 或范围比较。",
              "SELECT id FROM orders WHERE amount BETWEEN 80 AND 150 ORDER BY id;", "2\n4"),
            E("返回 amount 的最小值（单值）。", "MIN(amount)。",
              "SELECT MIN(amount) FROM orders;", "50"),
        ],
    ),
    L(
        111, "composite-index", "复合索引与最左前缀", "advanced", "indexes",
        concepts=["复合索引", "最左前缀"],
        objective="理解复合索引的列顺序与最左前缀规则",
        prerequisites=["掌握单列索引"],
        explain=(
            "复合索引 (a,b) 按 a 再按 b 排序，可服务条件 a、a AND b、以及 a 的范围+ b 的等值；"
            "但只给 b 的条件无法用该索引（最左前缀规则）。示例在 (city, age) 上建索引，查询 "
            "city='beijing' AND age>20 可用；查询仅 age>20 则用不上。列顺序应按选择性和常用"
            "过滤模式设计。"
        ),
        setup=(
            "CREATE TABLE people (id INTEGER PRIMARY KEY, city TEXT, age INTEGER);\n"
            "INSERT INTO people VALUES (1,'beijing',30),(2,'beijing',18),(3,'shanghai',25);\n"
            "CREATE INDEX idx_people_city_age ON people(city, age);"
        ),
        query="SELECT id, city, age FROM people WHERE city = 'beijing' AND age > 20 ORDER BY id;",
        expected="1|beijing|30",
        pitfalls=["把低选择性列放在最左会削弱复合索引效果。", "范围条件之后的列无法继续用于索引定位。"],
        exercises=[
            E("返回 city 为 beijing 的人数（单值）。", "COUNT(*) 配 WHERE。",
              "SELECT COUNT(*) FROM people WHERE city = 'beijing';", "2"),
            E("返回 age 大于 20 的人 id，按 id 排序。", "WHERE age>20。",
              "SELECT id FROM people WHERE age > 20 ORDER BY id;", "1\n3"),
        ],
    ),
    L(
        112, "covering-index", "覆盖索引", "advanced", "indexes",
        concepts=["覆盖索引", "回表"],
        objective="用覆盖索引避免回表读取",
        prerequisites=["掌握复合索引"],
        explain=(
            "当索引包含查询需要的所有列时，数据库可直接从索引返回结果，无需回表，称为覆盖"
            "索引。示例索引 (city, age) 覆盖 SELECT city, age 的查询，计划中无表访问步骤。"
            "覆盖索引能显著减少随机 I/O，但更多列会让索引变大、写入更重。"
        ),
        setup=(
            "CREATE TABLE people (id INTEGER PRIMARY KEY, city TEXT, age INTEGER, note TEXT);\n"
            "INSERT INTO people VALUES (1,'beijing',30,'x'),(2,'beijing',18,'y'),(3,'shanghai',25,'z');\n"
            "CREATE INDEX idx_people_city_age ON people(city, age);"
        ),
        query="SELECT city, age FROM people WHERE city = 'beijing' ORDER BY city, age;",
        expected="beijing|18\nbeijing|30",
        pitfalls=["覆盖索引对 SELECT * 无效，因为星号引入了未索引列。", "覆盖索引列顺序要与查询返回的列匹配才有意义。"],
        exercises=[
            E("返回 beijing 组内年龄最大值（单值）。", "WHERE city='beijing' 再 MAX(age)。",
              "SELECT MAX(age) FROM people WHERE city = 'beijing';", "30"),
            E("返回所有 city 去重列表，按字母升序。", "SELECT DISTINCT city。",
              "SELECT DISTINCT city FROM people ORDER BY city;", "beijing\nshanghai"),
        ],
    ),
    L(
        113, "unique-primary-index", "唯一索引与主键索引", "advanced", "indexes",
        concepts=["唯一索引", "主键索引", "隐式索引"],
        objective="理解主键与唯一约束背后的索引",
        prerequisites=["掌握 UNIQUE 与主键"],
        explain=(
            "PRIMARY KEY 与 UNIQUE 会自动创建索引（SQLite 中 INTEGER PRIMARY KEY 用 rowid，无"
            "独立索引）。这些隐式索引既保证唯一性也加速按该列的查找。示例通过 sqlite_master "
            "与 pragma 列出索引，说明系统自动建了哪些索引，避免重复建同名索引。"
        ),
        setup=(
            "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT UNIQUE, name TEXT);\n"
            "INSERT INTO users VALUES (1,'a@x.com','alice'),(2,'b@x.com','bob');"
        ),
        query="SELECT name FROM sqlite_master WHERE type = 'index' AND tbl_name = 'users' ORDER BY name;",
        expected="sqlite_autoindex_users_1",
        pitfalls=["对已由唯一约束覆盖的列再建普通索引是浪费。", "删除唯一约束需重建表，不能直接删索引来移除唯一性。"],
        exercises=[
            E("返回 email 为 'b@x.com' 的用户 id（单值）。", "WHERE email=...。",
              "SELECT id FROM users WHERE email = 'b@x.com';", "2"),
            E("统计类型为 index 且表为 users 的索引数（单值）。", "COUNT(*) 配 WHERE。",
              "SELECT COUNT(*) FROM sqlite_master WHERE type='index' AND tbl_name='users';", "1"),
        ],
    ),
    L(
        114, "index-not-used", "索引失效场景", "advanced", "indexes",
        concepts=["索引失效", "函数", "隐式转换"],
        objective="识别导致索引无法使用的常见写法",
        prerequisites=["掌握复合索引"],
        explain=(
            "当 WHERE 中的列被函数包裹、发生隐式类型转换、以通配符开头做 LIKE、或使用 OR 连接"
            "不同列时，普通索引常无法使用。示例对比 lower(name)='alice'（无法用 name 索引）与"
            "name='alice'（可用），并说明改写方式如使用表达式的函数索引或规范化存储。"
        ),
        setup=(
            "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT);\n"
            "INSERT INTO users VALUES (1,'alice'),(2,'bob');\n"
            "CREATE INDEX idx_users_name ON users(name);"
        ),
        query="SELECT id, name FROM users WHERE name = 'alice' ORDER BY id;",
        expected="1|alice",
        pitfalls=["WHERE lower(name)='alice' 让 name 索引失效。", "LIKE '%x' 前导通配符无法走索引。"],
        exercises=[
            E("返回 name 以 'a' 开头的用户 id，按 id 排序。", "LIKE 'a%' 可用索引。",
              "SELECT id FROM users WHERE name LIKE 'a%' ORDER BY id;", "1"),
            E("返回 name 长度等于 3 的用户 id，按 id 排序。", "length(name)=3。",
              "SELECT id FROM users WHERE length(name) = 3 ORDER BY id;", "2"),
        ],
    ),
    L(
        115, "explain-plan", "EXPLAIN 与 EXPLAIN QUERY PLAN", "advanced", "indexes",
        concepts=["EXPLAIN", "查询计划", "SCAN/SEARCH"],
        objective="用 EXPLAIN QUERY PLAN 判断是否使用索引",
        prerequisites=["掌握索引失效场景"],
        explain=(
            "EXPLAIN 输出虚拟机指令，EXPLAIN QUERY PLAN 输出高层计划：SEARCH 表示用索引定位，"
            "SCAN 表示全表扫描。在 CLI 里直接执行 `EXPLAIN QUERY PLAN SELECT ...` 可看到计划行，"
            "例如 `SEARCH users USING INDEX idx_users_name (name=?)`。由于计划文本随 SQLite 版本"
            "与统计信息变化，本课的验证查询只断言索引查找的领域结果（name='alice' 的 id），并在"
            "讲解中说明如何用计划确认索引生效，避免把易变的计划文本当作断言。"
        ),
        setup=(
            "CREATE TABLE accounts (id INTEGER PRIMARY KEY, owner TEXT, balance INTEGER);\n"
            "INSERT INTO accounts VALUES (1,'alice',100),(2,'bob',50);\n"
            "CREATE INDEX idx_accounts_owner ON accounts(owner);"
        ),
        query="SELECT id, owner, balance FROM accounts WHERE owner = 'alice' ORDER BY id;",
        expected="1|alice|100",
        pitfalls=["计划会随版本、统计信息和数据量变化，不要硬编码完整计划文本。", "SCAN 不一定是问题，小表全扫常比索引更快。"],
        exercises=[
            E("返回 owner='bob' 的账户 id（单值）。", "WHERE owner='bob'。",
              "SELECT id FROM accounts WHERE owner = 'bob';", "2"),
            E("返回 accounts 的索引名（单值）。", "sqlite_master 中该表的索引。",
              "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='accounts';",
              "idx_accounts_owner"),
        ],
    ),
    L(
        116, "index-capstone", "综合练习：慢查询优化", "advanced", "indexes",
        concepts=["索引", "查询计划", "优化"],
        objective="为慢查询选择并验证合适的索引",
        prerequisites=["掌握本 track"],
        explain=(
            "优化步骤：看计划确认扫描方式，再为过滤/连接/排序列建索引，最后用计划验证。示例"
            "在 (city, amount) 上建索引服务 city 等值加 amount 范围，并用 EXPLAIN 风格查询确认"
            "使用索引；返回 beijing 区 amount>100 的订单。索引列顺序按“等值列在前、范围列在后”。"
        ),
        setup=(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, city TEXT, amount INTEGER);\n"
            "INSERT INTO orders VALUES (1,'beijing',50),(2,'beijing',150),(3,'shanghai',200);\n"
            "CREATE INDEX idx_orders_city_amount ON orders(city, amount);"
        ),
        query="SELECT id, city, amount FROM orders WHERE city = 'beijing' AND amount > 100 ORDER BY id;",
        expected="2|beijing|150",
        pitfalls=["索引列顺序与查询条件不匹配会退化。", "优化后仍需回归验证计划，避免写入变慢或索引未命中。"],
        exercises=[
            E("返回 beijing 区订单数量（单值）。", "COUNT(*) 配 WHERE。",
              "SELECT COUNT(*) FROM orders WHERE city = 'beijing';", "2"),
            E("返回所有订单 amount 的总和（单值）。", "SUM(amount)。",
              "SELECT SUM(amount) FROM orders;", "400"),
        ],
    ),
]
