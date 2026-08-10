extends Node
## 全局应用管理器（Autoload）
## 项目生命周期管理：启动自检、统一退出入口、场景切换预留。

func _ready() -> void:
	GameLog.info("AppManager 就绪 —— 离线 AI 虚拟城邦 启动")
	_bootstrap()


func _bootstrap() -> void:
	GameLog.info("配置节点: %s ｜ AI 模型: %s ｜ 工具开关: code_execute=%s" % [
		DataManager.settings.size(),
		AIService.model,
		DataManager.get_setting("tools", "enable_code_execute", true),
	])


## 统一退出入口：先关 AI 进程，再退出游戏。
func quit(exit_code: int = 0) -> void:
	GameLog.info("应用退出, code=%d" % exit_code)
	AIService.shutdown()
	get_tree().quit(exit_code)
