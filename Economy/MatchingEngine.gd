class_name MatchingEngine
extends RefCounted
## 多主体智能撮合交易系统（阶段三）
## 遵循「价格优先、时间优先」规则，自动撮合 AI↔AI、AI↔玩家订单；
## 成交后统一结算资金与库存、更新成交量，保障经济闭环运转。

const EPS := 0.0001


## 撮合整个订单簿。返回 { "trades": Array, "volumes": { commodity_id: 成交量 } }
static func match(state: CityState) -> Dictionary:
	var trades: Array = []
	var volumes := {}
	for cid in state.commodities:
		var cid_volume := _match_commodity(state, cid, trades)
		if cid_volume > 0.0:
			volumes[cid] = cid_volume
	return {"trades": trades, "volumes": volumes}


static func _match_commodity(state: CityState, cid: String, trades: Array) -> float:
	var buys := _active_orders(state.orders, cid, TradeOrder.Type.BUY)
	var sells := _active_orders(state.orders, cid, TradeOrder.Type.SELL)
	var bi := 0
	var si := 0
	var volume := 0.0

	while bi < buys.size() and si < sells.size():
		var b: TradeOrder = buys[bi]
		var s: TradeOrder = sells[si]
		if b.price < s.price:
			break  # 价格优先：买价低于卖价，无交叉，停止

		var buyer = _resolve_owner(state, b)
		var seller = _resolve_owner(state, s)
		var qty := minf(b.remaining(), s.remaining())
		if buyer != null:
			qty = minf(qty, floorf(buyer.cash / maxf(s.price, 0.01)))
		if seller != null:
			qty = minf(qty, float(seller.inventory.get(cid, 0.0)))
		qty = maxf(0.0, qty)

		if qty <= EPS:
			# 无资金或无货：推进相应一侧，避免死循环
			if buyer != null and buyer.cash < EPS:
				bi += 1
			else:
				si += 1
			continue

		var price := s.price
		_settle(buyer, seller, cid, price, qty)
		b.filled_quantity += qty
		s.filled_quantity += qty
		b.status = TradeOrder.Status.FILLED if b.remaining() <= EPS else TradeOrder.Status.PARTIAL
		s.status = TradeOrder.Status.FILLED if s.remaining() <= EPS else TradeOrder.Status.PARTIAL

		trades.append({
			"commodity": cid, "price": price, "qty": qty,
			"buy_order": b.id, "sell_order": s.id,
			"buyer": b.owner_id, "seller": s.owner_id,
			"tick": state.tick,
		})
		volume += qty

		if b.remaining() <= EPS:
			bi += 1
		if s.remaining() <= EPS:
			si += 1

	return volume


## 成交结算：买方扣款收货、卖方收款交货
static func _settle(buyer, seller, cid: String, price: float, qty: float) -> void:
	if buyer != null:
		buyer.cash -= price * qty
		buyer.inventory[cid] = float(buyer.inventory.get(cid, 0.0)) + qty
		buyer.record_trade(cid, "buy", price, qty)
	if seller != null:
		seller.cash += price * qty
		seller.inventory[cid] = float(seller.inventory.get(cid, 0.0)) - qty
		seller.record_trade(cid, "sell", price, qty)


static func _active_orders(orders: Array, cid: String, order_type: int) -> Array:
	var out: Array = []
	for o in orders:
		if o.commodity_id == cid and o.order_type == order_type and o.is_active():
			out.append(o)
	# 价格优先 + 时间优先（同价先到先得）
	if order_type == TradeOrder.Type.BUY:
		out.sort_custom(func(a: TradeOrder, b: TradeOrder) -> bool:
			if is_equal_approx(a.price, b.price):
				return a.created_at < b.created_at
			return a.price > b.price)
	else:
		out.sort_custom(func(a: TradeOrder, b: TradeOrder) -> bool:
			if is_equal_approx(a.price, b.price):
				return a.created_at < b.created_at
			return a.price < b.price)
	return out


static func _resolve_owner(state: CityState, order: TradeOrder):
	if order.owner_kind == "player":
		return state.player
	for a in state.agents:
		if a.id == order.owner_id:
			return a
	return null
