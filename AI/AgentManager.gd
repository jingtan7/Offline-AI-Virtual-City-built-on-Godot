extends Node
## 多 Agent 并发轮询机制（阶段四）
## 以固定间隔异步轮询 Agent，让 LLM 独立推理并落地执行（感知→自查→记忆→推理→执行）。
## LLM 决策后的 Agent 由 LLM 接管（引擎跳过其规则行为），实现多智能体自主决策集群。

const DEFAULT_INTERVAL_SEC := 3.0
const DEFAULT_BATCH := 2

var enabled := true
var interval_sec := DEFAULT_INTERVAL_SEC
var agents_per_batch := DEFAULT_BATCH

var _timer: Timer
var _cursor := 0
var decisions_total := 0


func _ready() -> void:
	_timer = Timer.new()
	_timer.wait_time = interval_sec
	_timer.timeout.connect(_process_batch)
	_timer.autostart = true
	add_child(_timer)
	GameLog.info("AgentManager 就绪: %d个/批, 间隔%.1fs" % [agents_per_batch, interval_sec])


func set_enabled(v: bool) -> void:
	enabled = v
	_timer.paused = not v


func _process_batch() -> void:
	if not enabled:
		return
	var st := EconomyEngine.state
	if st == null or st.agents.is_empty():
		return
	for i in range(agents_per_batch):
		var idx := _cursor % st.agents.size()
		_cursor += 1
		_decide_async(st.agents[idx])


## 异步决策（fire-and-forget）
func _decide_async(agent: AgentData) -> void:
	var decision: Dictionary = await AgentBrain.decide(agent, EconomyEngine.state)
	if decision.is_empty():
		return
	apply_decision(agent, decision)


## 落地 LLM 决策到经济（公开，便于测试）
func apply_decision(agent: AgentData, decision: Dictionary) -> void:
	var action := str(decision.get("action", "hold"))
	var cid := str(decision.get("commodity", "")).to_lower().strip_edges()
	var price := maxf(0.0, float(decision.get("price", 0.0)))
	var qty := maxf(0.0, float(decision.get("quantity", 0.0)))
	var reason := str(decision.get("reason", ""))

	# 物资名校验：支持 ID 与中文名，统一为 ID；无效则按 hold 处理
	var st := EconomyEngine.state
	if not cid.is_empty() and st != null and not st.commodities.has(cid):
		var c: Commodity = st.find_commodity_by_name(cid)
		cid = c.id if c != null else ""
	if (action == "buy" or action == "sell") and (cid.is_empty() or price <= 0.0 or qty <= 0.0):
		action = "hold"
		GameLog.warn("Agent %s 决策物资非法，回退 hold: %s" % [agent.display_name, cid])

	agent.llm_controlled = true
	agent.last_decision = decision

	match action:
		"work":
			agent.state = AgentData.State.WORKING
		"buy":
			EconomyEngine.place_agent_order(agent, TradeOrder.Type.BUY, cid, price, qty)
			agent.state = AgentData.State.HOARDING
		"sell":
			EconomyEngine.place_agent_order(agent, TradeOrder.Type.SELL, cid, price, qty)
			agent.state = AgentData.State.TRADING
		_:
			agent.state = AgentData.State.IDLE

	MemoryStore.record_behavior(agent.id, action, cid, price, qty)
	SQLiteService.record_behavior(agent.id, action, cid, price, qty, reason, EconomyEngine.state.tick)
	decisions_total += 1
	GameLog.info("Agent %s 决策: %s %s@%.2f x%.0f (%s)" % [agent.display_name, action, cid, price, qty, reason])
