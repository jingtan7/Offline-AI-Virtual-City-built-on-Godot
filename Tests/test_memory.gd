extends Node
## 阶段五：本地 RAG 记忆与自适应博弈测试
## 覆盖：向量确定性 / 检索相关性 / 行为事件入库 / 玩家习惯自适应 / 持久化

func run_test(reporter: Node) -> void:
	MemoryStore.clear()
	var checks: Array = []
	checks.append(_check_embed_determinism())
	checks.append(_check_search_relevance())
	checks.append(_check_record_behaviors())
	checks.append(_check_player_habit_adaptive())
	checks.append(_check_persistence())
	_report(reporter, checks)


func _check_embed_determinism() -> Dictionary:
	var a := MemoryStore.embed("粮食价格上涨，市场火热")
	var b := MemoryStore.embed("粮食价格上涨，市场火热")
	if a != b:
		return {"ok": false, "name": "向量确定性", "msg": "同文本向量不一致"}
	var c := MemoryStore.embed("矿石价格暴跌")
	if a == c:
		return {"ok": false, "name": "向量确定性", "msg": "不同文本向量相同"}
	if cosine_norm(a) <= 0.99:
		return {"ok": false, "name": "向量确定性", "msg": "向量未归一化"}
	return {"ok": true, "name": "向量确定性: 同文同向量/已归一化"}


func _check_search_relevance() -> Dictionary:
	MemoryStore.clear()
	MemoryStore.add_memory("粮食价格大涨，城邦饥荒预警", "event")
	MemoryStore.add_memory("矿石价格暴跌，矿工亏损", "event")
	MemoryStore.add_memory("城主颁布粮食限购令", "event")
	var top := MemoryStore.search("粮食涨价 饥荒", 1)
	if top.is_empty():
		return {"ok": false, "name": "检索相关性", "msg": "无检索结果"}
	if not str(top[0].get("text", "")).contains("粮食"):
		return {"ok": false, "name": "检索相关性", "msg": "检索结果不相关: " + str(top[0].get("text", ""))}
	return {"ok": true, "name": "检索相关性: top1=「%s」" % str(top[0].get("text", "")).substr(0, 20)}


func _check_record_behaviors() -> Dictionary:
	MemoryStore.clear()
	MemoryStore.record_behavior("agent_0001", "buy", "ore", 14.0, 10.0)
	MemoryStore.record_behavior("agent_0002", "sell", "tool", 28.0, 5.0)
	MemoryStore.record_event({"label": "天灾减产", "desc": "粮食减产"})
	if MemoryStore.memories.size() != 3:
		return {"ok": false, "name": "行为/事件入库", "msg": "记忆条数=%d" % MemoryStore.memories.size()}
	return {"ok": true, "name": "行为/事件入库: 3条记忆已写入"}


func _check_player_habit_adaptive() -> Dictionary:
	MemoryStore.clear()
	MemoryStore.record_player_trade("ore", "buy", 15.0, 50.0)
	var top := MemoryStore.search("城主 买入 矿石", 1)
	if top.is_empty() or str(top[0].get("category", "")) != "player_trade":
		return {"ok": false, "name": "玩家习惯自适应", "msg": "玩家交易记忆未被检索到"}
	return {"ok": true, "name": "玩家习惯自适应: Agent可检索城主操作"}


func _check_persistence() -> Dictionary:
	MemoryStore.clear()
	MemoryStore.add_memory("粮食价格持续上涨", "event")
	MemoryStore.add_memory("城主大量买入矿石", "player_trade")
	if not MemoryStore.save_db():
		return {"ok": false, "name": "记忆持久化", "msg": "保存失败"}
	MemoryStore.clear()
	MemoryStore.load_db()
	if MemoryStore.memories.size() != 2:
		return {"ok": false, "name": "记忆持久化", "msg": "读档条数=%d" % MemoryStore.memories.size()}
	var top := MemoryStore.search("矿石 城主 买入", 1)
	if top.is_empty() or not str(top[0].get("text", "")).contains("矿石"):
		return {"ok": false, "name": "记忆持久化", "msg": "读档后检索失效"}
	return {"ok": true, "name": "记忆持久化: 存读档+检索可用"}


func cosine_norm(v: PackedFloat32Array) -> float:
	var s := 0.0
	for i in range(v.size()):
		s += v[i] * v[i]
	return sqrt(s)


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
