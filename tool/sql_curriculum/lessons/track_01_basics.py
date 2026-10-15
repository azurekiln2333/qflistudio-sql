"""Track 1 — basics and single-table queries (lessons 1-14)."""

from __future__ import annotations

from lessons.helper import E, L

LESSONS = [
    L(
        1,
        "select-columns",
        "SELECT 基础与列选择",
        "beginner",
        "basics",
        concepts=["SELECT", "投影", "列别名"],
        objective="用 SELECT 指定要返回的列，并给列起别名",
        prerequisites=["了解表、行、列的概念"],
        explain=(
            "SQLite 3.50 中 SELECT 的基本形态是 SELECT 列表 FROM 表。SELECT 后面的"
            "列表决定返回哪些列，顺序也由它决定，与建表顺序无关。AS 给列起别名，别名"
            "只影响结果集的列名，不改变存储。示例先建一张 employees 表并插入三行，"
            "然后只投影 name 和 salary 两列并按 salary 降序，因此返回的是薪资从高到低"
            "的三行；这里没有 WHERE，全部行都参与。"
        ),
        setup=(
            "CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT NOT NULL, salary REAL NOT NULL);\n"
            "INSERT INTO employees (id, name, salary) VALUES\n"
            "  (1, 'Alice', 12000.0),\n"
            "  (2, 'Bob', 9000.0),\n"
            "  (3, 'Carol', 15000.0);"
        ),
        query="SELECT name AS 姓名, salary AS 月薪 FROM employees ORDER BY salary DESC;",
        expected="Carol|15000.0\nAlice|12000.0\nBob|9000.0",
        pitfalls=[
            "SELECT * 会随表结构变化而变化，生产查询应显式列出所需列。",
            "表达式列的别名在 WHERE/GROUP BY 中的可见性在 SQLite 与 MySQL 有差异。",
        ],
        exercises=[
            E(
                "只返回 name 列，并按 name 升序。",
                "SELECT 指定单列后接 ORDER BY。",
                "SELECT name FROM employees ORDER BY name;",
                "Alice\nBob\nCarol",
            ),
            E(
                "返回 id 与 name 两列，按 id 升序。",
                "列顺序由 SELECT 列表决定。",
                "SELECT id, name FROM employees ORDER BY id;",
                "1|Alice\n2|Bob\n3|Carol",
            ),
        ],
    ),
    L(
        2,
        "where-basic",
        "WHERE 行过滤入门",
        "beginner",
        "basics",
        concepts=["WHERE", "比较运算符"],
        objective="用 WHERE 和比较运算符筛选满足条件的行",
        prerequisites=["会用 SELECT 选列"],
        explain=(
            "WHERE 在 FROM 之后、返回之前对每一行求值，只有条件为真的行进入结果。SQLite "
            "3.50 支持 =、<>（或 !=）、<、<=、>、>= 等比较运算符。示例在 products 表上用"
            "price > 100 过滤，返回价格严格大于 100 的商品：键盘 199 与显示器 899 命中，"
            "鼠标 89 因低于 100 被排除，U盘恰为 100 既不大于也不被选中——这正是“严格大于”"
            "与“大于等于”的分界，若改成 price >= 100 则 U盘 会进入结果。结果按 id 排序"
            "以保证可复现。"
        ),
        setup=(
            "CREATE TABLE products (id INTEGER PRIMARY KEY, name TEXT NOT NULL, price REAL NOT NULL);\n"
            "INSERT INTO products VALUES\n"
            "  (1, '键盘', 199.0),\n"
            "  (2, '鼠标', 89.0),\n"
            "  (3, '显示器', 899.0),\n"
            "  (4, 'U盘', 100.0);"
        ),
        query="SELECT id, name, price FROM products WHERE price > 100 ORDER BY id;",
        expected="1|键盘|199.0\n3|显示器|899.0",
        pitfalls=[
            "NULL 与任何比较都返回 NULL（非真），需要用 IS NULL 判断。",
            "比较字符串时大小写与排序规则由 collation 决定。",
        ],
        exercises=[
            E(
                "返回价格低于 100 的商品 id 与 name，按 id 排序。",
                "使用 price < 100。",
                "SELECT id, name FROM products WHERE price < 100 ORDER BY id;",
                "2|鼠标",
            ),
            E(
                "返回名称不是“鼠标”的商品 id，按 id 排序。",
                "使用 <> 或 !=。",
                "SELECT id FROM products WHERE name <> '鼠标' ORDER BY id;",
                "1\n3\n4",
            ),
        ],
    ),
    L(
        3,
        "logical-operators",
        "逻辑运算符与优先级",
        "beginner",
        "basics",
        concepts=["AND", "OR", "NOT", "括号"],
        objective="组合多个条件并用括号控制优先级",
        prerequisites=["会用 WHERE 做单条件过滤"],
        explain=(
            "AND 比 OR 优先级高，所以 a OR b AND c 等价于 a OR (b AND c)。要表达“两个"
            "备选之一再叠加一个条件”必须显式加括号。SQLite 3.50 中 AND/OR/NOT 遵循三值"
            "逻辑。示例用 (department='sales' OR department='support') AND active=1 选出"
            "在职的销售或支持人员，括号确保 OR 先分组再看 active。"
        ),
        setup=(
            "CREATE TABLE staff (id INTEGER PRIMARY KEY, name TEXT, department TEXT, active INTEGER);\n"
            "INSERT INTO staff VALUES\n"
            "  (1, 'Alice', 'sales', 1),\n"
            "  (2, 'Bob', 'sales', 0),\n"
            "  (3, 'Carol', 'support', 1),\n"
            "  (4, 'Dave', 'engineering', 1);"
        ),
        query=(
            "SELECT id, name FROM staff "
            "WHERE (department = 'sales' OR department = 'support') AND active = 1 "
            "ORDER BY id;"
        ),
        expected="1|Alice\n3|Carol",
        pitfalls=[
            "漏写括号时 OR 会被整体条件优先级影响，结果常与预期不同。",
            "NOT 作用于整个后续表达式时也需要括号界定范围。",
        ],
        exercises=[
            E(
                "返回工程部门或非在职的员工 id，按 id 排序。",
                "用 department='engineering' OR active=0。",
                "SELECT id FROM staff WHERE department = 'engineering' OR active = 0 ORDER BY id;",
                "2\n4",
            ),
            E(
                "返回既不是销售又不在职的员工 id，按 id 排序。",
                "用 NOT 或 <> 配 AND。",
                "SELECT id FROM staff WHERE department <> 'sales' AND active = 0 ORDER BY id;",
                "(no rows)",
            ),
        ],
    ),
    L(
        4,
        "between-in",
        "BETWEEN 与 IN 区间判断",
        "beginner",
        "basics",
        concepts=["BETWEEN", "IN", "范围"],
        objective="用 BETWEEN 表示闭区间、用 IN 表示集合成员",
        prerequisites=["掌握 WHERE 与比较运算符"],
        explain=(
            "BETWEEN a AND b 是闭区间，等价于 x >= a AND x <= b，两端都包含。IN (…) 判断"
            "值是否属于给定集合，等价于一串 OR，但更短更清晰。示例用 score BETWEEN 60 "
            "AND 80 选出 60 到 80 分（含两端）的学生，因此 60 和 80 都会被选中。"
        ),
        setup=(
            "CREATE TABLE scores (id INTEGER PRIMARY KEY, name TEXT, score INTEGER);\n"
            "INSERT INTO scores VALUES\n"
            "  (1, 'Alice', 75),\n"
            "  (2, 'Bob', 80),\n"
            "  (3, 'Carol', 59),\n"
            "  (4, 'Dave', 60),\n"
            "  (5, 'Eve', 95);"
        ),
        query="SELECT name, score FROM scores WHERE score BETWEEN 60 AND 80 ORDER BY score, name;",
        expected="Dave|60\nAlice|75\nBob|80",
        pitfalls=[
            "BETWEEN 是闭区间，容易误以为不含端点。",
            "NOT IN 遇到集合中含 NULL 时整体结果可能为空。",
        ],
        exercises=[
            E(
                "用 IN 返回 id 为 1 或 5 的记录，按 id 排序。",
                "WHERE id IN (1, 5)。",
                "SELECT id, name FROM scores WHERE id IN (1, 5) ORDER BY id;",
                "1|Alice\n5|Eve",
            ),
            E(
                "返回分数不在 60 到 80 之间的学生，按分数升序。",
                "使用 NOT BETWEEN。",
                "SELECT name, score FROM scores WHERE score NOT BETWEEN 60 AND 80 ORDER BY score;",
                "Carol|59\nEve|95",
            ),
        ],
    ),
    L(
        5,
        "like-pattern",
        "LIKE 模式匹配",
        "beginner",
        "basics",
        concepts=["LIKE", "通配符", "ESCAPE"],
        objective="用 LIKE 的 % 与 _ 通配符做模糊匹配",
        prerequisites=["掌握 WHERE"],
        explain=(
            "LIKE 用 % 匹配任意长度（含 0）字符、_ 匹配单个字符。SQLite 3.50 中 LIKE 默认"
            "对 ASCII 大小写不敏感、对非 ASCII 敏感；可用 ESCAPE 指定转义符匹配字面 % 或 "
            "_。示例匹配 email 以 'a' 开头且以 '.com' 结尾的行，前导 'a%' 与尾部 '%.com' "
            "组合实现首尾约束。"
        ),
        setup=(
            "CREATE TABLE users (id INTEGER PRIMARY KEY, email TEXT);\n"
            "INSERT INTO users VALUES\n"
            "  (1, 'alice@example.com'),\n"
            "  (2, 'bob@example.com'),\n"
            "  (3, 'amy@test.org'),\n"
            "  (4, 'adam@example.com');"
        ),
        query="SELECT id, email FROM users WHERE email LIKE 'a%.com' ORDER BY id;",
        expected="1|alice@example.com\n4|adam@example.com",
        pitfalls=[
            "LIKE 'a%.com' 中的 . 是普通字符，若要匹配任意单字符应使用 _。",
            "对非 ASCII 的大小写不敏感需要设置大小写折叠扩展。",
        ],
        exercises=[
            E(
                "返回 email 中包含 'example' 的用户 id，按 id 排序。",
                "使用 %example%。",
                "SELECT id FROM users WHERE email LIKE '%example%' ORDER BY id;",
                "1\n2\n4",
            ),
            E(
                "返回邮箱第二个字符为 'o' 的用户 id，按 id 排序。",
                "用 _ 匹配单个字符：'_o%'。",
                "SELECT id FROM users WHERE email LIKE '_o%' ORDER BY id;",
                "2",
            ),
        ],
    ),
    L(
        6,
        "order-by",
        "ORDER BY 排序与多列排序",
        "beginner",
        "basics",
        concepts=["ORDER BY", "ASC", "DESC"],
        objective="用单列和多列排序并指定升降序",
        prerequisites=["掌握 SELECT 与 WHERE"],
        explain=(
            "ORDER BY 决定结果行顺序，默认升序 ASC，DESC 表示降序。多列排序时后面的列只在"
            "前面的列相等时才起作用。SQLite 3.50 中 NULL 在升序时排最前，可用 NULLS FIRST/"
            "LAST 显式指定。示例按部门升序、同部门内按薪资降序排列，因此 engineering 组的"
            "Dave 在 Carol 之前。"
        ),
        setup=(
            "CREATE TABLE emp (id INTEGER PRIMARY KEY, name TEXT, dept TEXT, salary INTEGER);\n"
            "INSERT INTO emp VALUES\n"
            "  (1, 'Alice', 'sales', 9000),\n"
            "  (2, 'Bob', 'sales', 12000),\n"
            "  (3, 'Carol', 'engineering', 8000),\n"
            "  (4, 'Dave', 'engineering', 15000);"
        ),
        query="SELECT dept, name, salary FROM emp ORDER BY dept ASC, salary DESC;",
        expected="engineering|Dave|15000\nengineering|Carol|8000\nsales|Bob|12000\nsales|Alice|9000",
        pitfalls=[
            "只按非唯一列排序时其余行的顺序不稳定。",
            "在 MySQL 中默认 NULL 升序排最前、降序排最后，与显式 NULLS 子句的方言不同。",
        ],
        exercises=[
            E(
                "按薪资从高到低返回 name 与 salary。",
                "ORDER BY salary DESC。",
                "SELECT name, salary FROM emp ORDER BY salary DESC;",
                "Dave|15000\nBob|12000\nAlice|9000\nCarol|8000",
            ),
            E(
                "按薪资升序返回 name。",
                "ORDER BY salary ASC。",
                "SELECT name FROM emp ORDER BY salary;",
                "Carol\nAlice\nBob\nDave",
            ),
        ],
    ),
    L(
        7,
        "limit-offset",
        "LIMIT 与 OFFSET 分页",
        "beginner",
        "basics",
        concepts=["LIMIT", "OFFSET", "分页"],
        objective="用 LIMIT/OFFSET 取前 N 行并分页",
        prerequisites=["会用 ORDER BY 得到确定顺序"],
        explain=(
            "LIMIT n 只返回前 n 行，OFFSET m 跳过前 m 行。分页必须有稳定的 ORDER BY，否则"
            "同一页可能重复或遗漏。示例按 id 升序跳过 2 行再取 2 行，即第 2 页（每页 2 行）"
            "返回 id 3、4。"
        ),
        setup=(
            "CREATE TABLE logs (id INTEGER PRIMARY KEY, message TEXT);\n"
            "INSERT INTO logs VALUES (1,'a'),(2,'b'),(3,'c'),(4,'d'),(5,'e');"
        ),
        query="SELECT id, message FROM logs ORDER BY id LIMIT 2 OFFSET 2;",
        expected="3|c\n4|d",
        pitfalls=[
            "没有 ORDER BY 时 LIMIT 的结果顺序不确定。",
            "大 OFFSET 会随页数增长而变慢，深分页应考虑键集分页。",
        ],
        exercises=[
            E(
                "取按 id 升序的前 3 行。",
                "LIMIT 3，无 OFFSET。",
                "SELECT id, message FROM logs ORDER BY id LIMIT 3;",
                "1|a\n2|b\n3|c",
            ),
            E(
                "取最后一行（跳过 4 行取 1 行），按 id 升序。",
                "LIMIT 1 OFFSET 4。",
                "SELECT id FROM logs ORDER BY id LIMIT 1 OFFSET 4;",
                "5",
            ),
        ],
    ),
    L(
        8,
        "distinct",
        "DISTINCT 去重",
        "beginner",
        "basics",
        concepts=["DISTINCT", "去重"],
        objective="用 DISTINCT 去掉结果中的重复行",
        prerequisites=["掌握 SELECT 列表"],
        explain=(
            "DISTINCT 作用于整个 SELECT 列表，消除完全相同的组合行，而不是某一列。示例从"
            "orders 表取去重后的 customer 列，只有单个列的重复会被合并。DISTINCT 通常需要"
            "排序或哈希，数据量大时比 GROUP BY 有额外开销。"
        ),
        setup=(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, customer TEXT, amount INTEGER);\n"
            "INSERT INTO orders VALUES (1,'alice',100),(2,'alice',200),(3,'bob',150),(4,'bob',150);"
        ),
        query="SELECT DISTINCT customer FROM orders ORDER BY customer;",
        expected="alice\nbob",
        pitfalls=[
            "误以为 DISTINCT 只对紧跟的第一列生效——它针对整行组合。",
            "对含大文本列做整行去重代价高。",
        ],
        exercises=[
            E(
                "返回去重后的 (customer, amount) 组合，按 customer 升序、amount 升序。",
                "SELECT DISTINCT customer, amount。",
                "SELECT DISTINCT customer, amount FROM orders ORDER BY customer, amount;",
                "alice|100\nalice|200\nbob|150",
            ),
            E(
                "统计有多少个不同客户（返回一个数字）。",
                "用 COUNT(DISTINCT customer)。",
                "SELECT COUNT(DISTINCT customer) FROM orders;",
                "2",
            ),
        ],
    ),
    L(
        9,
        "expressions",
        "表达式与计算列",
        "beginner",
        "basics",
        concepts=["算术表达式", "运算符优先级", "计算列"],
        objective="在 SELECT 中做算术运算并理解优先级",
        prerequisites=["掌握 SELECT 与列"],
        explain=(
            "SELECT 列表里可以写任意表达式，算术运算符 + - * / % 中 * / % 优先级高于 + -，"
            "可用括号改变顺序。SQLite 3.50 中整数除法会截断，要保留小数需至少一个操作数为"
            "实数。示例用 price * qty 计算订单小计，price 是 REAL，所以 19.5*3=58.5 保留小数；"
            "若两列都是整数，7/2 只能得到 3。"
        ),
        setup=(
            "CREATE TABLE order_items (id INTEGER PRIMARY KEY, price REAL, qty INTEGER);\n"
            "INSERT INTO order_items VALUES (1, 19.5, 3), (2, 100.0, 2);"
        ),
        query="SELECT id, price, qty, price * qty AS subtotal FROM order_items ORDER BY id;",
        expected="1|19.5|3|58.5\n2|100.0|2|200.0",
        pitfalls=[
            "整数相除在 SQLite 中会截断，例如 7/2 = 3。",
            "除零在 SQLite 中返回 NULL，不报错。",
        ],
        exercises=[
            E(
                "返回 id 与 price+qty 的结果（列名 total），按 id 排序。",
                "直接相加。",
                "SELECT id, price + qty FROM order_items ORDER BY id;",
                "1|22.5\n2|102.0",
            ),
            E(
                "返回每个商品单价加 10% 后的价格（列名 markup），按 id 排序。",
                "price * 1.1。",
                "SELECT id, price * 1.1 FROM order_items ORDER BY id;",
                "1|21.45\n2|110.0",
            ),
        ],
    ),
    L(
        10,
        "types-cast",
        "类型亲和与 CAST",
        "beginner",
        "basics",
        concepts=["类型亲和", "CAST", "隐式转换"],
        objective="理解 SQLite 动态类型并用 CAST 显式转换",
        prerequisites=["掌握表达式"],
        explain=(
            "SQLite 是动态类型：列有“类型亲和”，但任何列都能存任意类型。CAST(x AS type) "
            "显式转换，常用 INTEGER/TEXT/REAL。示例把文本 '42' 与 '7' 用 CAST 转成整数后"
            "分别加 1，得到 43 与 8；若不写 CAST，'42'+1 虽也会被 SQLite 隐式转成数字，但显式"
            "CAST 语义更清楚、可移植性更好。注意这是逐行转换加 1，不是把两行相加（求和需要"
            "聚合，见练习一）。"
        ),
        setup=(
            "CREATE TABLE raw (id INTEGER PRIMARY KEY, value TEXT);\n"
            "INSERT INTO raw VALUES (1, '42'), (2, '7');"
        ),
        query="SELECT id, CAST(value AS INTEGER) + 1 AS next_int FROM raw ORDER BY id;",
        expected="1|43\n2|8",
        pitfalls=[
            "CAST 不能转换的文本会变成 0 而不是报错。",
            "类型亲和不是强制类型，写入时不会自动严格校验。",
        ],
        exercises=[
            E(
                "把 value 转成整数后相加求和（返回单个数字）。",
                "SUM(CAST(value AS INTEGER))。",
                "SELECT SUM(CAST(value AS INTEGER)) FROM raw;",
                "49",
            ),
            E(
                "返回把 id 与 value 拼成一个字符串的列 combined，按 id 排序。",
                "用 || 拼接，必要时先 CAST id 为 TEXT。",
                "SELECT id || '-' || value FROM raw ORDER BY id;",
                "1-42\n2-7",
            ),
        ],
    ),
    L(
        11,
        "table-alias",
        "表别名与列限定名",
        "beginner",
        "basics",
        concepts=["表别名", "限定列名"],
        objective="用表别名简写并消除列名歧义",
        prerequisites=["掌握 SELECT 与 WHERE"],
        explain=(
            "FROM 表 AS 别名 之后可以用 别名.列 限定引用。单表时别名只是简写；多表连接时"
            "限定名是消除同名列歧义的必需手段。示例给 employees 起别名 e，并用 e.name、"
            "e.salary 限定引用，效果与全名一致。"
        ),
        setup=(
            "CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, salary INTEGER);\n"
            "INSERT INTO employees VALUES (1,'Alice',9000),(2,'Bob',12000);"
        ),
        query="SELECT e.name, e.salary FROM employees AS e WHERE e.salary > 10000 ORDER BY e.id;",
        expected="Bob|12000",
        pitfalls=[
            "起了别名后，某些数据库不允许再用原名引用（SQLite 允许，但不可移植）。",
            "列别名与表别名不可混用，e.name 的 e 必须是表别名。",
        ],
        exercises=[
            E(
                "用别名 x 返回 employees 的 id 与 name，按 id 排序。",
                "FROM employees AS x。",
                "SELECT x.id, x.name FROM employees AS x ORDER BY x.id;",
                "1|Alice\n2|Bob",
            ),
            E(
                "用别名返回薪资大于等于 9000 的 name，按 id 排序。",
                "WHERE 中用别名限定。",
                "SELECT e.name FROM employees AS e WHERE e.salary >= 9000 ORDER BY e.id;",
                "Alice\nBob",
            ),
        ],
    ),
    L(
        12,
        "projection-stability",
        "SELECT 结果集与列顺序",
        "beginner",
        "basics",
        concepts=["投影", "结果稳定性"],
        objective="理解结果列顺序由 SELECT 决定并可显式控制",
        prerequisites=["掌握 SELECT 基础"],
        explain=(
            "结果集列的顺序、名称完全由 SELECT 列表决定：重命名表列不会影响 SELECT * 以外"
            "的显式投影，而 SELECT * 会随表结构变化。示例交换 id 与 name 的投影顺序，证明列"
            "顺序由查询而非建表决定。"
        ),
        setup=(
            "CREATE TABLE t (id INTEGER PRIMARY KEY, name TEXT);\n"
            "INSERT INTO t VALUES (1,'Alice'),(2,'Bob');"
        ),
        query="SELECT name, id FROM t ORDER BY id;",
        expected="Alice|1\nBob|2",
        pitfalls=[
            "依赖 SELECT * 的列顺序在表结构变更后会破坏下游。",
            "列别名与源列名相同容易混淆投影来源。",
        ],
        exercises=[
            E(
                "按 id 降序返回 id 与 name。",
                "ORDER BY id DESC。",
                "SELECT id, name FROM t ORDER BY id DESC;",
                "2|Bob\n1|Alice",
            ),
            E(
                "只返回 name，按 name 降序。",
                "ORDER BY name DESC。",
                "SELECT name FROM t ORDER BY name DESC;",
                "Bob\nAlice",
            ),
        ],
    ),
    L(
        13,
        "nulls-ordering",
        "排序中的 NULL 位置",
        "beginner",
        "basics",
        concepts=["NULL", "NULLS FIRST", "NULLS LAST"],
        objective="控制 NULL 在排序结果中的位置",
        prerequisites=["会用 ORDER BY"],
        explain=(
            "SQLite 3.30 起支持 ORDER BY ... NULLS FIRST/LAST。默认升序时 NULL 排最前、降序"
            "时排最后。示例显式使用 NULLS LAST 让缺失分数排在最后，因此 90、60 在前，NULL 在"
            "后。MySQL 的行为不同，需要 NULLS 子句或 ISNULL 技巧。"
        ),
        setup=(
            "CREATE TABLE exam (id INTEGER PRIMARY KEY, name TEXT, score INTEGER);\n"
            "INSERT INTO exam VALUES (1,'Alice',90),(2,'Bob',NULL),(3,'Carol',60);"
        ),
        query="SELECT name, score FROM exam ORDER BY score ASC NULLS LAST, name;",
        expected="Carol|60\nAlice|90\nBob|",
        pitfalls=[
            "把 NULL 当作 0 比较会得到错误排序或过滤结果。",
            "默认 NULL 位置在 SQLite 与 MySQL 之间不一致。",
        ],
        exercises=[
            E(
                "把 NULL 排在前面，按分数升序返回 name 与 score（NULL 在前）。",
                "ORDER BY score ASC NULLS FIRST。",
                "SELECT name, score FROM exam ORDER BY score ASC NULLS FIRST;",
                "Bob|\nCarol|60\nAlice|90",
            ),
            E(
                "返回分数不为 NULL 的学生 name，按分数降序。",
                "WHERE score IS NOT NULL。",
                "SELECT name FROM exam WHERE score IS NOT NULL ORDER BY score DESC;",
                "Alice\nCarol",
            ),
        ],
    ),
    L(
        14,
        "single-table-capstone",
        "综合练习：单表查询",
        "beginner",
        "basics",
        concepts=["WHERE", "ORDER BY", "LIMIT", "DISTINCT"],
        objective="组合过滤、排序与分页完成单表查询",
        prerequisites=["掌握本 track 前 13 课"],
        explain=(
            "真实查询常同时用到多个子句：WHERE 过滤、ORDER BY 排序、LIMIT 取前几名。本课用"
            "sales 表筛选出金额大于等于 100 的订单，按金额降序取前 3 条，因此返回金额最高的"
            "三条。子句顺序固定为 SELECT … FROM … WHERE … ORDER BY … LIMIT。"
        ),
        setup=(
            "CREATE TABLE sales (id INTEGER PRIMARY KEY, region TEXT, amount INTEGER);\n"
            "INSERT INTO sales VALUES\n"
            "  (1,'north',150),(2,'south',90),(3,'north',300),\n"
            "  (4,'east',120),(5,'south',500),(6,'east',80);"
        ),
        query=(
            "SELECT id, region, amount FROM sales "
            "WHERE amount >= 100 ORDER BY amount DESC LIMIT 3;"
        ),
        expected="5|south|500\n3|north|300\n1|north|150",
        pitfalls=[
            "LIMIT 在 ORDER BY 之后生效，先排序再截断。",
            "WHERE 不能引用 SELECT 列表里的聚合函数。",
        ],
        exercises=[
            E(
                "返回所有区域去重后的列表，按字母升序。",
                "SELECT DISTINCT region。",
                "SELECT DISTINCT region FROM sales ORDER BY region;",
                "east\nnorth\nsouth",
            ),
            E(
                "返回金额小于 100 的订单 id，按金额升序。",
                "WHERE amount < 100。",
                "SELECT id FROM sales WHERE amount < 100 ORDER BY amount;",
                "6\n2",
            ),
        ],
    ),
]
