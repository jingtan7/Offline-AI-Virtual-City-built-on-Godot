class_name AgentBrain
extends RefCounted
## 标准化 Agent 思考链路（阶段四，核心技术亮点）
## 环境感知 → 状态自查 → 记忆检索 → LLM 离线推理 → 落地执行
## 强制 LLM 结构化输出，解决大模型输出不可控问题。

const DECISION_TEMPERATURE := 0.3
const DECISION_MAX_TOKENS := 256


## 一次完整决策。LLM 未就绪或输出非法时返回空 {}（由调度器忽略）。
static func decide(agent: AgentData, state: CityState) -> Dictionary:
	if not AIService.is_ready:
		return {}
	var perception := _perceive(state, agent)
	var self_check := _self_check(agent)
	var memories := MemoryStore.search(_memory_query(agent), 3)
	var system := AgentPrompts.system_prompt_for(agent.occupation)
	var user := _build_prompt(agent, perception, self_check, memories)
	var raw: Dictionary = await AIService.llm_client.chat_structured(
		user, system, "", DECISION_TEMPERATURE)
	if raw.is_empty() or not raw.get("success", false):
		return {}
	return normalize(raw)


## 校验并规范化 LLM 决策（非法值回退 hold，保证安全可执行）
static func normalize(raw: Dictionary) -> Dictionary:
	var action := str(raw.get("action", "hold")).to_lower().strip_edges()
	if not ["work", "buy", "sell", "hold"].has(action):
		action = "hold"
	var cid := str(raw.get("commodity", "")).to_lower().strip_edges()
	var price := maxf(0.0, float(raw.get("price", 0.0)))
	var qty := maxf(0.0, float(raw.get("quantity", 0.0)))
	var reason := str(raw.get("reason", "")).substr(0, 120)
	return {"action": action, "commodity": cid, "price": price, "quantity": qty, "reason": reason}


## 环境感知：读取实时物价、存量、趋势
static func _perceive(state: CityState, agent: AgentData) -> String:
	var lines: Array = []
	for cid in state.commodities:
		var c: Commodity = state.commodities[cid]
		var trend := "平"
		var bar := state.latest_bar(cid)
		if bar != null:
			var chg := bar.change_pct()
			trend = "涨%.1f%%" % chg if absf(chg) > 0.5 else "平"
		lines.append("%s: 价%.2f/基准%.2f, 存量%.0f, %s" % [c.name, c.current_price, c.base_price, c.total_stock, trend])
	return "\n".join(lines)


## 状态自查：自身资金、库存、当前需求
static func _self_check(agent: AgentData) -> String:
	return "资金=%.1f, 库存=%s, 当前状态=%s, 风险偏好=%s" % [
		agent.cash, JSON.stringify(agent.inventory), agent.state_label(), agent.risk_profile,
	]


## 记忆检索查询词
static func _memory_query(agent: AgentData) -> String:
	return "行情走势 城邦事件 城主交易 交易经验 %s" % agent.occupation_label()


static func _build_prompt(agent: AgentData, perception: String, self_check: String, memories: Array) -> String:
	var mem_text := "（无相关记忆）"
	if not memories.is_empty():
		var arr: Array = []
		for m in memories:
			arr.append("- " + str(m.get("text", "")))
		mem_text = "\n".join(arr)
	return (
		"你是%s。请基于以下信息做出本回合决策：\n\n"
		+ "【实时行情】\n%s\n\n"
		+ "【我的状态】\n%s\n\n"
		+ "【相关记忆】\n%s\n\n"
		+ "请按格式输出决策 JSON。"
	) % [agent.display_name, perception, self_check, mem_text]
