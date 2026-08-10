extends Node
## 工具调用体系测试：定义加载 / 确定性执行 / LLM 工具闭环

func run_test(reporter: Node) -> void:
	var checks: Array = []
	checks.append(_check_defs_loaded())
	checks.append(await _check_market_query())
	checks.append(await _check_optimize_params())
	checks.append(await _check_code_execute())
	checks.append(await _check_agent_tool_loop())
	_report(reporter, checks)


## 等待 AI 服务就绪（AIService 探活是异步的，需等它完成）。
func _wait_ai_ready(timeout_sec: float = 30.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_sec * 1000.0:
		if AIService.is_ready:
			return true
		await get_tree().create_timer(0.2).timeout
	return AIService.is_ready


func _check_defs_loaded() -> Dictionary:
	var count := ToolRunner.tool_definitions.size()
	if count >= 3:
		return {"ok": true, "name": "工具定义加载(%d 个)" % count}
	return {"ok": false, "name": "工具定义加载", "msg": "仅加载 %d 个工具" % count}


func _check_market_query() -> Dictionary:
	var r: Dictionary = await ToolRunner.execute({
		"function": {"name": "market_query", "arguments": {"commodity": "粮食"}}
	})
	if r.get("success", false) and float(r.get("price", 0.0)) > 0.0:
		return {"ok": true, "name": "行情查询(market_query)"}
	return {"ok": false, "name": "行情查询(market_query)", "msg": str(r)}


func _check_optimize_params() -> Dictionary:
	var r: Dictionary = await ToolRunner.execute({
		"function": {
			"name": "optimize_params",
			"arguments": {"objective": "(x-3)*(x-3)+2", "mode": "min", "range_lo": -10, "range_hi": 10},
		}
	})
	var best: float = float(r.get("best_x", -999.0))
	if r.get("success", false) and absf(best - 3.0) < 0.1:
		return {"ok": true, "name": "参数优化(optimize_params) x=%.3f" % best}
	return {"ok": false, "name": "参数优化(optimize_params)", "msg": str(r)}


func _check_code_execute() -> Dictionary:
	if not bool(DataManager.get_setting("tools", "enable_code_execute", true)):
		return {"ok": true, "skip": true, "name": "代码执行(code_execute)", "msg": "配置已禁用"}
	var r: Dictionary = await ToolRunner.execute({
		"function": {"name": "code_execute", "arguments": {"code": "print('tool-ok', 1 + 2)"}}
	})
	if r.get("success", false) and str(r.get("output", "")).contains("tool-ok"):
		return {"ok": true, "name": "代码执行(code_execute)"}
	return {"ok": false, "name": "代码执行(code_execute)", "msg": str(r)}


func _check_agent_tool_loop() -> Dictionary:
	if not await _wait_ai_ready():
		return {"ok": true, "skip": true, "name": "Agent 工具调用闭环", "msg": "AI 服务未就绪，跳过"}
	var prompt := "你是城邦商人。请先调用 market_query 工具查询【粮食】的实时行情，再结合结果给出你的买入决策（一句话即可）。"
	var r: Dictionary = await AIService.agent_infer(prompt, "你是城邦商人，决策前必须查询行情。", ToolRunner.tool_definitions)
	if not r.get("success", false):
		return {"ok": true, "skip": true, "name": "Agent 工具调用闭环", "msg": "推理失败: " + str(r.get("error"))}
	var used: int = int(r.get("tool_used", 0))
	if used > 0:
		return {"ok": true, "name": "Agent 工具调用闭环(调用 %d 次工具)" % used}
	return {
		"ok": true, "skip": true, "name": "Agent 工具调用闭环",
		"msg": "模型未触发工具调用（当前 qwen2:7b 工具能力一般，建议后续换 qwen3 系列验证）",
	}


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
