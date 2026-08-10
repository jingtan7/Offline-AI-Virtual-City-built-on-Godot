extends CanvasLayer
## 城邦沙盘主界面（阶段六）
## 总览 / 物资行情列表 / K线可视化 / 玩家交易 / 库存复盘 / AI 对话交互

var selected_commodity := "food"
var _selected_agent_id := ""

var header_label: Label
var market_list: ItemList
var kline_title: Label
var kline: KLineChart
var stats_label: Label
var event_label: Label
var commodity_select: OptionButton
var price_edit: LineEdit
var qty_edit: LineEdit
var buy_btn: Button
var sell_btn: Button
var inventory_label: Label
var agent_select: OptionButton
var chat_log: RichTextLabel
var chat_input: LineEdit
var footer_label: Label

var _refreshing := false


func _ready() -> void:
	_build_ui()
	SimulationLoop.tick.connect(_on_tick)
	refresh()


## ==================== UI 构建 ====================

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	header_label = Label.new()
	header_label.text = "🏰 离线 AI 虚拟城邦 · 城邦总览"
	header_label.add_theme_font_size_override("font_size", 20)
	root.add_child(header_label)

	var main_row := HBoxContainer.new()
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_row.add_theme_constant_override("separation", 8)
	root.add_child(main_row)

	# ---- 左：行情列表 ----
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(230, 0)
	left.add_theme_constant_override("separation", 4)
	main_row.add_child(left)
	left.add_child(_mk_label("📊 物资行情", 15))
	market_list = ItemList.new()
	market_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	market_list.item_selected.connect(_on_market_selected)
	left.add_child(market_list)

	# ---- 中：K 线 ----
	var center := VBoxContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.add_theme_constant_override("separation", 4)
	main_row.add_child(center)
	kline_title = _mk_label("📈 价格走势：粮食", 15)
	center.add_child(kline_title)
	kline = KLineChart.new()
	kline.custom_minimum_size = Vector2(0, 280)
	kline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kline.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(kline)
	stats_label = _mk_label("", 13)
	center.add_child(stats_label)
	event_label = _mk_label("", 12)
	event_label.modulate = Color(1, 0.85, 0.5)
	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	center.add_child(event_label)

	# ---- 右：交易 / 库存 / 对话 ----
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(420, 0)
	right.add_theme_constant_override("separation", 5)
	main_row.add_child(right)
	right.add_child(_mk_label("🧾 交易面板（城主）", 15))

	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 4)
	right.add_child(row1)
	commodity_select = OptionButton.new()
	commodity_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	commodity_select.item_selected.connect(_on_commodity_selected)
	row1.add_child(commodity_select)
	qty_edit = LineEdit.new()
	qty_edit.placeholder_text = "数量"
	qty_edit.text = "10"
	qty_edit.custom_minimum_size = Vector2(70, 0)
	row1.add_child(qty_edit)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 4)
	right.add_child(row2)
	price_edit = LineEdit.new()
	price_edit.placeholder_text = "价格（留空=市价）"
	price_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row2.add_child(price_edit)
	buy_btn = Button.new()
	buy_btn.text = "求购"
	buy_btn.pressed.connect(_on_buy_pressed)
	row2.add_child(buy_btn)
	sell_btn = Button.new()
	sell_btn.text = "出售"
	sell_btn.pressed.connect(_on_sell_pressed)
	row2.add_child(sell_btn)

	inventory_label = _mk_label("库存：-", 13)
	inventory_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(inventory_label)

	right.add_child(_mk_label("💬 对话市民（城主 ↔ AI）", 15))
	agent_select = OptionButton.new()
	right.add_child(agent_select)
	chat_log = RichTextLabel.new()
	chat_log.bbcode_enabled = true
	chat_log.scroll_following = true
	chat_log.custom_minimum_size = Vector2(0, 120)
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(chat_log)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "输入想对市民说的话，回车发送…"
	chat_input.text_submitted.connect(_on_chat_submitted)
	right.add_child(chat_input)

	footer_label = _mk_label("", 12)
	footer_label.modulate = Color(0.7, 0.75, 0.8)
	root.add_child(footer_label)


func _mk_label(text: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	return l


## ==================== 数据刷新 ====================

func _on_tick(_idx: int, _delta: float) -> void:
	refresh()


func refresh() -> void:
	var st: CityState = EconomyEngine.state
	if st == null or _refreshing:
		return
	_refreshing = true
	_refresh_overview(st)
	_refresh_market_list(st)
	_refresh_selection_sync(st)
	_refresh_inventory(st)
	_refresh_agents(st)
	_refresh_footer(st)
	_refreshing = false


func _refresh_overview(st: CityState) -> void:
	var prices := EconomyEngine.market_prices()
	var total := StatsService.city_total_assets(st, prices)
	var roi := StatsService.player_roi(st, prices)
	header_label.text = "🏰 离线 AI 虚拟城邦 · 城邦总览 ｜ tick#%d ｜ 城主资金 %.0f ｜ 城邦总资产 %.0f ｜ 收益率 %.1f%%" % [
		st.tick, st.player.cash, total, roi,
	]


func _refresh_market_list(st: CityState) -> void:
	var prev_selected := selected_commodity
	market_list.clear()
	var sorted_ids: Array = st.commodities.keys()
	sorted_ids.sort()
	for cid in sorted_ids:
		var c: Commodity = st.commodities[cid]
		var bar := st.latest_bar(cid)
		var chg := bar.change_pct() if bar != null else 0.0
		var txt := "%s  %.2f  %+.1f%%" % [c.name, c.current_price, chg]
		market_list.add_item(txt)
		var idx := market_list.get_item_count() - 1
		market_list.set_item_metadata(idx, cid)
		market_list.set_item_custom_fg_color(idx,
			Color(0.95, 0.4, 0.4) if chg < -0.5 else (Color(0.4, 0.9, 0.55) if chg > 0.5 else Color(0.85, 0.88, 0.92)))
		if cid == prev_selected:
			market_list.select(idx)
	if market_list.get_selected_items().is_empty() and market_list.get_item_count() > 0:
		market_list.select(0)
		selected_commodity = market_list.get_item_metadata(0)


func _refresh_selection_sync(st: CityState) -> void:
	if commodity_select.get_item_count() != st.commodities.size():
		var old := selected_commodity
		commodity_select.clear()
		var sorted_ids: Array = st.commodities.keys()
		sorted_ids.sort()
		for i in range(sorted_ids.size()):
			var cid: String = sorted_ids[i]
			commodity_select.add_item((st.commodities[cid] as Commodity).name)
			commodity_select.set_item_metadata(i, cid)
			if cid == old:
				commodity_select.select(i)
	if not st.commodities.has(selected_commodity):
		selected_commodity = st.commodities.keys()[0]

	var c: Commodity = st.commodities.get(selected_commodity)
	if c != null:
		kline_title.text = "📈 价格走势：%s" % c.name
		kline.set_bars(st.market_bars.get(selected_commodity, []))
		var bar := st.latest_bar(selected_commodity)
		var chg := bar.change_pct() if bar != null else 0.0
		stats_label.text = "%s ｜ 实时价 %.2f ｜ 基准价 %.2f ｜ 存量 %.0f ｜ 涨跌 %+.1f%% ｜ 品类 %s" % [
			c.name, c.current_price, c.base_price, c.total_stock, chg, c.category_label(),
		]
		var ev_text := ""
		if not st.event_log.is_empty():
			var ev: Dictionary = st.event_log[st.event_log.size() - 1]
			ev_text = "🎲 %s：%s" % [ev.get("label", ""), ev.get("desc", "")]
		event_label.text = ev_text


func _refresh_inventory(st: CityState) -> void:
	var p: PlayerData = st.player
	var parts: Array = []
	for cid in p.inventory:
		if float(p.inventory[cid]) > 0.0:
			parts.append("%s:%.0f" % [_cid_label(cid), float(p.inventory[cid])])
	var inv_text := "库存：" + ("、".join(parts) if not parts.is_empty() else "空")
	inv_text += " ｜ 可用资金 %.1f ｜ 总资产 %.1f" % [p.cash, p.total_assets(EconomyEngine.market_prices())]
	inventory_label.text = inv_text


func _refresh_agents(st: CityState) -> void:
	var old := _selected_agent_id
	agent_select.clear()
	for i in range(st.agents.size()):
		var a: AgentData = st.agents[i]
		var tag := "🤖" if a.llm_controlled else "⚙️"
		agent_select.add_item("%s %s (%s)" % [tag, a.display_name, a.state_label()])
		agent_select.set_item_metadata(i, a.id)
		if a.id == old:
			agent_select.select(i)
	if _selected_agent_id.is_empty() and agent_select.get_item_count() > 0:
		agent_select.select(0)
		_selected_agent_id = agent_select.get_item_metadata(0)


func _refresh_footer(st: CityState) -> void:
	footer_label.text = "挂单 %d 笔 ｜ 事件 %d 起 ｜ 记忆 %d 条 ｜ LLM 决策 %d 次 ｜ 模型 %s" % [
		st.orders.size(), st.event_log.size(), MemoryStore.memories.size(),
		AgentManager.decisions_total, AIService.model,
	]


func _cid_label(cid: String) -> String:
	var c: Commodity = EconomyEngine.state.commodities.get(cid, null)
	return c.name if c != null else cid


## ==================== 交互 ====================

func _on_market_selected(index: int) -> void:
	selected_commodity = market_list.get_item_metadata(index)
	refresh()


func _on_commodity_selected(index: int) -> void:
	selected_commodity = commodity_select.get_item_metadata(index)
	refresh()


func _on_buy_pressed() -> void:
	place_player_trade(TradeOrder.Type.BUY)


func _on_sell_pressed() -> void:
	place_player_trade(TradeOrder.Type.SELL)


func place_player_trade(order_type: int) -> void:
	var cid := selected_commodity
	var st := EconomyEngine.state
	if st == null or not st.commodities.has(cid):
		return
	var price := float(price_edit.text) if not price_edit.text.is_empty() else (st.commodities[cid] as Commodity).current_price
	var qty := maxf(1.0, float(qty_edit.text))
	if price <= 0.0 or qty <= 0.0:
		return
	EconomyEngine.place_player_order(order_type, cid, price, qty)
	var side := "求购" if order_type == TradeOrder.Type.BUY else "出售"
	chat_log.append_text("[color=#ffd166]城主 挂单 %s %s：%.1f 单位 @%.2f[/color]\n" % [side, _cid_label(cid), qty, price])
	refresh()


func _on_chat_submitted(text: String) -> void:
	var msg := text.strip_edges()
	if msg.is_empty():
		return
	var st := EconomyEngine.state
	var idx := agent_select.get_selected()
	if idx < 0 or idx >= st.agents.size():
		return
	var agent: AgentData = st.agents[idx]
	_selected_agent_id = agent.id
	chat_log.append_text("[color=#ffffff][b]城主[/b][/color]: %s\n" % msg)
	chat_input.clear()
	chat_log.append_text("[color=#88ccff]%s 正在思考…[/color]\n" % agent.display_name)
	_do_chat(agent, msg)


func _do_chat(agent: AgentData, msg: String) -> void:
	var sys := AgentPrompts.chat_system_for(agent)
	var resp: Dictionary = await AIService.agent_infer(msg, sys, ToolRunner.tool_definitions)
	var content := str(resp.get("content", "（没有回复，请稍后再试）"))
	chat_log.append_text("[color=#6fe0a8][b]%s[/b][/color]: %s\n" % [agent.display_name, content])
