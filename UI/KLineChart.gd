class_name KLineChart
extends Control
## 经济 K 线可视化（阶段六）：价格走势曲线 + 成交量柱状图
## 支持数据刷新即重绘，为行情回溯/缩放预留。

var bars: Array = []
var line_color := Color(0.4, 0.85, 0.6)
var up_color := Color(0.3, 0.9, 0.55)
var down_color := Color(0.95, 0.35, 0.35)
var grid_color := Color(1, 1, 1, 0.12)


func set_bars(data: Array) -> void:
	bars = data
	queue_redraw()


func _draw() -> void:
	if bars.is_empty():
		draw_string(ThemeDB.fallback_font, Vector2(8, 20), "暂无行情数据",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.65, 0.7))
		return

	var w := size.x
	var h := size.y
	if w <= 1.0 or h <= 1.0:
		return

	var min_p := INF
	var max_p := -INF
	var max_vol := 1.0
	for b in bars:
		min_p = minf(min_p, float(b.close))
		max_p = maxf(max_p, float(b.close))
		max_vol = maxf(max_vol, float(b.volume))
	if is_equal_approx(min_p, max_p):
		max_p = min_p + 1.0

	var chart_h := h * 0.7
	var vol_h := h * 0.25
	var chart_top := h * 0.05

	# 网格
	for i in range(1, 4):
		var gy := lerpf(chart_top, chart_h, float(i) / 4.0)
		draw_line(Vector2(0, gy), Vector2(w, gy), grid_color, 1.0)
	draw_line(Vector2(0, chart_h), Vector2(w, chart_h), Color(1, 1, 1, 0.25), 1.0)

	# 价格曲线
	var prev := Vector2.ZERO
	for i in range(bars.size()):
		var b: MarketBar = bars[i]
		var x := lerpf(0.0, w, float(i) / float(maxi(1, bars.size() - 1)))
		var norm := (float(b.close) - min_p) / (max_p - min_p)
		var y := lerpf(chart_h, chart_top, norm)
		var pt := Vector2(x, y)
		if i > 0:
			draw_line(prev, pt, line_color, 2.0)
		prev = pt

	# 成交量柱
	var bar_w := maxf(1.0, w / float(bars.size()) - 1.0)
	for i in range(bars.size()):
		var b: MarketBar = bars[i]
		var x := lerpf(0.0, w, float(i) / float(maxi(1, bars.size() - 1)))
		var vh := vol_h * (float(b.volume) / max_vol)
		var col := up_color if float(b.close) >= float(b.prev_close) else down_color
		draw_rect(Rect2(x - bar_w / 2.0, chart_h + (vol_h - vh), bar_w, vh), col)

	# 最新价标注
	var last_b: MarketBar = bars[bars.size() - 1]
	draw_string(ThemeDB.fallback_font, Vector2(8, 16), "最新: %.2f" % float(last_b.close),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, line_color)
