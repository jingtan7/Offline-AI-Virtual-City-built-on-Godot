class_name LLMClient
extends Node
## 离线 LLM 通用调用客户端（Ollama /api/chat）
## 统一入参/出参/异常捕获；支持 Function Calling(tools) 与多轮消息。
## 场景复用：智能体决策 / 自然语言对话 / 结构化数据生成。

signal response_received(result: Dictionary)

var endpoint: String = "http://127.0.0.1:11434"
var default_model: String = "qwen2:7b"
var default_temperature: float = 0.7
var default_max_tokens: int = 1024
var timeout_sec: float = 120.0

var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = timeout_sec
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)


func _on_request_completed(_result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	response_received.emit({})


## 统一调用入口。
## 入参：message 单条用户消息 / system_prompt 系统提示 / messages 完整消息数组(优先) /
##       model 模型 / tools 工具定义 / temperature 温度 / max_tokens 最大生成长度
## 出参：{ success, content, tool_calls, raw, elapsed_ms, error?, model? }
func chat(
	message: String = "",
	system_prompt: String = "",
	model: String = "",
	tools: Array = [],
	temperature: float = -1.0,
	max_tokens: int = -1,
	messages: Array = []
) -> Dictionary:
	var msgs: Array = messages.duplicate()
	if msgs.is_empty():
		if not system_prompt.is_empty():
			msgs.append({"role": "system", "content": system_prompt})
		if not message.is_empty():
			msgs.append({"role": "user", "content": message})

	var body := {
		"model": model if not model.is_empty() else default_model,
		"messages": msgs,
		"stream": false,
		"temperature": temperature if temperature >= 0.0 else default_temperature,
		"options": {"num_predict": max_tokens if max_tokens > 0 else default_max_tokens},
	}
	if not tools.is_empty():
		body["tools"] = tools

	var t0 := Time.get_ticks_msec()
	var err := _http.request(endpoint + "/api/chat", ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		return _make_error("请求发送失败(%d)" % err)

	var result: Array = await _http.request_completed
	var elapsed := Time.get_ticks_msec() - t0

	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return _make_error("网络错误(%d)，Ollama 不可达？" % result[0], elapsed)
	if result[1] != 200:
		return _make_error("HTTP %d: %s" % [result[1], _body_text(result)], elapsed)

	var parsed = JSON.parse_string(_body_text(result))
	if not (parsed is Dictionary):
		return _make_error("响应 JSON 解析失败", elapsed)

	var msg: Dictionary = parsed.get("message", {})
	var out := {
		"success": true,
		"content": str(msg.get("content", "")),
		"tool_calls": msg.get("tool_calls", []),
		"raw": parsed,
		"elapsed_ms": elapsed,
		"model": parsed.get("model", ""),
	}
	response_received.emit(out)
	return out


## 结构化输出调用：返回已解析的 JSON Dictionary；失败时返回 { success:false }。
func chat_structured(message: String, system_prompt: String = "", model: String = "", temperature: float = -1.0) -> Dictionary:
	var r: Dictionary = await chat(message, system_prompt, model, [], temperature, 512)
	if not r.get("success", false):
		return r
	var parsed := parse_json_object(str(r.get("content", "")))
	if parsed.is_empty():
		return {"success": false, "error": "结构化输出解析失败", "content": r.get("content", ""), "raw": r}
	parsed["success"] = true
	return parsed


func _make_error(msg: String, elapsed_ms: int = -1) -> Dictionary:
	return {"success": false, "content": "", "tool_calls": [], "error": msg, "elapsed_ms": elapsed_ms}


func _body_text(result: Array) -> String:
	var body: PackedByteArray = result[3]
	return body.get_string_from_utf8()


## 解析模型输出中的 JSON 对象：支持 ```json 代码围栏与前后杂质文本。
static func parse_json_object(text: String) -> Dictionary:
	var t := text.strip_edges()
	if t.begins_with("```"):
		var nl := t.find("\n")
		if nl != -1:
			t = t.substr(nl + 1)
		t = t.replace("```", "").strip_edges()
	var a := t.find("{")
	var b := t.rfind("}")
	if a != -1 and b > a:
		t = t.substr(a, b - a + 1)
	var parsed = JSON.parse_string(t)
	return parsed if parsed is Dictionary else {}
