extends Node2D
## 主场景入口：启动子系统并装配城邦沙盘 UI（阶段六）

var _city_ui: CanvasLayer


func _ready() -> void:
	EconomyEngine.start_auto()
	_city_ui = load("res://UI/CityUI.gd").new()
	add_child(_city_ui)
	GameLog.info("主场景就绪（沙盘 UI 已装配）")

