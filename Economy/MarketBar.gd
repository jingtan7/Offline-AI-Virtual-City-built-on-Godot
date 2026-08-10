class_name MarketBar
extends RefCounted
## 经济行情数据（单根分时/K线）（阶段二）
## 字段覆盖：时间戳、实时物价(close)、开盘价、昨日收盘价、区间最高/最低、
## 涨跌幅度、市场成交量、挂单量、物资供需差值。

var timestamp: int = 0         # 时间戳（毫秒）
var commodity_id: String = ""  # 物资ID
var open: float = 0.0          # 开盘价
var close: float = 0.0         # 实时物价（收盘）
var high: float = 0.0          # 区间最高价
var low: float = 0.0           # 区间最低价
var prev_close: float = 0.0    # 昨日收盘价
var volume: float = 0.0        # 市场成交量
var pending_orders: int = 0    # 挂单量（笔数）
var supply_demand_gap: float = 0.0  # 供需差值（需求 - 供给）


## 涨跌幅度（百分比）
func change_pct() -> float:
	if prev_close == 0.0:
		return 0.0
	return (close - prev_close) / prev_close * 100.0


## 便捷构造：单个价格点生成一根 bar
static func create(
	timestamp: int,
	commodity_id: String,
	price: float,
	prev_close: float,
	volume: float = 0.0,
	pending: int = 0,
	gap: float = 0.0
) -> MarketBar:
	var b := MarketBar.new()
	b.timestamp = timestamp
	b.commodity_id = commodity_id
	b.open = price
	b.close = price
	b.high = price
	b.low = price
	b.prev_close = prev_close
	b.volume = volume
	b.pending_orders = pending
	b.supply_demand_gap = gap
	return b


func to_dict() -> Dictionary:
	return {
		"timestamp": timestamp, "commodity_id": commodity_id,
		"open": open, "close": close, "high": high, "low": low,
		"prev_close": prev_close, "volume": volume,
		"pending_orders": pending_orders, "supply_demand_gap": supply_demand_gap,
	}


static func from_dict(d: Dictionary) -> MarketBar:
	var b := MarketBar.new()
	b.timestamp = int(d.get("timestamp", 0))
	b.commodity_id = str(d.get("commodity_id", ""))
	b.open = float(d.get("open", 0.0))
	b.close = float(d.get("close", 0.0))
	b.high = float(d.get("high", 0.0))
	b.low = float(d.get("low", 0.0))
	b.prev_close = float(d.get("prev_close", 0.0))
	b.volume = float(d.get("volume", 0.0))
	b.pending_orders = int(d.get("pending_orders", 0))
	b.supply_demand_gap = float(d.get("supply_demand_gap", 0.0))
	return b
