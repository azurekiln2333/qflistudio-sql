"""Track 4 — joins (lessons 41-52)."""

from __future__ import annotations

from lessons.helper import E, L

LESSONS = [
    L(
        41, "cross-join", "CROSS JOIN 与笛卡尔积", "beginner", "joins",
        concepts=["CROSS JOIN", "笛卡尔积"],
        objective="理解 CROSS JOIN 生成所有组合的语义",
        prerequisites=["掌握 SELECT 与 WHERE"],
        explain=(
            "SQLite 3.50 中 CROSS JOIN 把左表每一行与右表每一行配对，结果行数为两表行数之积。"
            "示例 colors 有 3 行、sizes 有 2 行，因此输出 6 行，顺序按左表外层、右表内层展开。"
            "CROSS JOIN 不做任何匹配，通常用于生成组合清单或作为笛卡尔积教学样本。"
        ),
        setup=(
            "CREATE TABLE colors (name TEXT);\n"
            "INSERT INTO colors VALUES ('red'),('green'),('blue');\n"
            "CREATE TABLE sizes (label TEXT);\n"
            "INSERT INTO sizes VALUES ('S'),('M');"
        ),
        query="SELECT colors.name, sizes.label FROM colors CROSS JOIN sizes;",
        expected="red|S\nred|M\ngreen|S\ngreen|M\nblue|S\nblue|M",
        pitfalls=["忘记 WHERE 连接条件会得到笛卡尔积，行数暴增。", "CROSS JOIN 与逗号连接语法等价，但显式写法更清晰。"],
        exercises=[
            E("按 size 标签统计组合数，返回 label 与计数，按 label 升序。", "GROUP BY label COUNT(*)。",
              "SELECT sizes.label, COUNT(*) FROM colors CROSS JOIN sizes GROUP BY sizes.label ORDER BY sizes.label;",
              "M|3\nS|3"),
            E("只返回 red 与各 size 的组合，按 label 升序。", "WHERE colors.name='red'。",
              "SELECT colors.name, sizes.label FROM colors CROSS JOIN sizes WHERE colors.name = 'red' ORDER BY sizes.label;",
              "red|M\nred|S"),
        ],
    ),
    L(
        42, "inner-join", "INNER JOIN 等值连接", "beginner", "joins",
        concepts=["INNER JOIN", "ON", "等值连接"],
        objective="用 INNER JOIN 按外键匹配两表并只保留匹配行",
        prerequisites=["掌握 CROSS JOIN"],
        explain=(
            "INNER JOIN 只保留 ON 条件成立的行。示例 authors 有 3 位作者、books 有 4 本书，"
            "其中一本的 author_id=99 找不到作者，因此结果只有 3 行匹配记录。SQLite 3.50 的 "
            "INNER JOIN 与 JOIN 完全等价。"
        ),
        setup=(
            "CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT);\n"
            "INSERT INTO authors VALUES (1,'Alice'),(2,'Bob'),(3,'Carol');\n"
            "CREATE TABLE books (id INTEGER PRIMARY KEY, title TEXT, author_id INTEGER);\n"
            "INSERT INTO books VALUES (1,'SQL Basic',1),(2,'SQL Advanced',1),"
            "(3,'Data 101',2),(4,'Mystery',99);"
        ),
        query=(
            "SELECT books.title, authors.name FROM books "
            "INNER JOIN authors ON books.author_id = authors.id ORDER BY books.id;"
        ),
        expected="SQL Basic|Alice\nSQL Advanced|Alice\nData 101|Bob",
        pitfalls=["ON 写错列会得到空结果或错配。", "INNER JOIN 会丢弃无匹配的行，和 LEFT JOIN 语义不同。"],
        exercises=[
            E("统计每位作者的书籍数，返回 name 与计数，按 name 升序。", "GROUP BY authors.name。",
              "SELECT authors.name, COUNT(*) FROM authors INNER JOIN books ON books.author_id = authors.id GROUP BY authors.name ORDER BY authors.name;",
              "Alice|2\nBob|1"),
            E("返回 Alice 写的书名，按 id 升序。", "WHERE authors.name='Alice'。",
              "SELECT books.title FROM books INNER JOIN authors ON books.author_id = authors.id WHERE authors.name = 'Alice' ORDER BY books.id;",
              "SQL Basic\nSQL Advanced"),
        ],
    ),
    L(
        43, "join-multi-table", "三表连接与连接顺序", "intermediate", "joins",
        concepts=["多表连接", "ON 链"],
        objective="在一条语句里按顺序连接三张表",
        prerequisites=["掌握 INNER JOIN"],
        explain=(
            "多表连接从左到右逐次连接，每一步的输出成为下一步的左输入。示例用 orders 连接 "
            "customers 再连接 products，3 条订单各自补上客户名与商品名，全部能匹配，输出 3 行。"
            "SQLite 3.50 按 ON 条件构建中间行集，条件写在各自 JOIN 后面最清楚。"
        ),
        setup=(
            "CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT);\n"
            "INSERT INTO customers VALUES (1,'Ann'),(2,'Ben');\n"
            "CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, price INTEGER);\n"
            "INSERT INTO products VALUES (10,'pen',5),(20,'book',50);\n"
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, product_id INTEGER);\n"
            "INSERT INTO orders VALUES (1,1,10),(2,1,20),(3,2,10);"
        ),
        query=(
            "SELECT orders.id, customers.name, products.name, products.price FROM orders "
            "INNER JOIN customers ON customers.id = orders.customer_id "
            "INNER JOIN products ON products.id = orders.product_id ORDER BY orders.id;"
        ),
        expected="1|Ann|pen|5\n2|Ann|book|50\n3|Ben|pen|5",
        pitfalls=["连接条件遗漏会退化成笛卡尔积。", "多表时列名冲突必须用表名限定。"],
        exercises=[
            E("按客户汇总订单金额，返回客户名与总额，按总额降序。", "SUM(products.price)。",
              "SELECT customers.name, SUM(products.price) FROM orders INNER JOIN customers ON customers.id = orders.customer_id INNER JOIN products ON products.id = orders.product_id GROUP BY customers.name ORDER BY SUM(products.price) DESC;",
              "Ann|55\nBen|5"),
            E("统计商品 pen 被订购次数（单值）。", "WHERE products.name='pen'。",
              "SELECT COUNT(*) FROM orders INNER JOIN products ON products.id = orders.product_id WHERE products.name = 'pen';",
              "2"),
        ],
    ),
    L(
        44, "left-join-missing", "LEFT JOIN 保留左表缺失行", "beginner", "joins",
        concepts=["LEFT JOIN", "NULL 补位"],
        objective="用 LEFT JOIN 保留左表全部行，缺失的右表列填 NULL",
        prerequisites=["掌握 INNER JOIN"],
        explain=(
            "LEFT JOIN 保留左表每行，右表无匹配时右列全为 NULL。示例 customers 有 4 行，"
            "只有 3 行在 orders 里有记录，Dan 没有任何订单，因此它的 order_id 列输出为空字段。"
            "这正是 SQLite CLI 中 NULL 的渲染形式。"
        ),
        setup=(
            "CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT);\n"
            "INSERT INTO customers VALUES (1,'Ann'),(2,'Ben'),(3,'Cara'),(4,'Dan');\n"
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, amount INTEGER);\n"
            "INSERT INTO orders VALUES (101,1,30),(102,2,40),(103,2,60);"
        ),
        query=(
            "SELECT customers.name, orders.id FROM customers "
            "LEFT JOIN orders ON orders.customer_id = customers.id ORDER BY customers.id;"
        ),
        expected="Ann|101\nBen|102\nBen|103\nCara|\nDan|",
        pitfalls=["把 LEFT JOIN 的 ON 条件挪到 WHERE 会过滤掉 NULL 行，退化成 INNER JOIN。", "NULL 参与比较需用 IS NULL。"],
        exercises=[
            E("列出所有客户名及订单数，无订单记 0，按 id 升序。", "COUNT(orders.id) 会跳过 NULL。",
              "SELECT customers.name, COUNT(orders.id) FROM customers LEFT JOIN orders ON orders.customer_id = customers.id GROUP BY customers.id ORDER BY customers.id;",
              "Ann|1\nBen|2\nCara|0\nDan|0"),
            E("返回没有任何订单的客户名，按 id 升序。", "HAVING COUNT(orders.id)=0。",
              "SELECT customers.name FROM customers LEFT JOIN orders ON orders.customer_id = customers.id GROUP BY customers.id HAVING COUNT(orders.id) = 0 ORDER BY customers.id;",
              "Cara\nDan"),
        ],
    ),
    L(
        45, "anti-join", "LEFT JOIN + IS NULL 反连接", "intermediate", "joins",
        concepts=["反连接", "IS NULL", "NOT EXISTS 等价"],
        objective="用 LEFT JOIN 加 IS NULL 找出右表没有匹配的行",
        prerequisites=["掌握 LEFT JOIN"],
        explain=(
            "反连接（anti-join）模式：LEFT JOIN 后用 WHERE 右表主键 IS NULL 筛出未匹配的左行。"
            "示例 orders 有 5 条，其中 product_id=99 的商品在 products 中不存在，因此该行 product 列为空。"
            "SQLite 3.50 支持该写法，也支持等价的 NOT EXISTS。"
        ),
        setup=(
            "CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT);\n"
            "INSERT INTO products VALUES (1,'pen'),(2,'book');\n"
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, product_id INTEGER);\n"
            "INSERT INTO orders VALUES (1,1),(2,2),(3,1),(4,1),(5,99);"
        ),
        query=(
            "SELECT orders.id, products.name FROM orders "
            "LEFT JOIN products ON products.id = orders.product_id "
            "WHERE products.id IS NULL ORDER BY orders.id;"
        ),
        expected="5|",
        pitfalls=["判空必须用 IS NULL，= NULL 永远不成立。", "若要找左表缺失行应调换左右表顺序。"],
        exercises=[
            E("统计没有匹配商品的订单数（单值）。", "WHERE products.id IS NULL。",
              "SELECT COUNT(*) FROM orders LEFT JOIN products ON products.id = orders.product_id WHERE products.id IS NULL;",
              "1"),
            E("返回匹配到商品的订单 id，按 id 升序。", "WHERE products.id IS NOT NULL。",
              "SELECT orders.id FROM orders LEFT JOIN products ON products.id = orders.product_id WHERE products.id IS NOT NULL ORDER BY orders.id;",
              "1\n2\n3\n4"),
        ],
    ),
    L(
        46, "right-join", "RIGHT JOIN 与左右对称", "intermediate", "joins",
        concepts=["RIGHT JOIN", "改写为 LEFT JOIN"],
        objective="理解 RIGHT JOIN 语义并知道如何改写成 LEFT JOIN",
        prerequisites=["掌握 LEFT JOIN"],
        explain=(
            "SQLite 自 3.39 起支持 RIGHT JOIN，3.50 可用；它保留右表全部行。示例以 authors "
            "为左表、books 为右表做 RIGHT JOIN，无书籍的作者以 NULL 补位。等价写法是交换左右表"
            "后用 LEFT JOIN，可读性更好且兼容更老版本。"
        ),
        setup=(
            "CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT);\n"
            "INSERT INTO authors VALUES (1,'Alice'),(2,'Bob'),(3,'Carol');\n"
            "CREATE TABLE books (id INTEGER PRIMARY KEY, title TEXT, author_id INTEGER);\n"
            "INSERT INTO books VALUES (1,'SQL Basic',1),(2,'Data 101',2),(3,'Mystery',3);"
        ),
        query=(
            "SELECT authors.name, books.title FROM books "
            "RIGHT JOIN authors ON books.author_id = authors.id ORDER BY authors.id;"
        ),
        expected="Alice|SQL Basic\nBob|Data 101\nCarol|Mystery",
        pitfalls=["把 RIGHT JOIN 当成 INNER JOIN 会看不出差异，需构造缺失行样本。", "混用左右连接顺序时容易搞反保留哪一侧。"],
        exercises=[
            E("用 LEFT JOIN 改写并返回作者名与书名，按作者 id 升序。", "交换 FROM 与 JOIN 两侧。",
              "SELECT authors.name, books.title FROM authors LEFT JOIN books ON books.author_id = authors.id ORDER BY authors.id;",
              "Alice|SQL Basic\nBob|Data 101\nCarol|Mystery"),
            E("统计每位作者的书籍数，按作者 id 升序。", "COUNT(books.id)。",
              "SELECT authors.name, COUNT(books.id) FROM authors LEFT JOIN books ON books.author_id = authors.id GROUP BY authors.id ORDER BY authors.id;",
              "Alice|1\nBob|1\nCarol|1"),
        ],
    ),
    L(
        47, "full-outer-dialect", "FULL OUTER JOIN 与方言说明", "advanced", "joins",
        concepts=["FULL OUTER JOIN", "UNION ALL", "方言差异"],
        objective="在 SQLite 中用 LEFT + RIGHT JOIN 的 UNION 模拟 FULL OUTER JOIN",
        prerequisites=["掌握 LEFT/RIGHT JOIN"],
        explain=(
            "SQLite 3.50 已支持 FULL OUTER JOIN，但更老版本只能用 LEFT JOIN 与 RIGHT JOIN 的 "
            "UNION 模拟。示例中左边 a 表有 1/2/3，右边 b 表有 2/3/4：匹配 2、3，仅左有 1，"
            "仅右有 4，合计 4 行。用 UNION 而非 UNION ALL 可合并重复的匹配行。"
        ),
        setup=(
            "CREATE TABLE a (id INTEGER);\n"
            "INSERT INTO a VALUES (1),(2),(3);\n"
            "CREATE TABLE b (id INTEGER);\n"
            "INSERT INTO b VALUES (2),(3),(4);"
        ),
        query=(
            "SELECT a.id AS aid, b.id AS bid FROM a LEFT JOIN b ON a.id = b.id "
            "UNION SELECT a.id, b.id FROM a RIGHT JOIN b ON a.id = b.id ORDER BY 1, 2;"
        ),
        expected="|4\n1|\n2|2\n3|3",
        pitfalls=["UNION 会做去重排序开销，UNION ALL 不去重需自行处理重复匹配行。", "列顺序与别名必须在两个分支一致。"],
        exercises=[
            E("返回只存在于 a、不在 b 中的 id，按升序。", "LEFT JOIN + IS NULL。",
              "SELECT a.id FROM a LEFT JOIN b ON a.id = b.id WHERE b.id IS NULL ORDER BY a.id;",
              "1"),
            E("返回 a 与 b 共同的 id，按升序。", "INNER JOIN。",
              "SELECT a.id FROM a INNER JOIN b ON a.id = b.id ORDER BY a.id;",
              "2\n3"),
        ],
    ),
    L(
        48, "self-join", "自连接：同表比较", "intermediate", "joins",
        concepts=["自连接", "别名"],
        objective="对同一张表做自连接以比较行之间的关系",
        prerequisites=["掌握 INNER JOIN"],
        explain=(
            "自连接是给同一张表取两个别名后连接。示例 employees 中每行有 id、name、manager_id，"
            "把 e 当员工、m 当经理连接，找出每位员工的直属上级；Alice 的 manager_id 为 NULL，"
            "所以不出现。共 3 名有上级的员工输出 3 行。"
        ),
        setup=(
            "CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER);\n"
            "INSERT INTO employees VALUES (1,'Alice',NULL),(2,'Ben',1),(3,'Cara',1),(4,'Dan',2);"
        ),
        query=(
            "SELECT e.name AS employee, m.name AS manager FROM employees e "
            "INNER JOIN employees m ON e.manager_id = m.id ORDER BY e.id;"
        ),
        expected="Ben|Alice\nCara|Alice\nDan|Ben",
        pitfalls=["忘记别名会导致列引用歧义。", "自连接在大表上代价高，注意索引 manager_id。"],
        exercises=[
            E("统计每位经理的下属人数，返回经理名与人数，按经理 id 升序。", "GROUP BY m.id。",
              "SELECT m.name, COUNT(*) FROM employees e INNER JOIN employees m ON e.manager_id = m.id GROUP BY m.id ORDER BY m.id;",
              "Alice|2\nBen|1"),
            E("返回没有上级的员工名，按 id 升序。", "WHERE manager_id IS NULL。",
              "SELECT name FROM employees WHERE manager_id IS NULL ORDER BY id;",
              "Alice"),
        ],
    ),
    L(
        49, "non-equi-join", "非等值（范围）连接", "advanced", "joins",
        concepts=["非等值连接", "BETWEEN", "范围匹配"],
        objective="用不等式或区间条件代替等值条件做连接",
        prerequisites=["掌握 INNER JOIN"],
        explain=(
            "JOIN 的 ON 条件不限于等号。示例把 scores.score 落在 grades 区间内的映射出来："
            "grade 用 lo <= score < hi 的半开区间，85 落入 [80,90)，95 落入 [90,100)，"
            "72 落入 [70,80)，每条成绩匹配唯一档位，输出 3 行。SQLite 3.50 对不等值连接"
            "无法用普通 B 树索引加速，大表代价较高。"
        ),
        setup=(
            "CREATE TABLE grades (label TEXT, lo INTEGER, hi INTEGER);\n"
            "INSERT INTO grades VALUES ('C',60,70),('B',70,80),('A',80,90),('S',90,100);\n"
            "CREATE TABLE scores (student TEXT, score INTEGER);\n"
            "INSERT INTO scores VALUES ('Ann',95),('Ben',85),('Cara',72);"
        ),
        query=(
            "SELECT scores.student, scores.score, grades.label FROM scores "
            "INNER JOIN grades ON scores.score >= grades.lo AND scores.score < grades.hi "
            "ORDER BY scores.score DESC;"
        ),
        expected="Ann|95|S\nBen|85|A\nCara|72|B",
        pitfalls=["用 BETWEEN 处理浮点边界可能重复匹配。", "半开区间能避免相邻区间同时命中同一点。"],
        exercises=[
            E("返回分数 >= 80 的学生与档位，按分数降序。", "ON 条件再加 score>=80。",
              "SELECT scores.student, grades.label FROM scores INNER JOIN grades ON scores.score >= grades.lo AND scores.score < grades.hi WHERE scores.score >= 80 ORDER BY scores.score DESC;",
              "Ann|S\nBen|A"),
            E("统计每个档位的学生数，返回 label 与人数，按 label 升序。", "GROUP BY grades.label。",
              "SELECT grades.label, COUNT(*) FROM scores INNER JOIN grades ON scores.score >= grades.lo AND scores.score < grades.hi GROUP BY grades.label ORDER BY grades.label;",
              "A|1\nB|1\nS|1"),
        ],
    ),
    L(
        50, "using-vs-on", "USING 与 ON 的对比", "intermediate", "joins",
        concepts=["USING", "ON", "同名列"],
        objective="理解 USING 对同名列的简写及其结果列合并行为",
        prerequisites=["掌握 INNER JOIN"],
        explain=(
            "当两表连接列同名时，USING(col) 可替代 ON a.col = b.col，并且 SELECT * 时该列只"
            "出现一次。示例 orders 与 items 都有 order_id，用 USING(order_id) 连接后输出 3 行；"
            "ON 写法结果相同但列会重复。SQLite 3.50 两种写法均可。"
        ),
        setup=(
            "CREATE TABLE orders (order_id INTEGER, customer TEXT);\n"
            "INSERT INTO orders VALUES (1,'Ann'),(2,'Ben');\n"
            "CREATE TABLE items (order_id INTEGER, product TEXT);\n"
            "INSERT INTO items VALUES (1,'pen'),(1,'book'),(2,'bag');"
        ),
        query=(
            "SELECT order_id, customer, product FROM orders "
            "INNER JOIN items USING (order_id) ORDER BY order_id, product;"
        ),
        expected="1|Ann|book\n1|Ann|pen\n2|Ben|bag",
        pitfalls=["USING 只能用于两边完全同名的列。", "USING 合并列后 SELECT order_id 不带表前缀，需注意歧义。"],
        exercises=[
            E("用 USING 统计每个订单的商品数，返回 order_id 与数量，按 order_id 升序。", "GROUP BY order_id。",
              "SELECT order_id, COUNT(*) FROM orders INNER JOIN items USING (order_id) GROUP BY order_id ORDER BY order_id;",
              "1|2\n2|1"),
            E("用 ON 返回订单 1 的客户与商品，按 product 升序。", "ON orders.order_id = items.order_id。",
              "SELECT orders.customer, items.product FROM orders INNER JOIN items ON orders.order_id = items.order_id WHERE orders.order_id = 1 ORDER BY items.product;",
              "Ann|book\nAnn|pen"),
        ],
    ),
    L(
        51, "join-aggregation", "连接后聚合", "intermediate", "joins",
        concepts=["JOIN", "GROUP BY", "聚合"],
        objective="在连接结果上做分组聚合生成统计",
        prerequisites=["掌握 INNER JOIN 与 GROUP BY"],
        explain=(
            "连接把维度信息补齐后再聚合，是报表的标准套路。示例把 sales 按 customers 的 city "
            "分组求金额合计：beijing 两条共 250，shanghai 一条 200。SQLite 3.50 先连接再分组，"
            "分组键来自被连接表。"
        ),
        setup=(
            "CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, city TEXT);\n"
            "INSERT INTO customers VALUES (1,'Ann','beijing'),(2,'Ben','shanghai'),(3,'Cara','beijing');\n"
            "CREATE TABLE sales (id INTEGER PRIMARY KEY, customer_id INTEGER, amount INTEGER);\n"
            "INSERT INTO sales VALUES (1,1,100),(2,3,150),(3,2,200);"
        ),
        query=(
            "SELECT customers.city, SUM(sales.amount) AS total FROM sales "
            "INNER JOIN customers ON customers.id = sales.customer_id "
            "GROUP BY customers.city ORDER BY customers.city;"
        ),
        expected="beijing|250\nshanghai|200",
        pitfalls=["在连接后聚合可能导致重复计数（一对多行放大）。", "分组列要来自正确的表。"],
        exercises=[
            E("按客户名汇总销售额，返回 name 与 total，按 total 降序。", "GROUP BY customers.name。",
              "SELECT customers.name, SUM(sales.amount) AS total FROM sales INNER JOIN customers ON customers.id = sales.customer_id GROUP BY customers.name ORDER BY total DESC;",
              "Ben|200\nCara|150\nAnn|100"),
            E("统计城市 beijing 的销售总笔数（单值）。", "COUNT(*)。",
              "SELECT COUNT(*) FROM sales INNER JOIN customers ON customers.id = sales.customer_id WHERE customers.city = 'beijing';",
              "2"),
        ],
    ),
    L(
        52, "joins-capstone", "综合练习：多表销售报表", "advanced", "joins",
        concepts=["多表连接", "聚合", "HAVING", "排序"],
        objective="综合多表连接、聚合、过滤与排序输出报表",
        prerequisites=["掌握本 track"],
        explain=(
            "本课连接 orders、customers、products 三表，按 (city, product) 汇总金额，"
            "用 HAVING 只保留总额 >= 60 的组合，再按总额降序。beijing 的 pen 订单有 Ann 两笔"
            "(30+30) 与 Cara 一笔 30共 90，shanghai 的 book 为 80，两者都达标，最终 2 行。"
        ),
        setup=(
            "CREATE TABLE customers (id INTEGER PRIMARY KEY, name TEXT, city TEXT);\n"
            "INSERT INTO customers VALUES (1,'Ann','beijing'),(2,'Ben','shanghai'),(3,'Cara','beijing');\n"
            "CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT, price INTEGER);\n"
            "INSERT INTO products VALUES (10,'pen',30),(20,'book',80);\n"
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer_id INTEGER, product_id INTEGER, qty INTEGER);\n"
            "INSERT INTO orders VALUES (1,1,10,1),(2,3,10,1),(3,2,20,1),(4,1,10,1);"
        ),
        query=(
            "SELECT customers.city, products.name, SUM(products.price * orders.qty) AS total "
            "FROM orders "
            "INNER JOIN customers ON customers.id = orders.customer_id "
            "INNER JOIN products ON products.id = orders.product_id "
            "GROUP BY customers.city, products.name "
            "HAVING SUM(products.price * orders.qty) >= 60 ORDER BY total DESC;"
        ),
        expected="beijing|pen|90\nshanghai|book|80",
        pitfalls=["忘记乘 qty 会把金额算成单价。", "多表连接后 HAVING 引用的聚合需与 SELECT 一致。"],
        exercises=[
            E("按客户汇总消费额，返回 name 与 total，按 total 降序。", "SUM(products.price*orders.qty)。",
              "SELECT customers.name, SUM(products.price * orders.qty) AS total FROM orders INNER JOIN customers ON customers.id = orders.customer_id INNER JOIN products ON products.id = orders.product_id GROUP BY customers.name ORDER BY total DESC;",
              "Ben|80\nAnn|60\nCara|30"),
            E("返回订单数大于 1 的客户名，按 name 升序。", "HAVING COUNT(*) > 1。",
              "SELECT customers.name FROM orders INNER JOIN customers ON customers.id = orders.customer_id GROUP BY customers.name HAVING COUNT(*) > 1 ORDER BY customers.name;",
              "Ann"),
        ],
    ),
]
