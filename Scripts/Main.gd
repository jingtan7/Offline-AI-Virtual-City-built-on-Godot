extends Node2D
## 主场景入口（阶段一：启动状态看板）
## 展示本地 AI 服务初始化结果、工具加载数量与仿真心跳。

@onready var status_label: Label = $CanvasLayer/Panel/VBox/StatusLabel
@onready var detail_label: Label = $CanvasLayer/Panel/VBox/DetailLabel


func _ready() -> void:
	status_label.text = "🏰 城邦引擎启动中…"
	detail_label.text = "模型: %s  端点: %s" % [AIService.model, AIService.endpoint]
	AIService.llm_ready.connect(_on_llm_ready)
	AIService.llm_failed.connect(_on_llm_failed)
	SimulationLoop.tick.connect(_on_tick)
	EconomyEngine.start_auto()
	GameLog.info("主场景就绪（经济引擎已接入仿真循环）")


func _on_llm_ready() -> void:
	status_label.text = "✅ 本地 AI 已就绪：" + AIService.model
	detail_label.text = "工具已加载: %d 个 ｜ 经济仿真运行中" % ToolRunner.tool_definitions.size()


func _on_llm_failed() -> void:
	status_label.text = "⚠️ 本地 AI 启动失败（请检查 Ollama）"
	detail_label.text = "经济仿真仍将运行，详见 logs/ 目录日志"


func _on_tick(tick_index: int, _delta: float) -> void:
	var food: Commodity = EconomyEngine.state.commodities.get("food", null)
	var detail := "仿真心跳 #%d ｜ Agent: %d ｜ 挂单: %d" % [
		tick_index,
		EconomyEngine.state.agents.size(),
		EconomyEngine.state.orders.size(),
	]
	if food != null:
		detail += " ｜ 粮食价: %.2f" % food.current_price
	detail += " ｜ 工具: %d 个" % ToolRunner.tool_definitions.size()
	detail_label.text = detail
