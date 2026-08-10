extends Node
## 全局数据管理单例（Autoload）
## 配置读取（res:// 默认值 + user:// 覆盖合并）、JSON 存档基础能力。

const DEFAULT_CONFIG := "res://Data/config/settings.json"
const USER_CONFIG := "user://Data/config/settings.json"

var settings: Dictionary = {}


func _ready() -> void:
	load_settings()
	GameLog.info("配置已加载: %d 个配置键" % settings.size())


## 加载配置：res:// 默认配置 与 user:// 用户配置做深合并，用户配置优先。
func load_settings() -> Dictionary:
	var merged: Dictionary = _read_json(DEFAULT_CONFIG)
	var user := _read_json(USER_CONFIG)
	merged = _deep_merge(merged, user)
	settings = merged
	return settings


## 保存用户配置到 user://Data/config/settings.json（导出后 res:// 只读）。
func save_settings() -> bool:
	DirAccess.make_dir_recursive_absolute("user://Data/config")
	var f := FileAccess.open(USER_CONFIG, FileAccess.WRITE)
	if f == null:
		GameLog.error("配置保存失败: " + USER_CONFIG)
		return false
	f.store_string(JSON.stringify(settings, "\t"))
	f.close()
	GameLog.info("配置已保存到: " + USER_CONFIG)
	return true


func get_setting(section: String, key: String, default_value = null):
	return settings.get(section, {}).get(key, default_value)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	return parsed if parsed is Dictionary else {}


func _deep_merge(base: Dictionary, override: Dictionary) -> Dictionary:
	var result: Dictionary = base.duplicate(true)
	for k in override:
		if override[k] is Dictionary and result.get(k) is Dictionary:
			result[k] = _deep_merge(result[k], override[k])
		else:
			result[k] = override[k]
	return result
