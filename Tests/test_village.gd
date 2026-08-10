extends Node
## 阶段九横版：像素村庄测试
## 覆盖：村庄构建 / NPC 移动 / 动画切换 / 决策映射 / 坐标同步

func run_test(reporter: Node) -> void:
	EconomyEngine.reset()
	var checks: Array = []
	checks.append(await _check_village_builds())
	checks.append(await _check_npc_animations())
	checks.append(await _check_npc_movement())
	checks.append(await _check_decision_mapping())
	checks.append(await _check_pos_sync())
	_report(reporter, checks)


func _build_village() -> Node2D:
	var v: Node2D = load("res://Village/VillageDirector.gd").new()
	v.paused = true  # 测试中暂停导演自主调度，保证确定性
	add_child(v)
	return v


func _check_village_builds() -> Dictionary:
	var v: Node2D = _build_village()
	await get_tree().process_frame
	await get_tree().process_frame
	if v.npcs.size() != 15:
		return {"ok": false, "name": "村庄构建", "msg": "NPC数=%d" % v.npcs.size()}
	if v.tilemap == null or v.camera == null or v.hud == null:
		return {"ok": false, "name": "村庄构建", "msg": "地图/相机/HUD 缺失"}
	if v.camera.zoom != Vector2(2, 2):
		return {"ok": false, "name": "村庄构建", "msg": "相机缩放错误"}
	v.queue_free()
	return {"ok": true, "name": "村庄构建: 15 NPC + 地图 + 相机 + HUD"}


func _check_npc_animations() -> Dictionary:
	var v: Node2D = _build_village()
	await get_tree().process_frame
	var npc: VillageNPC = v.npcs[0]
	npc.walk_to(npc.position.x + 100.0, "test")
	if npc.sprite.animation != "walk" or npc.state != VillageNPC.State.WALK:
		return {"ok": false, "name": "NPC动画切换", "msg": "walk 未生效"}
	npc.do_work(3.0)
	if npc.sprite.animation != "work" or npc.state != VillageNPC.State.WORK:
		return {"ok": false, "name": "NPC动画切换", "msg": "work 未生效"}
	npc.to_idle()
	if npc.sprite.animation != "idle" or npc.state != VillageNPC.State.IDLE:
		return {"ok": false, "name": "NPC动画切换", "msg": "idle 未生效"}
	v.queue_free()
	return {"ok": true, "name": "NPC动画切换: walk/work/idle"}


func _check_npc_movement() -> Dictionary:
	var v: Node2D = _build_village()
	await get_tree().process_frame
	var npc: VillageNPC = v.npcs[1]
	var start_x: float = npc.position.x
	npc.walk_to(start_x + 400.0, "test")
	await get_tree().create_timer(0.6).timeout
	if npc.position.x <= start_x + 10.0:
		return {"ok": false, "name": "NPC横向移动", "msg": "未移动: %.1f -> %.1f" % [start_x, npc.position.x]}
	v.queue_free()
	return {"ok": true, "name": "NPC横向移动: %.0f -> %.0f" % [start_x, npc.position.x]}


func _check_decision_mapping() -> Dictionary:
	var v: Node2D = _build_village()
	v.paused = false
	await get_tree().process_frame
	var agent: AgentData = EconomyEngine.state.agents[0]
	var npc: VillageNPC = v.npcs[0]
	agent.state = AgentData.State.WORKING
	v._on_tick(1, 0.0)
	if npc.state != VillageNPC.State.WALK:
		return {"ok": false, "name": "决策→行动映射", "msg": "WORKING 未触发行走"}
	if absf(npc.target_x - npc.work_x) > 1.0:
		return {"ok": false, "name": "决策→行动映射", "msg": "目标点错误: %.0f vs work_x=%.0f" % [npc.target_x, npc.work_x]}
	# 交易状态 → 去集市
	agent.state = AgentData.State.TRADING
	npc.to_idle()
	v._on_tick(2, 0.0)
	if absf(npc.target_x - 2050.0) > 1.0:
		return {"ok": false, "name": "决策→行动映射", "msg": "TRADING 未去集市"}
	v.queue_free()
	return {"ok": true, "name": "决策→行动映射: WORKING→工作点 / TRADING→集市"}


func _check_pos_sync() -> Dictionary:
	var v: Node2D = _build_village()
	v.paused = false
	await get_tree().process_frame
	var agent: AgentData = EconomyEngine.state.agents[2]
	var npc: VillageNPC = v.npcs[2]
	v._on_tick(3, 0.0)
	if not is_equal_approx(agent.pos_x, npc.position.x):
		return {"ok": false, "name": "坐标同步", "msg": "pos_x=%.1f != npc=%.1f" % [agent.pos_x, npc.position.x]}
	if agent.anim != npc.sprite.animation:
		return {"ok": false, "name": "坐标同步", "msg": "anim 未同步"}
	v.queue_free()
	return {"ok": true, "name": "坐标同步: pos_x/anim 写回数据层"}


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
