extends Node
## 工具执行器单例（Autoload）—— 阶段一工具调用体系
## 职责：
##   1. 加载 AI/tools/*.json 工具定义（LLM Function Calling 声明用）
##   2. 解析 LLM 返回的 tool_calls，安全校验并执行
##   3. 内置工具：market_query / code_execute / optimize_params
##   4. 可选：将工具转发给本地 Python 工具服务（HTTPService）

const TOOLS_DIR := "res://AI/tools"

var tool_definitions: Array = []


func _ready() -> void:
	load_tool_definitions()
	GameLog.info("工具定义加载完成: %d 个" % tool_definitions.size())


## 加载工具定义 JSON 到 tool_definitions。
func load_tool_definitions() -> Array:
	tool_definitions = []
	var dir := DirAccess.open(TOOLS_DIR)
	if dir == null:
		GameLog.warn("工具定义目录不存在: " + TOOLS_DIR)
		return tool_definitions
	for file_name in dir.get_files():
		if not file_name.ends_with(".json"):
			continue
		var f := FileAccess.open(TOOLS_DIR.path_join(file_name), FileAccess.READ)
		if f == null:
			continue
		var parsed = JSON.parse_string(f.get_as_text())
		f.close()
		if parsed is Dictionary and parsed.get("type", "") == "function":
			tool_definitions.append(parsed)
	return tool_definitions


## 执行一次工具调用。tool_call 结构: { "function": { "name": "...", "arguments": {...} } }
func execute(tool_call: Dictionary) -> Dictionary:
	var fn: Dictionary = tool_call.get("function", {})
	var name := str(fn.get("name", ""))
	var args := _normalize_args(fn.get("arguments", {}))

	if name.is_empty():
		return {"success": false, "error": "工具调用缺少名称"}

	# 可选：转发到本地 Python 工具服务
	if _use_remote_tool_server() and name in ["market_query", "code_execute", "optimize_params"]:
		return await AIService.tool_service.call_tool(name, args)

	match name:
		"market_query":
			return await _market_query(args)
		"code_execute":
			return await _code_execute(args)
		"optimize_params":
			return await _optimize_params(args)
		_:
			return {"success": false, "error": "未知工具: " + name}


## 行情查询：优先返回经济引擎实时数据（阶段三），引擎不可用时回退示例数据。
func _market_query(args: Dictionary) -> Dictionary:
	var commodity := str(args.get("commodity", "")).strip_edges()

	var engine := get_node_or_null("/root/EconomyEngine")
	if engine != null:
		var st: CityState = engine.get("state")
		if st != null:
			var c: Commodity = st.find_commodity_by_name(commodity)
			if c != null:
				var bar := st.latest_bar(c.id)
				var gap := 0.0
				var trend := "横盘"
				if bar != null:
					gap = bar.supply_demand_gap
					var chg := bar.change_pct()
					trend = "上涨" if chg > 1.0 else ("下跌" if chg < -1.0 else "横盘")
				return {
					"success": true,
					"commodity": c.name,
					"price": c.current_price,
					"base_price": c.base_price,
					"supply": c.total_stock,
					"demand": maxf(0.0, c.total_stock + gap),
					"trend": trend,
				}

	# 兜底：示例数据
	var market := {
		"粮食": {"price": 12.5, "supply": 3200, "demand": 3050, "trend": "横盘"},
		"木材": {"price": 8.2, "supply": 2100, "demand": 2400, "trend": "上涨"},
		"矿石": {"price": 15.0, "supply": 900, "demand": 1300, "trend": "上涨"},
		"药剂": {"price": 32.0, "supply": 400, "demand": 380, "trend": "横盘"},
		"工具": {"price": 25.5, "supply": 300, "demand": 350, "trend": "下跌"},
	}
	if market.has(commodity):
		var data: Dictionary = market[commodity].duplicate()
		data["commodity"] = commodity
		data["success"] = true
		return data
	return {"success": false, "error": "未知物资: " + commodity}


## 代码执行（沙箱实验）：调用本机 Python 执行代码片段，超时与输出受限。
func _code_execute(args: Dictionary) -> Dictionary:
	var code := str(args.get("code", "")).strip_edges()
	if code.is_empty():
		return {"success": false, "error": "缺少 code 参数"}

	var timeout_ms: int = int(args.get("timeout_ms", 0))
	if timeout_ms <= 0:
		timeout_ms = int(DataManager.get_setting("tools", "code_execute_timeout_ms", 3000))

	var python_exe := find_python()
	if python_exe.is_empty():
		return {"success": false, "error": "未找到 Python 解释器（code_execute 需要）"}

	# 临时脚本与输出文件
	var work_dir := "user://Data/tools"
	DirAccess.make_dir_recursive_absolute(work_dir)
	var stamp := str(Time.get_ticks_usec())
	var script_path := work_dir.path_join("run_" + stamp + ".py")
	var out_path := work_dir.path_join("out_" + stamp + ".txt")

	var f := FileAccess.open(script_path, FileAccess.WRITE)
	if f == null:
		return {"success": false, "error": "无法创建临时脚本"}
	f.store_string(code)
	f.close()

	var args_list := PackedStringArray([
		"/c", python_exe,
		"\"" + ProjectSettings.globalize_path(script_path) + "\"",
		">", "\"" + ProjectSettings.globalize_path(out_path) + "\"", "2>&1",
	])
	var pid: int = OS.execute("cmd", args_list, [], false)

	# 轮询等待 + 超时强杀
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_ms:
		if not OS.is_process_running(pid):
			break
		await get_tree().create_timer(0.1).timeout

	if OS.is_process_running(pid):
		OS.kill(pid)
		return {"success": false, "error": "代码执行超时(%dms)" % timeout_ms}

	var output := ""
	if FileAccess.file_exists(out_path):
		var rf := FileAccess.open(out_path, FileAccess.READ)
		output = rf.get_as_text()
		rf.close()
	return {"success": true, "output": output.substr(0, 8000)}


## 参数优化（示例算法）：对单变量目标表达式做网格寻优。
func _optimize_params(args: Dictionary) -> Dictionary:
	var objective := str(args.get("objective", "")).strip_edges()
	if objective.is_empty():
		return {"success": false, "error": "缺少 objective 表达式，示例: \"(x-3)*(x-3)+2\" 求最小值"}
	var mode := str(args.get("mode", "min"))
	var lo := float(args.get("range_lo", -10.0))
	var hi := float(args.get("range_hi", 10.0))
	var steps := maxi(1, int(args.get("steps", 200)))

	var best_x := lo
	var best_v := INF if mode == "min" else -INF
	var expr := Expression.new()
	var parse_err := expr.parse(objective, PackedStringArray(["x"]))
	if parse_err != OK:
		return {"success": false, "error": "表达式解析失败: " + expr.get_error_text()}

	for i in range(steps + 1):
		var x := lo + (hi - lo) * float(i) / float(steps)
		var v = expr.execute([x])
		if v == null:
			return {"success": false, "error": "表达式执行失败: " + expr.get_error_text()}
		var fv := float(v)
		if (mode == "min" and fv < best_v) or (mode == "max" and fv > best_v):
			best_v = fv
			best_x = x

	return {"success": true, "best_x": best_x, "best_value": best_v, "range": [lo, hi], "steps": steps}


func _normalize_args(raw) -> Dictionary:
	if raw is Dictionary:
		return raw
	if raw is String and not (raw as String).is_empty():
		var parsed = JSON.parse_string(raw as String)
		return parsed if parsed is Dictionary else {}
	return {}


func _use_remote_tool_server() -> bool:
	return AIService.tool_service != null and is_instance_valid(AIService.tool_service)


## 查找 Python 解释器：常见安装路径 + PATH 探测。
static func find_python() -> String:
	var candidates: PackedStringArray = [
		"C:/Program Files/Python314/python.exe",
		"C:/Program Files/Python313/python.exe",
		"C:/Users/" + OS.get_environment("USERNAME") + "/AppData/Local/Programs/Python/Python314/python.exe",
		"C:/Users/" + OS.get_environment("USERNAME") + "/AppData/Local/Programs/Python/Python313/python.exe",
	]
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	var out: Array = [""]
	var code := OS.execute("python", ["-c", "import sys;print(sys.executable)"], out, true)
	if code == 0 and out.size() > 1:
		return str(out[out.size() - 1]).strip_edges()
	return ""
