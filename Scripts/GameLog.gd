extends Node
## 全局日志单例（Autoload）
## 同时输出到控制台与本地日志文件（user://Data/logs/YYYY-MM-DD.log）。

const LOG_DIR := "user://Data/logs"

var _log_path := ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	var date := Time.get_date_string_from_system()
	_log_path = LOG_DIR.path_join(date + ".log")
	info("========== 日志系统启动 ==========")


func info(msg: String) -> void:
	_write("INFO", msg)


func warn(msg: String) -> void:
	_write("WARN", msg)


func error(msg: String) -> void:
	_write("ERROR", msg)


func debug(msg: String) -> void:
	_write("DEBUG", msg)


func _write(level: String, msg: String) -> void:
	var line := "[%s][%s] %s" % [Time.get_time_string_from_system(), level, msg]
	print(line)
	if _log_path.is_empty():
		return
	var f := FileAccess.open(_log_path, FileAccess.WRITE)
	if f:
		f.store_line(line)
		f.close()
