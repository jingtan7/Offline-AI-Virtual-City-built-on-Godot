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
	var cid := str(decision.get("commodity", ""))
	var price := float(decision.get("price", 0.0))
	var qty := float(decision.get("quantity", 0.0))
	var reason := str(decision.get("reason", ""))

	agent.llm_controlled = true
	agent.last_decision = decision

	match action:
		"work":
			agent.state = AgentData.State.WORKING
		"buy":
			if cid.is_empty() or price <= 0.0 or qty <= 0.0:
				agent.state = AgentData.State.IDLE
			else:
				EconomyEngine.place_agent_order(agent, TradeOrder.Type.BUY, cid, price, qty)
				agent.state = AgentData.State.HOARDING
		"sell":
			if cid.is_empty() or price <= 0.0 or qty <= 0.0:
				agent.state = AgentData.State.IDLE
			else:
				EconomyEngine.place_agent_order(agent, TradeOrder.Type.SELL, cid, price, qty)
				agent.state = AgentData.State.TRADING
		_:
			agent.state = AgentData.State.IDLE

	MemoryStore.record_behavior(agent.id, action, cid, price, qty)
	decisions_total += 1
	GameLog.info("Agent %s 决策: %s %s@%.2f x%.0f (%s)" % [agent.display_name, action, cid, price, qty, reason])
