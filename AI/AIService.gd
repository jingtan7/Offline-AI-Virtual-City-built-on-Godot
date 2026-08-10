extends Node
## AI 服务单例（Autoload）—— 阶段一核心
## 职责：
##   1. Ollama 进程托管：启动探活 → 自动拉起 → 保活 → 退出销毁（游戏启动自动唤醒 LLM）
##   2. 持有 LLMClient 统一调用客户端（离线 /api/chat）
##   3. agent_infer：LLM 决策 + Function Calling 工具调用闭环（工具调用接口封装）

signal llm_ready
signal llm_failed

const DEFAULT_ENDPOINT := "http://127.0.0.1:11434"
const MAX_TOOL_ROUNDS := 4
const PROBE_TIMEOUT_SEC := 3.0
const START_RETRY_COUNT := 8

var endpoint: String = DEFAULT_ENDPOINT
var model: String = "qwen2:7b"
var temperature: float = 0.7
var max_tokens: int = 1024
var is_ready: bool = false

var llm_client: LLMClient
var tool_service: HTTPService

var ollama_pid: int = -1

var _probe_http: HTTPRequest


func _ready() -> void:
	var cfg: Dictionary = DataManager.settings.get("llm", {})
	endpoint = str(cfg.get("endpoint", DEFAULT_ENDPOINT))
	model = str(cfg.get("model", "qwen2:7b"))
	temperature = float(cfg.get("temperature", 0.7))
	max_tokens = int(cfg.get("max_tokens", 1024))

	llm_client = LLMClient.new()
	llm_client.endpoint = endpoint
	llm_client.default_model = model
	llm_client.default_temperature = temperature
	llm_client.default_max_tokens = max_tokens
	add_child(llm_client)

	GameLog.info("AI 服务初始化: 模型=%s 端点=%s" % [model, endpoint])
	start()


## 启动 AI 服务：探测 Ollama，不可用则自动拉起进程并重试。
func start() -> void:
	GameLog.info("AI 服务启动：探测 Ollama…")
	if await _probe():
		is_ready = true
		GameLog.info("✅ Ollama 在线，AI 服务就绪: %s" % model)
		_maybe_start_tool_server()
		llm_ready.emit()
		return

	GameLog.warn("Ollama 未响应，尝试自动拉起进程…")
	_spawn_ollama()
	for i in range(START_RETRY_COUNT):
		await get_tree().create_timer(1.0).timeout
		if await _probe():
			is_ready = true
			GameLog.info("✅ 已自动拉起 Ollama，AI 服务就绪: %s" % model)
			_maybe_start_tool_server()
			llm_ready.emit()
			return
	GameLog.error("AI 服务启动失败：Ollama 不可达（请检查安装与模型）")
	llm_failed.emit()


## 关闭 AI 服务：停止工具服务、销毁本服务拉起的 Ollama 进程。
func shutdown() -> void:
	is_ready = false
	if tool_service != null and is_instance_valid(tool_service):
		tool_service.stop_server()
		GameLog.info("本地工具服务已停止")
	if ollama_pid != -1:
		OS.kill(ollama_pid)
		GameLog.info("Ollama 进程已销毁 (pid=%d)" % ollama_pid)
		ollama_pid = -1


func _exit_tree() -> void:
	shutdown()


## Agent 推理闭环：感知 → LLM 决策 → 工具执行 → 结果回填 → 最终回答。
## 返回: { success, content, tool_used, executions, error? }
func agent_infer(user_message: String, system_prompt := "", tools: Array = [], max_rounds: int = MAX_TOOL_ROUNDS) -> Dictionary:
	if not is_ready:
		return {"success": false, "error": "AI 服务未就绪"}

	var messages: Array = []
	if not system_prompt.is_empty():
		messages.append({"role": "system", "content": system_prompt})
	messages.append({"role": "user", "content": user_message})

	var executions: Array = []
	var final_content := ""

	for i in range(max_rounds):
		var resp: Dictionary = await llm_client.chat("", "", model, tools, -1.0, -1, messages)
		if not resp.get("success", false):
			return {"success": false, "error": resp.get("error", "未知错误"), "executions": executions}

		final_content = str(resp.get("content", ""))
		var tool_calls: Array = resp.get("tool_calls", [])
		if tool_calls.is_empty():
			return {"success": true, "content": final_content, "tool_used": executions.size(), "executions": executions}

		# LLM 请求调用工具：记录工具调用并执行
		messages.append({"role": "assistant", "content": final_content, "tool_calls": _sanitize_tool_calls(tool_calls)})
		for tc in tool_calls:
			var fn: Dictionary = tc.get("function", {})
			var tool_name := str(fn.get("name", ""))
			var result: Dictionary = await ToolRunner.execute(tc)
			executions.append({"name": tool_name, "result": result})
			messages.append({"role": "tool", "name": tool_name, "content": JSON.stringify(result)})

	GameLog.warn("Agent 推理达到最大工具轮次 %d" % max_rounds)
	return {"success": true, "content": final_content, "tool_used": executions.size(), "executions": executions, "truncated": true}


## 净化 tool_calls 后回传给 Ollama：去掉 index 等元数据字段，
## 避免 Godot 序列化产生 "0.0" 导致 Ollama 严格反序列化失败（HTTP 400）。
func _sanitize_tool_calls(tool_calls: Array) -> Array:
	var out: Array = []
	for tc in tool_calls:
		var fn: Dictionary = tc.get("function", {})
		var args = fn.get("arguments", {})
		if args is String and not (args as String).is_empty():
			var parsed = JSON.parse_string(args as String)
			args = parsed if parsed is Dictionary else {}
		out.append({
			"function": {
				"name": str(fn.get("name", "")),
				"arguments": args,
			}
		})
	return out


## 探测 Ollama 是否在线（GET /api/tags 返回 200）。
func _probe() -> bool:
	if _probe_http == null or not is_instance_valid(_probe_http):
		_probe_http = HTTPRequest.new()
		_probe_http.timeout = PROBE_TIMEOUT_SEC
		add_child(_probe_http)
	var err := _probe_http.request(endpoint + "/api/tags", [], HTTPClient.METHOD_GET)
	if err != OK:
		return false
	var result: Array = await _probe_http.request_completed
	return result.size() >= 3 and result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200


## 拉起 Ollama 后台进程（仅当本服务启动了它，退出时才负责销毁）。
func _spawn_ollama() -> void:
	var exe := _find_ollama_exe()
	if exe.is_empty():
		GameLog.error("未找到 ollama.exe，请先安装 Ollama 或手动启动")
		return
	var pid: int = OS.create_process(exe, ["serve"], false)
	if pid != -1:
		ollama_pid = pid
		GameLog.info("已拉起 Ollama 进程, pid=%d" % pid)
	else:
		GameLog.error("Ollama 进程启动失败: %s" % exe)


func _find_ollama_exe() -> String:
	var candidates: PackedStringArray = [
		"ollama",
		OS.get_environment("LOCALAPPDATA") + "/Programs/Ollama/ollama.exe",
		"C:/Program Files/Ollama/ollama.exe",
	]
	for c in candidates:
		if FileAccess.file_exists(c):
			return c
	return ""


## 可选：本地 Python 工具服务（进阶项），由配置 tools.tool_server_enabled 控制。
func _maybe_start_tool_server() -> void:
	if not bool(DataManager.get_setting("tools", "tool_server_enabled", false)):
		return
	var port: int = int(DataManager.get_setting("tools", "tool_server_port", 8770))
	tool_service = HTTPService.new()
	add_child(tool_service)
	if tool_service.start_server(port):
		GameLog.info("本地工具服务已启动: http://127.0.0.1:%d" % port)
