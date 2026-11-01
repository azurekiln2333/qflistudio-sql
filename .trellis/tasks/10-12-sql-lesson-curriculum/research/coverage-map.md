# SQL Curriculum Coverage Map

Parent: `.trellis/tasks/10-12-sql-curriculum-and-home` · Child: C2

Target: **120 lessons** (floor 110). One tutorial entry = one lesson = one
chapter (matches `LocalContentAdapter`). Each lesson has a matching example.

Dialect policy: default engine **SQLite 3.50.6** (validated by the `sqlite3` CLI
at `D:\ProgramFiles\platform-tools\sqlite3.exe`). MySQL-specific lessons set
`inputFixtures.engine = "mysql"` with a version label and are listed separately
as "not executed" in the validation report.

Levels: `beginner` (1–~60), `intermediate` (~61–105), `advanced` (~106–120).

## Track 1 — Basics and single-table queries (14)

| # | id | Title | Concepts |
| --- | --- | --- | --- |
| 1 | sql-tutorial-001 | SELECT 基础与列选择 | SELECT, 列, 别名 |
| 2 | sql-tutorial-002 | WHERE 行过滤入门 | WHERE, 比较运算符 |
| 3 | sql-tutorial-003 | 逻辑运算符与优先级 | AND/OR/NOT, 括号 |
| 4 | sql-tutorial-004 | BETWEEN 与 IN 区间判断 | BETWEEN, IN |
| 5 | sql-tutorial-005 | LIKE 模式匹配 | LIKE, %, _ |
| 6 | sql-tutorial-006 | ORDER BY 排序与多列排序 | ORDER BY, ASC/DESC |
| 7 | sql-tutorial-007 | LIMIT 与 OFFSET 分页 | LIMIT, OFFSET |
| 8 | sql-tutorial-008 | DISTINCT 去重 | DISTINCT |
| 9 | sql-tutorial-009 | 表达式与计算列 | 算术表达式, 优先级 |
| 10 | sql-tutorial-010 | 类型与隐式转换 | 类型亲和, CAST |
| 11 | sql-tutorial-011 | 表别名与列限定名 | 别名, 限定名 |
| 12 | sql-tutorial-012 | SELECT 结果集与列顺序 | 投影, 稳定性 |
| 13 | sql-tutorial-013 | 排序中的 NULL 位置 | NULLS FIRST/LAST |
| 14 | sql-tutorial-014 | 综合练习：单表查询 | 组合过滤排序 |

## Track 2 — Expressions, functions, NULL, CASE (16)

| # | id | Title |
| --- | --- | --- |
| 15 | sql-tutorial-015 | 字符串函数（上）：长度与截取 |
| 16 | sql-tutorial-016 | 字符串函数（下）：拼接、替换、大小写 |
| 17 | sql-tutorial-017 | 数值函数与舍入 |
| 18 | sql-tutorial-018 | 日期时间函数入门 |
| 19 | sql-tutorial-019 | 日期时间运算与格式化 |
| 20 | sql-tutorial-020 | NULL 语义与三值逻辑 |
| 21 | sql-tutorial-021 | COALESCE 与 IFNULL |
| 22 | sql-tutorial-022 | NULLIF 与空字符串处理 |
| 23 | sql-tutorial-023 | CASE 简单表达式 |
| 24 | sql-tutorial-024 | CASE 搜索表达式与分桶 |
| 25 | sql-tutorial-025 | IIF 与条件表达式 |
| 26 | sql-tutorial-026 | 类型转换与 ROUND/TRUNC |
| 27 | sql-tutorial-027 | 字符串分割与拼接技巧 |
| 28 | sql-tutorial-028 | 随机数与 UUID 生成 |
| 29 | sql-tutorial-029 | 正则风格匹配（GLOB/REGEXP 差异） |
| 30 | sql-tutorial-030 | 综合练习：表达式与函数 |

## Track 3 — Aggregation (10)

| # | id | Title |
| --- | --- | --- |
| 31 | sql-tutorial-031 | COUNT 的三种写法与差异 |
| 32 | sql-tutorial-032 | SUM/AVG/MIN/MAX |
| 33 | sql-tutorial-033 | GROUP BY 分组基础 |
| 34 | sql-tutorial-034 | HAVING 过滤分组 |
| 35 | sql-tutorial-035 | GROUP BY 多列与聚合顺序 |
| 36 | sql-tutorial-036 | 聚合与 NULL 的交互 |
| 37 | sql-tutorial-037 | GROUP_CONCAT 分组拼接 |
| 38 | sql-tutorial-038 | 总计与小计（GROUPING SETS 方言） |
| 39 | sql-tutorial-039 | 聚合结果排序与分页 |
| 40 | sql-tutorial-040 | 综合练习：销售汇总 |

## Track 4 — Joins (12)

| # | id | Title |
| --- | --- | --- |
| 41 | sql-tutorial-041 | 笛卡尔积与 CROSS JOIN |
| 42 | sql-tutorial-042 | INNER JOIN 基础 |
| 43 | sql-tutorial-043 | 多表连接与连接顺序 |
| 44 | sql-tutorial-044 | LEFT JOIN 与缺失行 |
| 45 | sql-tutorial-045 | LEFT JOIN + IS NULL 反连接 |
| 46 | sql-tutorial-046 | RIGHT JOIN |
| 47 | sql-tutorial-047 | FULL OUTER JOIN（方言差异） |
| 48 | sql-tutorial-048 | 自连接 |
| 49 | sql-tutorial-049 | 非等值连接与区间连接 |
| 50 | sql-tutorial-050 | USING 与 ON 的差异 |
| 51 | sql-tutorial-051 | 连接与聚合的配合 |
| 52 | sql-tutorial-052 | 综合练习：多表报表 |

## Track 5 — Subqueries (10)

| # | id | Title |
| --- | --- | --- |
| 53 | sql-tutorial-053 | 标量子查询 |
| 54 | sql-tutorial-054 | IN 子查询 |
| 55 | sql-tutorial-055 | NOT IN 与 NULL 陷阱 |
| 56 | sql-tutorial-056 | EXISTS 与 NOT EXISTS |
| 57 | sql-tutorial-057 | 相关子查询 |
| 58 | sql-tutorial-058 | 派生表（FROM 子查询） |
| 59 | sql-tutorial-059 | 子查询改写为 JOIN |
| 60 | sql-tutorial-060 | 比较子查询与 ANY/ALL |
| 61 | sql-tutorial-061 | 子查询中的聚合 |
| 62 | sql-tutorial-062 | 综合练习：子查询求解 |

## Track 6 — CTE and recursive CTE (8)

| # | id | Title |
| --- | --- | --- |
| 63 | sql-tutorial-063 | WITH 基础 CTE |
| 64 | sql-tutorial-064 | 多个 CTE 与链式组合 |
| 65 | sql-tutorial-065 | CTE 与子查询的取舍 |
| 66 | sql-tutorial-066 | 递归 CTE 基础 |
| 67 | sql-tutorial-067 | 递归 CTE：层级结构 |
| 68 | sql-tutorial-068 | 递归 CTE：数字序列与日期序列 |
| 69 | sql-tutorial-069 | 递归 CTE 防环与终止条件 |
| 70 | sql-tutorial-070 | 综合练习：组织层级与路径 |

## Track 7 — Window functions (12)

| # | id | Title |
| --- | --- | --- |
| 71 | sql-tutorial-071 | 窗口函数概念与 OVER |
| 72 | sql-tutorial-072 | PARTITION BY 分组窗口 |
| 73 | sql-tutorial-073 | ORDER BY 与 ROWS/RANGE 帧 |
| 74 | sql-tutorial-074 | ROW_NUMBER |
| 75 | sql-tutorial-075 | RANK 与 DENSE_RANK |
| 76 | sql-tutorial-076 | NTILE 分桶 |
| 77 | sql-tutorial-077 | LAG/LEAD 前后行 |
| 78 | sql-tutorial-078 | FIRST_VALUE/LAST_VALUE |
| 79 | sql-tutorial-079 | 累计和与移动平均 |
| 80 | sql-tutorial-080 | 同比环比（自连接 vs 窗口） |
| 81 | sql-tutorial-081 | 去重与每组 Top-N |
| 82 | sql-tutorial-082 | 综合练习：窗口分析报表 |

## Track 8 — DDL and constraints (12)

| # | id | Title |
| --- | --- | --- |
| 83 | sql-tutorial-083 | CREATE TABLE 与列类型 |
| 84 | sql-tutorial-084 | PRIMARY KEY 与自增 |
| 85 | sql-tutorial-085 | NOT NULL 与 DEFAULT |
| 86 | sql-tutorial-086 | UNIQUE 约束 |
| 87 | sql-tutorial-087 | CHECK 约束 |
| 88 | sql-tutorial-088 | FOREIGN KEY 与外键动作 |
| 89 | sql-tutorial-089 | 生成列（GENERATED） |
| 90 | sql-tutorial-090 | ALTER TABLE 加列改列 |
| 91 | sql-tutorial-091 | DROP TABLE 与 IF EXISTS |
| 92 | sql-tutorial-092 | 临时表与内存表 |
| 93 | sql-tutorial-093 | 约束冲突与错误处理 |
| 94 | sql-tutorial-094 | 综合练习：设计规范表结构 |

## Track 9 — DML and upsert (8)

| # | id | Title |
| --- | --- | --- |
| 95 | sql-tutorial-095 | INSERT 多行插入 |
| 96 | sql-tutorial-096 | INSERT ... SELECT |
| 97 | sql-tutorial-097 | UPDATE 基础与 WHERE 安全 |
| 98 | sql-tutorial-098 | UPDATE 关联更新 |
| 99 | sql-tutorial-099 | DELETE 与条件删除 |
| 100 | sql-tutorial-100 | UPSERT：INSERT OR REPLACE |
| 101 | sql-tutorial-101 | UPSERT：ON CONFLICT DO UPDATE |
| 102 | sql-tutorial-102 | 综合练习：数据导入与幂等写入 |

## Track 10 — Transactions (6)

| # | id | Title |
| --- | --- | --- |
| 103 | sql-tutorial-103 | BEGIN/COMMIT/ROLLBACK |
| 104 | sql-tutorial-104 | SAVEPOINT 部分回滚 |
| 105 | sql-tutorial-105 | 事务中的错误与原子性 |
| 106 | sql-tutorial-106 | 隔离级别概念 |
| 107 | sql-tutorial-107 | 并发写与锁（概念 + SQLite 行为） |
| 108 | sql-tutorial-108 | 综合练习：转账原子操作 |

## Track 11 — Indexes and execution plans (8)

| # | id | Title |
| --- | --- | --- |
| 109 | sql-tutorial-109 | 索引原理与 B-Tree |
| 110 | sql-tutorial-110 | 单列索引与查询加速 |
| 111 | sql-tutorial-111 | 复合索引与最左前缀 |
| 112 | sql-tutorial-112 | 覆盖索引 |
| 113 | sql-tutorial-113 | 唯一索引与主键索引 |
| 114 | sql-tutorial-114 | 索引失效场景 |
| 115 | sql-tutorial-115 | EXPLAIN / EXPLAIN QUERY PLAN |
| 116 | sql-tutorial-116 | 综合练习：慢查询优化 |

## Track 12 — Modeling, normalization, dialects, capstone (4)

| # | id | Title |
| --- | --- | --- |
| 117 | sql-tutorial-117 | 数据建模与范式 |
| 118 | sql-tutorial-118 | SQLite 与 MySQL 方言差异（版本标注） |
| 119 | sql-tutorial-119 | 视图与查询封装 |
| 120 | sql-tutorial-120 | 综合实战：多表分析报表 |

## Category → Lesson Coverage Checklist

- [x] SELECT/WHERE/ORDER/LIMIT/DISTINCT → 001–014
- [x] Operators, string/date/numeric functions, NULL, CASE → 009–030
- [x] Aggregation (COUNT/SUM/AVG/GROUP BY/HAVING) → 031–040
- [x] Joins (INNER/LEFT/RIGHT/FULL/CROSS/self) → 041–052
- [x] Subqueries (scalar/IN/EXISTS/correlated/derived) → 053–062
- [x] CTE / recursive CTE → 063–070
- [x] Window functions → 071–082
- [x] DDL / constraints → 083–094
- [x] DML / upsert → 095–102
- [x] Transactions / isolation / savepoints → 103–108
- [x] Indexes / EXPLAIN → 109–116
- [x] Modeling / normalization / dialects → 117–118
- [x] Views → 119
- [x] Capstone scenarios → 120 (plus per-track 综合练习)

## MySQL-only (not executed) candidates

To be finalized during authoring; expected to include explicit MySQL 8.0
variants of: `ON DUPLICATE KEY UPDATE`, `GROUP_CONCAT ... SEPARATOR`,
`FULL OUTER JOIN` emulation, `GROUPING SETS`/ROLLUP, isolation-level statements,
and `REGEXP`. Each is labeled `inputFixtures.engine = "mysql"` with version and
listed as "not executed" in the validation report.
