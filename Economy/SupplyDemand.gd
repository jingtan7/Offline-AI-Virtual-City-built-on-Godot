class_name SupplyDemand
extends RefCounted
## 供需驱动自治物价算法（阶段三）
## 摒弃硬编码固定物价：完全基于城邦内所有主体的产出、消耗、囤货、交易行为，
## 实时统计供需差值、成交量、市场热度与存量水平，动态迭代实时价格：
##   - 供需差值    → 短缺涨价 / 过剩降价
##   - 存量水平    → 短缺溢价 / 产能过剩折价
##   - 成交量放大  → 囤货拉升、抛售崩盘由此涌现
##   - 均值回归    → 供求平衡时向基准价收敛（横盘震荡）

const EPS := 0.0001


## 计算单 tick 价格变化比例。返回比例（如 0.03 = +3%），已夹在单日波动限制内。
## demand: 本 tick 需求；supply: 本 tick 供给；volume: 本 tick 成交量；
## stock_ratio: 总存量 / 基准存量；current_price: 当前实时价。
static func price_delta(
	commodity: Commodity,
	demand: float,
	supply: float,
	volume: float,
	stock_ratio: float,
	current_price: float,
	heat_bonus: float = 0.0,
	volume_mult: float = 1.0,
	price_limit_mult: float = 1.0
) -> float:
	var total := demand + supply + EPS
	var gap_ratio := (demand - supply) / total          # 正=供不应求
	var volatility := commodity.scarcity_volatility
	var heat := clampf(commodity.heat_factor + heat_bonus, 0.0, 1.5)
	var limit := maxf(0.001, commodity.daily_price_limit * price_limit_mult)

	# 供需压力（核心）：短缺→涨价，过剩→降价
	var pressure := gap_ratio * volatility * (0.5 + heat)

	# 存量水平调节：低库存加价（短缺溢价），高库存折价（产能过剩降价）
	var stock_pressure := 0.0
	if stock_ratio < 0.5:
		stock_pressure = (0.5 - stock_ratio) * volatility * 0.8
	elif stock_ratio > 1.5:
		stock_pressure = -(stock_ratio - 1.5) * volatility * 0.5

	# 成交量放大：市场越活跃，价格变动越剧烈（集中囤货拉升 / 集体抛售崩盘）
	var volume_boost := clampf(volume * volume_mult / 200.0, 0.0, 1.0)

	# 均值回归：稳定产出时围绕基准价横盘震荡
	var mean_reversion := (commodity.base_price - current_price) / maxf(commodity.base_price, 0.01) * 0.02

	var delta := (pressure + stock_pressure) * (1.0 + volume_boost) + mean_reversion
	return clampf(delta, -limit, limit)
