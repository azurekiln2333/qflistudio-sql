"""Inventory balances, availability, allocation and separately scoped lot costing."""
from _draft_helpers import topic

S = """
CREATE TABLE product(sku TEXT PRIMARY KEY,unit_cost INTEGER,min_stock INTEGER);
INSERT INTO product VALUES('A',100,6),('B',200,2),('C',300,1);
CREATE TABLE movement(id INTEGER PRIMARY KEY,sku TEXT,warehouse TEXT,qty INTEGER,d TEXT);
INSERT INTO movement VALUES(1,'A','N',10,'2026-01-01'),(2,'A','N',-3,'2026-01-02'),
 (3,'A','S',4,'2026-01-01'),(4,'B','N',5,'2026-01-01'),
 (5,'A','N',-2,'2026-01-03'),(6,'B','N',-6,'2026-01-02'),(7,'A','S',-1,'2026-01-03');
CREATE TABLE reservation(sku TEXT,warehouse TEXT,qty INTEGER,PRIMARY KEY(sku,warehouse));
INSERT INTO reservation VALUES('A','N',2),('A','S',1),('B','N',0);
CREATE TABLE demand(id INTEGER PRIMARY KEY,sku TEXT,qty INTEGER);
INSERT INTO demand VALUES(1,'A',6),(2,'A',4),(3,'B',2);
CREATE TABLE physical(sku TEXT,warehouse TEXT,qty INTEGER,PRIMARY KEY(sku,warehouse));
INSERT INTO physical VALUES('A','N',4),('A','S',3),('B','N',0);
CREATE TABLE lot(id INTEGER PRIMARY KEY,sku TEXT,qty INTEGER,cost INTEGER,received TEXT,expires TEXT);
INSERT INTO lot VALUES(1,'A',5,90,'2026-01-01','2026-02-01'),(2,'A',5,110,'2026-01-02','2026-03-01'),(3,'B',2,200,'2026-01-01','2026-01-15');
"""
def T(n,slug,title,concepts,explain,q,out,p,a,b):
    return topic(n,slug,title,"inventory",concepts,explain,S,q,out,p,a,b)

LESSONS = [
 T(187,"inventory-on-hand","库存流水按商品仓库归集",["流水账","双重粒度","库存"],
   "入库为正、出库为负，对商品与仓库同时分组。A 在 N 仓为 10-3-2=5，在 S 仓为 4-1=3；B 在 N 仓为 -1，必须保留异常而不是补成零。单按商品分组会丢掉仓库位置。",
   "SELECT sku,warehouse,sum(qty) FROM movement GROUP BY sku,warehouse ORDER BY sku,warehouse;","A|N|5\nA|S|3\nB|N|-1",
   ["流水数量必须有统一正负约定。","负库存是异常信息，不能在基础账中悄悄裁零。"],
   ("按商品统计跨仓现存量。","仅按 sku 分组。","SELECT sku,sum(qty) FROM movement GROUP BY sku ORDER BY sku;","A|8\nB|-1"),
   ("按仓库统计所有商品的件数。","仅统计同一计量单位的示例件数。","SELECT warehouse,sum(qty) FROM movement GROUP BY warehouse ORDER BY warehouse;","N|4\nS|3")),
 T(188,"inventory-available","可用库存扣减预留但保留现存量",["预留","可用量","预聚合"],
   "先把流水归为一商品一仓，再连接预留，现存减预留得到 A/N=3、A/S=2、B/N=-1。预留不是实际出库，不应再次写成负流水。本报表同时显示现存和可用，避免重复扣减。",
   "WITH s AS(SELECT sku,warehouse,sum(qty) onhand FROM movement GROUP BY sku,warehouse) SELECT s.sku,s.warehouse,onhand,onhand-coalesce(r.qty,0) available FROM s LEFT JOIN reservation r USING(sku,warehouse) ORDER BY s.sku,s.warehouse;","A|N|5|3\nA|S|3|2\nB|N|-1|-1",
   ["连接预留前不聚合，会按每条流水重复扣预留。","可用负数应显示，承诺出货时可另做非负裁剪。"],
   ("统计 A 的跨仓总预留。","对 reservation 求和。","SELECT sum(qty) FROM reservation WHERE sku='A';","3"),
   ("计算 A 跨仓可承诺件数。","现存合计减预留合计。","SELECT (SELECT sum(qty) FROM movement WHERE sku='A')-(SELECT sum(qty) FROM reservation WHERE sku='A');","5")),
 T(189,"inventory-first-negative","找出库存首次跌破零的流水",["累计窗口","首次违规","库存审计"],
   "按商品仓库与流水 id 累计数量，在外层筛选首次负值。B 的入库 5 后出库 6，流水 6 使余额降为 -1；A 的各仓始终非负。只看最终负数不能定位到底哪笔造成缺货。",
   "WITH r AS(SELECT id,sku,warehouse,sum(qty) OVER(PARTITION BY sku,warehouse ORDER BY id ROWS UNBOUNDED PRECEDING) balance FROM movement) SELECT sku,warehouse,min(id) FROM r WHERE balance<0 GROUP BY sku,warehouse ORDER BY sku,warehouse;","B|N|6",
   ["窗口排序必须代表业务生效顺序。","过滤负流水后再开窗会丢掉入库。"],
   ("返回 B 每笔流水后的余额。","先全量开窗，再筛选 B。","SELECT id,sum(qty) OVER(ORDER BY id ROWS UNBOUNDED PRECEDING) FROM movement WHERE sku='B' ORDER BY id;","4|5\n6|-1"),
   ("返回 A/N 的最低历史余额。","累计后外层取 MIN。","WITH r AS(SELECT sum(qty) OVER(ORDER BY id ROWS UNBOUNDED PRECEDING) b FROM movement WHERE sku='A' AND warehouse='N') SELECT min(b) FROM r;","5")),
 T(190,"inventory-replenishment","包含零流水商品的补货缺口",["安全库存","LEFT JOIN","补货"],
   "以完整商品目录为主表，现存量低于 min_stock 才列入补货。A 总库存 8 不缺，B 为 -1 相对目标 2 缺 3，C 从无流水相对目标 1 缺 1。基础报表保留负库存，所以缺口会反映已欠数量。",
   "WITH s AS(SELECT sku,sum(qty) q FROM movement GROUP BY sku) SELECT p.sku,p.min_stock-coalesce(s.q,0) shortage FROM product p LEFT JOIN s USING(sku) WHERE coalesce(s.q,0)<p.min_stock ORDER BY p.sku;","B|3\nC|1",
   ["从流水开始查询会漏掉从未入库的商品。","安全库存与采购起订量是不同规则。"],
   ("列出完全没有流水的商品。","NOT EXISTS 检查流水表。","SELECT sku FROM product p WHERE NOT EXISTS(SELECT 1 FROM movement m WHERE m.sku=p.sku) ORDER BY sku;","C"),
   ("计算补到安全库存需要的总件数。","每商品缺口裁到非负后相加。","WITH s AS(SELECT sku,sum(qty) q FROM movement GROUP BY sku) SELECT sum(max(p.min_stock-coalesce(s.q,0),0)) FROM product p LEFT JOIN s USING(sku);","4")),
 T(191,"inventory-snapshot","按截止日重建历史库存快照",["时点库存","截至日","条件聚合"],
   "重建一月二日结束时的库存，只累加 d<一月三日的流水。A/N 为 7、A/S 为 4、B/N 为 -1；不能直接查询当前余额再假装是历史快照。回溯修正若允许更改旧日期，还需审计版本。",
   "SELECT sku,warehouse,sum(qty) FROM movement WHERE d<'2026-01-03' GROUP BY sku,warehouse ORDER BY sku,warehouse;","A|N|7\nA|S|4\nB|N|-1",
   ["截止时间要与流水生效时间使用相同约定。","晚到记录可能改变历史重算结果。"],
   ("重建一月一日的跨仓商品库存。","上界为一月二日。","SELECT sku,sum(qty) FROM movement WHERE d<'2026-01-02' GROUP BY sku ORDER BY sku;","A|14\nB|5"),
   ("计算一月三日的库存净变化。","按当天流水求和。","SELECT sku,sum(qty) FROM movement WHERE d='2026-01-03' GROUP BY sku ORDER BY sku;","A|-3")),
 T(192,"inventory-value","库存数量与估值异常分别展示",["库存估值","成本","负值审计"],
   "按商品合计现存数量再乘目录成本，A 为 8×100=800，B 为 -1×200=-200，C 为 0。负估值暴露账务问题，本例不是完整会计成本法；目录成本估值与批次 FIFO 估值应分开。",
   "WITH s AS(SELECT sku,sum(qty) q FROM movement GROUP BY sku) SELECT p.sku,coalesce(q,0),coalesce(q,0)*p.unit_cost FROM product p LEFT JOIN s USING(sku) ORDER BY p.sku;","A|8|800\nB|-1|-200\nC|0|0",
   ["目录成本不等同于实际批次成本。","金额应使用最小货币单位整数，避免浮点累计误差。"],
   ("求目录成本口径下的库存净估值。","按商品库存乘单价再 SUM。","WITH s AS(SELECT sku,sum(qty) q FROM movement GROUP BY sku) SELECT sum(q*unit_cost) FROM s JOIN product USING(sku);","600"),
   ("仅列出负库存估值的商品。","不要把负数自动裁掉。","SELECT m.sku,sum(m.qty)*p.unit_cost FROM movement m JOIN product p USING(sku) GROUP BY m.sku HAVING sum(m.qty)<0 ORDER BY m.sku;","B|-200")),
 T(193,"inventory-order-allocation","按订单顺序分配有限库存",["累计需求","分配","缺货"],
   "A 跨仓正向可用现存为 8，订单 1 先取 6，订单 2 只能取剩余 2；B 现存为负，承诺分配裁为 0。累计前序需求决定本单可分配量，本例仅模拟顺序分配，不持久化锁定库存。",
   "WITH s AS(SELECT sku,max(sum(qty),0) stock FROM movement GROUP BY sku),r AS(SELECT d.*,coalesce(sum(qty) OVER(PARTITION BY sku ORDER BY id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) prior FROM demand d) SELECT r.id,r.sku,min(r.qty,max(coalesce(s.stock,0)-prior,0)) allocated FROM r LEFT JOIN s USING(sku) ORDER BY r.id;","1|A|6\n2|A|2\n3|B|0",
   ["SELECT 分配模拟不能替代并发下的事务锁定。","先过滤部分订单会改变前序需求。"],
   ("计算每种商品总需求。","按 sku 聚合 demand。","SELECT sku,sum(qty) FROM demand GROUP BY sku ORDER BY sku;","A|10\nB|2"),
   ("求每个商品不考虑优先级的总缺口。","需求减非负现存并裁零。","WITH d AS(SELECT sku,sum(qty) q FROM demand GROUP BY sku),s AS(SELECT sku,max(sum(qty),0) q FROM movement GROUP BY sku) SELECT d.sku,max(d.q-coalesce(s.q,0),0) FROM d LEFT JOIN s USING(sku) ORDER BY d.sku;","A|2\nB|2")),
 T(194,"inventory-cycle-count","盘点实数与账面数差异",["盘点","差异","双向核对"],
   "把流水聚合成商品仓库账面数，再与 physical 实盘表比较。A/N 实盘 4 比账面 5 少 1，B/N 实盘 0 比账面 -1 多 1；A/S 相符不输出。差异报告不直接写调整流水，须经审批。",
   "WITH s AS(SELECT sku,warehouse,sum(qty) q FROM movement GROUP BY sku,warehouse) SELECT p.sku,p.warehouse,p.qty-s.q diff FROM physical p JOIN s USING(sku,warehouse) WHERE p.qty<>s.q ORDER BY p.sku,p.warehouse;","A|N|-1\nB|N|1",
   ["内连接仅覆盖两边都有的键，完整盘点需另查单边缺失。","净差为零不代表每个仓库都相符。"],
   ("计算所有盘点差异的净件数。","正负差相加。","WITH s AS(SELECT sku,warehouse,sum(qty) q FROM movement GROUP BY sku,warehouse) SELECT sum(p.qty-s.q) FROM physical p JOIN s USING(sku,warehouse);","0"),
   ("计算差异绝对值合计。","ABS 后相加防止抵消。","WITH s AS(SELECT sku,warehouse,sum(qty) q FROM movement GROUP BY sku,warehouse) SELECT sum(abs(p.qty-s.q)) FROM physical p JOIN s USING(sku,warehouse);","2")),
 T(195,"inventory-fifo-lots","独立批次账按 FIFO 计算余量",["FIFO","批次","累计收货"],
   "本课 lot 是独立批次练习，不与 movement 混算。A 两批各 5，累计消耗 7 时先耗尽第一批，第二批剩 3；前序累计量决定本批被消耗多少。B 未发生批次消耗，仍余 2。",
   "WITH r AS(SELECT *,coalesce(sum(qty) OVER(PARTITION BY sku ORDER BY received,id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) prior FROM lot),used(sku,q) AS(VALUES('A',7),('B',0)) SELECT id,sku,qty-min(qty,max(used.q-prior,0)) remaining FROM r JOIN used USING(sku) ORDER BY id;","1|A|0\n2|A|3\n3|B|2",
   ["批次排序要有稳定 id 打破相同收货日期。","此模型假设消耗量不为负且无退货重分配。"],
   ("计算 A 剩余 FIFO 库存金额。","余下 3 件来自成本 110 的第二批。","WITH r AS(SELECT *,coalesce(sum(qty) OVER(ORDER BY received,id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) prior FROM lot WHERE sku='A') SELECT sum((qty-min(qty,max(7-prior,0)))*cost) FROM r;","330"),
   ("计算 A 已消耗的 FIFO 成本。","第一批消耗 5，第二批消耗 2。","WITH r AS(SELECT *,coalesce(sum(qty) OVER(ORDER BY received,id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING),0) prior FROM lot WHERE sku='A') SELECT sum(min(qty,max(7-prior,0))*cost) FROM r;","670")),
 T(196,"lot-expiry-exposure","固定日期评估过期批次风险",["有效期","批次风险","固定日期"],
   "以 2026-01-20 为审计日，expires 严格小于审计日的 B 批次已过期，数量 2、原始成本 400。这里只检查 lot 原始批次量，不代表结合消耗后的真实在手风险；与 FIFO 剩余量结合时必须先明确账本口径。",
   "SELECT id,sku,qty,qty*cost FROM lot WHERE expires<'2026-01-20' ORDER BY id;","3|B|2|400",
   ["过期日当天能否销售需要业务明确。","原始入库量不能自动当作当前余量。"],
   ("找出一月二十日起未来十五天内到期的批次。","半开期限从当天到加十五天。","SELECT id FROM lot WHERE expires>='2026-01-20' AND expires<date('2026-01-20','+15 days') ORDER BY id;","1"),
   ("输出每个商品最早到期日。","按 sku 取 MIN。","SELECT sku,min(expires) FROM lot GROUP BY sku ORDER BY sku;","A|2026-02-01\nB|2026-01-15")),
 T(197,"inventory-last-activity","按商品区分最近入库与最近出库",["FILTER","最后活动","滞销分析"],
   "最近任何活动无法区分补货和消耗，因此分别取正、负流水日期的 MAX。A 最近入库一日、出库三日，B 入库一日、出库二日；C 从无活动，保留 NULL。不能把缺失日期补为今天。",
   "SELECT p.sku,max(m.d) FILTER(WHERE m.qty>0),max(m.d) FILTER(WHERE m.qty<0) FROM product p LEFT JOIN movement m USING(sku) GROUP BY p.sku ORDER BY p.sku;","A|2026-01-01|2026-01-03\nB|2026-01-01|2026-01-02\nC||",
   ["最近活动不是最近销售，调拨也可能是出库。","无记录的 NULL 不应伪装成有效时间。"],
   ("统计每种商品的出库总件数，缺失补零。","负流水取负后汇总。","SELECT p.sku,coalesce(-sum(m.qty) FILTER(WHERE m.qty<0),0) FROM product p LEFT JOIN movement m USING(sku) GROUP BY p.sku ORDER BY p.sku;","A|6\nB|6\nC|0"),
   ("找出一月三日没有出库的商品。","NOT EXISTS 包括从无活动的 C。","SELECT p.sku FROM product p WHERE NOT EXISTS(SELECT 1 FROM movement m WHERE m.sku=p.sku AND m.qty<0 AND m.d='2026-01-03') ORDER BY p.sku;","B\nC")),
 T(198,"inventory-transfer-balance","调拨两端数量守恒审计",["调拨","守恒","分组约束"],
   "调拨记录按 transfer_id 合计应为零，且应有两端。示例 T1 出 3 入 3 正常，T2 出 2 入 1 失衡为 -1。按商品或日期合计会让不同调拨相互抵消，必须使用调拨业务键。",
   "WITH transfer(t,warehouse,q) AS(VALUES('T1','N',-3),('T1','S',3),('T2','N',-2),('T2','S',1)) SELECT t,count(*),sum(q) FROM transfer GROUP BY t HAVING count(*)<>2 OR sum(q)<>0 ORDER BY t;","T2|2|-1",
   ["数量守恒还不足以验证商品、批次和仓库正确。","跨日期在途业务需单独状态而非直接判错。"],
   ("列出数量平衡的调拨号。","按调拨求和为零。","WITH transfer(t,q) AS(VALUES('T1',-3),('T1',3),('T2',-2),('T2',1)) SELECT t FROM transfer GROUP BY t HAVING sum(q)=0 ORDER BY t;","T1"),
   ("分别统计调拨出入总量。","对正负数使用条件聚合。","WITH transfer(q) AS(VALUES(-3),(3),(-2),(1)) SELECT -sum(q) FILTER(WHERE q<0),sum(q) FILTER(WHERE q>0) FROM transfer;","5|4")),
 T(199,"inventory-count-coverage","检查盘点是否覆盖所有账面位置",["集合差","盘点覆盖","业务键"],
   "完整盘点应覆盖每个存在流水的商品仓库键。示例 physical 覆盖了三个位置，所以缺失清单为空，用明确的空结果预期表达这一点。检查键覆盖与检查数量差异应分别执行，不能因为没有缺失就宣称账实相符。",
   "SELECT DISTINCT sku,warehouse FROM movement EXCEPT SELECT sku,warehouse FROM physical ORDER BY sku,warehouse;","(no rows)",
   ["空缺失清单不等于数量全部一致。","EXCEPT 去重，适合比较位置键而非重复流水。"],
   ("统计应盘点的不同位置数。","先按复合键去重再计数。","SELECT count(*) FROM(SELECT DISTINCT sku,warehouse FROM movement);","3"),
   ("统计实盘表中数量不为负的位置数。","检查 physical 自身。","SELECT count(*) FROM physical WHERE qty>=0;","3")),
 T(200,"inventory-demand-cover","用订单需求评估库存覆盖率",["需求覆盖","分母","缺货报告"],
   "A 需求 10、非负现存 8，覆盖率 80%；B 需求 2、非负现存 0，覆盖率 0%。覆盖率先按商品聚合再相除，不能平均每条订单的覆盖率；是否扣预留应与口径一起展示。",
   "WITH d AS(SELECT sku,sum(qty) q FROM demand GROUP BY sku),s AS(SELECT sku,max(sum(qty),0) q FROM movement GROUP BY sku) SELECT d.sku,d.q,coalesce(s.q,0),round(100.0*min(coalesce(s.q,0),d.q)/d.q,1) FROM d LEFT JOIN s USING(sku) ORDER BY d.sku;","A|10|8|80.0\nB|2|0|0.0",
   ["需求为零时应通过 NULLIF 或单独分支避免除零。","覆盖率不同商品直接平均可能失去业务意义。"],
   ("统计需求商品种类数。","COUNT DISTINCT SKU。","SELECT count(DISTINCT sku) FROM demand;","2"),
   ("计算全量需求件数。","SUM 订单数量。","SELECT sum(qty) FROM demand;","12")),
 T(201,"inventory-positive-capacity","区分净库存与正仓可调拨量",["仓库能力","负数","汇总顺序"],
   "每仓先求余额再对正余额求和，代表可从正常仓调出的量；直接跨仓净额则会让负仓抵消。A 正仓合计 8，B 没有正仓为 0，C 无流水为 0。两个口径回答不同问题，不能互相替代。",
   "WITH w AS(SELECT sku,warehouse,sum(qty) q FROM movement GROUP BY sku,warehouse),s AS(SELECT sku,sum(max(q,0)) q FROM w GROUP BY sku) SELECT p.sku,coalesce(s.q,0) FROM product p LEFT JOIN s USING(sku) ORDER BY p.sku;","A|8\nB|0\nC|0",
   ["先裁每条流水的负数会丢掉所有出库。","跨仓调拨还受运输、预留和商品状态约束。"],
   ("错误地只加正流水会得到多少 A 入库量。","这是毛入库量，用于与库存区分。","SELECT sum(qty) FROM movement WHERE sku='A' AND qty>0;","14"),
   ("返回存在正库存的商品仓库。","先聚合，再 HAVING。","SELECT sku,warehouse FROM movement GROUP BY sku,warehouse HAVING sum(qty)>0 ORDER BY sku,warehouse;","A|N\nA|S")),
]
