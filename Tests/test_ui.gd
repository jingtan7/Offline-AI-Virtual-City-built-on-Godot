extends Node
## 阶段六：城邦沙盘 UI 测试
## 覆盖：界面构建 / 行情列表 / K线 / 玩家交易 / 统计服务

func run_test(reporter: Node) -> void:
	EconomyEngine.reset()
	var checks: Array = []
	checks.append(await _check_ui_builds())
	checks.append(await _check_kline_data())
	checks.append(await _check_player_trade())
	checks.append(_check_stats_service())
	_report(reporter, checks)


func _check_ui_builds() -> Dictionary:
	EconomyEngine.reset()
	var ui: CanvasLayer = load("res://UI/CityUI.gd").new()
	add_child(ui)
	await get_tree().process_frame
	await get_tree().process_frame
	if ui.market_list == null or ui.market_list.get_item_count() != 6:
		return {"ok": false, "name": "UI构建(行情列表)", "msg": "列表项=%d" % (ui.market_list.get_item_count() if ui.market_list else -1)}
	if ui.kline == null or ui.agent_select.get_item_count() != 15:
		return {"ok": false, "name": "UI构建(Agent列表)", "msg": "agent项=%d" % (ui.agent_select.get_item_count() if ui.agent_select else -1)}
	if ui.chat_log == null or ui.inventory_label == null:
		return {"ok": false, "name": "UI构建", "msg": "面板缺失"}
	ui.queue_free()
	return {"ok": true, "name": "UI构建: 行情6项+Agent15项+面板齐全"}


func _check_kline_data() -> Dictionary:
	var ui: CanvasLayer = load("res://UI/CityUI.gd").new()
	add_child(ui)
	await get_tree().process_frame
	await get_tree().process_frame
	# 手动生成 20 根行情条注入
	var bars: Array = []
	var p := 10.0
	for i in range(20):
		p += sin(i) * 0.5
		bars.append(MarketBar.create(i, "food", p, p - 0.1))
	ui.kline.set_bars(bars)
	if ui.kline.bars.size() != 20:
		return {"ok": false, "name": "K线数据", "msg": "bars=%d" % ui.kline.bars.size()}
	if ui.kline_title.text.is_empty() or not ui.kline_title.text.contains("粮食"):
		return {"ok": false, "name": "K线数据", "msg": "标题未同步商品"}
	ui.queue_free()
	return {"ok": true, "name": "K线数据: 20根行情注入+标题同步"}


func _check_player_trade() -> Dictionary:
	EconomyEngine.reset()
	var ui: CanvasLayer = load("res://UI/CityUI.gd").new()
	add_child(ui)
	await get_tree().process_frame
	await get_tree().process_frame
	var before := EconomyEngine.state.orders.size()
	ui.price_edit.text = "30.0"
	ui.qty_edit.text = "15"
	ui.selected_commodity = "ore"
	ui.place_player_trade(TradeOrder.Type.BUY)
	if EconomyEngine.state.orders.size() != before + 1:
		return {"ok": false, "name": "玩家交易UI", "msg": "未创建订单"}
	var o: TradeOrder = EconomyEngine.state.orders[EconomyEngine.state.orders.size() - 1]
	if o.owner_kind != "player" or o.commodity_id != "ore" or not is_equal_approx(o.price, 30.0):
		return {"ok": false, "name": "玩家交易UI", "msg": "订单内容错误"}
	if o.quantity != 15.0:
		return {"ok": false, "name": "玩家交易UI", "msg": "数量错误"}
	ui.queue_free()
	return {"ok": true, "name": "玩家交易UI: 求购矿石15@30已挂单"}


func _check_stats_service() -> Dictionary:
	EconomyEngine.reset()
	for i in range(10):
		EconomyEngine.step_tick(i)
	var st := EconomyEngine.state
	var prices := EconomyEngine.market_prices()
	var total := StatsService.city_total_assets(st, prices)
	if total <= 0.0:
		return {"ok": false, "name": "统计服务", "msg": "总资产非法"}
	var roi := StatsService.player_roi(st, prices)
	var activity := StatsService.agent_activity(st)
	if activity.get("agents", 0) != 15:
		return {"ok": false, "name": "统计服务", "msg": "Agent统计错误"}
	var summary := StatsService.commodity_summary(st, "food")
	if summary.get("bars", 0) < 10:
		return {"ok": false, "name": "统计服务", "msg": "行情统计错误"}
	return {"ok": true, "name": "统计服务: 总资产=%.0f ROI=%.1f%%" % [total, roi]}


func _report(reporter: Node, checks: Array) -> void:
	for c in checks:
		if c.get("skip", false):
			print("  [SKIP] %s | %s" % [c.get("name", ""), c.get("msg", "")])
		elif c.get("ok", false):
			reporter.passed += 1
			print("  [PASS] " + str(c.get("name", "")))
		else:
			reporter.failed += 1
			print("  [FAIL] %s | %s" % [c.get("name", ""), c.get("msg", "")])
