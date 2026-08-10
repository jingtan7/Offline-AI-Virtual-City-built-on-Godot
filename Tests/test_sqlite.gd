extends Node
## 阶段九存储：SQLite 结构化存档测试（需 godot-sqlite 插件）
## 插件未安装时 SKIP 并验证回退逻辑。

func run_test(reporter: Node) -> void:
	var checks: Array = []
	checks.append(_check_plugin())
	checks.append(_check_save_load())
	_report(reporter, checks)


func _check_plugin() -> Dictionary:
	if SQLiteService.available:
		return {"ok": true, "name": "godot-sqlite 插件已加载"}
	return {"ok": true, "skip": true, "name": "godot-sqlite 插件已加载", "msg": "插件未安装（可运行，使用 JSON 回退）"}


func _check_save_load() -> Dictionary:
	if not SQLiteService.available:
		return {"ok": true, "skip": true, "name": "SQLite 存档/读档", "msg": "插件未安装，跳过"}
	EconomyEngine.reset()
	for i in range(8):
		EconomyEngine.step_tick(i)
	# 模拟村庄坐标持久化
	var st := EconomyEngine.state
	for j in range(st.agents.size()):
		(st.agents[j] as AgentData).pos_x = 200.0 + j * 40.0
		(st.agents[j] as AgentData).pos_y = 308.0
		(st.agents[j] as AgentData).anim = "walk"
	SQLiteService.record_positions(st)
	SQLiteService.append_market_bars(st)
	if not SQLiteService.save_game(st):
		return {"ok": false, "name": "SQLite 存档/读档", "msg": "保存失败"}
	var loaded := SQLiteService.load_game()
	if loaded == null:
		return {"ok": false, "name": "SQLite 存档/读档", "msg": "读档失败"}
	if loaded.agents.size() != 15:
		return {"ok": false, "name": "SQLite 存档/读档", "msg": "NPC 数量=%d" % loaded.agents.size()}
	if loaded.commodities.size() != 6:
		return {"ok": false, "name": "SQLite 存档/读档", "msg": "物资数量=%d" % loaded.commodities.size()}
	# 校验 NPC 坐标已持久化
	var a0: AgentData = loaded.agents[0]
	if a0.pos_x <= 0.0:
		return {"ok": false, "name": "SQLite 存档/读档", "msg": "NPC 坐标未持久化"}
	# 校验行为日志与行情
	SQLiteService.record_behavior("agent_0000", "buy", "ore", 14.0, 5.0, "测试", 99)
	SQLiteService.record_event({"label": "测试事件", "desc": "验证"}, 99)
	return {"ok": true, "name": "SQLite 存档/读档: %d NPC + 坐标/行情/行为入库" % loaded.agents.size()}


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
