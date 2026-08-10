class_name PlayerData
extends RefCounted
## 玩家（城邦城主）数据（阶段二）
## 字段覆盖：初始运营资金、物资库存、可用资金、总资产、盈亏统计、
## 城邦治理记录、与AI交互历史、市场操作习惯。

const DEFAULT_CAPITAL := 10000.0

var player_id: String = "player"
var display_name: String = "城主"
var initial_capital: float = DEFAULT_CAPITAL  # 初始运营资金
var cash: float = DEFAULT_CAPITAL             # 可用资金
var inventory: Dictionary = {}                # commodity_id -> 数量（物资库存）
var pnl: float = 0.0                          # 累计盈亏
var governance_log: Array = []                # 城邦治理记录
var interaction_history: Array = []           # 与AI交互历史
var market_habits: Dictionary = {}            # 市场操作习惯统计 { commodity_id: {buy/sell: 金额} }


func _init(p_initial_capital: float = DEFAULT_CAPITAL) -> void:
	initial_capital = p_initial_capital
	cash = p_initial_capital


func add_inventory(commodity_id: String, quantity: float) -> void:
	inventory[commodity_id] = float(inventory.get(commodity_id, 0.0)) + quantity


func remove_inventory(commodity_id: String, quantity: float) -> bool:
	var cur: float = float(inventory.get(commodity_id, 0.0))
	if cur + 0.0001 < quantity:
		return false
	inventory[commodity_id] = cur - quantity
	return true


## 库存市值（prices: commodity_id -> 单价）
func inventory_value(prices: Dictionary) -> float:
	var total := 0.0
	for cid in inventory:
		total += float(inventory[cid]) * float(prices.get(cid, 0.0))
	return total


## 总资产 = 可用资金 + 库存市值
func total_assets(prices: Dictionary) -> float:
	return cash + inventory_value(prices)


func record_governance(action: String, detail: Dictionary = {}) -> void:
	governance_log.append({"action": action, "detail": detail, "time": Time.get_ticks_msec()})


func record_interaction(agent_id: String, message: String) -> void:
	interaction_history.append({"agent": agent_id, "message": message, "time": Time.get_ticks_msec()})


## 记录一笔交易并更新市场操作习惯统计
func record_trade(commodity_id: String, side: String, price: float, quantity: float) -> void:
	var amount := price * quantity
	cash += amount if side == "sell" else -amount
	var habit: Dictionary = market_habits.get(commodity_id, {})
	habit[side] = float(habit.get(side, 0.0)) + amount
	market_habits[commodity_id] = habit


func to_dict() -> Dictionary:
	return {
		"player_id": player_id, "display_name": display_name,
		"initial_capital": initial_capital, "cash": cash,
		"inventory": inventory, "pnl": pnl,
		"governance_log": governance_log,
		"interaction_history": interaction_history,
		"market_habits": market_habits,
	}


static func from_dict(d: Dictionary) -> PlayerData:
	var p := PlayerData.new(float(d.get("initial_capital", DEFAULT_CAPITAL)))
	p.player_id = str(d.get("player_id", "player"))
	p.display_name = str(d.get("display_name", "城主"))
	p.cash = float(d.get("cash", p.initial_capital))
	p.inventory = d.get("inventory", {})
	p.pnl = float(d.get("pnl", 0.0))
	p.governance_log = d.get("governance_log", [])
	p.interaction_history = d.get("interaction_history", [])
	p.market_habits = d.get("market_habits", {})
	return p
