extends Node2D
## 主场景入口：构建横版像素村庄 + 接入仿真与 AI 子系统

var _village: Node2D


func _ready() -> void:
	EconomyEngine.start_auto()
	_village = load("res://Village/VillageDirector.gd").new()
	add_child(_village)
	GameLog.info("主场景就绪（横版像素村庄）")

