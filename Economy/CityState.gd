class_name CityState
extends RefCounted
## 城邦总状态容器（阶段二）
## 聚合：物资表、玩家、Agent 集群、订单簿、行情历史、事件日志。
## 提供 to_dict/from_dict 与 save/load（JSON 持久化，为阶段三仿真引擎提供数据底座）。

const SAVE_PATH := "user://Data/saves/city_state.json"

var tick: int = 0                      # 当前仿真 tick
var commodities: Dictionary = {}       # commodity_id -> Commodity
var player: PlayerData                 # 城邦城主
var agents: Array = []                 # Array[AgentData]
var orders: Array = []                 # Array[TradeOrder] 订单簿
var market_bars: Dictionary = {}       # commodity_id -> Array[MarketBar] 行情历史
var event_log: Array = []              # 城邦重大经济事件（阶段三随机事件系统用）


func _init() -> void:
	player = PlayerData.new()


## 重置为默认城邦：物资表 + 玩家 + 15 个示例智能体。
func reset() -> void:
	tick = 0
	commodities.clear()
	for c in Commodity.default_commodities():
		commodities[c.id] = c
	player = PlayerData.new()
	agents = AgentData.make_sample_agents(15)
	orders = []
	market_bars = {}
	event_log = []


## 便捷：创建默认城邦
static func create_default() -> CityState:
	var s := CityState.new()
	s.reset()
	return s


## 追加一条行情记录（超过 max_kept 条时裁剪最旧）
func append_market_bar(bar: MarketBar, max_kept: int = 10000) -> void:
	var bars: Array = market_bars.get(bar.commodity_id, [])
	bars.append(bar)
	if bars.size() > max_kept:
		bars.pop_front()
	market_bars[bar.commodity_id] = bars


## 某物资最新行情（无则返回 null）
func latest_bar(commodity_id: String) -> MarketBar:
	var bars: Array = market_bars.get(commodity_id, [])
	if bars.is_empty():
		return null
	return bars[bars.size() - 1]


## 按中文名称查找物资（供工具/UI 使用）
func find_commodity_by_name(display_name: String) -> Commodity:
	for cid in commodities:
		var c: Commodity = commodities[cid]
		if c.name == display_name:
			return c
	return null


func add_order(order: TradeOrder) -> void:
	orders.append(order)


func to_dict() -> Dictionary:
	var bars := {}
	for cid in market_bars:
		var arr: Array = []
		for b in market_bars[cid]:
			arr.append((b as MarketBar).to_dict())
		bars[cid] = arr
	return {
		"tick": tick,
		"commodities": Commodity.commodities_to_dict(commodities),
		"player": player.to_dict(),
		"agents": AgentData.agents_to_dict(agents),
		"orders": TradeOrder.orders_to_dict(orders),
		"market_bars": bars,
		"event_log": event_log,
	}


static func from_dict(data: Dictionary) -> CityState:
	var s := CityState.new()
	s.tick = int(data.get("tick", 0))
	s.commodities = Commodity.commodities_from_dict(data.get("commodities", {}))
	s.player = PlayerData.from_dict(data.get("player", {}))
	s.agents = AgentData.agents_from_dict(data.get("agents", []))
	s.orders = TradeOrder.orders_from_dict(data.get("orders", []))
	var bars := {}
	var bars_data: Dictionary = data.get("market_bars", {})
	for cid in bars_data:
		var arr: Array = []
		for bd in bars_data[cid]:
			if bd is Dictionary:
				arr.append(MarketBar.from_dict(bd))
		bars[cid] = arr
	s.market_bars = bars
	s.event_log = data.get("event_log", [])
	return s


## 保存到 user://Data/saves/city_state.json
func save() -> bool:
	DirAccess.make_dir_recursive_absolute("user://Data/saves")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	f.close()
	return true


## 读取存档；无存档返回 null
static func load() -> CityState:
	if not FileAccess.file_exists(SAVE_PATH):
		return null
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return from_dict(parsed) if parsed is Dictionary else null
