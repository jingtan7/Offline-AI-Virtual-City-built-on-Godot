extends Node
## 阶段七：多 Agent 经济全链路闭环联调测试
## 覆盖：全链路闭环 / 稀缺暴涨 / 产能过剩崩盘 / 事件驱动 / 玩家干预 / LLM Agent 参与

func run_test(reporter: Node) -> void:
	AgentManager.set_enabled(false)
	EconomyEngine.reset()
	var checks: Array = []
	checks.append(await _check_full_chain())
	checks.append(_check_scarcity_spike())
	checks.append(_check_overcapacity_crash())
	checks.append(_check_event_driven())
	checks.append(_check_player_intervention())
	checks.append(await _check_llm_agent_cycle())
	_report(reporter, checks)


func _check_full_chain() -> Dictionary:
	EconomyEngine.reset()
	for i in range(40):
		EconomyEngine.step_tick(i)
	var st := EconomyEngine.state
	var bars: Array = st.market_bars.get("food", [])
	if bars.size() != 40:
		return {"ok": false, "name": "全链路闭环", "msg": "行情条数=%d" % bars.size()}
	var price_moved := false
	for cid in st.commodities:
		if absf((st.commodities[cid] as Commodity).current_price - (st.commodities[cid] as Commodity).base_price) > 0.001:
			price_moved = true
	var traded := false
	for a in st.agents:
		if (a as AgentData).trade_history.size() > 0:
			traded = true
	if not price_moved or not traded:
		return {"ok": false, "name": "全链路闭环", "msg": "价格未动或无成交"}
	return {"ok": true, "name": "全链路闭环: 产出→挂单→撮合→物价→行情40条"}


func _check_scarcity_spike() -> Dictionary:
	EconomyEngine.reset()
	EconomyEngine.state.commodities["food"].total_stock = 50.0  # 严重短缺
	for i in range(30):
		EconomyEngine.step_tick(i)
	var food: Commodity = EconomyEngine.state.commodities["food"]
	if food.current_price <= food.base_price:
		return {"ok": false, "name": "稀缺暴涨", "msg": "粮食价%.2f未涨过基准%.2f" % [food.current_price, food.base_price]}
	return {"ok": true, "name": "稀缺暴涨: 粮食 %.2f -> %.2f" % [food.base_price, food.current_price]}


func _check_overcapacity_crash() -> Dictionary:
	EconomyEngine.reset()
	EconomyEngine.state.commodities["food"].total_stock = 30000.0  # 严重过剩
	for i in range(30):
		EconomyEngine.step_tick(i)
	var food: Commodity = EconomyEngine.state.commodities["food"]
	if food.current_price >= food.base_price - 0.01:
		return {"ok": false, "name": "产能过剩降价", "msg": "粮食价%.2f未跌破基准%.2f" % [food.current_price, food.base_price]}
	return {"ok": true, "name": "产能过剩降价: 粮食 %.2f -> %.2f" % [food.base_price, food.current_price]}


func _check_event_driven() -> Dictionary:
	EconomyEngine.reset()
	var before: float = EconomyEngine.state.commodities["food"].total_stock
	EconomyEngine.inject_effect("food", {
		"ticks_left": 3, "output_mult": 1.0, "heat_boost": 0.0,
		"volume_mult": 1.0, "price_limit_mult": 1.0,
		"stock_mult": 0.85, "stock_delta": 0.0, "applied_once": false,
	})
	for i in range(5):
		EconomyEngine.step_tick(i)
	var after: float = EconomyEngine.state.commodities["food"].total_stock
	if after > before * 0.92:
		return {"ok": false, "name": "事件驱动行情", "msg": "天灾减产未生效: %f -> %f" % [before, after]}
	return {"ok": true, "name": "事件驱动行情: 天灾后存量 %.0f -> %.0f" % [before, after]}


func _check_player_intervention() -> Dictionary:
	EconomyEngine.reset()
	for i in range(5):
		EconomyEngine.step_tick(i)
	var ore: Commodity = EconomyEngine.state.commodities["ore"]
	EconomyEngine.place_player_order(TradeOrder.Type.BUY, "ore", ore.current_price * 1.5, 100.0)
	for i in range(12):
		EconomyEngine.step_tick(i)
	var got := float(EconomyEngine.state.player.inventory.get("ore", 0.0))
	if got <= 0.0:
		return {"ok": false, "name": "玩家干预", "msg": "玩家高价求购未被撮合"}
	return {"ok": true, "name": "玩家干预: 高价求购矿石, 成交%.0f单位" % got}


func _check_llm_agent_cycle() -> Dictionary:
	if not AIService.is_ready:
		return {"ok": true, "skip": true, "name": "LLM Agent 参与闭环", "msg": "AI服务未就绪，跳过"}
	EconomyEngine.reset()
	var agent: AgentData = EconomyEngine.state.agents[0]
	var decision: Dictionary = await AgentBrain.decide(agent, EconomyEngine.state)
	if decision.is_empty():
		return {"ok": true, "skip": true, "name": "LLM Agent 参与闭环", "msg": "LLM未返回有效决策"}
	var before := EconomyEngine.state.orders.size()
	AgentManager.apply_decision(agent, decision)
	var applied := agent.llm_controlled
	if not applied:
		return {"ok": false, "name": "LLM Agent 参与闭环", "msg": "决策未落地"}
	return {"ok": true, "name": "LLM Agent 参与闭环: %s(挂单%+d)" % [decision.get("action"), EconomyEngine.state.orders.size() - before]}


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
