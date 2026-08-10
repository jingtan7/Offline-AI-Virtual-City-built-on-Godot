extends Node
## LLM 功能测试：服务就绪 / 稳定推理 / 结构化输出 / 中文对话
## 注意：测试调用使用较小的 token 预算，保证 CPU 环境也能快速完成。

func run_test(reporter: Node) -> void:
	var checks: Array = []
	checks.append(await _check_ready())
	checks.append(await _check_stable_inference())
	checks.append(await _check_structured_output())
	checks.append(await _check_chinese_chat())
	_report(reporter, checks)


## 等待 AI 服务就绪（AIService 探活是异步的，需等它完成）。
func _wait_ai_ready(timeout_sec: float = 30.0) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_sec * 1000.0:
		if AIService.is_ready:
			return true
		await get_tree().create_timer(0.2).timeout
	return AIService.is_ready


func _check_ready() -> Dictionary:
	if await _wait_ai_ready():
		return {"ok": true, "name": "AI 服务已就绪(%s)" % AIService.model}
	return {"ok": false, "name": "AI 服务就绪", "msg": "Ollama 不可达，请先启动 Ollama 并确认模型存在"}


func _check_stable_inference() -> Dictionary:
	if not AIService.is_ready:
		return {"ok": true, "skip": true, "name": "连续 2 次稳定推理", "msg": "AI 服务未就绪，跳过"}
	var fail_msg := ""
	for i in range(2):
		var r: Dictionary = await AIService.llm_client.chat("请只回复两个字：好的", "", "", [], -1.0, 48)
		if not r.get("success", false):
			fail_msg = "第%d次调用失败: %s" % [i + 1, str(r.get("error", "未知"))]
			break
		if str(r.get("content", "")).is_empty():
			fail_msg = "第%d次返回空内容" % (i + 1)
			break
	if fail_msg.is_empty():
		return {"ok": true, "name": "连续 2 次稳定推理"}
	return {"ok": false, "name": "连续 2 次稳定推理", "msg": fail_msg}


func _check_structured_output() -> Dictionary:
	if not AIService.is_ready:
		return {"ok": true, "skip": true, "name": "结构化输出(JSON)", "msg": "AI 服务未就绪，跳过"}
	var prompt := "只输出 JSON，不要输出任何其他文字：{\"action\":\"buy\",\"price\":12.5,\"qty\":10}"
	var r: Dictionary = await AIService.llm_client.chat(prompt, "", AIService.model, [], 0.2, 128)
	if not r.get("success", false):
		return {"ok": false, "name": "结构化输出(JSON)", "msg": "调用失败: " + str(r.get("error"))}
	var parsed: Dictionary = LLMClient.parse_json_object(str(r.get("content", "")))
	if parsed.is_empty():
		return {"ok": false, "name": "结构化输出(JSON)", "msg": "解析失败, content=" + str(r.get("content", "")).substr(0, 200)}
	return {"ok": true, "name": "结构化输出(JSON): " + JSON.stringify(parsed)}


func _check_chinese_chat() -> Dictionary:
	if not AIService.is_ready:
		return {"ok": true, "skip": true, "name": "中文自然对话", "msg": "AI 服务未就绪，跳过"}
	var r: Dictionary = await AIService.llm_client.chat("你好，请用一句话介绍你自己。", "", "", [], -1.0, 96)
	if r.get("success", false) and not str(r.get("content", "")).is_empty():
		return {"ok": true, "name": "中文自然对话"}
	return {"ok": false, "name": "中文自然对话", "msg": str(r.get("error", "空回复"))}


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

