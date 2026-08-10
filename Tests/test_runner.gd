extends Node
## 阶段一自动化测试执行器（作为场景运行）
## 运行方式（项目根目录下）：
##   Godot.exe --headless --path . res://Tests/test_runner.tscn
## 退出码：0 = 全部通过；1 = 存在失败；2 = 超时

const WATCHDOG_SEC := 600.0

var passed: int = 0
var failed: int = 0


func _ready() -> void:
	# 看门狗：防止异常挂起
	get_tree().create_timer(WATCHDOG_SEC).timeout.connect(func() -> void:
		print("!! 测试超时(" + str(WATCHDOG_SEC) + "s) 强制退出")
		get_tree().quit(2)
	)
	_run_all()


func _run_all() -> void:
	print("========== 阶段一自动化测试 ==========")
	await _run_test("LLM 稳定性/结构化输出/中文对话", "res://Tests/test_llm.gd")
	await _run_test("工具调用体系（定义/执行/闭环）", "res://Tests/test_tools.gd")
	print("\n========== 汇总: 通过=%d 失败=%d ==========" % [passed, failed])
	get_tree().quit(0 if failed == 0 else 1)


func _run_test(title: String, script_path: String) -> void:
	print("\n---- " + title + " ----")
	var script: GDScript = load(script_path)
	if script == null:
		print("  [FAIL] 测试脚本加载失败: " + script_path)
		failed += 1
		return
	if not script.can_instantiate():
		print("  [FAIL] 测试脚本无法实例化（可能存在解析错误）: " + script_path)
		failed += 1
		return
	var inst: Node = script.new()
	add_child(inst)
	await inst.run_test(self)
	inst.queue_free()
