"""Track 6 — CTE (lessons 63-70)."""

from __future__ import annotations

from lessons.helper import E, L

LESSONS = [
    L(
        63, "cte-basics", "WITH 基础", "beginner", "cte",
        concepts=["WITH", "CTE", "命名子查询"],
        objective="用 WITH 定义可读性更好的命名临时结果集",
        prerequisites=["掌握子查询"],
        explain=(
            "CTE（公用表表达式）用 WITH name AS (查询) 定义一个命名结果集，供后续主查询引用。"
            "它和派生表逻辑等价，但可读性更好、可被多次引用。示例把各区域总额命名为 regional，"
            "主查询直接筛选总额大于 100 的行。SQLite 3.50 中 CTE 默认可能被物化或内联，"
            "由优化器决定。"
        ),
        setup=(
            "CREATE TABLE sales (id INTEGER PRIMARY KEY, region TEXT, amount INTEGER);\n"
            "INSERT INTO sales VALUES (1,'north',100),(2,'north',50),(3,'south',200),(4,'east',40);"
        ),
        query=(
            "WITH regional AS (SELECT region, SUM(amount) AS total FROM sales GROUP BY region)\n"
            "SELECT region, total FROM regional WHERE total > 100 ORDER BY total DESC;"
        ),
        expected="south|200\nnorth|150",
        pitfalls=["CTE 只在其后的单条语句内有效。", "CTE 名称会遮蔽同名真实表。"],
        exercises=[
            E("把区域总额 CTE 命名为 regional，返回总额小于 100 的区域与总额，按总额升序。", "WHERE total < 100。",
              "WITH regional AS (SELECT region, SUM(amount) AS total FROM sales GROUP BY region) SELECT region, total FROM regional WHERE total < 100 ORDER BY total ASC;",
              "east|40"),
            E("用 CTE 统计单量最多的区域名与单量。", "COUNT(*) 分组。",
              "WITH counts AS (SELECT region, COUNT(*) AS n FROM sales GROUP BY region) SELECT region, n FROM counts ORDER BY n DESC LIMIT 1;",
              "north|2"),
        ],
    ),
    L(
        64, "cte-multiple", "多个 CTE 与链式引用", "intermediate", "cte",
        concepts=["多重 CTE", "链式引用"],
        objective="定义多个 CTE 并让后者引用前者",
        prerequisites=["掌握 WITH 基础"],
        explain=(
            "一个 WITH 可以定义多个 CTE，用逗号分隔，后面的 CTE 可以引用前面已定义的。示例先"
            "用 orders_total 汇总每位客户消费，再用 big_spenders 筛出总额达标的客户，最终输出 "
            "Ann 90 与 Cara 50。SQLite 3.50 保证 CTE 定义顺序即依赖顺序，不能向前引用。"
        ),
        setup=(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer TEXT, amount INTEGER);\n"
            "INSERT INTO orders VALUES (1,'Ann',30),(2,'Ann',60),(3,'Ben',20),(4,'Cara',50);"
        ),
        query=(
            "WITH orders_total AS (SELECT customer, SUM(amount) AS total FROM orders GROUP BY customer),\n"
            "     big_spenders AS (SELECT customer, total FROM orders_total WHERE total >= 50)\n"
            "SELECT customer, total FROM big_spenders ORDER BY total DESC;"
        ),
        expected="Ann|90\nCara|50",
        pitfalls=["后面的 CTE 引用前面的可以，反过来会报错。", "CTE 数量过多会降低可读性，适当拆分。"],
        exercises=[
            E("用两个 CTE 返回总额小于 50 的客户与总额，按总额升序。", "big_spenders 改条件。",
              "WITH orders_total AS (SELECT customer, SUM(amount) AS total FROM orders GROUP BY customer), small AS (SELECT customer, total FROM orders_total WHERE total < 50) SELECT customer, total FROM small ORDER BY total ASC;",
              "Ben|20"),
            E("用 CTE 统计客户总数（单值）。", "COUNT(DISTINCT customer)。",
              "WITH names AS (SELECT DISTINCT customer FROM orders) SELECT COUNT(*) FROM names;",
              "3"),
        ],
    ),
    L(
        65, "cte-vs-subquery", "CTE 与子查询的取舍", "advanced", "cte",
        concepts=["CTE", "派生表", "可读性与性能"],
        objective="根据复用次数与可读性在 CTE 与子查询间选择",
        prerequisites=["掌握多重 CTE"],
        explain=(
            "当同一段逻辑被引用两次以上，CTE 避免重复书写；只引用一次时派生表与 CTE 性能相近。"
            "示例用同一个 CTE 得到「总额最高的客户」与「客户数」，若用派生表要写两遍聚合。"
            "SQLite 3.50 会把只引用一次的 CTE 内联，避免额外物化开销。"
        ),
        setup=(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer TEXT, amount INTEGER);\n"
            "INSERT INTO orders VALUES (1,'Ann',30),(2,'Ann',60),(3,'Ben',20),(4,'Cara',50);"
        ),
        query=(
            "WITH totals AS (SELECT customer, SUM(amount) AS total FROM orders GROUP BY customer)\n"
            "SELECT (SELECT MAX(total) FROM totals) AS best, (SELECT COUNT(*) FROM totals) AS n;"
        ),
        expected="90|3",
        pitfalls=["CTE 被物化时可能产生额外临时存储开销。", "过度把简单查询拆成 CTE 反而增加阅读成本。"],
        exercises=[
            E("用 CTE 返回客户数与平均总额（单行两列，平均保留浮点）。", "AVG(total)。",
              "WITH totals AS (SELECT customer, SUM(amount) AS total FROM orders GROUP BY customer) SELECT COUNT(*), AVG(total) FROM totals;",
              "3|53.3333333333333"),
            E("用 CTE 返回总额最低的客户名。", "ORDER BY total ASC LIMIT 1。",
              "WITH totals AS (SELECT customer, SUM(amount) AS total FROM orders GROUP BY customer) SELECT customer FROM totals ORDER BY total ASC LIMIT 1;",
              "Ben"),
        ],
    ),
    L(
        66, "cte-recursive-basics", "递归 CTE 基础", "advanced", "cte",
        concepts=["RECURSIVE", "递归 CTE", "基础项与递归项"],
        objective="用 WITH RECURSIVE 生成序列",
        prerequisites=["掌握多重 CTE"],
        explain=(
            "递归 CTE 由基础项（anchor，种子行）与递归项（引用自身）通过 UNION ALL 组成。示例用"
            "种子值 1 和 n+1 递归条件 n<5 生成 1 到 5。SQLite 3.50 要求显式 WITH RECURSIVE，"
            "每轮把上一轮结果代入递归项，直到不再产生新行。"
        ),
        setup=(
            "CREATE TABLE seed (n INTEGER);\n"
            "INSERT INTO seed VALUES (1);"
        ),
        query=(
            "WITH RECURSIVE seq(n) AS (\n"
            "  SELECT n FROM seed\n"
            "  UNION ALL\n"
            "  SELECT n + 1 FROM seq WHERE n < 5\n"
            ")\n"
            "SELECT n FROM seq;"
        ),
        expected="1\n2\n3\n4\n5",
        pitfalls=["递归条件写错或缺失会导致无限循环。", "递归项必须引用 CTE 自身名，否则它不构成递归。"],
        exercises=[
            E("用递归 CTE 生成 2 到 8 的偶数，按升序。", "种子 2，n+2，n<8。",
              "WITH RECURSIVE evens(n) AS (SELECT 2 UNION ALL SELECT n + 2 FROM evens WHERE n < 8) SELECT n FROM evens;",
              "2\n4\n6\n8"),
            E("用递归 CTE 生成 3 到 1 的递减序列，按 n 降序。", "种子 3，n-1，n>1。",
              "WITH RECURSIVE down(n) AS (SELECT 3 UNION ALL SELECT n - 1 FROM down WHERE n > 1) SELECT n FROM down ORDER BY n DESC;",
              "3\n2\n1"),
        ],
    ),
    L(
        67, "cte-hierarchy", "递归遍历层级", "advanced", "cte",
        concepts=["递归 CTE", "层级遍历", "路径"],
        objective="用递归 CTE 展开组织/分类树并计算层级",
        prerequisites=["掌握递归 CTE 基础"],
        explain=(
            "层级表用 parent_id 自引用。递归 CTE 从根节点（parent_id 为 NULL）出发，每轮连接"
            "子节点并让 depth+1。示例 CEO(1) 是根，dept(2,3) 为其子，team(4) 是 2 的子，"
            "depth 依次为 0、1、2，输出按深度与 id 排序共 4 行。SQLite 3.50 支持该标准写法。"
        ),
        setup=(
            "CREATE TABLE org (id INTEGER PRIMARY KEY, name TEXT, parent_id INTEGER);\n"
            "INSERT INTO org VALUES (1,'CEO',NULL),(2,'Dept-A',1),(3,'Dept-B',1),(4,'Team-1',2);"
        ),
        query=(
            "WITH RECURSIVE tree(id, name, depth) AS (\n"
            "  SELECT id, name, 0 FROM org WHERE parent_id IS NULL\n"
            "  UNION ALL\n"
            "  SELECT o.id, o.name, t.depth + 1 FROM org o JOIN tree t ON o.parent_id = t.id\n"
            ")\n"
            "SELECT name, depth FROM tree ORDER BY depth, id;"
        ),
        expected="CEO|0\nDept-A|1\nDept-B|1\nTeam-1|2",
        pitfalls=["根节点条件写错会漏掉整棵树。", "没有终止条件的数据（环）会让递归永不结束。"],
        exercises=[
            E("返回深度为 2 的节点名，按 id 升序。", "在 tree 上 WHERE depth=2。",
              "WITH RECURSIVE tree(id, name, depth) AS (SELECT id, name, 0 FROM org WHERE parent_id IS NULL UNION ALL SELECT o.id, o.name, t.depth + 1 FROM org o JOIN tree t ON o.parent_id = t.id) SELECT name FROM tree WHERE depth = 2 ORDER BY id;",
              "Team-1"),
            E("统计树的节点总数（单值）。", "SELECT COUNT(*) FROM tree。",
              "WITH RECURSIVE tree(id, depth) AS (SELECT id, 0 FROM org WHERE parent_id IS NULL UNION ALL SELECT o.id, t.depth + 1 FROM org o JOIN tree t ON o.parent_id = t.id) SELECT COUNT(*) FROM tree;",
              "4"),
        ],
    ),
    L(
        68, "cte-number-series", "递归生成序列与日期", "advanced", "cte",
        concepts=["数字序列", "日期序列", "递归 CTE"],
        objective="用递归 CTE 生成连续日期序列用于补齐报表",
        prerequisites=["掌握递归 CTE 基础"],
        explain=(
            "报表常需补齐没有数据的日期。示例从 2026-10-01 起用 date(d,'+1 day') 递归生成 5 天。"
            "SQLite 3.50 的 date() 基于儒略日计算，跨月跨年自动进位，无需手工处理月末。生成"
            "序列后 LEFT JOIN 事实表即可得到零值占位行。"
        ),
        setup=(
            "CREATE TABLE holidays (d TEXT);\n"
            "INSERT INTO holidays VALUES ('2026-10-01');"
        ),
        query=(
            "WITH RECURSIVE days(d, i) AS (\n"
            "  SELECT d, 1 FROM holidays\n"
            "  UNION ALL\n"
            "  SELECT date(d, '+1 day'), i + 1 FROM days WHERE i < 5\n"
            ")\n"
            "SELECT d FROM days;"
        ),
        expected="2026-10-01\n2026-10-02\n2026-10-03\n2026-10-04\n2026-10-05",
        pitfalls=["迭代计数必须递增，否则递归永不停止。", "date() 参数格式必须是 YYYY-MM-DD。"],
        exercises=[
            E("生成 2026-12-30 起的 3 天日期，按升序。", "i < 3。",
              "WITH RECURSIVE days(d, i) AS (SELECT '2026-12-30', 1 UNION ALL SELECT date(d, '+1 day'), i + 1 FROM days WHERE i < 3) SELECT d FROM days;",
              "2026-12-30\n2026-12-31\n2027-01-01"),
            E("跳过周末：生成 2026-10-01 起一周内的工作日，按升序。", "用 strftime('%w', d) NOT IN ('0','6')。",
              "WITH RECURSIVE days(d, i) AS (SELECT '2026-10-01', 1 UNION ALL SELECT date(d, '+1 day'), i + 1 FROM days WHERE i < 7) SELECT d FROM days WHERE strftime('%w', d) NOT IN ('0', '6') ORDER BY d;",
              "2026-10-01\n2026-10-02\n2026-10-05\n2026-10-06\n2026-10-07"),
        ],
    ),
    L(
        69, "cte-cycle-guard", "递归终止与环路防护", "advanced", "cte",
        concepts=["递归终止", "环路检测", "深度上限"],
        objective="用路径字符串检测环路并限制递归深度",
        prerequisites=["掌握递归遍历层级"],
        explain=(
            "当数据存在环路（A 的父是 B、B 的父是 A）时，朴素递归会无限展开。防护方式是携带"
            "已访问路径，用 instr(path, ',' || o.id || ',') = 0 判断是否已走过。示例数据无环，"
            "因此正常输出 3 层路径，但同样的写法在含环数据上会安全终止。SQLite 3.50 支持 "
            "instr 与字符串拼接。"
        ),
        setup=(
            "CREATE TABLE edges (src TEXT, dst TEXT);\n"
            "INSERT INTO edges VALUES ('A','B'),('B','C');"
        ),
        query=(
            "WITH RECURSIVE path(node, route) AS (\n"
            "  SELECT 'A', ',A,'\n"
            "  UNION ALL\n"
            "  SELECT e.dst, p.route || e.dst || ',' FROM edges e JOIN path p ON e.src = p.node\n"
            "  WHERE instr(p.route, ',' || e.dst || ',') = 0\n"
            ")\n"
            "SELECT node FROM path ORDER BY length(route);"
        ),
        expected="A\nB\nC",
        pitfalls=["不做环路检测在生产图数据上会耗尽内存或超时。", "路径分隔符要选数据中不出现的字符。"],
        exercises=[
            E("返回路径字符串长度大于 4 的节点数（单值）。", "length(route) > 4。",
              "WITH RECURSIVE path(node, route) AS (SELECT 'A', ',A,' UNION ALL SELECT e.dst, p.route || e.dst || ',' FROM edges e JOIN path p ON e.src = p.node WHERE instr(p.route, ',' || e.dst || ',') = 0) SELECT COUNT(*) FROM path WHERE length(route) > 4;",
              "2"),
            E("返回最终节点（路径最长）名，单值。", "ORDER BY length(route) DESC LIMIT 1。",
              "WITH RECURSIVE path(node, route) AS (SELECT 'A', ',A,' UNION ALL SELECT e.dst, p.route || e.dst || ',' FROM edges e JOIN path p ON e.src = p.node WHERE instr(p.route, ',' || e.dst || ',') = 0) SELECT node FROM path ORDER BY length(route) DESC LIMIT 1;",
              "C"),
        ],
    ),
    L(
        70, "cte-capstone", "综合练习：组织路径报表", "advanced", "cte",
        concepts=["递归 CTE", "路径拼接", "聚合"],
        objective="用递归 CTE 输出每名员工到根的完整路径",
        prerequisites=["掌握本 track"],
        explain=(
            "本课递归展开 org 表，把每层的名字拼成 CEO > ... 形式的路径，并统计各员工深度。"
            "根节点 CEO 路径就是 'CEO'，Dept-A 与 Dept-B 路径为 'CEO > Dept-A' / 'CEO > Dept-B'，"
            "Team-1 为 'CEO > Dept-A > Team-1'，共 4 行。这类写法广泛用于组织图、目录树和物料 "
            "BOM。"
        ),
        setup=(
            "CREATE TABLE org (id INTEGER PRIMARY KEY, name TEXT, parent_id INTEGER);\n"
            "INSERT INTO org VALUES (1,'CEO',NULL),(2,'Dept-A',1),(3,'Dept-B',1),(4,'Team-1',2);"
        ),
        query=(
            "WITH RECURSIVE tree(id, path, depth) AS (\n"
            "  SELECT id, name, 0 FROM org WHERE parent_id IS NULL\n"
            "  UNION ALL\n"
            "  SELECT o.id, t.path || ' > ' || o.name, t.depth + 1 FROM org o JOIN tree t ON o.parent_id = t.id\n"
            ")\n"
            "SELECT path, depth FROM tree ORDER BY depth, id;"
        ),
        expected=(
            "CEO|0\nCEO > Dept-A|1\nCEO > Dept-B|1\nCEO > Dept-A > Team-1|2"
        ),
        pitfalls=["concatenation 顺序反了会得到倒置路径。", "路径字符串随深度增长，深层级时内存占用上升。"],
        exercises=[
            E("返回深度为 1 的节点路径，按 id 升序。", "WHERE depth = 1。",
              "WITH RECURSIVE tree(id, path, depth) AS (SELECT id, name, 0 FROM org WHERE parent_id IS NULL UNION ALL SELECT o.id, t.path || ' > ' || o.name, t.depth + 1 FROM org o JOIN tree t ON o.parent_id = t.id) SELECT path FROM tree WHERE depth = 1 ORDER BY id;",
              "CEO > Dept-A\nCEO > Dept-B"),
            E("返回最大深度值（单值）。", "MAX(depth)。",
              "WITH RECURSIVE tree(id, depth) AS (SELECT id, 0 FROM org WHERE parent_id IS NULL UNION ALL SELECT o.id, t.depth + 1 FROM org o JOIN tree t ON o.parent_id = t.id) SELECT MAX(depth) FROM tree;",
              "2"),
        ],
    ),
]
