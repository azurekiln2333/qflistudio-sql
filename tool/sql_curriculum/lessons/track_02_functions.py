"""Track 2 — expressions, functions, NULL, CASE (lessons 15-30)."""

from __future__ import annotations

from lessons.helper import E, L

LESSONS = [
    L(
        15, "str-functions-1", "字符串函数（上）：长度与截取", "beginner", "functions",
        concepts=["length", "substr", "字符串"],
        objective="用 length、substr 处理字符串长度与子串",
        prerequisites=["掌握 SELECT 与表达式"],
        explain=(
            "SQLite 3.50 提供 length(x) 返回字符数（BLOB 返回字节数），substr(x,start,len) "
            "从 1 开始计位取子串。示例取姓名首字符作为缩写，并用 length 显示姓名长度；"
            "substr(name,1,1) 返回第一个字符。"
        ),
        setup=(
            "CREATE TABLE people (id INTEGER PRIMARY KEY, name TEXT);\n"
            "INSERT INTO people VALUES (1,'Alice'),(2,'Bob'),(3,'Charlotte');"
        ),
        query="SELECT id, name, length(name) AS len, substr(name,1,1) AS initial FROM people ORDER BY id;",
        expected="1|Alice|5|A\n2|Bob|3|B\n3|Charlotte|9|C",
        pitfalls=["substr 起始下标是 1，不是 0。", "length 对中文按字符计数，对 BLOB 按字节。"],
        exercises=[
            E("返回 name 的前 3 个字符，按 id 排序。", "substr(name,1,3)。",
              "SELECT substr(name,1,3) FROM people ORDER BY id;", "Ali\nBob\nCha"),
            E("返回 name 长度大于 3 的 id，按 id 排序。", "WHERE length(name) > 3。",
              "SELECT id FROM people WHERE length(name) > 3 ORDER BY id;", "1\n3"),
        ],
    ),
    L(
        16, "str-functions-2", "字符串函数（下）：拼接、替换、大小写", "beginner", "functions",
        concepts=["||", "replace", "upper", "lower", "trim"],
        objective="用拼接、替换、大小写和去空白函数清洗文本",
        prerequisites=["掌握基础字符串函数"],
        explain=(
            "|| 拼接字符串，replace(x,from,to) 替换，upper/lower 改大小写，trim 去两端空白。"
            "示例把名字与域名拼成邮箱，并用 upper 输出大写名。SQLite 3.50 中 upper/lower 只"
            "处理 ASCII，非 ASCII 需要外部函数。"
        ),
        setup=(
            "CREATE TABLE accounts (id INTEGER PRIMARY KEY, user_name TEXT, domain TEXT);\n"
            "INSERT INTO accounts VALUES (1,'alice','example.com'),(2,'  bob  ','test.org');"
        ),
        query="SELECT id, upper(trim(user_name)) AS uname, trim(user_name) || '@' || domain AS email FROM accounts ORDER BY id;",
        expected="1|ALICE|alice@example.com\n2|BOB|bob@test.org",
        pitfalls=["upper/lower 对中文与带重音的拉丁字符不生效。", "拼接 NULL 会得到 NULL，需要 COALESCE。"],
        exercises=[
            E("把 domain 中 'example.com' 替换为 'sample.net'，按 id 排序。",
              "replace(domain,'example.com','sample.net')。",
              "SELECT replace(domain,'example.com','sample.net') FROM accounts ORDER BY id;",
              "sample.net\ntest.org"),
            E("返回 user_name 已去除空白的长度，按 id 排序。",
              "length(trim(user_name))。",
              "SELECT length(trim(user_name)) FROM accounts ORDER BY id;", "5\n3"),
        ],
    ),
    L(
        17, "numeric-functions", "数值函数与舍入", "beginner", "functions",
        concepts=["abs", "round", "max", "min"],
        objective="用数值函数处理取绝对值与舍入",
        prerequisites=["掌握算术表达式"],
        explain=(
            "abs(x) 取绝对值，round(x,n) 四舍五入到 n 位小数。SQLite 的 round 使用远离零的"
            "四舍五入（half away from zero），作用于十进制表示，无需指定模式。示例对存款差额"
            "取绝对值并保留 1 位小数：10.456 → 10.5，-3.2 取绝对值后为 3.2。另外 SQLite 中"
            "max/min 既可作聚合（作用于多行）也可作标量函数（作用于多个参数），含义随上下文变化。"
        ),
        setup=(
            "CREATE TABLE txn (id INTEGER PRIMARY KEY, balance REAL);\n"
            "INSERT INTO txn VALUES (1, 10.456), (2, -3.2), (3, 5.0);"
        ),
        query="SELECT id, balance, abs(balance) AS a, round(abs(balance), 1) AS r FROM txn ORDER BY id;",
        expected="1|10.456|10.456|10.5\n2|-3.2|3.2|3.2\n3|5.0|5.0|5.0",
        pitfalls=["round 的结果仍是浮点，可能残留表示误差。", "标量 min/max 至少需要两个参数。"],
        exercises=[
            E("返回每行 balance 的整数部分（向下取整需注意负数），按 id 排序。",
              "SQLite 中 CAST(balance AS INTEGER) 对负数向零截断。",
              "SELECT id, CAST(balance AS INTEGER) FROM txn ORDER BY id;", "1|10\n2|-3\n3|5"),
            E("返回 balance 的最大值（标量，仅一行）。", "max(balance)。",
              "SELECT max(balance) FROM txn;", "10.456"),
        ],
    ),
    L(
        18, "date-functions-1", "日期时间函数入门", "beginner", "functions",
        concepts=["date", "datetime", "julianday"],
        objective="用日期函数提取日期部分并做时间运算",
        prerequisites=["掌握字符串与表达式"],
        explain=(
            "SQLite 3.50 把日期存为 TEXT（ISO8601）或数字。date(x)、datetime(x) 归一化，"
            "date(x,'+1 day') 做日期加法。示例把 shipped_at 加一天得到预计到达日期。SQLite "
            "没有专门的 DATE 类型，'2026-01-01' 只是普通文本，函数负责解释。"
        ),
        setup=(
            "CREATE TABLE shipments (id INTEGER PRIMARY KEY, shipped_at TEXT);\n"
            "INSERT INTO shipments VALUES (1,'2026-01-01'),(2,'2026-02-28');"
        ),
        query="SELECT id, shipped_at, date(shipped_at, '+1 day') AS eta FROM shipments ORDER BY id;",
        expected="1|2026-01-01|2026-01-02\n2|2026-02-28|2026-03-01",
        pitfalls=["日期必须是可解析的格式，否则 date() 返回 NULL。", "闰年由 date 函数正确处理，别手算。"],
        exercises=[
            E("返回每行的年份部分，按 id 排序。", "strftime('%Y', shipped_at)。",
              "SELECT id, strftime('%Y', shipped_at) FROM shipments ORDER BY id;", "1|2026\n2|2026"),
            E("返回 2026-02-28 加 2 天后的日期。", "date('2026-02-28','+2 days')。",
              "SELECT date('2026-02-28', '+2 days');", "2026-03-02"),
        ],
    ),
    L(
        19, "date-functions-2", "日期时间运算与格式化", "beginner", "functions",
        concepts=["julianday", "strftime", "日期差"],
        objective="计算两个日期之间的天数并按格式输出",
        prerequisites=["掌握日期函数入门"],
        explain=(
            "julianday(x) 返回儒略日数（含小数），两日期相减得到天数差。strftime 按格式串"
            "输出，如 %Y-%m-%d。示例计算已发货到到货的天数差，并用 strftime 输出年月。"
        ),
        setup=(
            "CREATE TABLE trips (id INTEGER PRIMARY KEY, start_date TEXT, end_date TEXT);\n"
            "INSERT INTO trips VALUES (1,'2026-01-01','2026-01-05'),(2,'2026-03-01','2026-03-11');"
        ),
        query=(
            "SELECT id, CAST(julianday(end_date) - julianday(start_date) AS INTEGER) AS days, "
            "strftime('%Y-%m', start_date) AS ym FROM trips ORDER BY id;"
        ),
        expected="1|4|2026-01\n2|10|2026-03",
        pitfalls=["julianday 差是浮点，直接比较可能受精度影响。", "strftime 的格式串大小写敏感。"],
        exercises=[
            E("返回天数差大于 5 的行程 id，按 id 排序。",
              "用 julianday 差比较。",
              "SELECT id FROM trips WHERE julianday(end_date) - julianday(start_date) > 5 ORDER BY id;",
              "2"),
            E("返回 start_date 的星期几（0=周日，用 %w），按 id 排序。", "strftime('%w', start_date)。",
              "SELECT id, strftime('%w', start_date) FROM trips ORDER BY id;", "1|4\n2|0"),
        ],
    ),
    L(
        20, "null-semantics", "NULL 语义与三值逻辑", "beginner", "functions",
        concepts=["NULL", "IS NULL", "三值逻辑"],
        objective="理解 NULL 表示未知以及三值逻辑的判定",
        prerequisites=["掌握 WHERE"],
        explain=(
            "NULL 表示“未知”，与任何值比较（包括 NULL = NULL）结果都是 NULL，在 WHERE 中"
            "视为不成立。判断缺失必须用 IS NULL / IS NOT NULL。示例用 IS NULL 找出没有"
            "经理的员工，NULL=0 或 NULL<>0 都无法命中。"
        ),
        setup=(
            "CREATE TABLE emp (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER);\n"
            "INSERT INTO emp VALUES (1,'Alice',NULL),(2,'Bob',1),(3,'Carol',1),(4,'Dave',NULL);"
        ),
        query="SELECT id, name FROM emp WHERE manager_id IS NULL ORDER BY id;",
        expected="1|Alice\n4|Dave",
        pitfalls=["NULL = NULL 返回 NULL 而非真，不能用等号判空。", "COUNT(列) 会跳过 NULL，COUNT(*) 不会。"],
        exercises=[
            E("返回有经理（manager_id 非空）的员工 id，按 id 排序。", "IS NOT NULL。",
              "SELECT id FROM emp WHERE manager_id IS NOT NULL ORDER BY id;", "2\n3"),
            E("统计有经理的员工数量与总员工数量（一行两列）。", "COUNT(manager_id), COUNT(*)。",
              "SELECT COUNT(manager_id), COUNT(*) FROM emp;", "2|4"),
        ],
    ),
    L(
        21, "coalesce", "COALESCE 与 IFNULL", "beginner", "functions",
        concepts=["COALESCE", "IFNULL", "默认值"],
        objective="用 COALESCE/IFNULL 为 NULL 提供默认值",
        prerequisites=["理解 NULL 语义"],
        explain=(
            "COALESCE(a,b,...) 返回第一个非 NULL 参数；IFNULL(a,b) 是双参数的简写。示例给"
            "缺失的折扣补 0，再计算折后价，避免 NULL 参与运算导致整行结果为 NULL。"
        ),
        setup=(
            "CREATE TABLE items (id INTEGER PRIMARY KEY, price REAL, discount REAL);\n"
            "INSERT INTO items VALUES (1,100.0,NULL),(2,200.0,10.0);"
        ),
        query="SELECT id, price, COALESCE(discount,0) AS d, price - COALESCE(discount,0) AS net FROM items ORDER BY id;",
        expected="1|100.0|0|100.0\n2|200.0|10.0|190.0",
        pitfalls=["COALESCE 参数类型应一致，混合类型会触发类型比较规则。", "IFNULL 只有两个参数，多级回退要用 COALESCE。"],
        exercises=[
            E("用 IFNULL 把 discount 为空的显示为 -1，按 id 排序。", "IFNULL(discount,-1)。",
              "SELECT id, IFNULL(discount,-1) FROM items ORDER BY id;", "1|-1\n2|10.0"),
            E("返回折后价净额总和（单值）。", "SUM(price - COALESCE(discount,0))。",
              "SELECT SUM(price - COALESCE(discount,0)) FROM items;", "290.0"),
        ],
    ),
    L(
        22, "nullif", "NULLIF 与空字符串处理", "beginner", "functions",
        concepts=["NULLIF", "空字符串", "除零保护"],
        objective="用 NULLIF 把特定值转为 NULL，常用于除零保护",
        prerequisites=["掌握 COALESCE"],
        explain=(
            "NULLIF(a,b) 在 a = b 时返回 NULL，否则返回 a。常用于把空字符串或 0 转换为 NULL，"
            "例如 x / NULLIF(y,0) 可避免除零。示例把分母为 0 的行的除法结果变为 NULL（第 2 行"
            "显示为空），其余行正常相除；如需把 NULL 展示成占位值，可在外层再套 COALESCE，见"
            "练习二。"
        ),
        setup=(
            "CREATE TABLE ratio (id INTEGER PRIMARY KEY, num INTEGER, den INTEGER);\n"
            "INSERT INTO ratio VALUES (1,10,2),(2,10,0),(3,0,5);"
        ),
        query="SELECT id, num / NULLIF(den,0) AS q FROM ratio ORDER BY id;",
        expected="1|5\n2|\n3|0",
        pitfalls=["NULLIF 相等判断遵循类型比较规则，'0' 与 0 可能不等。", "除零在 SQLite 本身返回 NULL，但显式 NULLIF 语义更清晰、可移植。"],
        exercises=[
            E("返回 num=NULLIF(den,den) 的结果（应全为 NULL 故为空），按 id 排序。",
              "NULLIF(den,den) 恒为 NULL。",
              "SELECT id, NULLIF(den,den) FROM ratio ORDER BY id;",
              "1|\n2|\n3|"),
            E("用 COALESCE 把上一题的除法结果 NULL 显示为 -1，按 id 排序。",
              "COALESCE(num/NULLIF(den,0),-1)。",
              "SELECT id, COALESCE(num / NULLIF(den,0), -1) FROM ratio ORDER BY id;", "1|5\n2|-1\n3|0"),
        ],
    ),
    L(
        23, "case-simple", "CASE 简单表达式", "beginner", "functions",
        concepts=["CASE", "映射"],
        objective="用简单 CASE 把取值映射为标签",
        prerequisites=["掌握 WHERE 与表达式"],
        explain=(
            "CASE expr WHEN v1 THEN r1 WHEN v2 THEN r2 ELSE rd END 是等值映射，逐一比较 expr。"
            "示例把 code 1/2/3 映射为中文状态标签，无匹配的走 ELSE。"
        ),
        setup=(
            "CREATE TABLE orders (id INTEGER PRIMARY KEY, code INTEGER);\n"
            "INSERT INTO orders VALUES (1,1),(2,2),(3,3),(4,9);"
        ),
        query=(
            "SELECT id, CASE code WHEN 1 THEN '新建' WHEN 2 THEN '已支付' WHEN 3 THEN '已发货' "
            "ELSE '未知' END AS status FROM orders ORDER BY id;"
        ),
        expected="1|新建\n2|已支付\n3|已发货\n4|未知",
        pitfalls=["所有分支与 ELSE 应返回相同类型；缺失 ELSE 时无匹配返回 NULL。", "简单 CASE 不能写区间比较，区间要用搜索 CASE。"],
        exercises=[
            E("把 code 为 1 显示 'A'，其余显示 'B'，按 id 排序。",
              "CASE code WHEN 1 THEN 'A' ELSE 'B' END。",
              "SELECT id, CASE code WHEN 1 THEN 'A' ELSE 'B' END FROM orders ORDER BY id;",
              "1|A\n2|B\n3|B\n4|B"),
            E("只返回 code 为 2 的状态标签，按 id 排序。",
              "在 WHERE 中限定 code=2，并复用 CASE。",
              "SELECT CASE code WHEN 2 THEN '已支付' ELSE '其他' END FROM orders WHERE code = 2;",
              "已支付"),
        ],
    ),
    L(
        24, "case-searched", "CASE 搜索表达式与分桶", "beginner", "functions",
        concepts=["CASE", "分桶", "区间"],
        objective="用搜索 CASE 按区间把数值分桶",
        prerequisites=["掌握简单 CASE"],
        explain=(
            "搜索 CASE 的每个 WHEN 是独立布尔条件，按顺序求值，命中即停。示例把成绩按 >=90 "
            "为 A、>=80 为 B、>=60 为 C、其余为 D 分档。条件顺序很重要，必须先判高区间。"
        ),
        setup=(
            "CREATE TABLE grades (id INTEGER PRIMARY KEY, name TEXT, score INTEGER);\n"
            "INSERT INTO grades VALUES (1,'Alice',95),(2,'Bob',82),(3,'Carol',60),(4,'Dave',45);"
        ),
        query=(
            "SELECT name, score, CASE WHEN score >= 90 THEN 'A' WHEN score >= 80 THEN 'B' "
            "WHEN score >= 60 THEN 'C' ELSE 'D' END AS grade FROM grades ORDER BY id;"
        ),
        expected="Alice|95|A\nBob|82|B\nCarol|60|C\nDave|45|D",
        pitfalls=["分桶条件必须从高到低写，顺序错会误判。", "CASE 一旦命中就停止，后续条件不再求值。"],
        exercises=[
            E("返回 score 是否及格（>=60 为 'pass' 否则 'fail'），按 id 排序。",
              "CASE WHEN score>=60 THEN 'pass' ELSE 'fail' END。",
              "SELECT id, CASE WHEN score >= 60 THEN 'pass' ELSE 'fail' END FROM grades ORDER BY id;",
              "1|pass\n2|pass\n3|pass\n4|fail"),
            E("统计每个等级的人数，按等级升序。",
              "GROUP BY 分桶表达式。",
              "SELECT CASE WHEN score >= 90 THEN 'A' WHEN score >= 80 THEN 'B' WHEN score >= 60 THEN 'C' ELSE 'D' END AS g, COUNT(*) FROM grades GROUP BY g ORDER BY g;",
              "A|1\nB|1\nC|1\nD|1"),
        ],
    ),
    L(
        25, "iif", "IIF 与条件表达式", "beginner", "functions",
        concepts=["IIF", "条件"],
        objective="用 IIF 写简洁的二元条件",
        prerequisites=["掌握 CASE"],
        explain=(
            "SQLite 3.32 起提供 IIF(cond, a, b)，等价于两分支 CASE，更简短。示例用 IIF 给"
            "库存为 0 的商品标注 '缺货' 否则 '有货'。复杂多分支仍应使用 CASE。"
        ),
        setup=(
            "CREATE TABLE stock (id INTEGER PRIMARY KEY, name TEXT, qty INTEGER);\n"
            "INSERT INTO stock VALUES (1,'pen',0),(2,'book',10),(3,'bag',0);"
        ),
        query="SELECT id, name, IIF(qty = 0, '缺货', '有货') AS label FROM stock ORDER BY id;",
        expected="1|pen|缺货\n2|book|有货\n3|bag|缺货",
        pitfalls=["IIF 只有两个分支，多分支要嵌套或改 CASE。", "IIF 的条件为 NULL 时走 else 分支。"],
        exercises=[
            E("返回 qty 是否大于 0 的布尔标记（1/0），按 id 排序。",
              "IIF(qty>0,1,0)。",
              "SELECT id, IIF(qty > 0, 1, 0) FROM stock ORDER BY id;", "1|0\n2|1\n3|0"),
            E("返回缺货商品的 id，按 id 排序。", "WHERE qty = 0。",
              "SELECT id FROM stock WHERE qty = 0 ORDER BY id;", "1\n3"),
        ],
    ),
    L(
        26, "cast-round", "类型转换与 ROUND/TRUNC 取舍", "beginner", "functions",
        concepts=["CAST", "ROUND", "截断"],
        objective="区分四舍五入与截断并选择合适转换",
        prerequisites=["掌握数值函数"],
        explain=(
            "round 四舍五入，CAST(x AS INTEGER) 向零截断。示例比较同一数值的两种处理："
            "2.6 四舍五入为 3，截断为 2；-2.6 四舍五入为 -3，截断为 -2。理解差异避免对账偏差。"
        ),
        setup="CREATE TABLE vals (id INTEGER PRIMARY KEY, v REAL);\nINSERT INTO vals VALUES (1,2.6),(2,-2.6),(3,2.4);",
        query="SELECT id, v, round(v) AS r, CAST(v AS INTEGER) AS t FROM vals ORDER BY id;",
        expected="1|2.6|3.0|2\n2|-2.6|-3.0|-2\n3|2.4|2.0|2",
        pitfalls=["CAST 负数向零截断，与 floor 不同。", "round(x) 返回浮点，显示可能带 .0。"],
        exercises=[
            E("返回每行乘以 100 后转成整数，按 id 排序。", "CAST(round(v*100) AS INTEGER)。",
              "SELECT id, CAST(round(v * 100) AS INTEGER) FROM vals ORDER BY id;", "1|260\n2|-260\n3|240"),
            E("返回 v 的绝对值再四舍五入，按 id 排序。", "round(abs(v))。",
              "SELECT id, round(abs(v)) FROM vals ORDER BY id;", "1|3.0\n2|3.0\n3|2.0"),
        ],
    ),
    L(
        27, "string-split", "字符串分割与拼接技巧", "beginner", "functions",
        concepts=["instr", "substr", "group_concat"],
        objective="用 instr/substr 解析简单分隔字符串",
        prerequisites=["掌握字符串函数"],
        explain=(
            "instr(x,sub) 返回子串位置（1 起，找不到为 0）。结合 substr 可截取分隔符前后。"
            "示例把 'a:b' 形式的键值拆成键和值，用 instr 定位冒号。"
        ),
        setup=(
            "CREATE TABLE kv (id INTEGER PRIMARY KEY, pair TEXT);\n"
            "INSERT INTO kv VALUES (1,'name:alice'),(2,'city:beijing');"
        ),
        query=(
            "SELECT id, substr(pair,1,instr(pair,':')-1) AS k, "
            "substr(pair,instr(pair,':')+1) AS v FROM kv ORDER BY id;"
        ),
        expected="1|name|alice\n2|city|beijing",
        pitfalls=["找不到分隔符时 instr 返回 0，substr 会得到空串或边界异常。", "多分隔符场景应使用递归 CTE 或应用层处理。"],
        exercises=[
            E("返回 pair 中冒号后的值，按 id 排序。", "substr(pair, instr(pair,':')+1)。",
              "SELECT substr(pair, instr(pair, ':') + 1) FROM kv ORDER BY id;", "alice\nbeijing"),
            E("返回 pair 的长度，按 id 排序。", "length(pair)。",
              "SELECT id, length(pair) FROM kv ORDER BY id;", "1|10\n2|12"),
        ],
    ),
    L(
        28, "random-uuid", "随机数与唯一标识生成", "beginner", "functions",
        concepts=["random", "hex", "randomblob"],
        objective="用 random/hex/randomblob 生成随机数与伪 UUID",
        prerequisites=["掌握字符串函数"],
        explain=(
            "random() 返回 64 位随机整数，randomblob(n) 返回 n 字节随机 BLOB，hex() 转十六"
            "进制。示例用 lower(hex(randomblob(16))) 生成 32 位十六进制串作为伪 UUID。随机"
            "值每次运行不同，因此本课示例用固定长度的判断而非固定值来保证可复现。"
        ),
        setup="CREATE TABLE tokens (id INTEGER PRIMARY KEY, token TEXT);\nINSERT INTO tokens VALUES (1,'') ,(2,'');",
        query="SELECT id, length(lower(hex(randomblob(16)))) AS n FROM tokens ORDER BY id;",
        expected="1|32\n2|32",
        pitfalls=["randomblob 结果不可用于排序或等值断言。", "伪 UUID 不保证全局唯一，外键场景应使用正式 UUID。"],
        exercises=[
            E("返回一个 8 个十六进制字符的随机串的长度（单值）。",
              "length(hex(randomblob(4)))。",
              "SELECT length(hex(randomblob(4)));", "8"),
            E("返回 1 的绝对值（测试确定性，单值）。", "abs(1)。",
              "SELECT abs(1);", "1"),
        ],
    ),
    L(
        29, "glob-regexp", "GLOB 与模式匹配差异", "beginner", "functions",
        concepts=["GLOB", "通配符", "大小写"],
        objective="区分 LIKE 与 GLOB 的匹配规则",
        prerequisites=["掌握 LIKE"],
        explain=(
            "GLOB 使用 Unix 风格通配：* 匹配任意长度，? 匹配单字符，[] 字符类，且大小写敏感。"
            "LIKE 使用 %/_ 且 ASCII 下不区分大小写。示例用 GLOB 'A*' 精确匹配大写 A 开头。"
        ),
        setup="CREATE TABLE words (id INTEGER PRIMARY KEY, w TEXT);\nINSERT INTO words VALUES (1,'Apple'),(2,'apple'),(3,'Apricot'),(4,'banana');",
        query="SELECT id, w FROM words WHERE w GLOB 'A*' ORDER BY id;",
        expected="1|Apple\n3|Apricot",
        pitfalls=["GLOB 区分大小写，而 LIKE 默认不区分（ASCII）。", "字符类 [a-z] 在 GLOB 中有效，_ 是 LIKE 的概念。"],
        exercises=[
            E("用 GLOB 返回小写 a 开头的词 id，按 id 排序。", "w GLOB 'a*'。",
              "SELECT id FROM words WHERE w GLOB 'a*' ORDER BY id;", "2"),
            E("用 GLOB 返回第二个字母为小写 a 的词 id，按 id 排序。", "'?a*'。",
              "SELECT id FROM words WHERE w GLOB '?a*' ORDER BY id;", "4"),
        ],
    ),
    L(
        30, "functions-capstone", "综合练习：表达式与函数", "beginner", "functions",
        concepts=["CASE", "COALESCE", "字符串", "函数组合"],
        objective="组合函数完成一个清洗与分类查询",
        prerequisites=["掌握本 track"],
        explain=(
            "真实数据处理常把 trim、upper、COALESCE、CASE 组合使用。本课把混合大小写与空白"
            "的客户名规范化，把文本金额转成整数（空串被 CAST 成 0），并据此分高/低两档。示例"
            "按 id 升序输出，以保持结果可复现。"
        ),
        setup=(
            "CREATE TABLE raw_orders (id INTEGER PRIMARY KEY, customer TEXT, amount TEXT);\n"
            "INSERT INTO raw_orders VALUES (1,' alice ', '100'),(2,'BOB',''),(3,'Carol','250');"
        ),
        query=(
            "SELECT id, upper(trim(customer)) AS c, COALESCE(CAST(amount AS INTEGER),0) AS a, "
            "CASE WHEN COALESCE(CAST(amount AS INTEGER),0) >= 200 THEN '高' ELSE '低' END AS tier "
            "FROM raw_orders ORDER BY id;"
        ),
        expected="1|ALICE|100|低\n2|BOB|0|低\n3|CAROL|250|高",
        pitfalls=["CAST 空串为 0 而非 NULL，需要先用 NULLIF 区分。", "函数嵌套层次多时注意每层返回类型。"],
        exercises=[
            E("返回规范化后客户名长度大于 4 的 id，按 id 排序。",
              "length(trim(customer)) > 4。",
              "SELECT id FROM raw_orders WHERE length(trim(customer)) > 4 ORDER BY id;", "1\n3"),
            E("返回金额为空字符串的订单 id，按 id 排序。", "amount = ''。",
              "SELECT id FROM raw_orders WHERE amount = '' ORDER BY id;", "2"),
        ],
    ),
]
