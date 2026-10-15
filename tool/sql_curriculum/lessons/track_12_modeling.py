"""Track 12 — modeling, normalization, dialect, views, capstone (117-120)."""

from __future__ import annotations

from lessons.helper import E, L

LESSONS = [
    L(
        117, "normalization", "数据建模与范式", "advanced", "modeling",
        concepts=["规范化", "范式", "冗余"],
        objective="用规范化拆分实体，消除更新异常",
        prerequisites=["掌握 JOIN 与 DDL"],
        explain=(
            "规范化把重复数据拆到独立实体表，避免插入/更新/删除异常。第一范式列不可再分，"
            "第二范式消除部分依赖，第三范式消除传递依赖。示例把订单里的客户名与城市抽成 "
            "customers 表，orders 只存 customer_id，改城市只需改一处。反范式（如冗余城市名）"
            "在只读报表场景可换取查询性能，属有意权衡。示例 JOIN 两表得到含城市的订单列表。"
        ),
        setup=(
            "CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, city TEXT);\n"
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, amount INTEGER);\n"
            "INSERT INTO customers VALUES (1,'alice','beijing'),(2,'bob','shanghai');\n"
            "INSERT INTO orders VALUES (1,1,100),(2,1,50),(3,2,200);"
        ),
        query=(
            "SELECT o.id, c.name, c.city, o.amount FROM orders AS o "
            "JOIN customers AS c ON c.id = o.customer_id ORDER BY o.id;"
        ),
        expected="1|alice|beijing|100\n2|alice|beijing|50\n3|bob|shanghai|200",
        pitfalls=["过度规范化导致查询需大量 JOIN，读性能下降。", "缺少唯一键时去重困难，规范化前提是稳定的业务键。"],
        exercises=[
            E("返回 alice 的订单总额（单值）。", "JOIN 后 WHERE c.name='alice' 再 SUM。",
              "SELECT SUM(o.amount) FROM orders AS o JOIN customers AS c ON c.id = o.customer_id WHERE c.name = 'alice';",
              "150"),
            E("返回每个客户下过的订单数，按客户 id 升序。", "GROUP BY c.id。",
              "SELECT c.id, COUNT(*) FROM customers AS c JOIN orders AS o ON o.customer_id = c.id GROUP BY c.id ORDER BY c.id;",
              "1|2\n2|1"),
        ],
    ),
    L(
        118, "dialect-differences", "SQLite 与 MySQL 方言差异", "advanced", "modeling",
        concepts=["方言", "兼容性", "版本"],
        objective="识别 SQLite 与 MySQL 的关键语法差异",
        prerequisites=["掌握聚合与 DDL"],
        explain=(
            "同一查询在两库常需改写：字符串拼接 SQLite 用 ||，MySQL 用 CONCAT；UPSERT SQLite "
            "用 INSERT ... ON CONFLICT，MySQL 用 ON DUPLICATE KEY UPDATE；SQLite 无 RIGHT/FULL "
            "JOIN（3.39 起支持 RIGHT/FULL）；GROUP_CONCAT 分隔符语法相似但排序子句不同；日期"
            "运算 SQLite 用 date(x,'+1 day')，MySQL 用 DATE_ADD。示例用 SQLite 的 || 与 date() "
            "完成清洗，讲解给出对应 MySQL 写法。本课为 SQLite 3.50 可执行，MySQL 写法标注为"
            "需在 MySQL 8.0 执行。"
        ),
        setup=(
            "CREATE TABLE events (id INTEGER PRIMARY KEY, name TEXT, at TEXT);\n"
            "INSERT INTO events VALUES (1,'start','2026-01-01'),(2,'stop','2026-01-02');"
        ),
        query=(
            "SELECT id, name || '@' || date(at, '+1 day') AS label FROM events ORDER BY id;"
        ),
        expected="1|start@2026-01-02\n2|stop@2026-01-03",
        pitfalls=["把 MySQL 的 CONCAT 直接拿到 SQLite 会报无此函数。", "MySQL 默认 REPEATABLE READ 与 SQLite 锁模型不同，并发行为差异需分别验证。"],
        exercises=[
            E("返回 label 为 start@ 开头的行 id（单值）。", "name='start'。",
              "SELECT id FROM events WHERE name = 'start';", "1"),
            E("用 +1 天后的日期统计有多少行（单值）。", "COUNT(*)。",
              "SELECT COUNT(*) FROM events WHERE date(at, '+1 day') IS NOT NULL;", "2"),
        ],
    ),
    L(
        119, "views", "视图与查询封装", "advanced", "modeling",
        concepts=["VIEW", "封装", "复用"],
        objective="用视图封装常用查询并复用",
        prerequisites=["掌握 JOIN 与聚合"],
        explain=(
            "CREATE VIEW 把查询保存为命名对象，使用时像表一样查询，实际每次展开执行。视图能"
            "封装复杂 JOIN/聚合、限制暴露字段。示例建视图 v_customer_totals 汇总每客户总额，"
            "随后查询它。视图默认只读；SQLite 中简单视图可配合 INSTEAD OF 触发器实现可写。"
        ),
        setup=(
            "CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT);\n"
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, amount INTEGER);\n"
            "INSERT INTO customers VALUES (1,'alice'),(2,'bob');\n"
            "INSERT INTO orders VALUES (1,1,100),(2,1,50),(3,2,200);\n"
            "CREATE VIEW v_customer_totals AS "
            "SELECT c.id AS customer_id, c.name AS name, SUM(o.amount) AS total "
            "FROM customers AS c JOIN orders AS o ON o.customer_id = c.id GROUP BY c.id, c.name;"
        ),
        query="SELECT customer_id, name, total FROM v_customer_totals ORDER BY customer_id;",
        expected="1|alice|150\n2|bob|200",
        pitfalls=["视图不存储数据，复杂视图每次查询都重新计算。", "嵌套视图过多会难以优化和排错。"],
        exercises=[
            E("从视图返回 total 大于 150 的客户名，按 customer_id 升序。", "WHERE total>150。",
              "SELECT name FROM v_customer_totals WHERE total > 150 ORDER BY customer_id;", "bob"),
            E("统计视图中的客户数量（单值）。", "COUNT(*)。",
              "SELECT COUNT(*) FROM v_customer_totals;", "2"),
        ],
    ),
    L(
        120, "capstone-analytics", "综合实战：多表分析报表", "advanced", "modeling",
        concepts=["JOIN", "CTE", "窗口", "聚合", "报表"],
        objective="综合多表、CTE 与窗口函数生成分析报表",
        prerequisites=["掌握本课程全部 track"],
        explain=(
            "本课把所学组合成一张运营报表：用 CTE 先按 (region, product) 汇总销售额，再用窗口"
            "函数计算每个 region 内按销售额的排名，最后按 region、rank 输出。用 SQLite 3.50 的 "
            "窗口函数与 CTE 一次查询完成，避免多层子查询。窗口函数理解要点：PARTITION BY 划"
            "分分组，ORDER BY 决定组内排名顺序，SUM() OVER(...) 不折叠行。这类报表常见于销售"
            "看板，注意数据量大时先在 CTE 层过滤再开窗以降低计算量。"
        ),
        setup=(
            "CREATE TABLE sales (id INTEGER PRIMARY KEY, region TEXT, product TEXT, amount INTEGER);\n"
            "INSERT INTO sales VALUES\n"
            "  (1,'north','pen',100),(2,'north','book',60),(3,'north','bag',40),\n"
            "  (4,'south','pen',80),(5,'south','book',120),(6,'south','bag',30);"
        ),
        query=(
            "WITH totals AS ("
            "SELECT region, product, SUM(amount) AS total FROM sales GROUP BY region, product) "
            "SELECT region, product, total, "
            "RANK() OVER (PARTITION BY region ORDER BY total DESC) AS rnk "
            "FROM totals ORDER BY region, rnk;"
        ),
        expected="north|pen|100|1\nnorth|book|60|2\nnorth|bag|40|3\nsouth|book|120|1\nsouth|pen|80|2\nsouth|bag|30|3",
        pitfalls=["开窗在聚合之后，顺序写反会得到错误粒度。", "排名并列时 RANK 跳号、DENSE_RANK 不跳，按业务选择。"],
        exercises=[
            E("返回每个 region 销售额最高的 product，按 region 升序（并列取全部）。",
              "CTE + RANK=1。",
              "WITH totals AS (SELECT region, product, SUM(amount) AS total FROM sales GROUP BY region, product), "
              "ranked AS (SELECT region, product, total, RANK() OVER (PARTITION BY region ORDER BY total DESC) AS rnk FROM totals) "
              "SELECT region, product FROM ranked WHERE rnk = 1 ORDER BY region;",
              "north|pen\nsouth|book"),
            E("返回所有销售额的总和（单值）。", "SUM(amount)。",
              "SELECT SUM(amount) FROM sales;", "430"),
        ],
    ),
]
