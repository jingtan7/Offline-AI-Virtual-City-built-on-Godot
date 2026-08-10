extends CanvasLayer
## 横版村庄 HUD 叠加层（阶段九横版改造）
## 顶部总览 / 行情条 / 交易按钮 / 市民对话 / 事件提示

var overview_label: Label
var market_bar: HBoxContainer
var event_label: Label
var chat_log: RichTextLabel
var chat_input: LineEdit
var status_label: Label

var _selected_cid := "food"
var _buttons: Dictionary = {}
var _hud_sec := 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	# 顶部总览
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 8
	top.offset_bottom = 46
	add_child(top)
	var v := VBoxContainer.new()
	top.add_child(v)
	overview_label = Label.new()
	overview_label.add_theme_font_size_override("font_size", 14)
	v.add_child(overview_label)

	# 行情条（顶部下方）
	var mpanel := PanelContainer.new()
	mpanel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	mpanel.offset_top = 50
	mpanel.offset_bottom = 76
	add_child(mpanel)
	var mv := VBoxContainer.new()
	mpanel.add_child(mv)
	market_bar = HBoxContainer.new()
	market_bar.add_theme_constant_override("separation", 10)
	mv.add_child(market_bar)

	# 状态（左下）
	var spanel := PanelContainer.new()
	spanel.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	spanel.offset_left = 8
	spanel.offset_top = -50
	spanel.offset_bottom = -8
	add_child(spanel)
	status_label = Label.new()
	spanel.add_child(status_label)

	# 事件（左上，总览下方）
	var epanel := PanelContainer.new()
	epanel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	epanel.offset_left = 8
	epanel.offset_top = 80
	epanel.offset_bottom = 130
	add_child(epanel)
	event_label = Label.new()
	event_label.modulate = Color(1, 0.85, 0.5)
	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_label.custom_minimum_size = Vector2(320, 0)
	epanel.add_child(event_label)

	# 聊天（右下）
	var chat_panel := PanelContainer.new()
	chat_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	chat_panel.offset_right = -8
	chat_panel.offset_left = -520
	chat_panel.offset_top = -220
	chat_panel.offset_bottom = -8
	add_child(chat_panel)
	var cv := VBoxContainer.new()
	chat_panel.add_child(cv)
	chat_log = RichTextLabel.new()
	chat_log.bbcode_enabled = true
	chat_log.scroll_following = true
	chat_log.custom_minimum_size = Vector2(0, 150)
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cv.add_child(chat_log)
	chat_input = LineEdit.new()
	chat_input.placeholder_text = "对选中的市民说话，回车发送…"
	chat_input.text_submitted.connect(_on_chat)
	cv.add_child(chat_input)

	_refresh_market_bar()


## ==================== 刷新 ====================

func refresh() -> void:
	var st := EconomyEngine.state
	if st == null:
		return
	var prices := EconomyEngine.market_prices()
	var total := StatsService.city_total_assets(st, prices)
	var roi := StatsService.player_roi(st, prices)
	overview_label.text = "🏰 横版城邦 ｜ tick#%d ｜ 资金 %.0f ｜ 总资产 %.0f ｜ 收益率 %.1f%%" % [
		st.tick, st.player.cash, total, roi,
	]
	var ev_text := ""
	if not st.event_log.is_empty():
		var ev: Dictionary = st.event_log[st.event_log.size() - 1]
		ev_text = "🎲 %s" % ev.get("label", "")
	event_label.text = ev_text


func _refresh_market_bar() -> void:
	for c in market_bar.get_children():
		c.queue_free()
	_buttons.clear()
	var st := EconomyEngine.state
	if st == null:
		return
	var sorted_ids: Array = st.commodities.keys()
	sorted_ids.sort()
	for cid in sorted_ids:
		var c: Commodity = st.commodities[cid]
		var b := Button.new()
		b.text = "%s %.2f" % [c.name, c.current_price]
		b.pressed.connect(func(): _select_commodity(cid))
		market_bar.add_child(b)
		_buttons[cid] = b
	_refresh_selection()


func _select_commodity(cid: String) -> void:
	_selected_cid = cid
	_refresh_selection()


func _refresh_selection() -> void:
	for cid in _buttons:
		(_buttons[cid] as Button).modulate = Color(1, 1, 1) if cid == _selected_cid else Color(0.75, 0.78, 0.82)


## ==================== 交易 ====================

func trade_buy(qty: float = 20.0) -> void:
	_do_trade(TradeOrder.Type.BUY, qty)


func trade_sell(qty: float = 20.0) -> void:
	_do_trade(TradeOrder.Type.SELL, qty)


func _do_trade(order_type: int, qty: float) -> void:
	var st := EconomyEngine.state
	if st == null or not st.commodities.has(_selected_cid):
		return
	var c: Commodity = st.commodities[_selected_cid]
	var price := c.current_price
	EconomyEngine.place_player_order(order_type, _selected_cid, price, qty)
	var side := "求购" if order_type == TradeOrder.Type.BUY else "出售"
	chat_log.append_text("[color=#ffd166]城主 挂单 %s %s %.0f @%.2f[/color]\n" % [side, c.name, qty, price])


## ==================== 对话 ====================

func _on_chat(text: String) -> void:
	var msg := text.strip_edges()
	if msg.is_empty():
		return
	var st := EconomyEngine.state
	if st == null:
		return
	chat_log.append_text("[color=#ffffff][b]城主[/b][/color]: %s\n" % msg)
	chat_input.clear()
	# 对话对象：选中的市民（未选中则随机一个）
	var agent: AgentData
	var npc_layer := get_parent()
	if npc_layer != null and npc_layer.has_method("focus_npc_agent"):
		agent = npc_layer.focus_npc_agent()
	if agent == null:
		agent = st.agents[randi() % st.agents.size()]
	chat_log.append_text("[color=#88ccff]%s 正在思考…[/color]\n" % agent.display_name)
	_do_chat(agent, msg)


func _do_chat(agent: AgentData, msg: String) -> void:
	var sys := AgentPrompts.chat_system_for(agent)
	var resp: Dictionary = await AIService.agent_infer(msg, sys, ToolRunner.tool_definitions)
	var content := str(resp.get("content", "（没有回复）"))
	chat_log.append_text("[color=#6fe0a8][b]%s[/b][/color]: %s\n" % [agent.display_name, content])
