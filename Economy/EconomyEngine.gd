extends Node
## 城邦自治仿真经济引擎（阶段三）—— 由 SimulationLoop tick 驱动
## 每 tick 闭环：事件效果 → Agent 产出/消耗 → Agent 挂单 → 撮合成交 → 供需物价迭代 → 行情入库
## 供主场景 start_auto() 接入；测试可直接 step_tick() 手动推进。

const FOOD_ID := "food"
const FOOD_NEED := 1.5
const TARGET_INVENTORY := 20.0
const ORDER_VALID_TICKS := 20
const MAX_ORDERS := 2000
const EVENT_PROBABILITY := 0.06

const OCCUPATION_OUTPUT := {
	"farmer": "food", "miner": "ore", "artisan": "tool",
	"merchant": "supply", "speculator": "",
}
const OCCUPATION_OUTPUT_RATE := {
	"farmer": 4.0, "miner": 3.0, "artisan": 2.0, "merchant": 3.0, "speculator": 0.0,
}

var state: CityState
var rng := RandomNumberGenerator.new()
var auto_running := false

var _active_effects: Dictionary = {}  # cid -> {ticks_left, output_mult, heat_boost, volume_mult, price_limit_mult, stock_mult, stock_delta, applied_once}
var _initial_stocks: Dictionary = {}  # cid -> 初始存量（存量水平参照）
var _tick_supply: Dictionary = {}     # cid -> 本 tick 供给
var _tick_demand: Dictionary = {}     # cid -> 本 tick 需求
var _order_seq := 0


func _ready() -> void:
	reset()


## 重置为全新城邦
func reset() -> void:
	state = CityState.create_default()
	_active_effects.clear()
	_initial_stocks.clear()
	for cid in state.commodities:
		_initial_stocks[cid] = state.commodities[cid].total_stock
		rng.seed = Time.get_ticks_usec() & 0xFFFFFFFF
	GameLog.info("经济引擎就绪: %d 物资 / %d Agent" % [state.commodities.size(), state.agents.size()])


## 接入仿真循环（由主场景调用）
func start_auto() -> void:
	if auto_running:
		return
	if not SimulationLoop.tick.is_connected(step_tick):
		SimulationLoop.tick.connect(step_tick)
	auto_running = true
	GameLog.info("经济引擎已接入仿真循环（tick 驱动）")


func stop_auto() -> void:
	if SimulationLoop.tick.is_connected(step_tick):
		SimulationLoop.tick.disconnect(step_tick)
	auto_running = false


## 推进一个经济 tick（连接 SimulationLoop.tick 信号）
func step_tick(tick_index: int = 0, _delta: float = 0.0) -> void:
	if state == null:
		return
	state.tick += 1
	_tick_supply = {}
	_tick_demand = {}
	_update_active_effects()
	_expire_orders()
	_agents_produce_and_consume()
	_agents_place_orders()
	var match_result := MatchingEngine.match(state)
	_update_prices(match_result.get("volumes", {}))
	_record_market_bars(match_result.get("volumes", {}))
	_prune_orders()
	_roll_events()


## ==================== 内部：每 tick 步骤 ====================

func _update_active_effects() -> void:
	var expired: Array = []
	for cid in _active_effects:
		var e: Dictionary = _active_effects[cid]
		if not e.get("applied_once", false):
			var commodity: Commodity = state.commodities.get(cid)
			if commodity != null:
				var stock_mult := float(e.get("stock_mult", 1.0))
				var stock_delta := float(e.get("stock_delta", 0.0))
				commodity.total_stock = maxf(0.0, commodity.total_stock * stock_mult + stock_delta)
			e["applied_once"] = true
		e["ticks_left"] = int(e.get("ticks_left", 0)) - 1
		if int(e["ticks_left"]) <= 0:
			expired.append(cid)
	for cid in expired:
		_active_effects.erase(cid)


func _effect_for(cid: String) -> Dictionary:
	var e: Dictionary = _active_effects.get(cid, {})
	return {
		"output_mult": float(e.get("output_mult", 1.0)),
		"heat_boost": float(e.get("heat_boost", 0.0)),
		"volume_mult": float(e.get("volume_mult", 1.0)),
		"price_limit_mult": float(e.get("price_limit_mult", 1.0)),
	}


func _expire_orders() -> void:
	for o in state.orders:
		if o.is_active() and state.tick >= o.expires_at:
			o.status = TradeOrder.Status.EXPIRED


func _prune_orders() -> void:
	if state.orders.size() > MAX_ORDERS:
		state.orders = state.orders.filter(func(o: TradeOrder) -> bool: return o.is_active())


func _roll_events() -> void:
	var ev := EconomyEvent.roll(state, rng, EVENT_PROBABILITY)
	if ev.is_empty():
		return
	state.event_log.append(ev)
	var effects: Dictionary = ev.get("effects", {})
	var cid := str(effects.get("commodity", ""))
	if cid.is_empty() or not state.commodities.has(cid):
		return
	_active_effects[cid] = {
		"ticks_left": int(effects.get("ticks", 5)),
		"output_mult": float(effects.get("output_mult", 1.0)),
		"heat_boost": float(effects.get("heat_boost", 0.0)),
		"volume_mult": float(effects.get("volume_mult", 1.0)),
		"price_limit_mult": float(effects.get("price_limit_mult", 1.0)),
		"stock_mult": float(effects.get("stock_mult", 1.0)),
		"stock_delta": float(effects.get("stock_delta", 0.0)),
		"applied_once": false,
	}
	GameLog.info("城邦事件: %s — %s" % [ev.get("label", ""), ev.get("desc", "")])


func _agents_produce_and_consume() -> void:
	for agent in state.agents:
		var output := str(OCCUPATION_OUTPUT.get(agent.occupation, ""))
		var rate := float(OCCUPATION_OUTPUT_RATE.get(agent.occupation, 0.0))
		if not output.is_empty() and rate > 0.0 and state.commodities.has(output):
			var eff := _effect_for(output)
			var qty := rate * float(eff.get("output_mult", 1.0))
			if float(agent.inventory.get(FOOD_ID, 0.0)) <= 1.0:
				qty *= 0.5  # 饥饿时效率减半
			agent.inventory[output] = float(agent.inventory.get(output, 0.0)) + qty
			(state.commodities[output] as Commodity).total_stock += qty
			_tick_supply[output] = float(_tick_supply.get(output, 0.0)) + qty
			agent.record_labor(output, qty)
		# 食物消耗
		var food := float(agent.inventory.get(FOOD_ID, 0.0))
		_tick_demand[FOOD_ID] = float(_tick_demand.get(FOOD_ID, 0.0)) + FOOD_NEED
		if food >= FOOD_NEED:
			agent.inventory[FOOD_ID] = food - FOOD_NEED
			if state.commodities.has(FOOD_ID):
				(state.commodities[FOOD_ID] as Commodity).total_stock = maxf(0.0, state.commodities[FOOD_ID].total_stock - FOOD_NEED)
		else:
			agent.inventory[FOOD_ID] = 0.0


func _agents_place_orders() -> void:
	var prices := _market_prices()
	for agent in state.agents:
		var occ_output := str(OCCUPATION_OUTPUT.get(agent.occupation, ""))
		var risk := float(agent.personality.get("risk_tolerance", 0.5))
		# 食物储备不足 → 求购
		if float(agent.inventory.get(FOOD_ID, 0.0)) < 10.0 and agent.cash > 30.0:
			_place_order(agent, TradeOrder.Type.BUY, FOOD_ID, float(prices.get(FOOD_ID, 12.5)) * 0.98, 10.0)
		# 职业产出盈余 → 出售
		if not occ_output.is_empty() and state.commodities.has(occ_output):
			var stock := float(agent.inventory.get(occ_output, 0.0))
			if stock > TARGET_INVENTORY:
				var margin := 1.0 + (risk - 0.5) * 0.1
				_place_order(agent, TradeOrder.Type.SELL, occ_output, float(prices.get(occ_output, 12.5)) * margin, stock - TARGET_INVENTORY)
		# 高风险性格 → 低价囤货
		if risk >= 0.6 and agent.cash > 100.0:
			for cid in prices:
				var p := float(prices[cid])
				var base := (state.commodities[cid] as Commodity).base_price
				if p < base * 0.92:
					_place_order(agent, TradeOrder.Type.BUY, cid, p * 1.01, 5.0)
		# 高风险性格 → 高价抛售
		if risk >= 0.7:
			for cid in prices:
				var p := float(prices[cid])
				var base := (state.commodities[cid] as Commodity).base_price
				if p > base * 1.15 and float(agent.inventory.get(cid, 0.0)) > 10.0:
					_place_order(agent, TradeOrder.Type.SELL, cid, p * 0.99, 5.0)


func _place_order(agent: AgentData, order_type: int, cid: String, price: float, qty: float) -> void:
	_order_seq += 1
	var q := maxf(1.0, qty)
	var o := TradeOrder.create("o%d" % _order_seq, order_type, cid, price, q, agent.id, "agent", state.tick, ORDER_VALID_TICKS)
	state.add_order(o)
	if order_type == TradeOrder.Type.BUY:
		_tick_demand[cid] = float(_tick_demand.get(cid, 0.0)) + q
	else:
		_tick_supply[cid] = float(_tick_supply.get(cid, 0.0)) + q


func _market_prices() -> Dictionary:
	var out := {}
	for cid in state.commodities:
		out[cid] = (state.commodities[cid] as Commodity).current_price
	return out


func _update_prices(volumes: Dictionary) -> void:
	for cid in state.commodities:
		var commodity: Commodity = state.commodities[cid]
		var eff := _effect_for(cid)
		var demand := float(_tick_demand.get(cid, 0.0))
		var supply := float(_tick_supply.get(cid, 0.0))
		var volume := float(volumes.get(cid, 0.0))
		var stock_ratio := commodity.total_stock / maxf(float(_initial_stocks.get(cid, commodity.total_stock)), 1.0)
		var delta := SupplyDemand.price_delta(
			commodity, demand, supply, volume, stock_ratio, commodity.current_price,
			float(eff.get("heat_boost", 0.0)),
			float(eff.get("volume_mult", 1.0)),
			float(eff.get("price_limit_mult", 1.0)),
		)
		commodity.current_price = maxf(0.01, commodity.current_price * (1.0 + delta))


func _record_market_bars(volumes: Dictionary) -> void:
	for cid in state.commodities:
		var commodity: Commodity = state.commodities[cid]
		var prev_bar := state.latest_bar(cid)
		var prev_close := prev_bar.close if prev_bar != null else commodity.base_price
		var bar := MarketBar.create(state.tick, cid, commodity.current_price, prev_close)
		bar.volume = float(volumes.get(cid, 0.0))
		bar.pending_orders = _count_pending(cid)
		bar.supply_demand_gap = float(_tick_demand.get(cid, 0.0)) - float(_tick_supply.get(cid, 0.0))
		state.append_market_bar(bar)


func _count_pending(cid: String) -> int:
	var n := 0
	for o in state.orders:
		if o.commodity_id == cid and o.is_active():
			n += 1
	return n


## ==================== 对外接口 ====================

## 玩家（城主）挂单，供交易 UI 使用
func place_player_order(order_type: int, cid: String, price: float, qty: float) -> TradeOrder:
	_order_seq += 1
	var o := TradeOrder.create("p%d" % _order_seq, order_type, cid, price, qty, state.player.player_id, "player", state.tick, ORDER_VALID_TICKS)
	state.add_order(o)
	return o


## 当前全部实时价格（供工具/UI）
func market_prices() -> Dictionary:
	return _market_prices()


## 注入事件效果（测试/调试用）
func inject_effect(cid: String, effect: Dictionary) -> void:
	_active_effects[cid] = effect


func save_now() -> bool:
	return state.save()


static func load_last() -> CityState:
	return CityState.load()
