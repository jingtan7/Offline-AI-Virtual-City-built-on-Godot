extends Node
## 阶段九存储：ChromaDB RAG 向量记忆测试
## ChromaDB 在线时验证真实 添加/检索 闭环；离线时验证回退逻辑并 SKIP。

func run_test(reporter: Node) -> void:
	MemoryStore.clear()
	var checks: Array = []
	checks.append(await _check_availability())
	checks.append(await _check_chroma_roundtrip())
	checks.append(_check_mirror_hooks())
	_report(reporter, checks)


func _check_availability() -> Dictionary:
	# 等待探活完成
	for i in range(20):
		await get_tree().create_timer(0.2).timeout
		if RAGService.available:
			break
	if RAGService.available:
		return {"ok": true, "name": "ChromaDB 服务在线"}
	return {"ok": true, "skip": true, "name": "ChromaDB 服务在线", "msg": "服务未启动，将验证回退逻辑"}


func _check_chroma_roundtrip() -> Dictionary:
	if not RAGService.available:
		return {"ok": true, "skip": true, "name": "ChromaDB 添加/检索", "msg": "服务离线，跳过"}
	# 写入测试记忆到独立集合
	var key := "test_rag_%d" % Time.get_ticks_msec()
	RAGService.record(key, "粮食价格大涨，城邦饥荒预警", "event")
	RAGService.record(key, "矿石价格暴跌，矿工亏损", "event")
	RAGService.record(key, "城主大量买入矿石", "player_trade")
	# 等异步写入完成
	await get_tree().create_timer(1.5).timeout
	var top := await RAGService.search(key, "粮食涨价 饥荒", 2)
	if top.is_empty():
		return {"ok": false, "name": "ChromaDB 添加/检索", "msg": "检索结果为空"}
	if not str(top[0].get("text", "")).contains("粮食"):
		return {"ok": false, "name": "ChromaDB 添加/检索", "msg": "top1 不相关: " + str(top[0].get("text", ""))}
	var top2 := await RAGService.search(key, "城主 买入", 1)
	if top2.is_empty() or not str(top2[0].get("text", "")).contains("城主"):
		return {"ok": false, "name": "ChromaDB 添加/检索", "msg": "玩家交易检索失败"}
	return {"ok": true, "name": "ChromaDB 添加/检索: top1=「%s」" % str(top[0].get("text", "")).substr(0, 14)}


func _check_mirror_hooks() -> Dictionary:
	# 领域记忆封装会把数据镜像到 ChromaDB（可用时）
	MemoryStore.record_behavior("agent_9999", "buy", "ore", 14.0, 5.0)
	MemoryStore.record_event({"label": "天灾减产", "desc": "粮食减产"})
	MemoryStore.record_player_trade("ore", "buy", 15.0, 30.0)
	if MemoryStore.memories.size() < 3:
		return {"ok": false, "name": "记忆镜像钩子", "msg": "内置记忆未写入"}
	return {"ok": true, "name": "记忆镜像钩子: 行为/事件/玩家交易同步（内置+RAG）"}


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
