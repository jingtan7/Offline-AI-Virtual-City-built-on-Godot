extends Node
## 阶段三：仿真经济算法测试
## 覆盖：供需物价 / 撮合(基础/价格优先/结算) / 引擎运行 / 不变量 / 事件系统 / 存档

func run_test(reporter: Node) -> void:
	var checks: Array = []
	checks.append(_check_supply_demand())
	checks.append(_check_matching_basic())
	checks.append(_check_matching_price_priority())
	checks.append(_check_matching_settlement())
	checks.append(_check_engine_runs())
	checks.append(_check_engine_invariants())
	checks.append(_check_event_roll())
	checks.append(_check_event_effect())
	checks.append(_check_engine_save_load())
	_report(reporter, checks)


func _check_supply_demand() -> Dictionary:
	var c := Commodity.new("t", "测试", "trade", 10.0, 100.0, 1.0, 1.0, 0.1, 0.5, 0.1)
	var delta_short := SupplyDemand.price_delta(c, 60.0, 40.0, 50.0, 0.8, 10.0)
	var delta_surplus := SupplyDemand.price_delta(c, 40.0, 60.0, 50.0, 1.2, 10.0)
	if delta_short <= 0.0:
		return {"ok": false, "name": "供需物价算法", "msg": "短缺应涨价, delta=%f" % delta_short}
	if delta_surplus >= 0.0:
		return {"ok": false, "name": "供需物价算法", "msg": "过剩应降价, delta=%f" % delta_surplus}
	if absf(delta_short) > c.daily_price_limit + 0.0001:
		return {"ok": false, "name": "供需物价算法", "msg": "超过单日波动限制"}
	var delta_balance := SupplyDemand.price_delta(c, 50.0, 50.0, 0.0, 1.0, 10.0)
	if absf(delta_balance) > 0.0001:
		return {"ok": false, "name": "供需物价算法", "msg": "均衡时应无变化"}
	return {"ok": true, "name": "供需物价算法: 短缺+%.2f%% / 过剩%.2f%%" % [delta_short * 100.0, delta_surplus * 100.0]}


func _mk_agent(id: String, cash: float, inventory: Dictionary) -> AgentData:
	var a := AgentData.new()
	a.id = id
	a.cash = cash
	a.inventory = inventory
	return a


func _check_matching_basic() -> Dictionary:
	var s := CityState.new()
	s.reset()
	var buyer := _mk_agent("agent_0000", 1000.0, {"food": 0.0})
	var seller := _mk_agent("agent_0001", 0.0, {"food": 100.0})
	s.agents = [buyer, seller]
	s.add_order(TradeOrder.create("b1", TradeOrder.Type.BUY, "food", 13.0, 10.0, buyer.id, "agent", 1, 60))
	s.add_order(TradeOrder.create("s1", TradeOrder.Type.SELL, "food", 12.0, 10.0, seller.id, "agent", 1, 60))
	var result := MatchingEngine.match(s)
	var trades: Array = result.get("trades", [])
	if trades.size() != 1:
		return {"ok": false, "name": "撮合基础成交", "msg": "应成交1笔, 实际%d" % trades.size()}
	if not is_equal_approx(float(buyer.inventory.get("food", 0.0)), 10.0):
		return {"ok": false, "name": "撮合基础成交", "msg": "买方库存错误"}
	if not is_equal_approx(seller.cash, 120.0):
		return {"ok": false, "name": "撮合基础成交", "msg": "卖方资金错误"}
	return {"ok": true, "name": "撮合基础成交: 10单位@12.0"}


func _check_matching_price_priority() -> Dictionary:
	var s := CityState.new()
	s.reset()
	var b1 := _mk_agent("agent_0001", 1000.0, {})
	var b2 := _mk_agent("agent_0002", 1000.0, {})
	var seller := _mk_agent("agent_0003", 0.0, {"food": 10.0})
	s.agents = [b1, b2, seller]
	s.add_order(TradeOrder.create("b_high", TradeOrder.Type.BUY, "food", 13.0, 10.0, b1.id, "agent", 1, 60))
	s.add_order(TradeOrder.create("b_low", TradeOrder.Type.BUY, "food", 11.0, 10.0, b2.id, "agent", 2, 60))
	s.add_order(TradeOrder.create("s1", TradeOrder.Type.SELL, "food", 12.0, 10.0, seller.id, "agent", 1, 60))
	var result := MatchingEngine.match(s)
	var trades: Array = result.get("trades", [])
	if trades.size() != 1 or str(trades[0].get("buy_order", "")) != "b_high":
		return {"ok": false, "name": "价格优先", "msg": "应优先撮合高价买单"}
	return {"ok": true, "name": "价格优先: 高价买单先成交"}


func _check_matching_settlement() -> Dictionary:
	var s := CityState.new()
	s.reset()
	var player := s.player
	player.cash = 500.0
	var seller := _mk_agent("agent_0009", 0.0, {"ore": 100.0})
	s.agents = [seller]
	s.add_order(TradeOrder.create("pb", TradeOrder.Type.BUY, "ore", 15.0, 20.0, player.player_id, "player", 1, 60))
	s.add_order(TradeOrder.create("sa", TradeOrder.Type.SELL, "ore", 14.0, 20.0, seller.id, "agent", 1, 60))
	var result := MatchingEngine.match(s)
	var trades: Array = result.get("trades", [])
	if trades.size() != 1:
		return {"ok": false, "name": "AI↔玩家结算", "msg": "应成交1笔"}
	if not is_equal_approx(player.cash, 500.0 - 20.0 * 14.0):
		return {"ok": false, "name": "AI↔玩家结算", "msg": "玩家资金错误: %f" % player.cash}
	if not is_equal_approx(float(player.inventory.get("ore", 0.0)), 20.0):
		return {"ok": false, "name": "AI↔玩家结算", "msg": "玩家库存错误"}
	if not is_equal_approx(seller.cash, 280.0) or not is_equal_approx(float(seller.inventory.get("ore", 0.0)), 80.0):
		return {"ok": false, "name": "AI↔玩家结算", "msg": "AI 资金/库存错误"}
	return {"ok": true, "name": "AI↔玩家结算: 玩家-280 / AI+280"}
func _check_engine_runs() -> Dictionary:
	EconomyEngine.reset()
	EconomyEngine.rng.seed = 12345
	for i in range(60):
		EconomyEngine.step_tick(i)
	var st := EconomyEngine.state
	if st.tick != 60:
		return {"ok": false, "name": "引擎60tick运行", "msg": "tick=%d" % st.tick}
	var bars: Array = st.market_bars.get("food", [])
	if bars.size() != 60:
		return {"ok": false, "name": "引擎60tick运行", "msg": "food行情条数=%d" % bars.size()}
	var price_moved := false
	for cid in st.commodities:
		var c: Commodity = st.commodities[cid]
		if absf(c.current_price - c.base_price) > 0.001:
			price_moved = true
	if not price_moved:
		return {"ok": false, "name": "引擎60tick运行", "msg": "价格未发生任何变化"}
	var traded := false
	for a in st.agents:
		if (a as AgentData).trade_history.size() > 0:
			traded = true
	if not traded:
		return {"ok": false, "name": "引擎60tick运行", "msg": "60tick内无任何成交"}
	return {"ok": true, "name": "引擎60tick运行: 价格变动+有成交+行情60条"}


func _check_engine_invariants() -> Dictionary:
	var st := EconomyEngine.state
	for cid in st.commodities:
		var c: Commodity = st.commodities[cid]
		if c.current_price <= 0.0:
			return {"ok": false, "name": "引擎不变量", "msg": c.id + " 价格<=0"}
		if c.total_stock < -0.0001:
			return {"ok": false, "name": "引擎不变量", "msg": c.id + " 存量<0"}
	for a in st.agents:
		if (a as AgentData).cash < -0.0001:
			return {"ok": false, "name": "引擎不变量", "msg": a.id + " 资金<0"}
		for cid in (a as AgentData).inventory:
			if float((a as AgentData).inventory[cid]) < -0.0001:
				return {"ok": false, "name": "引擎不变量", "msg": a.id + " 库存<0"}
	if st.player.cash < -0.0001:
		return {"ok": false, "name": "引擎不变量", "msg": "玩家资金<0"}
	return {"ok": true, "name": "引擎不变量: 无负资金/负库存/负价格"}


func _check_event_roll() -> Dictionary:
	var s := CityState.create_default()
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 777
	var ev := EconomyEvent.roll(s, rng2, 1.0)
	if ev.is_empty():
		return {"ok": false, "name": "事件系统(roll)", "msg": "概率1.0应触发事件"}
	if not ev.has("label") or not ev.has("desc") or not ev.has("effects"):
		return {"ok": false, "name": "事件系统(roll)", "msg": "事件结构不完整"}
	var effects: Dictionary = ev.get("effects", {})
	if not effects.has("commodity"):
		return {"ok": false, "name": "事件系统(roll)", "msg": "事件缺少影响物资"}
	return {"ok": true, "name": "事件系统(roll): " + str(ev.get("label", ""))}


func _check_event_effect() -> Dictionary:
	EconomyEngine.reset()
	EconomyEngine.rng.seed = 99
	var before: float = EconomyEngine.state.commodities["food"].total_stock
	EconomyEngine.inject_effect("food", {
		"ticks_left": 3, "output_mult": 1.0, "heat_boost": 0.0,
		"volume_mult": 1.0, "price_limit_mult": 1.0,
		"stock_mult": 0.5, "stock_delta": 0.0, "applied_once": false,
	})
	EconomyEngine.step_tick(1)
	var after: float = EconomyEngine.state.commodities["food"].total_stock
	if after > before * 0.75:
		return {"ok": false, "name": "事件效果(减产)", "msg": "存量应大幅下降: %f -> %f" % [before, after]}
	return {"ok": true, "name": "事件效果(减产): 存量 %.0f -> %.0f" % [before, after]}


func _check_engine_save_load() -> Dictionary:
	EconomyEngine.reset()
	for i in range(10):
		EconomyEngine.step_tick(i)
	var st: CityState = EconomyEngine.state
	st.player.cash = 5555.0
	if not EconomyEngine.save_now():
		return {"ok": false, "name": "引擎存档/读档", "msg": "保存失败"}
	var loaded := EconomyEngine.load_last()
	if loaded == null or loaded.player.cash != 5555.0:
		return {"ok": false, "name": "引擎存档/读档", "msg": "读档数据不一致"}
	return {"ok": true, "name": "引擎存档/读档: 经济状态可持久化"}


func _report(reporter: Node, checks: Array) -> void:
	for c in checks:
		if c.get("skip", false):
			print("  [SKIP] %s | %s" % [c.get("name", ""), c.get("msg", "")])
		elif c.get("ok", false):
			reporter.passed += 1
			print("  [PASS] " + str(c.get("name", "")))
		else:
			reporter.failed += 1
			print("  [FAIL] %s | %s" % [c.get("name", ""), c.get("msg", "")])

