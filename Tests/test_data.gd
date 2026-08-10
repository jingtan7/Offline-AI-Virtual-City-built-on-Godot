extends Node
## 阶段二：数据体系测试
## 覆盖：物资表 / 行情 / 订单 / 玩家 / Agent / 城邦状态 / JSON 序列化往返 / 存档读档

func run_test(reporter: Node) -> void:
	var checks: Array = []
	checks.append(_check_commodities())
	checks.append(_check_market_bar())
	checks.append(_check_trade_order())
	checks.append(_check_player())
	checks.append(_check_agents())
	checks.append(_check_city_state())
	checks.append(_check_serialize_roundtrip())
	checks.append(_check_save_load())
	_report(reporter, checks)


func _check_commodities() -> Dictionary:
	var list := Commodity.default_commodities()
	if list.size() != 6:
		return {"ok": false, "name": "物资表(6种)", "msg": "实际 %d 种" % list.size()}
	var ids := {}
	var cats := {}
	for c in list:
		ids[c.id] = true
		cats[c.category] = true
		if c.base_price <= 0.0 or c.total_stock <= 0.0:
			return {"ok": false, "name": "物资表(6种)", "msg": c.id + " 价格/存量非法"}
	if ids.size() != 6 or not cats.has("survival") or not cats.has("industrial") or not cats.has("trade"):
		return {"ok": false, "name": "物资表(6种)", "msg": "ID 或品类不完整"}
	return {"ok": true, "name": "物资表(6种, 3品类): " + str(ids.keys())}


func _check_market_bar() -> Dictionary:
	var b := MarketBar.create(1000, "food", 11.0, 10.0, 500.0, 8, 25.0)
	if not is_equal_approx(b.change_pct(), 10.0):
		return {"ok": false, "name": "行情数据(MarketBar)", "msg": "涨跌幅计算错误: " + str(b.change_pct())}
	if b.high != 11.0 or b.low != 11.0 or b.pending_orders != 8 or b.supply_demand_gap != 25.0:
		return {"ok": false, "name": "行情数据(MarketBar)", "msg": "字段不完整"}
	var d := b.to_dict()
	var b2 := MarketBar.from_dict(d)
	if b2.change_pct() != b.change_pct() or b2.volume != b.volume:
		return {"ok": false, "name": "行情数据(MarketBar)", "msg": "序列化往返不一致"}
	return {"ok": true, "name": "行情数据(MarketBar): 涨跌+%.1f%%" % b.change_pct()}


func _check_trade_order() -> Dictionary:
	var o := TradeOrder.create("o1", TradeOrder.Type.SELL, "wood", 8.5, 100.0, "agent_0001", "agent", 0, 60000)
	if not o.is_active() or o.remaining() != 100.0:
		return {"ok": false, "name": "交易订单(TradeOrder)", "msg": "初始状态错误"}
	o.filled_quantity = 40.0
	o.status = TradeOrder.Status.PARTIAL
	if o.remaining() != 60.0 or not o.is_active():
		return {"ok": false, "name": "交易订单(TradeOrder)", "msg": "部分成交状态错误"}
	o.filled_quantity = o.quantity
	o.status = TradeOrder.Status.FILLED
	if o.is_active() or o.remaining() != 0.0:
		return {"ok": false, "name": "交易订单(TradeOrder)", "msg": "成交完成状态错误"}
	return {"ok": true, "name": "交易订单(TradeOrder): %s 状态流转正确" % o.type_label()}


func _check_player() -> Dictionary:
	var p := PlayerData.new(10000.0)
	if p.cash != 10000.0 or p.total_assets({"food": 10.0}) != 10000.0:
		return {"ok": false, "name": "玩家数据(PlayerData)", "msg": "初始资金错误"}
	p.add_inventory("food", 50.0)
	p.add_inventory("ore", 20.0)
	if not p.remove_inventory("food", 10.0):
		return {"ok": false, "name": "玩家数据(PlayerData)", "msg": "移除库存失败"}
	if p.remove_inventory("wood", 5.0):
		return {"ok": false, "name": "玩家数据(PlayerData)", "msg": "空库存移除应失败"}
	var assets := p.total_assets({"food": 12.5, "ore": 15.0, "wood": 8.2})
	var expect := 10000.0 + 40.0 * 12.5 + 20.0 * 15.0
	if not is_equal_approx(assets, expect):
		return {"ok": false, "name": "玩家数据(PlayerData)", "msg": "总资产计算错误: %f != %f" % [assets, expect]}
	p.record_trade("food", "sell", 13.0, 20.0)
	if not p.market_habits.has("food"):
		return {"ok": false, "name": "玩家数据(PlayerData)", "msg": "市场习惯未记录"}
	p.record_governance("test")
	p.record_interaction("agent_0000", "你好")
	return {"ok": true, "name": "玩家数据(PlayerData): 总资产=%.1f" % assets}
func _check_agents() -> Dictionary:
	var agents := AgentData.make_sample_agents(15)
	if agents.size() != 15:
		return {"ok": false, "name": "Agent数据(AgentData)", "msg": "数量错误: %d" % agents.size()}
	var occs := {}
	var risks := {}
	for a in agents:
		occs[a.occupation] = true
		risks[a.risk_profile] = true
		if a.cash <= 0.0:
			return {"ok": false, "name": "Agent数据(AgentData)", "msg": a.id + " 资金非法"}
		if a.display_name.is_empty():
			return {"ok": false, "name": "Agent数据(AgentData)", "msg": a.id + " 缺名称"}
	if occs.size() != 5:
		return {"ok": false, "name": "Agent数据(AgentData)", "msg": "5职业不完整: " + str(occs.keys())}
	if risks.size() < 2:
		return {"ok": false, "name": "Agent数据(AgentData)", "msg": "风险策略应多样化"}
	return {"ok": true, "name": "Agent数据(AgentData): 15个/5职业"}


func _check_city_state() -> Dictionary:
	var s := CityState.create_default()
	if s.commodities.size() != 6 or s.player == null or s.agents.size() != 15:
		return {"ok": false, "name": "城邦状态(CityState)", "msg": "默认城邦初始化不完整"}
	s.append_market_bar(MarketBar.create(1, "food", 12.5, 12.0))
	s.append_market_bar(MarketBar.create(2, "food", 12.8, 12.5))
	var latest: MarketBar = s.latest_bar("food")
	if latest == null or latest.close != 12.8:
		return {"ok": false, "name": "城邦状态(CityState)", "msg": "行情追加/读取错误"}
	return {"ok": true, "name": "城邦状态(CityState): 6物资+15Agent+行情"}


func _check_serialize_roundtrip() -> Dictionary:
	var s := CityState.create_default()
	s.tick = 42
	s.append_market_bar(MarketBar.create(1, "food", 12.5, 12.0))
	s.add_order(TradeOrder.create("o9", TradeOrder.Type.BUY, "ore", 14.0, 50.0, "agent_0002", "agent", 0, 60000))
	s.player.record_governance("修路")
	var json_text := JSON.stringify(s.to_dict())
	var parsed = JSON.parse_string(json_text)
	if not (parsed is Dictionary):
		return {"ok": false, "name": "JSON序列化往返", "msg": "JSON 解析失败"}
	var s2 := CityState.from_dict(parsed)
	if s2.tick != 42 or s2.commodities.size() != 6 or s2.agents.size() != 15:
		return {"ok": false, "name": "JSON序列化往返", "msg": "恢复后数据不一致"}
	if s2.player.player_id != s.player.player_id or s2.orders.size() != 1:
		return {"ok": false, "name": "JSON序列化往返", "msg": "玩家/订单恢复错误"}
	return {"ok": true, "name": "JSON序列化往返: 全结构可逆"}


func _check_save_load() -> Dictionary:
	var s := CityState.create_default()
	s.player.cash = 7777.0
	if not s.save():
		return {"ok": false, "name": "存档/读档", "msg": "保存失败"}
	var s2 := CityState.load()
	if s2 == null:
		return {"ok": false, "name": "存档/读档", "msg": "读档失败"}
	if s2.player.cash != 7777.0 or s2.commodities.size() != 6:
		return {"ok": false, "name": "存档/读档", "msg": "读档数据不一致"}
	return {"ok": true, "name": "存档/读档: user:// 持久化成功"}


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

