class_name HTTPService
extends Node
## 本地工具服务客户端（进阶项）
## 管理 Python 工具服务进程 + 通过 HTTP 调用其暴露的工具接口。
## 默认端口 8770，仅监听 127.0.0.1（纯本机回环，符合离线要求）。

var base_url := "http://127.0.0.1:8770"
var server_pid: int = -1

var _http: HTTPRequest


func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)


## 启动 Python 工具服务进程（非阻塞）。
func start_server(port: int = 8770) -> bool:
	base_url = "http://127.0.0.1:%d" % port
	var python_exe := find_python()
	if python_exe.is_empty():
		GameLog.error("工具服务: 未找到 Python")
		return false
	var script := ProjectSettings.globalize_path("res://Tools/tool_server/tool_server.py")
	var pid: int = OS.execute(python_exe, [script, "--port", str(port)], [], false)
	if pid == 0:
		GameLog.error("工具服务: 进程启动失败")
		return false
	server_pid = pid
	GameLog.info("工具服务已启动: %s (pid=%d)" % [base_url, pid])
	return true


func stop_server() -> void:
	if server_pid != -1:
		OS.kill(server_pid)
		server_pid = -1


## 调用工具服务上的工具。返回 { success, ... }。
func call_tool(name: String, args: Dictionary) -> Dictionary:
	var body := JSON.stringify({"name": name, "arguments": args})
	var err := _http.request(base_url + "/tools/call", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		return {"success": false, "error": "工具服务请求失败(%d)" % err}
	var result: Array = await _http.request_completed
	if result[0] != HTTPRequest.RESULT_SUCCESS:
		return {"success": false, "error": "工具服务连接失败(%d)，服务未启动？" % result[0]}
	var text: String = (result[3] as PackedByteArray).get_string_from_utf8()
	var parsed = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {"success": false, "error": "工具服务响应解析失败", "raw": text.substr(0, 500)}


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
