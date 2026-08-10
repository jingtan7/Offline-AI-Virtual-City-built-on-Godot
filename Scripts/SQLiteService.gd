extends Node
## SQLite 结构化存档服务（阶段九存储改造）—— 基于 godot-sqlite 插件
## 通过 ClassDB 动态加载 SQLite 类（插件未装时优雅回退 JSON 存档）。
## 表：npc / inventory / orders / market_bars / prices / behavior_log / event_log / buildings / player
## 采用 WAL 模式 + 参数化查询，位置/行为高频写入不卡顿。

const DB_PATH := "user://Data/saves/city.db"

var available := false
var _db = null
var _error := ""


func _ready() -> void:
	init_db()


## 尝试初始化数据库；插件未安装时返回 false（回退 JSON）。
func init_db() -> bool:
	if ClassDB.class_exists("SQLite"):
		_db = ClassDB.instantiate("SQLite")
		if _db == null:
			_error = "SQLite 实例化失败"
			return false
		_db.set_path(DB_PATH)
		_db.open_db()
		if str(_db.get_error_message()) != "":
			_error = str(_db.get_error_message())
			_db = null
			return false
		available = true
		_db.query("PRAGMA journal_mode=WAL")
		_create_tables()
		GameLog.info("SQLite 就绪: %s" % DB_PATH)
		return true
	_error = "godot-sqlite 插件未安装"
	GameLog.warn("SQLite 存储不可用（%s），回退 JSON 存档" % _error)
	return false


func _create_tables() -> void:
	var ddl := [
		"CREATE TABLE IF NOT EXISTS npc (id TEXT PRIMARY KEY, name TEXT, occupation TEXT, x REAL, y REAL, anim TEXT, state INT, cash REAL, risk TEXT, llm_controlled INT, hp REAL)",
		"CREATE TABLE IF NOT EXISTS inventory (owner_id TEXT, commodity_id TEXT, qty REAL, PRIMARY KEY(owner_id, commodity_id))",
		"CREATE TABLE IF NOT EXISTS orders (id TEXT PRIMARY KEY, owner_id TEXT, owner_kind TEXT, type INT, commodity TEXT, price REAL, qty REAL, filled REAL, status INT, created INT, expires INT)",
		"CREATE TABLE IF NOT EXISTS market_bars (id INTEGER PRIMARY KEY AUTOINCREMENT, tick INT, commodity TEXT, open REAL, close REAL, high REAL, low REAL, prev_close REAL, volume REAL, pending INT, gap REAL)",
		"CREATE TABLE IF NOT EXISTS prices (tick INT, commodity TEXT, price REAL)",
		"CREATE TABLE IF NOT EXISTS behavior_log (id INTEGER PRIMARY KEY AUTOINCREMENT, tick INT, agent TEXT, action TEXT, commodity TEXT, price REAL, qty REAL, reason TEXT, time INT)",
		"CREATE TABLE IF NOT EXISTS event_log (id INTEGER PRIMARY KEY AUTOINCREMENT, tick INT, label TEXT, desc TEXT)",
		"CREATE TABLE IF NOT EXISTS buildings (id TEXT PRIMARY KEY, type TEXT, x REAL, y REAL, name TEXT)",
		"CREATE TABLE IF NOT EXISTS player (id TEXT PRIMARY KEY, name TEXT, cash REAL, initial_capital REAL, pnl REAL)",
	]
	for sql in ddl:
		_db.query(sql)


func is_open() -> bool:
	return _db != null and (_db.is_open() if _db.has_method("is_open") else true)


## ==================== 高频写入（WAL 下毫秒级） ====================

## 记录全部 NPC 位置/动画（每 tick 调用）
func record_positions(state: CityState) -> void:
	if not available or state == null:
		return
	for a in state.agents:
		var agent: AgentData = a
		_db.query_with_bindings(
			"UPDATE npc SET x=?, y=?, anim=?, state=? WHERE id=?",
			[agent.pos_x, agent.pos_y, agent.anim, int(agent.state), agent.id],
		)


func record_behavior(agent_id: String, action: String, cid: String, price: float, qty: float, reason: String, tick: int) -> void:
	if not available:
		return
	_db.query_with_bindings(
		"INSERT INTO behavior_log (tick, agent, action, commodity, price, qty, reason, time) VALUES (?,?,?,?,?,?,?,?)",
		[tick, agent_id, action, cid, price, qty, reason, Time.get_ticks_msec()],
	)


func record_event(ev: Dictionary, tick: int) -> void:
	if not available:
		return
	_db.query_with_bindings(
		"INSERT INTO event_log (tick, label, desc) VALUES (?,?,?)",
		[tick, str(ev.get("label", "")), str(ev.get("desc", ""))],
	)


## 追加本 tick 行情
func append_market_bars(state: CityState) -> void:
	if not available or state == null:
		return
	for cid in state.commodities:
		var bar: MarketBar = state.latest_bar(cid)
		if bar == null:
			continue
		_db.query_with_bindings(
			"INSERT INTO market_bars (tick, commodity, open, close, high, low, prev_close, volume, pending, gap) VALUES (?,?,?,?,?,?,?,?,?,?)",
			[bar.timestamp, cid, bar.open, bar.close, bar.high, bar.low, bar.prev_close, bar.volume, bar.pending_orders, bar.supply_demand_gap],
		)
		_db.query_with_bindings("INSERT INTO prices (tick, commodity, price) VALUES (?,?,?)",
			[state.tick, cid, (state.commodities[cid] as Commodity).current_price])


## ==================== 全量存档 / 读档 ====================

func save_game(state: CityState) -> bool:
	if not available or state == null:
		return false
	_db.query("BEGIN")
	_db.query_with_bindings("INSERT OR REPLACE INTO player (id, name, cash, initial_capital, pnl) VALUES (?,?,?,?,?)",
		[state.player.player_id, state.player.display_name, state.player.cash, state.player.initial_capital, state.player.pnl])
	_db.query("DELETE FROM npc")
	for a in state.agents:
		var agent: AgentData = a
		_db.query_with_bindings(
			"INSERT INTO npc (id, name, occupation, x, y, anim, state, cash, risk, llm_controlled, hp) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
			[agent.id, agent.display_name, agent.occupation, agent.pos_x, agent.pos_y, agent.anim, int(agent.state), agent.cash, agent.risk_profile, 1 if agent.llm_controlled else 0, 100.0],
		)
	_db.query("DELETE FROM inventory")
	for a in state.agents:
		var agent: AgentData = a
		for cid in agent.inventory:
			_db.query_with_bindings("INSERT INTO inventory (owner_id, commodity_id, qty) VALUES (?,?,?)",
				[agent.id, cid, float(agent.inventory[cid])])
	for cid in state.player.inventory:
		_db.query_with_bindings("INSERT INTO inventory (owner_id, commodity_id, qty) VALUES (?,?,?)",
			["player", cid, float(state.player.inventory[cid])])
	_db.query("DELETE FROM orders")
	for o in state.orders:
		var order: TradeOrder = o
		_db.query_with_bindings(
			"INSERT INTO orders (id, owner_id, owner_kind, type, commodity, price, qty, filled, status, created, expires) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
			[order.id, order.owner_id, order.owner_kind, int(order.order_type), order.commodity_id, order.price, order.quantity, order.filled_quantity, int(order.status), order.created_at, order.expires_at],
		)
	_db.query("COMMIT")
	return true


func load_game() -> CityState:
	if not available:
		return null
	var state := CityState.new()
	_db.query("SELECT * FROM player LIMIT 1")
	if _db.get_query_result().size() > 0:
		var p: Dictionary = _db.get_query_result()[0]
		state.player = PlayerData.new(float(p.get("initial_capital", 10000.0)))
		state.player.cash = float(p.get("cash", state.player.cash))
		state.player.pnl = float(p.get("pnl", 0.0))
		state.player.display_name = str(p.get("name", "城主"))
	for c in Commodity.default_commodities():
		state.commodities[c.id] = c
	_db.query("SELECT * FROM npc")
	for row in _db.get_query_result():
		var a := AgentData.new()
		a.id = str(row.get("id", ""))
		a.display_name = str(row.get("name", a.id))
		a.occupation = str(row.get("occupation", "farmer"))
		a.pos_x = float(row.get("x", 0.0))
		a.pos_y = float(row.get("y", 0.0))
		a.anim = str(row.get("anim", "idle"))
		a.state = int(row.get("state", 0))
		a.cash = float(row.get("cash", 0.0))
		a.risk_profile = str(row.get("risk", "balanced"))
		a.llm_controlled = int(row.get("llm_controlled", 0)) == 1
		state.agents.append(a)
	_db.query("SELECT * FROM inventory")
	for row in _db.get_query_result():
		var owner := str(row.get("owner_id", ""))
		var cid := str(row.get("commodity_id", ""))
		var qty := float(row.get("qty", 0.0))
		if owner == "player":
			state.player.inventory[cid] = qty
		else:
			for a in state.agents:
				if (a as AgentData).id == owner:
					(a as AgentData).inventory[cid] = qty
	_db.query("SELECT * FROM orders")
	for row in _db.get_query_result():
		var o := TradeOrder.new()
		o.id = str(row.get("id", ""))
		o.owner_id = str(row.get("owner_id", ""))
		o.owner_kind = str(row.get("owner_kind", "agent"))
		o.order_type = int(row.get("type", 0))
		o.commodity_id = str(row.get("commodity", ""))
		o.price = float(row.get("price", 0.0))
		o.quantity = float(row.get("qty", 0.0))
		o.filled_quantity = float(row.get("filled", 0.0))
		o.status = int(row.get("status", 0))
		o.created_at = int(row.get("created", 0))
		o.expires_at = int(row.get("expires", 0))
		state.orders.append(o)
	_db.query("SELECT commodity, price FROM prices ORDER BY tick DESC LIMIT 6")
	for row in _db.get_query_result():
		var cid := str(row.get("commodity", ""))
		if state.commodities.has(cid):
			(state.commodities[cid] as Commodity).current_price = float(row.get("price", 0.0))
	return state


func close_db() -> void:
	if _db != null and _db.has_method("close_db"):
		_db.close_db()
	_db = null
	available = false
