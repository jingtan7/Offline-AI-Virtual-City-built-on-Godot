extends Node
## 仿真循环驱动单例（Autoload）
## 主循环心跳：以固定间隔发出 tick 信号，供经济迭代、Agent 轮询、行情刷新使用。

signal tick(tick_index: int, delta: float)

var tick_index: int = 0

var _timer: Timer


func _ready() -> void:
	var interval_ms: int = int(DataManager.get_setting("simulation", "tick_interval_ms", 1000))
	_timer = Timer.new()
	_timer.wait_time = maxf(0.1, float(interval_ms) / 1000.0)
	_timer.autostart = true
	_timer.timeout.connect(_on_tick)
	add_child(_timer)
	GameLog.info("仿真循环启动, tick 间隔=%.1fs" % _timer.wait_time)


func _on_tick() -> void:
	tick_index += 1
	tick.emit(tick_index, _timer.wait_time)


func set_tick_interval(seconds: float) -> void:
	_timer.wait_time = maxf(0.1, seconds)
	GameLog.info("仿真 tick 间隔调整为 %.1fs" % _timer.wait_time)
