"""Track 5 — subqueries (lessons 53-62)."""

from __future__ import annotations

from lessons.helper import E, L

LESSONS = [
    L(
        53, "scalar-subquery", "标量子查询", "beginner", "subqueries",
        concepts=["标量子查询", "SELECT 中嵌套"],
        objective="在 SELECT 列表中用只返回单值的子查询",
        prerequisites=["掌握聚合与 WHERE"],
        explain=(
            "标量子查询必须只返回一行一列，可以在 SELECT、WHERE 里当值用。示例先用子查询算出"
            "全表平均分 85，再在主查询里为每名学生输出与平均分的差。SQLite 3.50 对返回多行的"
            "标量子查询只取第一行而不报错，因此应保证子查询唯一性。"
        ),
        setup=(
            "CREATE TABLE scores (name TEXT, score INTEGER);\n"
            "INSERT INTO scores VALUES ('Ann',95),('Ben',85),('Cara',75);"
        ),
        query=(
            "SELECT name, score, score - (SELECT AVG(score) FROM scores) AS diff "
            "FROM scores ORDER BY score DESC;"
        ),
        expected="Ann|95|10.0\nBen|85|0.0\nCara|75|-10.0",
        pitfalls=["子查询返回多列或多行时行为不确定。", "标量子查询在每行都求值，未缓存时开销大。"],
        exercises=[
            E("返回高于平均分的学生名，按分数降序。", "WHERE score > (SELECT AVG(score)...)。",
              "SELECT name FROM scores WHERE score > (SELECT AVG(score) FROM scores) ORDER BY score DESC;",
              "Ann"),
            E("返回全表总分的单值。", "SUM(score)。",
              "SELECT SUM(score) FROM scores;",
              "255"),
        ],
    ),
    L(
        54, "in-subquery", "IN 子查询", "beginner", "subqueries",
        concepts=["IN", "子查询"],
        objective="用 IN 判断某列是否出现在子查询结果集中",
        prerequisites=["掌握标量子查询"],
        explain=(
            "IN (子查询) 等价于把子查询结果当作集合做成员测试。示例 orders 里哪些客户有订单，"
            "子查询返回 customer_id 集合 {1,3}，主查询从 customers 中筛出这两行。SQLite 3.50 "
            "对 IN 子查询有优化，但返回结果不保证顺序，必须显式 ORDER BY。"
        ),
        setup=(
            "CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT);\n"
            "INSERT INTO customers VALUES (1,'Ann'),(2,'Ben'),(3,'Cara'),(4,'Dan');\n"
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER);\n"
            "INSERT INTO orders VALUES (1,1),(2,3),(3,1);"
        ),
        query=(
            "SELECT name FROM customers WHERE id IN (SELECT customer_id FROM orders) ORDER BY id;"
        ),
        expected="Ann\nCara",
        pitfalls=["子查询含 NULL 时 IN 的结果可能出乎意料（见下一课）。", "大结果集的 IN 比 EXISTS 更占内存。"],
        exercises=[
            E("用 IN 子查询返回有订单的客户 id，按 id 升序。", "SELECT customer_id FROM orders。",
              "SELECT id FROM customers WHERE id IN (SELECT customer_id FROM orders) ORDER BY id;",
              "1\n3"),
            E("统计有订单的客户数（单值）。", "COUNT(DISTINCT customer_id)。",
              "SELECT COUNT(DISTINCT customer_id) FROM orders;",
              "2"),
        ],
    ),
    L(
        55, "not-in-null-trap", "NOT IN 与 NULL 陷阱", "advanced", "subqueries",
        concepts=["NOT IN", "NULL", "三值逻辑"],
        objective="理解 NOT IN 遇上 NULL 会返回空结果的陷阱并给出替代",
        prerequisites=["掌握 IN 子查询"],
        explain=(
            "NOT IN 的语义是「与集合中每个元素都不相等」。若子查询结果含 NULL，则任何值 "
            "= NULL 得到 UNKNOWN，NOT IN 会整体变为 UNKNOWN，结果为空。示例 blocked.email 有 "
            "一行 NULL，因此 NOT IN 返回 0 行，而用 NOT EXISTS 或过滤掉 NULL 才能得到正确结果。"
        ),
        setup=(
            "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT);\n"
            "INSERT INTO users VALUES (1,'a@x.com'),(2,'b@x.com'),(3,'c@x.com');\n"
            "CREATE TABLE blocked (email TEXT);\n"
            "INSERT INTO blocked VALUES ('b@x.com'),(NULL);"
        ),
        query="SELECT id FROM users WHERE email NOT IN (SELECT email FROM blocked);",
        expected="(no rows)",
        pitfalls=["生产环境务必先排除 NULL 或改写成 NOT EXISTS。", "NOT IN 空集时返回全部行，与含 NULL 的行为相反。"],
        exercises=[
            E("过滤掉子查询中的 NULL 后，返回允许的 user id，按升序。", "子查询加 WHERE email IS NOT NULL。",
              "SELECT id FROM users WHERE email NOT IN (SELECT email FROM blocked WHERE email IS NOT NULL) ORDER BY id;",
              "1\n3"),
            E("用 NOT EXISTS 返回允许的 user id，按升序。", "NOT EXISTS 子查询无 NULL 陷阱。",
              "SELECT id FROM users u WHERE NOT EXISTS (SELECT 1 FROM blocked b WHERE b.email = u.email) ORDER BY id;",
              "1\n3"),
        ],
    ),
    L(
        56, "exists", "EXISTS 相关存在性", "intermediate", "subqueries",
        concepts=["EXISTS", "半连接"],
        objective="用 EXISTS 判断是否至少存在一条匹配行",
        prerequisites=["掌握 IN 子查询"],
        explain=(
            "EXISTS 只关心子查询是否返回至少一行，找到即短路，不再继续扫描。示例对每位客户"
            "检查 orders 中是否存在其订单，Ann 与 Cara 有，Ben 无，因此输出 2 行。EXISTS 的"
            "子查询通常写成相关子查询（引用外层列）。"
        ),
        setup=(
            "CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT);\n"
            "INSERT INTO customers VALUES (1,'Ann'),(2,'Ben'),(3,'Cara');\n"
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, amount INTEGER);\n"
            "INSERT INTO orders VALUES (1,1,30),(2,3,40),(3,3,50);"
        ),
        query=(
            "SELECT name FROM customers c "
            "WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id) ORDER BY c.id;"
        ),
        expected="Ann\nCara",
        pitfalls=["SELECT * 与 SELECT 1 在 EXISTS 中效果相同，但 SELECT 1 更省。", "相关子查询在大表上需索引支持。"],
        exercises=[
            E("用 EXISTS 返回有订单金额大于 40 的客户名，按 id 升序。", "子查询加 amount > 40。",
              "SELECT name FROM customers c WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id AND o.amount > 40) ORDER BY c.id;",
              "Cara"),
            E("用 EXISTS 返回订单数大于 1 的客户名，按 id 升序。", "配合 GROUP BY 或子查询聚合。",
              "SELECT name FROM customers c WHERE EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id GROUP BY o.customer_id HAVING COUNT(*) > 1) ORDER BY c.id;",
              "Cara"),
        ],
    ),
    L(
        57, "not-exists", "NOT EXISTS 反存在", "intermediate", "subqueries",
        concepts=["NOT EXISTS", "反连接"],
        objective="用 NOT EXISTS 找出右表不存在匹配的左表行",
        prerequisites=["掌握 EXISTS"],
        explain=(
            "NOT EXISTS 在「不存在任何匹配行」时成立，天然处理 NULL，不会像 NOT IN 那样被"
            "NULL 破坏。示例 customers 中 Ben 没有任何订单，因此只输出 Ben。SQLite 3.50 通常"
            "把 NOT EXISTS 优化成反连接执行。"
        ),
        setup=(
            "CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT);\n"
            "INSERT INTO customers VALUES (1,'Ann'),(2,'Ben'),(3,'Cara');\n"
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER);\n"
            "INSERT INTO orders VALUES (1,1),(2,3),(3,1);"
        ),
        query=(
            "SELECT name FROM customers c "
            "WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id) ORDER BY c.id;"
        ),
        expected="Ben",
        pitfalls=["写成 NOT (EXISTS ...) 结果相同，但可读性差。", "子查询忘记引用外层列会变成非相关判断。"],
        exercises=[
            E("用 NOT EXISTS 返回没有订单的客户 id，按升序。", "与上一课对称。",
              "SELECT id FROM customers c WHERE NOT EXISTS (SELECT 1 FROM orders o WHERE o.customer_id = c.id) ORDER BY id;",
              "2"),
            E("用 LEFT JOIN + IS NULL 返回没有订单的客户名，按 id 升序。", "反连接写法。",
              "SELECT c.name FROM customers c LEFT JOIN orders o ON o.customer_id = c.id WHERE o.id IS NULL ORDER BY c.id;",
              "Ben"),
        ],
    ),
    L(
        58, "correlated-subquery", "相关子查询", "advanced", "subqueries",
        concepts=["相关子查询", "逐行求值"],
        objective="让子查询引用外层行，实现逐分组比较",
        prerequisites=["掌握 EXISTS"],
        explain=(
            "相关子查询引用外层列，因此外层每一行都会重新求值一次。示例先算出每个城市的最高分"
            "(beijing 95、shanghai 88)，再逐行比较找出每人是否为该城市第一。SQLite 3.50 会把"
            "这类相关子查询做缓存，但复杂度仍近似 O(n*m)，大表需改写或加索引。"
        ),
        setup=(
            "CREATE TABLE scores (name TEXT, city TEXT, score INTEGER);\n"
            "INSERT INTO scores VALUES ('Ann','beijing',95),('Ben','beijing',80),"
            "('Cara','shanghai',88),('Dan','shanghai',70);"
        ),
        query=(
            "SELECT s.name, s.city FROM scores s "
            "WHERE s.score = (SELECT MAX(x.score) FROM scores x WHERE x.city = s.city) "
            "ORDER BY s.city;"
        ),
        expected="Ann|beijing\nCara|shanghai",
        pitfalls=["相关子查询忘记关联条件会退化为全局比较。", "列别名遮蔽要小心，子查询中的 x 与外层 s 必须区分。"],
        exercises=[
            E("返回每个城市的最低分学生名与城市，按城市升序。", "MIN(x.score)。",
              "SELECT s.name, s.city FROM scores s WHERE s.score = (SELECT MIN(x.score) FROM scores x WHERE x.city = s.city) ORDER BY s.city;",
              "Ben|beijing\nDan|shanghai"),
            E("统计 beijing 学生数（单值）。", "WHERE city='beijing'。",
              "SELECT COUNT(*) FROM scores WHERE city = 'beijing';",
              "2"),
        ],
    ),
    L(
        59, "derived-table", "FROM 子查询（派生表）", "intermediate", "subqueries",
        concepts=["派生表", "FROM 子查询", "别名"],
        objective="把子查询当作临时表在 FROM 中使用",
        prerequisites=["掌握分组聚合"],
        explain=(
            "FROM 里的子查询叫派生表，必须带别名。示例先在派生表 t 里算出每个区域的总额，"
            "再在外层筛选总额大于 100 的区域——因为 HAVING 内不能直接引用同级别名，派生表"
            "让过滤逻辑更清晰。SQLite 3.50 会把派生表展开进查询计划。"
        ),
        setup=(
            "CREATE TABLE sales (id INTEGER PRIMARY KEY, region TEXT, amount INTEGER);\n"
            "INSERT INTO sales VALUES (1,'north',100),(2,'north',50),(3,'south',200),(4,'east',40);"
        ),
        query=(
            "SELECT t.region, t.total FROM "
            "(SELECT region, SUM(amount) AS total FROM sales GROUP BY region) AS t "
            "WHERE t.total > 100 ORDER BY t.total DESC;"
        ),
        expected="south|200\nnorth|150",
        pitfalls=["派生表忘了别名会报错。", "派生表嵌套过深可读性差，超过两层建议改 CTE。"],
        exercises=[
            E("在派生表中计算区域总额，返回总额小于 100 的区域与总额，按总额升序。", "WHERE t.total < 100。",
              "SELECT t.region, t.total FROM (SELECT region, SUM(amount) AS total FROM sales GROUP BY region) AS t WHERE t.total < 100 ORDER BY t.total ASC;",
              "east|40"),
            E("在派生表中算区域单量，返回单量最多的区域与单量。", "ORDER BY n DESC LIMIT 1。",
              "SELECT t.region, t.n FROM (SELECT region, COUNT(*) AS n FROM sales GROUP BY region) AS t ORDER BY t.n DESC LIMIT 1;",
              "north|2"),
        ],
    ),
    L(
        60, "subquery-to-join", "子查询改写为连接", "advanced", "subqueries",
        concepts=["子查询 vs JOIN", "重写"],
        objective="把相关子查询重写成连接以获得更好的执行计划",
        prerequisites=["掌握相关子查询与 JOIN"],
        explain=(
            "相关子查询在逻辑上清晰，但连接通常更快，因为优化器能选择更优的连接顺序与索引。"
            "示例把「每个客户的最新订单金额」用 JOIN 一次分组算出：Ann 60、Ben 40，与相关子查询"
            "结果一致但只扫一遍表。SQLite 3.50 常能自动改写，但显式 JOIN 更可控。"
        ),
        setup=(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer TEXT, amount INTEGER);\n"
            "INSERT INTO orders VALUES (1,'Ann',30),(2,'Ann',60),(3,'Ben',40),(4,'Ben',10);"
        ),
        query=(
            "SELECT o.customer, MAX(o.amount) AS top FROM orders o "
            "GROUP BY o.customer ORDER BY o.customer;"
        ),
        expected="Ann|60\nBen|40",
        pitfalls=["一对多连接后再聚合需确认基数，否则会重复计数。", "改写后必须逐条核对结果与原查询一致。"],
        exercises=[
            E("返回每位客户的订单总额，按客户名升序。", "SUM(amount) GROUP BY customer。",
              "SELECT customer, SUM(amount) FROM orders GROUP BY customer ORDER BY customer;",
              "Ann|90\nBen|50"),
            E("用子查询返回订单金额大于 30 的客户名去重，按升序。", "IN 子查询或 DISTINCT。",
              "SELECT DISTINCT customer FROM orders WHERE amount > 30 ORDER BY customer;",
              "Ann\nBen"),
        ],
    ),
    L(
        61, "any-all", "ANY 与 ALL 比较", "advanced", "subqueries",
        concepts=["ANY", "ALL", "量化比较"],
        objective="理解 SQL 标准量化比较语义并用 MIN/MAX 等价表达",
        prerequisites=["掌握相关子查询"],
        explain=(
            "> ANY (子查询) 表示大于集合中至少一个值，等价于大于最小值；> ALL 表示大于所有值，"
            "等价于大于最大值。SQLite 3.50 不实现 ANY/ALL 关键字，需要用 MIN/MAX 重写。示例"
            "找出分数高于 shanghai 学生最高分 88 的人，即 Ann(95)。"
        ),
        setup=(
            "CREATE TABLE scores (name TEXT, city TEXT, score INTEGER);\n"
            "INSERT INTO scores VALUES ('Ann','beijing',95),('Ben','beijing',80),"
            "('Cara','shanghai',88),('Dan','shanghai',70);"
        ),
        query=(
            "SELECT name, score FROM scores "
            "WHERE score > (SELECT MAX(score) FROM scores WHERE city = 'shanghai') ORDER BY score DESC;"
        ),
        expected="Ann|95",
        pitfalls=["误把 ANY 当 ALL 会得到相反结果集。", "MySQL 的 ANY/ALL 可用，SQLite 需重写，注意方言。"],
        exercises=[
            E("返回分数低于 beijing 学生最低分的人名，按分数升序。", "score < MIN(beijing)。",
              "SELECT name FROM scores WHERE score < (SELECT MIN(score) FROM scores WHERE city = 'beijing') ORDER BY score ASC;",
              "Dan"),
            E("返回高于全局平均分的学生名，按分数降序。", "score > AVG(score)。",
              "SELECT name FROM scores WHERE score > (SELECT AVG(score) FROM scores) ORDER BY score DESC;",
              "Ann\nCara"),
        ],
    ),
    L(
        62, "subqueries-capstone", "综合练习：子查询组合报表", "advanced", "subqueries",
        concepts=["子查询", "聚合", "EXISTS"],
        objective="组合多种子查询形式完成综合分析",
        prerequisites=["掌握本 track"],
        explain=(
            "本课统计每位客户的订单总额，只保留总额高于全局平均订单金额(45)的客户，并按总额"
            "降序。Ann 总额 90、Ben 40、Cara 50，全局平均 = 180/4 = 45，因此只输出 Ann(90) "
            "与 Cara(50)。这里用相关子查询的形态配合分组，完整涵盖聚合子查询用法。"
        ),
        setup=(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer TEXT, amount INTEGER);\n"
            "INSERT INTO orders VALUES (1,'Ann',30),(2,'Ann',60),(3,'Ben',40),(4,'Cara',50);"
        ),
        query=(
            "SELECT customer, SUM(amount) AS total FROM orders GROUP BY customer "
            "HAVING SUM(amount) > (SELECT AVG(amount) FROM orders) ORDER BY total DESC;"
        ),
        expected="Ann|90\nCara|50",
        pitfalls=["HAVING 与子查询都引用 AVG(amount)，分母含义不同要看清。", "聚合子查询要用括号包裹。"],
        exercises=[
            E("返回订单金额高于全局平均的订单 id，按升序。", "WHERE amount > AVG(amount)。",
              "SELECT id FROM orders WHERE amount > (SELECT AVG(amount) FROM orders) ORDER BY id;",
              "2\n4"),
            E("返回总额等于最大客户总额的客户名。", "子查询 MAX 分组总额。",
              "SELECT customer FROM (SELECT customer, SUM(amount) AS total FROM orders GROUP BY customer) t WHERE t.total = (SELECT MAX(s.total) FROM (SELECT SUM(amount) AS total FROM orders GROUP BY customer) s);",
              "Ann"),
        ],
    ),
]
