extends SceneTree
## 临时诊断脚本：验证 Godot headless 模式下 HTTPRequest 访问本地 Ollama 是否正常
## 运行: Godot.exe --headless --path . -s res://Tests/probe_test.gd


func _initialize() -> void:
	call_deferred("_run_probe")


func _run_probe() -> void:
	print("=== Godot HTTP 探活诊断 ===")
	var http := HTTPRequest.new()
	http.timeout = 5.0
	root.add_child(http)

	var err := http.request("http://127.0.0.1:11434/api/tags", [], HTTPClient.METHOD_GET)
	print("request() err = ", err, " (OK=", OK, ")")

	var result: Array = await http.request_completed
	print("RESULT_CODE = ", result[0], " (SUCCESS=", HTTPRequest.RESULT_SUCCESS, ")")
	print("HTTP_CODE   = ", result[1])
	var body: String = (result[3] as PackedByteArray).get_string_from_utf8()
	print("BODY[:200]  = ", body.substr(0, 200))
	quit()
