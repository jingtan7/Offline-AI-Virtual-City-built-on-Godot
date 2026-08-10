extends Node
## 阶段四：多 AI Agent 智能体系统测试
## 覆盖：职业人设 Prompt / 决策规范化 / 决策落地(work/buy/sell) / LLM接管跳过规则 / 实机LLM决策

func run_test(reporter: Node) -> void:
	EconomyEngine.reset()
	var checks: Array = []
	checks.append(_check_prompts())
	checks.append(_check_normalize())
	checks.append(_check_apply_work())
	checks.append(_check_apply_buy())
	checks.append(_check_apply_sell())
	checks.append(_check_llm_controlled_skip())
	checks.append(await _check_llm_decision())
	_report(reporter, checks)


func _check_prompts() -> Dictionary:
	var texts := {}
	for occ in ["farmer", "miner", "merchant", "artisan", "speculator"]:
		var p := AgentPrompts.system_prompt_for(occ)
		if p.is_empty() or not p.contains("决策输出格式"):
			return {"ok": false, "name": "职业人设Prompt", "msg": occ + " prompt 不完整"}
		texts[occ] = p
	if texts["farmer"] == texts["speculator"]:
		return {"ok": false, "name": "职业人设Prompt", "msg": "不同职业 prompt 应差异化"}
	var a := AgentData.new()
	a.display_name = "测试"
	a.occupation = "farmer"
	if AgentPrompts.chat_system_for(a).is_empty():
		return {"ok": false, "name": "职业人设Prompt", "msg": "对话 prompt 为空"}
	return {"ok": true, "name": "职业人设Prompt: 5职业差异化"}


func _check_normalize() -> Dictionary:
	var good := AgentBrain.normalize({
		"action": "buy", "commodity": "ore", "price": 14.5, "quantity": 20, "reason": "矿石便宜"
	})
	if good.get("action") != "buy" or good.get("commodity") != "ore":
		return {"ok": false, "name": "决策规范化", "msg": "合法输入未通过"}
	var bad := AgentBrain.normalize({"action": "hack", "commodity": "", "price": -5, "quantity": -1})
	if bad.get("action") != "hold" or bad.get("price") != 0.0:
		return {"ok": false, "name": "决策规范化", "msg": "非法输入未回退 hold"}
	return {"ok": true, "name": "决策规范化: 合法通过/非法回退hold"}


func _check_apply_work() -> Dictionary:
	EconomyEngine.reset()
	var agent: AgentData = EconomyEngine.state.agents[0]
	AgentManager.apply_decision(agent, {"action": "work", "commodity": "", "price": 0, "quantity": 0, "reason": "稳定劳作"})
	if not agent.llm_controlled or agent.state != AgentData.State.WORKING:
		return {"ok": false, "name": "决策落地work", "msg": "状态错误"}
	return {"ok": true, "name": "决策落地work: LLM接管+打工状态"}


func _check_apply_buy() -> Dictionary:
	EconomyEngine.reset()
	var agent: AgentData = EconomyEngine.state.agents[0]
	var before := EconomyEngine.state.orders.size()
	AgentManager.apply_decision(agent, {"action": "buy", "commodity": "ore", "price": 14.5, "quantity": 20, "reason": "低价囤货"})
	if EconomyEngine.state.orders.size() != before + 1:
		return {"ok": false, "name": "决策落地buy", "msg": "未创建买单"}
	var o: TradeOrder = EconomyEngine.state.orders[EconomyEngine.state.orders.size() - 1]
	if o.order_type != TradeOrder.Type.BUY or o.owner_id != agent.id or o.commodity_id != "ore":
		return {"ok": false, "name": "决策落地buy", "msg": "订单内容错误"}
	if agent.state != AgentData.State.HOARDING:
		return {"ok": false, "name": "决策落地buy", "msg": "应为囤货状态"}
	return {"ok": true, "name": "决策落地buy: 买单@%s x%.0f" % [o.commodity_id, o.quantity]}


func _check_apply_sell() -> Dictionary:
	EconomyEngine.reset()
	var agent: AgentData = EconomyEngine.state.agents[0]
	var before := EconomyEngine.state.orders.size()
	AgentManager.apply_decision(agent, {"action": "sell", "commodity": "tool", "price": 28.0, "quantity": 10, "reason": "高价出货"})
	if EconomyEngine.state.orders.size() != before + 1:
		return {"ok": false, "name": "决策落地sell", "msg": "未创建卖单"}
	var o: TradeOrder = EconomyEngine.state.orders[EconomyEngine.state.orders.size() - 1]
	if o.order_type != TradeOrder.Type.SELL or o.owner_id != agent.id:
		return {"ok": false, "name": "决策落地sell", "msg": "订单内容错误"}
	if agent.state != AgentData.State.TRADING:
		return {"ok": false, "name": "决策落地sell", "msg": "应为交易状态"}
	return {"ok": true, "name": "决策落地sell: 卖单@%s x%.0f" % [o.commodity_id, o.quantity]}


func _check_llm_controlled_skip() -> Dictionary:
	EconomyEngine.reset()
	for a in EconomyEngine.state.agents:
		a.llm_controlled = true
	var before := EconomyEngine.state.orders.size()
	EconomyEngine.step_tick(1)
	if EconomyEngine.state.orders.size() != before:
		return {"ok": false, "name": "LLM接管跳过规则", "msg": "LLM接管Agent仍产生规则挂单"}
	return {"ok": true, "name": "LLM接管跳过规则: 无规则挂单"}


func _check_llm_decision() -> Dictionary:
	if not AIService.is_ready:
		return {"ok": true, "skip": true, "name": "实机LLM决策", "msg": "AI服务未就绪，跳过"}
	EconomyEngine.reset()
	var agent: AgentData = EconomyEngine.state.agents[0]
	var decision: Dictionary = await AgentBrain.decide(agent, EconomyEngine.state)
	if decision.is_empty():
		return {"ok": true, "skip": true, "name": "实机LLM决策", "msg": "LLM未返回有效决策"}
	if not ["work", "buy", "sell", "hold"].has(decision.get("action", "")):
		return {"ok": false, "name": "实机LLM决策", "msg": "action非法: " + str(decision)}
	AgentManager.apply_decision(agent, decision)
	if not agent.llm_controlled:
		return {"ok": false, "name": "实机LLM决策", "msg": "决策未落地"}
	return {"ok": true, "name": "实机LLM决策: %s %s@%.2f" % [decision.get("action"), decision.get("commodity"), float(decision.get("price", 0))]}


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
