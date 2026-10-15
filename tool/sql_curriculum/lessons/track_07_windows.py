"""Track 7 — window functions (lessons 71-82)."""

from __future__ import annotations

from lessons.helper import E, L

LESSONS = [
    L(
        71, "over-basics", "窗口函数与 OVER 概念", "advanced", "windows",
        concepts=["OVER", "窗口函数", "不折叠行"],
        objective="理解窗口函数在保留明细行的同时计算分组统计",
        prerequisites=["掌握 GROUP BY 聚合"],
        explain=(
            "窗口函数用 OVER() 定义一个窗口，对每行计算一个「参考同一分组」的值，但不会像 "
            "GROUP BY 那样把多行折叠成一行。示例在保留 4 条订单明细的同时，为每行附加全局总额 "
            "250。SQLite 3.50 自 3.25 起支持窗口函数；OVER 中不含 PARTITION/ORDER 时整个结果集"
            "就是同一个窗口，因此每行总额相同。"
        ),
        setup=(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer TEXT, amount INTEGER);\n"
            "INSERT INTO orders VALUES (1,'Ann',30),(2,'Ann',60),(3,'Ben',80),(4,'Cara',80);"
        ),
        query="SELECT id, amount, SUM(amount) OVER () AS total FROM orders ORDER BY id;",
        expected="1|30|250\n2|60|250\n3|80|250\n4|80|250",
        pitfalls=["把窗口函数当成 GROUP BY 会误以为结果会折叠。", "OVER() 空窗口对所有行适用，常被误认为分组。"],
        exercises=[
            E("返回每行与全局平均额的差，列依次为 id、diff，按 id 升序（平均额保留浮点）。", "amount - AVG(amount) OVER ()。",
              "SELECT id, amount - AVG(amount) OVER () FROM orders ORDER BY id;",
              "1|-32.5\n2|-2.5\n3|17.5\n4|17.5"),
            E("返回每行的 id 与全局最大值，按 id 升序。", "MAX(amount) OVER ()。",
              "SELECT id, MAX(amount) OVER () FROM orders ORDER BY id;",
              "1|80\n2|80\n3|80\n4|80"),
        ],
    ),
    L(
        72, "partition-by", "PARTITION BY 分组窗口", "advanced", "windows",
        concepts=["PARTITION BY", "分区"],
        objective="用 PARTITION BY 在客户内部分别计算汇总",
        prerequisites=["掌握 OVER 基础"],
        explain=(
            "PARTITION BY 把行按分区键切成互不相交的窗口，窗口函数在每个分区内独立计算，不会"
            "跨分区。示例 Ann 两笔合计 90，Ben 与 Cara 各 80，明细行保留原样，同时每行看到"
            "自己所在客户的合计。SQLite 3.50 支持多列 PARTITION BY。"
        ),
        setup=(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer TEXT, amount INTEGER);\n"
            "INSERT INTO orders VALUES (1,'Ann',30),(2,'Ann',60),(3,'Ben',80),(4,'Cara',80);"
        ),
        query=(
            "SELECT customer, amount, SUM(amount) OVER (PARTITION BY customer) AS cust_total "
            "FROM orders ORDER BY id;"
        ),
        expected="Ann|30|90\nAnn|60|90\nBen|80|80\nCara|80|80",
        pitfalls=["PARTITION BY 与 GROUP BY 混淆：前者不减少行数。", "分区结果行顺序仍需 ORDER BY 才稳定。"],
        exercises=[
            E("返回每行的 customer 与其分区平均额，按 id 升序（平均保留浮点）。", "AVG(amount) OVER (PARTITION BY customer)。",
              "SELECT customer, AVG(amount) OVER (PARTITION BY customer) FROM orders ORDER BY id;",
              "Ann|45.0\nAnn|45.0\nBen|80.0\nCara|80.0"),
            E("用 GROUP BY 返回每个客户的合计，按客户名升序。", "对照窗口写法。",
              "SELECT customer, SUM(amount) FROM orders GROUP BY customer ORDER BY customer;",
              "Ann|90\nBen|80\nCara|80"),
        ],
    ),
    L(
        73, "order-by-frame", "ORDER BY 与 ROWS/RANGE 窗口帧", "advanced", "windows",
        concepts=["窗口帧", "ROWS", "RANGE", "累计"],
        objective="理解带 ORDER BY 的窗口默认累计帧与显式帧的区别",
        prerequisites=["掌握 PARTITION BY"],
        explain=(
            "窗口里加 ORDER BY 后，默认帧是 RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW，"
            "即累计到当前行；对金额有序且无重复时与 ROWS 结果一致。示例按 id 排序累计 30、90、"
            "170、250。ROWS 是物理行计数，RANGE 按排序值分组，遇到相同排序值时二者会不同。"
        ),
        setup=(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, amount INTEGER);\n"
            "INSERT INTO orders VALUES (1,30),(2,60),(3,80),(4,80);"
        ),
        query=(
            "SELECT id, amount, SUM(amount) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running "
            "FROM orders ORDER BY id;"
        ),
        expected="1|30|30\n2|60|90\n3|80|170\n4|80|250",
        pitfalls=["误用 ORDER BY 得到累计值却以为是分组总额。", "RANGE 默认帧在重复排序值上会一次纳入多行。"],
        exercises=[
            E("返回每行 id 与前一行金额相加的累计和（不分区），按 id 升序。", "ROWS 累计帧。",
              "SELECT id, SUM(amount) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) FROM orders ORDER BY id;",
              "1|30\n2|90\n3|170\n4|250"),
            E("返回每行 id 与全部金额总和，按 id 升序。", "OVER () 无帧。",
              "SELECT id, SUM(amount) OVER () FROM orders ORDER BY id;",
              "1|250\n2|250\n3|250\n4|250"),
        ],
    ),
    L(
        74, "row-number", "ROW_NUMBER 行号", "advanced", "windows",
        concepts=["ROW_NUMBER", "序号"],
        objective="用 ROW_NUMBER 为每行分配唯一序号",
        prerequisites=["掌握 ORDER BY 窗口帧"],
        explain=(
            "ROW_NUMBER() 按窗口 ORDER BY 为每行分配从 1 开始的连续序号，排序值相同时序号仍"
            "各不相同（由实现决定先后）。示例按 amount 降序给 4 行编号 1-4；并列 80 的两行"
            "得到 2 与 3，说明它不是 RANK。SQLite 3.50 保证序号连续无缺口。"
        ),
        setup=(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, amount INTEGER);\n"
            "INSERT INTO orders VALUES (1,30),(2,80),(3,80),(4,50);"
        ),
        query=(
            "SELECT id, amount, ROW_NUMBER() OVER (ORDER BY amount DESC, id) AS rn "
            "FROM orders ORDER BY amount DESC, id;"
        ),
        expected="2|80|1\n3|80|2\n4|50|3\n1|30|4",
        pitfalls=["ROW_NUMBER 不处理并列，需要 RANK/DENSE_RANK。", "不加 ORDER BY 时序号顺序不确定。"],
        exercises=[
            E("按 id 升序为每行编号，返回 id 与 rn，按 id 升序。", "ROW_NUMBER() OVER (ORDER BY id)。",
              "SELECT id, ROW_NUMBER() OVER (ORDER BY id) FROM orders ORDER BY id;",
              "1|1\n2|2\n3|3\n4|4"),
            E("取金额最大的订单 id（单值）。", "ORDER BY amount DESC LIMIT 1，并列取最小 id。",
              "SELECT id FROM orders ORDER BY amount DESC, id LIMIT 1;",
              "2"),
        ],
    ),
    L(
        75, "rank-dense-rank", "RANK 与 DENSE_RANK", "advanced", "windows",
        concepts=["RANK", "DENSE_RANK", "并列"],
        objective="区分并列排名中 RANK 跳号与 DENSE_RANK 不跳号",
        prerequisites=["掌握 ROW_NUMBER"],
        explain=(
            "RANK 并列时同名次并跳过后续名次；DENSE_RANK 并列时同名次但下一名次加 1 不跳号。"
            "示例金额 80、80、50、30：RANK 为 1、1、3、4，DENSE_RANK 为 1、1、2、3。选择哪个"
            "取决于报表是否需要「第 2 名」这样的连续名次。"
        ),
        setup=(
            "CREATE TABLE scores (name TEXT, score INTEGER);\n"
            "INSERT INTO scores VALUES ('Ann',80),('Ben',80),('Cara',50),('Dan',30);"
        ),
        query=(
            "SELECT name, score, RANK() OVER (ORDER BY score DESC) AS rnk, "
            "DENSE_RANK() OVER (ORDER BY score DESC) AS dense FROM scores ORDER BY score DESC, name;"
        ),
        expected="Ann|80|1|1\nBen|80|1|1\nCara|50|3|2\nDan|30|4|3",
        pitfalls=["把 RANK 当 DENSE_RANK 会以为名次断层是错误。", "排名必须显式指定 ORDER BY。"],
        exercises=[
            E("只返回 RANK 为 1 的学生名，按名字升序。", "用子查询筛选 rnk=1。",
              "SELECT name FROM (SELECT name, RANK() OVER (ORDER BY score DESC) AS rnk FROM scores) t WHERE rnk = 1 ORDER BY name;",
              "Ann\nBen"),
            E("返回 DENSE_RANK 为 2 的学生名，按名字升序。", "dense=2。",
              "SELECT name FROM (SELECT name, DENSE_RANK() OVER (ORDER BY score DESC) AS dense FROM scores) t WHERE dense = 2 ORDER BY name;",
              "Cara"),
        ],
    ),
    L(
        76, "ntile", "NTILE 分桶", "advanced", "windows",
        concepts=["NTILE", "分位桶"],
        objective="用 NTILE(n) 把有序行均分成 n 个桶",
        prerequisites=["掌握 RANK"],
        explain=(
            "NTILE(n) 按窗口排序把行尽量均分为 n 桶，余数从第一桶开始多分一行。示例 5 行分"
            "3 桶得到 2、2、1：先按 id 排序分桶，桶号 1 含 id 1、2，桶号 2 含 3、4，桶号 3 "
            "含 5。常用于分位数、ABCD 档位或资源轮询。"
        ),
        setup=(
            "CREATE TABLE t (id INTEGER PRIMARY KEY);\n"
            "INSERT INTO t VALUES (1),(2),(3),(4),(5);"
        ),
        query="SELECT id, NTILE(3) OVER (ORDER BY id) AS bucket FROM t ORDER BY id;",
        expected="1|1\n2|1\n3|2\n4|2\n5|3",
        pitfalls=["NTILE 不保证每桶绝对均等，余数分配规则要注意。", "桶内顺序由窗口 ORDER BY 决定。"],
        exercises=[
            E("把 5 行分 2 桶，返回 id 与 bucket，按 id 升序。", "NTILE(2)。",
              "SELECT id, NTILE(2) OVER (ORDER BY id) FROM t ORDER BY id;",
              "1|1\n2|1\n3|1\n4|2\n5|2"),
            E("返回第 3 桶（bucket=3）的 id，按升序。", "子查询取 bucket=3。",
              "SELECT id FROM (SELECT id, NTILE(3) OVER (ORDER BY id) AS b FROM t) WHERE b = 3 ORDER BY id;",
              "5"),
        ],
    ),
    L(
        77, "lag-lead", "LAG 与 LEAD 取邻行", "advanced", "windows",
        concepts=["LAG", "LEAD", "偏移"],
        objective="用 LAG/LEAD 比较当前行与前后行",
        prerequisites=["掌握 PARTITION BY"],
        explain=(
            "LAG(col, n) 取排序后向前 n 行的值，LEAD 向后取；无对应行时返回 NULL，可用第三个"
            "参数给默认值。示例按 id 排序比较相邻金额：第 1 行无前值结果为 NULL，第 2 行 60-30=30，"
            "第 3 行 80-60=20（按 id 顺序）。这是同比/环比计算的基础。"
        ),
        setup=(
            "CREATE TABLE sales (id INTEGER PRIMARY KEY, amount INTEGER);\n"
            "INSERT INTO sales VALUES (1,30),(2,60),(3,80);"
        ),
        query=(
            "SELECT id, amount, LAG(amount) OVER (ORDER BY id) AS prev, "
            "amount - LAG(amount) OVER (ORDER BY id) AS diff FROM sales ORDER BY id;"
        ),
        expected="1|30||\n2|60|30|30\n3|80|60|20",
        pitfalls=["LAG 默认偏移 1，忘记参数会与预期不符。", "NULL 参与减法得到 NULL，需 COALESCE 处理首行。"],
        exercises=[
            E("返回每行 id 与下一行金额，最后一行无值留空，按 id 升序。", "LEAD(amount)。",
              "SELECT id, LEAD(amount) OVER (ORDER BY id) FROM sales ORDER BY id;",
              "1|60\n2|80\n3|"),
            E("返回第 3 行相对第 1 行的金额差（单值）。", "amount - LAG(amount,2)。",
              "SELECT amount - LAG(amount, 2) OVER (ORDER BY id) FROM sales ORDER BY id DESC LIMIT 1;",
              "50"),
        ],
    ),
    L(
        78, "first-last-value", "FIRST_VALUE 与 LAST_VALUE", "advanced", "windows",
        concepts=["FIRST_VALUE", "LAST_VALUE", "窗口帧"],
        objective="用 FIRST_VALUE/LAST_VALUE 取窗口边界值并理解默认帧陷阱",
        prerequisites=["掌握 LAG/LEAD"],
        explain=(
            "FIRST_VALUE 取窗口帧第一行，LAST_VALUE 取帧最后一行。关键陷阱：带 ORDER BY 时默认"
            "帧截止当前行，于是 LAST_VALUE 往往等于当前行而非分区末行，必须显式写 ROWS BETWEEN "
            "UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING。示例显式写全帧后，三行的 last 都是 80。"
        ),
        setup=(
            "CREATE TABLE sales (id INTEGER PRIMARY KEY, amount INTEGER);\n"
            "INSERT INTO sales VALUES (1,30),(2,60),(3,80);"
        ),
        query=(
            "SELECT id, FIRST_VALUE(amount) OVER (ORDER BY id) AS first, "
            "LAST_VALUE(amount) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS last "
            "FROM sales ORDER BY id;"
        ),
        expected="1|30|80\n2|30|80\n3|30|80",
        pitfalls=["LAST_VALUE 不写全帧会退化成当前行值。", "PARTITION BY 后 first/last 是分区边界而非全局。"],
        exercises=[
            E("用默认帧返回每行 id 与 LAST_VALUE(amount)，按 id 升序。", "默认帧到当前行。",
              "SELECT id, LAST_VALUE(amount) OVER (ORDER BY id) FROM sales ORDER BY id;",
              "1|30\n2|60\n3|80"),
            E("返回分区最小金额（用 FIRST_VALUE），每行相同，按 id 升序，列依次为 id、first。", "ORDER BY amount ASC 后 FIRST_VALUE。",
              "SELECT id, FIRST_VALUE(amount) OVER (ORDER BY amount ASC, id) FROM sales ORDER BY id;",
              "1|30\n2|30\n3|30"),
        ],
    ),
    L(
        79, "running-total-ma", "累计与移动平均", "advanced", "windows",
        concepts=["累计求和", "移动平均", "窗口帧"],
        objective="用窗口帧算累计总和与滑动平均",
        prerequisites=["掌握窗口帧"],
        explain=(
            "移动平均用 ROWS BETWEEN n PRECEDING AND CURRENT ROW 限定最近 n+1 行。示例先算累计"
            "30、90、170、250，再算 3 行滑动平均：第 1 行仅 30 得 30.0，第 2 行 (30+60)/2=45.0，"
            "第 3 行 (30+60+80)/3 ≈ 56.67（SQLite 显示 56.6666666666667），第 4 行 (60+80+80)/3 "
            "≈ 73.33。移动平均是平滑时序趋势的常用手段。"
        ),
        setup=(
            "CREATE TABLE sales (id INTEGER PRIMARY KEY, amount INTEGER);\n"
            "INSERT INTO sales VALUES (1,30),(2,60),(3,80),(4,80);"
        ),
        query=(
            "SELECT id, SUM(amount) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running, "
            "AVG(amount) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS ma3 "
            "FROM sales ORDER BY id;"
        ),
        expected=(
            "1|30|30.0\n2|90|45.0\n3|170|56.6666666666667\n4|250|73.3333333333333"
        ),
        pitfalls=["ROWS 与 RANGE 在重复值上移动窗口不同。", "窗口过大会显著增加内存与计算量。"],
        exercises=[
            E("只算 3 行滑动平均，返回 id 与 ma，按 id 升序。", "AVG ... ROWS 2 PRECEDING。",
              "SELECT id, AVG(amount) OVER (ORDER BY id ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) FROM sales ORDER BY id;",
              "1|30.0\n2|45.0\n3|56.6666666666667\n4|73.3333333333333"),
            E("算全局累计总和（不设帧），返回 id 与 running，按 id 升序。", "ORDER BY id 默认累计帧。",
              "SELECT id, SUM(amount) OVER (ORDER BY id) FROM sales ORDER BY id;",
              "1|30\n2|90\n3|170\n4|250"),
        ],
    ),
    L(
        80, "period-over-period", "环比与同比", "advanced", "windows",
        concepts=["环比", "LAG", "增长率"],
        objective="用 LAG 计算相邻期环比增长",
        prerequisites=["掌握 LAG/LEAD"],
        explain=(
            "环比用本期减上期再除以上期。示例四个月的销售 100、120、90、150：环比差为 +20、"
            "-30、+60，增长率为 0.2、-0.25、0.6667；首月无上期，差与率均为 NULL。SQLite 3.50 中"
            "整数相除会取整，因此计算比率前需把分子乘 1.0 转浮点。"
        ),
        setup=(
            "CREATE TABLE monthly (m TEXT, amount INTEGER);\n"
            "INSERT INTO monthly VALUES ('2026-01',100),('2026-02',120),('2026-03',90),('2026-04',150);"
        ),
        query=(
            "SELECT m, amount, amount - LAG(amount) OVER (ORDER BY m) AS delta, "
            "(amount - LAG(amount) OVER (ORDER BY m)) * 1.0 / LAG(amount) OVER (ORDER BY m) AS rate "
            "FROM monthly ORDER BY m;"
        ),
        expected=(
            "2026-01|100||\n2026-02|120|20|0.2\n2026-03|90|-30|-0.25\n2026-04|150|60|0.666666666666667"
        ),
        pitfalls=["忘记乘 1.0 会得到整数除法结果 0 或 1。", "首期无上期需在报表层处理 NULL。"],
        exercises=[
            E("返回每期与上期的差额 delta（不算比率），首期留空，按月份升序。", "amount - LAG(amount)。",
              "SELECT m, amount - LAG(amount) OVER (ORDER BY m) FROM monthly ORDER BY m;",
              "2026-01|\n2026-02|20\n2026-03|-30\n2026-04|60"),
            E("用 LAG 返回每期上期金额 prev，首期留空，按月份升序。", "LAG(amount)。",
              "SELECT m, LAG(amount) OVER (ORDER BY m) FROM monthly ORDER BY m;",
              "2026-01|\n2026-02|100\n2026-03|120\n2026-04|90"),
        ],
    ),
    L(
        81, "top-n-dedup", "分组 Top-N 与去重", "advanced", "windows",
        concepts=["ROW_NUMBER", "PARTITION BY", "Top-N", "去重"],
        objective="用分区行号取每组前 N 名或保留每组一行的去重",
        prerequisites=["掌握 ROW_NUMBER 与 PARTITION BY"],
        explain=(
            "分组 Top-N 的标准套路：在子查询里用 ROW_NUMBER() OVER (PARTITION BY 组 ORDER BY "
            "指标 DESC)，外层筛 rn <= N。示例按客户取金额最高的两笔：Ann 有 3 笔按 90、60、30 "
            "排序取前两笔，Ben 只有 2 笔全部保留（40、25），共 4 行。若取 rn=1 即成为每组去重。"
        ),
        setup=(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer TEXT, amount INTEGER);\n"
            "INSERT INTO orders VALUES (1,'Ann',30),(2,'Ann',90),(3,'Ann',60),"
            "(4,'Ben',40),(5,'Ben',25);"
        ),
        query=(
            "SELECT customer, amount FROM ("
            "SELECT customer, amount, ROW_NUMBER() OVER (PARTITION BY customer ORDER BY amount DESC) AS rn "
            "FROM orders) t WHERE rn <= 2 ORDER BY customer, amount DESC;"
        ),
        expected="Ann|90\nAnn|60\nBen|40\nBen|25",
        pitfalls=["WHERE 不能直接引用窗口别名，必须套一层子查询/CTE。", "并列时 ROW_NUMBER 会任意取舍，改 RANK 可保留并列。"],
        exercises=[
            E("取每位客户金额最小的一笔，返回 customer 与 amount，按 customer 升序。", "rn=1，ORDER BY amount ASC。",
              "SELECT customer, amount FROM (SELECT customer, amount, ROW_NUMBER() OVER (PARTITION BY customer ORDER BY amount ASC) AS rn FROM orders) t WHERE rn = 1 ORDER BY customer;",
              "Ann|30\nBen|25"),
            E("取每种客户金额最大的一笔，返回 customer 与 amount，按 customer 升序。", "rn=1，ORDER BY amount DESC。",
              "SELECT customer, amount FROM (SELECT customer, amount, ROW_NUMBER() OVER (PARTITION BY customer ORDER BY amount DESC) AS rn FROM orders) t WHERE rn = 1 ORDER BY customer;",
              "Ann|90\nBen|40"),
        ],
    ),
    L(
        82, "windows-capstone", "综合练习：销售分析报表", "advanced", "windows",
        concepts=["窗口函数", "占比", "排名", "累计"],
        objective="组合分区占比、组内排名与累计完成分析报表",
        prerequisites=["掌握本 track"],
        explain=(
            "本课在一条查询里同时给出：每笔金额占其所在客户合计的比例、按金额的组内排名、"
            "以及按 id 全局累计。数据有 4 笔订单：Ann 两笔 30 与 60（合计 90），Ben 两笔 40 "
            "与 55（合计 95）。因此占比为 Ann 30/90=0.3333、60/90=0.6667，Ben 40/95=0.4211、"
            "55/95=0.5789；组内排名按金额降序，60 与 55 各为组内第 1，30 与 40 为第 2；按 id "
            "的全局累计为 30、90、130、185。SQLite 3.50 的分区窗口与全局窗口可在同一 SELECT "
            "里共存，是 BI 看板的典型形态。"
        ),
        setup=(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer TEXT, amount INTEGER);\n"
            "INSERT INTO orders VALUES (1,'Ann',30),(2,'Ann',60),(3,'Ben',40),(4,'Ben',55);"
        ),
        query=(
            "SELECT id, customer, amount, "
            "ROUND(amount * 1.0 / SUM(amount) OVER (PARTITION BY customer), 4) AS share, "
            "RANK() OVER (PARTITION BY customer ORDER BY amount DESC) AS rnk, "
            "SUM(amount) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running "
            "FROM orders ORDER BY id;"
        ),
        expected=(
            "1|Ann|30|0.3333|2|30\n2|Ann|60|0.6667|1|90\n3|Ben|40|0.4211|2|130\n4|Ben|55|0.5789|1|185"
        ),
        pitfalls=["占比分母必须用分区窗口而非全局窗口。", "ROUND 只影响显示精度，浮点存储仍有误差。"],
        exercises=[
            E("按 id 升序返回每行 id 与全局累计金额。", "SUM(amount) OVER (ORDER BY id)。",
              "SELECT id, SUM(amount) OVER (ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) FROM orders ORDER BY id;",
              "1|30\n2|90\n3|130\n4|185"),
            E("返回每位客户的合计与最大单笔金额，按客户名升序。", "普通 GROUP BY 聚合即可。",
              "SELECT customer, SUM(amount), MAX(amount) FROM orders GROUP BY customer ORDER BY customer;",
              "Ann|90|60\nBen|95|55"),
        ],
    ),
]
