"""Track 3 — aggregation (lessons 31-40)."""

from __future__ import annotations

from lessons.helper import E, L

LESSONS = [
    L(
        31, "count-forms", "COUNT 的三种写法与差异", "beginner", "aggregation",
        concepts=["COUNT(*)", "COUNT(col)", "COUNT(DISTINCT)"],
        objective="区分 COUNT(*)、COUNT(列) 与 COUNT(DISTINCT 列)",
        prerequisites=["掌握 WHERE"],
        explain=(
            "COUNT(*) 统计行数，COUNT(col) 跳过该列为 NULL 的行，COUNT(DISTINCT col) 统计"
            "去重后的非 NULL 值个数。示例同一张表三种计数结果不同：4 行中 email 有 2 个 NULL，"
            "不同城市有 3 个。"
        ),
        setup=(
            "CREATE TABLE members (id INTEGER PRIMARY KEY, city TEXT, email TEXT);\n"
            "INSERT INTO members VALUES (1,'beijing','a@x.com'),(2,'beijing',NULL),"
            "(3,'shanghai','c@x.com'),(4,'shenzhen',NULL);"
        ),
        query=(
            "SELECT COUNT(*) AS rows, COUNT(email) AS with_email, "
            "COUNT(DISTINCT city) AS cities FROM members;"
        ),
        expected="4|2|3",
        pitfalls=["把 COUNT(col) 当作行数会漏掉 NULL 行。", "COUNT(DISTINCT) 忽略 NULL，不会把 NULL 计为一种。"],
        exercises=[
            E("统计不同 email 的个数（单值）。", "COUNT(DISTINCT email)。",
              "SELECT COUNT(DISTINCT email) FROM members;", "2"),
            E("统计 city 为 beijing 的行数（单值）。", "COUNT(*) 配 WHERE。",
              "SELECT COUNT(*) FROM members WHERE city = 'beijing';", "2"),
        ],
    ),
    L(
        32, "sum-avg-min-max", "SUM/AVG/MIN/MAX", "beginner", "aggregation",
        concepts=["SUM", "AVG", "MIN", "MAX"],
        objective="用四个基本聚合函数做汇总",
        prerequisites=["掌握 COUNT"],
        explain=(
            "SUM 求和、AVG 求平均、MIN/MAX 求最小最大，都忽略 NULL。示例对订单金额汇总："
            "总额 530、平均 132.5、最小 80、最大 250。AVG 是 530/4，NULL 不参与。"
        ),
        setup=(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, amount REAL);\n"
            "INSERT INTO orders VALUES (1,100),(2,80),(3,250),(4,NULL),(5,100);"
        ),
        query="SELECT SUM(amount) AS total, AVG(amount) AS avg_amt, MIN(amount) AS lo, MAX(amount) AS hi FROM orders;",
        expected="530.0|132.5|80.0|250.0",
        pitfalls=["AVG 的分母是非 NULL 计数，不是总行数。", "全为 NULL 时 SUM/AVG/MIN/MAX 都返回 NULL。"],
        exercises=[
            E("统计 amount 非空的订单数（单值）。", "COUNT(amount)。",
              "SELECT COUNT(amount) FROM orders;", "4"),
            E("返回 amount 的总和（单值）。", "SUM(amount)。",
              "SELECT SUM(amount) FROM orders;", "530.0"),
        ],
    ),
    L(
        33, "group-by-basic", "GROUP BY 分组基础", "beginner", "aggregation",
        concepts=["GROUP BY", "分组聚合"],
        objective="按分组列对数据分组并聚合",
        prerequisites=["掌握基本聚合"],
        explain=(
            "GROUP BY 把行按分组键分成若干组，每组产生一行聚合结果。SELECT 列表中非聚合列"
            "必须出现在 GROUP BY 中。示例按 region 分组求销售额合计，返回每个区域的总额。"
        ),
        setup=(
            "CREATE TABLE sales (id INTEGER PRIMARY KEY, region TEXT, amount INTEGER);\n"
            "INSERT INTO sales VALUES (1,'north',100),(2,'south',200),(3,'north',150),(4,'south',50);"
        ),
        query="SELECT region, SUM(amount) AS total FROM sales GROUP BY region ORDER BY region;",
        expected="north|250\nsouth|250",
        pitfalls=["SELECT 里出现未分组的裸列在 SQLite 中会任取一行，语义不确定。", "GROUP BY 后 ORDER BY 才决定组间顺序。"],
        exercises=[
            E("按 region 统计订单数量，按 region 升序。", "COUNT(*)。",
              "SELECT region, COUNT(*) FROM sales GROUP BY region ORDER BY region;", "north|2\nsouth|2"),
            E("按 region 求金额平均值，按 region 升序。", "AVG(amount)。",
              "SELECT region, AVG(amount) FROM sales GROUP BY region ORDER BY region;", "north|125.0\nsouth|125.0"),
        ],
    ),
    L(
        34, "having", "HAVING 过滤分组", "beginner", "aggregation",
        concepts=["HAVING", "分组过滤"],
        objective="用 HAVING 在聚合后过滤分组",
        prerequisites=["掌握 GROUP BY"],
        explain=(
            "WHERE 在分组前过滤行，HAVING 在分组后过滤组。示例先按 region 分组求总额，再用 "
            "HAVING SUM(amount) >= 200 只保留总额达标的区域。HAVING 可以引用聚合结果，而 WHERE "
            "不能直接引用聚合函数。"
        ),
        setup=(
            "CREATE TABLE sales (id INTEGER PRIMARY KEY, region TEXT, amount INTEGER);\n"
            "INSERT INTO sales VALUES (1,'north',100),(2,'south',200),(3,'north',50),(4,'east',500);"
        ),
        query="SELECT region, SUM(amount) AS total FROM sales GROUP BY region HAVING SUM(amount) >= 200 ORDER BY region;",
        expected="east|500\nsouth|200",
        pitfalls=["把聚合条件写进 WHERE 会报错或语义错误。", "HAVING 里列名别名在部分数据库不可用，写聚合表达式最稳妥。"],
        exercises=[
            E("保留订单数大于 1 的区域，按 region 升序。", "HAVING COUNT(*) > 1。",
              "SELECT region FROM sales GROUP BY region HAVING COUNT(*) > 1 ORDER BY region;", "north"),
            E("求总额严格大于 300 的区域，按 region 升序。", "HAVING SUM(amount) > 300。",
              "SELECT region FROM sales GROUP BY region HAVING SUM(amount) > 300 ORDER BY region;", "east"),
        ],
    ),
    L(
        35, "group-by-multi", "GROUP BY 多列与聚合顺序", "beginner", "aggregation",
        concepts=["GROUP BY 多列", "组合键"],
        objective="按多列组合分组并理解分组粒度",
        prerequisites=["掌握 GROUP BY"],
        explain=(
            "GROUP BY a, b 按 (a,b) 组合分组，分组数等于不同组合数。示例按 (region, product) "
            "分组求和，north/pen 与 north/book 是两个不同的组。"
        ),
        setup=(
            "CREATE TABLE sales (id INTEGER PRIMARY KEY, region TEXT, product TEXT, amount INTEGER);\n"
            "INSERT INTO sales VALUES (1,'north','pen',10),(2,'north','pen',20),"
            "(3,'north','book',50),(4,'south','pen',5);"
        ),
        query="SELECT region, product, SUM(amount) AS total FROM sales GROUP BY region, product ORDER BY region, product;",
        expected="north|book|50\nnorth|pen|30\nsouth|pen|5",
        pitfalls=["分组列顺序影响结果行顺序，需配合 ORDER BY。", "组合键基数被低估会得到比预期更多的组。"],
        exercises=[
            E("按 region 与 product 统计行数，按 region、product 升序。", "COUNT(*)。",
              "SELECT region, product, COUNT(*) FROM sales GROUP BY region, product ORDER BY region, product;",
              "north|book|1\nnorth|pen|2\nsouth|pen|1"),
            E("按 product 汇总总额，按总额降序。", "GROUP BY product。",
              "SELECT product, SUM(amount) FROM sales GROUP BY product ORDER BY SUM(amount) DESC;",
              "book|50\npen|35"),
        ],
    ),
    L(
        36, "aggregate-null", "聚合与 NULL 的交互", "beginner", "aggregation",
        concepts=["NULL", "聚合", "COUNT"],
        objective="理解聚合函数对 NULL 的处理规则",
        prerequisites=["掌握聚合基础"],
        explain=(
            "除 COUNT(*) 外，所有聚合函数都跳过 NULL。示例 scores 表中 Bob 分数为 NULL："
            "COUNT(*) = 3，COUNT(score) = 2，SUM = 180，AVG = 90（180/2，不是 180/3）。"
        ),
        setup=(
            "CREATE TABLE scores (id INTEGER PRIMARY KEY, name TEXT, score INTEGER);\n"
            "INSERT INTO scores VALUES (1,'Alice',90),(2,'Bob',NULL),(3,'Carol',90);"
        ),
        query="SELECT COUNT(*) AS rows, COUNT(score) AS n, SUM(score) AS s, AVG(score) AS a FROM scores;",
        expected="3|2|180|90.0",
        pitfalls=["误以为 AVG 会按总行数做分母。", "用 SUM/COUNT(*) 手算平均会与 AVG 不同。"],
        exercises=[
            E("返回 score 的总和（单值）。", "SUM(score)。",
              "SELECT SUM(score) FROM scores;", "180"),
            E("返回 score 非空的行数（单值）。", "COUNT(score)。",
              "SELECT COUNT(score) FROM scores;", "2"),
        ],
    ),
    L(
        37, "group-concat", "GROUP_CONCAT 分组拼接", "beginner", "aggregation",
        concepts=["GROUP_CONCAT", "分隔符"],
        objective="用 GROUP_CONCAT 把组内值拼成一个字符串",
        prerequisites=["掌握 GROUP BY"],
        explain=(
            "GROUP_CONCAT(col, sep) 把组内值按 sep（默认逗号）拼接。SQLite 3.44 起支持"
            "ORDER BY 子句控制拼接顺序；本课示例保证顺序以稳定输出。示例把每个区域的"
            "产品名拼成一串。"
        ),
        setup=(
            "CREATE TABLE sales (id INTEGER PRIMARY KEY, region TEXT, product TEXT);\n"
            "INSERT INTO sales VALUES (1,'north','pen'),(2,'north','book'),(3,'south','bag');"
        ),
        query="SELECT region, GROUP_CONCAT(product, ',') AS products FROM sales GROUP BY region ORDER BY region;",
        expected="north|pen,book\nsouth|bag",
        pitfalls=["默认分隔符是逗号，拼接文本本身含逗号会产生歧义。", "拼接结果长度受 string 长度限制影响。"],
        exercises=[
            E("按 region 用分号拼接 product，按 region 升序。", "GROUP_CONCAT(product,';')。",
              "SELECT region, GROUP_CONCAT(product, ';') FROM sales GROUP BY region ORDER BY region;",
              "north|pen;book\nsouth|bag"),
            E("统计每个区域的产品数量，按 region 升序。", "COUNT(product)。",
              "SELECT region, COUNT(product) FROM sales GROUP BY region ORDER BY region;", "north|2\nsouth|1"),
        ],
    ),
    L(
        38, "rollup-grouping", "小计与总计（ROLLUP 思路）", "intermediate", "aggregation",
        concepts=["ROLLUP", "UNION ALL", "小计"],
        objective="用 UNION ALL 手工构造分组小计",
        prerequisites=["掌握 GROUP BY 与 UNION ALL"],
        explain=(
            "SQLite 3.50 不支持 GROUPING SETS/ROLLUP，需要 UNION ALL 拼接明细组与总计。示例"
            "先用 GROUP BY 得到各区域小计，再 UNION ALL 一行全表总计，用 'TOTAL' 标记。MySQL "
            "8.0 原生支持 WITH ROLLUP。"
        ),
        setup=(
            "CREATE TABLE sales (id INTEGER PRIMARY KEY, region TEXT, amount INTEGER);\n"
            "INSERT INTO sales VALUES (1,'north',100),(2,'south',200),(3,'north',50);"
        ),
        query=(
            "SELECT region, SUM(amount) AS total FROM sales GROUP BY region "
            "UNION ALL SELECT 'TOTAL', SUM(amount) FROM sales;"
        ),
        expected="north|150\nsouth|200\nTOTAL|350",
        pitfalls=["UNION ALL 不去重也不排序，需要外层 ORDER BY。", "各分支列类型应一致，否则类型比较规则会介入。"],
        exercises=[
            E("只返回全表总额（单值）。", "SUM(amount)。",
              "SELECT SUM(amount) FROM sales;", "350"),
            E("返回 north 区域总额（单值）。", "WHERE region='north'。",
              "SELECT SUM(amount) FROM sales WHERE region = 'north';", "150"),
        ],
    ),
    L(
        39, "aggregate-order-limit", "聚合结果排序与分页", "beginner", "aggregation",
        concepts=["ORDER BY", "LIMIT", "聚合"],
        objective="对分组结果排序后取前几名",
        prerequisites=["掌握 HAVING"],
        explain=(
            "聚合结果要排序必须用 ORDER BY 引用聚合表达式或别名，LIMIT 取前 N。示例按区域"
            "汇总后取金额最高前 2 名区域。"
        ),
        setup=(
            "CREATE TABLE sales (id INTEGER PRIMARY KEY, region TEXT, amount INTEGER);\n"
            "INSERT INTO sales VALUES (1,'north',100),(2,'south',200),(3,'east',500),(4,'west',50);"
        ),
        query="SELECT region, SUM(amount) AS total FROM sales GROUP BY region ORDER BY total DESC LIMIT 2;",
        expected="east|500\nsouth|200",
        pitfalls=["ORDER BY 别名在 SQLite/MySQL 都可用，但标准 SQL 只保证部分场景。", "LIMIT 无 ORDER BY 时取哪几组不确定。"],
        exercises=[
            E("按区域汇总后取金额最低 1 个区域，返回 region 与 total。", "ORDER BY total ASC LIMIT 1。",
              "SELECT region, SUM(amount) AS total FROM sales GROUP BY region ORDER BY total ASC LIMIT 1;",
              "west|50"),
            E("按区域汇总后返回 region 列表，按 total 降序。", "只 SELECT region。",
              "SELECT region FROM sales GROUP BY region ORDER BY SUM(amount) DESC;",
              "east\nsouth\nnorth\nwest"),
        ],
    ),
    L(
        40, "aggregation-capstone", "综合练习：销售汇总报表", "intermediate", "aggregation",
        concepts=["GROUP BY", "HAVING", "聚合", "排序"],
        objective="组合分组、聚合、过滤与排序生成汇总报表",
        prerequisites=["掌握本 track"],
        explain=(
            "本课把订单按 (region, product) 汇总，筛掉总额小于 30 的组合，再按总额降序输出。"
            "这是最常见的销售报表形态：先分组聚合，再 HAVING 过滤，最后排序。"
        ),
        setup=(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, region TEXT, product TEXT, amount INTEGER);\n"
            "INSERT INTO orders VALUES (1,'north','pen',10),(2,'north','pen',20),"
            "(3,'north','book',15),(4,'south','pen',40),(5,'south','book',5);"
        ),
        query=(
            "SELECT region, product, SUM(amount) AS total FROM orders "
            "GROUP BY region, product HAVING SUM(amount) >= 30 ORDER BY total DESC, region, product;"
        ),
        expected="south|pen|40\nnorth|pen|30",
        pitfalls=["HAVING 与 WHERE 混用位置错误会改变分组前的行集。", "排序键不唯一时结果顺序不稳，应加次级排序键。"],
        exercises=[
            E("按 region 汇总总额，返回 region 与 total，按 region 升序。", "GROUP BY region。",
              "SELECT region, SUM(amount) AS total FROM orders GROUP BY region ORDER BY region;",
              "north|45\nsouth|45"),
            E("统计 product 为 pen 的订单总额（单值）。", "WHERE product='pen'。",
              "SELECT SUM(amount) FROM orders WHERE product = 'pen';", "70"),
        ],
    ),
]
