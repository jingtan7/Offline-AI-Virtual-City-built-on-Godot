class_name AgentData
extends RefCounted
## 多类型 AI Agent 智能体数据（阶段二）
## 字段覆盖：独立资金、专属物资库存、职业人设标签、性格偏好、风险策略、
## 行为记忆库、历史交易与劳作记录、当前状态。

enum State { WORKING, TRADING, HOARDING, CONSUMING, IDLE }

const OCCUPATIONS := ["farmer", "miner", "merchant", "artisan", "speculator"]
const OCCUPATION_LABELS := {
	"farmer": "农夫", "miner": "矿工", "merchant": "商人",
	"artisan": "工匠", "speculator": "投机者",
}

var id: String = ""                 # Agent ID
var display_name: String = ""       # 显示名
var occupation: String = "farmer"   # 职业人设标签
var personality: Dictionary = {}    # 性格偏好 { risk_tolerance, patience, greed, sociality }
var risk_profile: String = "balanced"  # 风险策略 conservative/balanced/aggressive
var cash: float = 0.0               # 独立资金
var inventory: Dictionary = {}      # 专属物资库存 commodity_id -> 数量
var memory: Array = []              # 行为记忆库（阶段五 RAG 入库用）
var trade_history: Array = []       # 历史交易记录
var labor_history: Array = []       # 劳作记录
var state: State = State.IDLE       # 当前状态
var llm_controlled: bool = false    # 是否由 LLM 决策接管（阶段四）
var last_decision: Dictionary = {}  # 最近一次 LLM 决策记录
var pos_x := 0.0                    # 横版村庄坐标（阶段九横版改造）
var pos_y := 0.0
var anim := "idle"                  # 当前播放动画名


func occupation_label() -> String:
	return OCCUPATION_LABELS.get(occupation, occupation)


func state_label() -> String:
	match state:
		State.WORKING:
			return "打工"
		State.TRADING:
			return "交易"
		State.HOARDING:
			return "囤货"
		State.CONSUMING:
			return "消费"
		State.IDLE:
			return "闲置"
	return "未知"


func record_trade(commodity_id: String, side: String, price: float, quantity: float) -> void:
	trade_history.append({
		"commodity": commodity_id, "side": side,
		"price": price, "quantity": quantity,
		"time": Time.get_ticks_msec(),
	})


func record_labor(output_commodity: String, quantity: float) -> void:
	labor_history.append({
		"output": output_commodity, "quantity": quantity,
		"time": Time.get_ticks_msec(),
	})


func to_dict() -> Dictionary:
	return {
		"id": id, "display_name": display_name, "occupation": occupation,
		"personality": personality, "risk_profile": risk_profile,
		"cash": cash, "inventory": inventory,
		"memory": memory, "trade_history": trade_history,
		"labor_history": labor_history, "state": int(state),
		"llm_controlled": llm_controlled, "last_decision": last_decision,
		"pos_x": pos_x, "pos_y": pos_y, "anim": anim,
	}


static func from_dict(d: Dictionary) -> AgentData:
	var a := AgentData.new()
	a.id = str(d.get("id", ""))
	a.display_name = str(d.get("display_name", ""))
	a.occupation = str(d.get("occupation", "farmer"))
	a.personality = d.get("personality", {})
	a.risk_profile = str(d.get("risk_profile", "balanced"))
	a.cash = float(d.get("cash", 0.0))
	a.inventory = d.get("inventory", {})
	a.memory = d.get("memory", [])
	a.trade_history = d.get("trade_history", [])
	a.labor_history = d.get("labor_history", [])
	a.state = int(d.get("state", int(State.IDLE)))
	a.llm_controlled = bool(d.get("llm_controlled", false))
	a.last_decision = d.get("last_decision", {})
	a.pos_x = float(d.get("pos_x", 0.0))
	a.pos_y = float(d.get("pos_y", 0.0))
	a.anim = str(d.get("anim", "idle"))
	return a


## 生成示例智能体（确定性，便于测试复现）：5 职业轮转。
static func make_sample_agents(count: int) -> Array:
	var agents: Array = []
	var base_cash := {
		"farmer": 800.0, "miner": 1000.0, "merchant": 1500.0,
		"artisan": 1200.0, "speculator": 900.0,
	}
	var base_inventory := {
		"farmer": {"food": 120.0},
		"miner": {"ore": 80.0},
		"merchant": {"food": 30.0, "tool": 20.0},
		"artisan": {"wood": 40.0, "tool": 15.0},
		"speculator": {"ore": 60.0},
	}
	for i in range(count):
		var occ: String = OCCUPATIONS[i % OCCUPATIONS.size()]
		var a := AgentData.new()
		a.id = "agent_%04d" % i
		a.display_name = OCCUPATION_LABELS[occ] + "%02d" % (i + 1)
		a.occupation = occ
		var risk: float = [0.25, 0.45, 0.65, 0.85][i % 4]
		a.personality = {
			"risk_tolerance": risk,
			"patience": 0.3 + float((i * 7) % 60) / 100.0,
			"greed": 0.3 + float((i * 13) % 60) / 100.0,
			"sociality": 0.3 + float((i * 17) % 60) / 100.0,
		}
		a.risk_profile = risk_profile_from_tolerance(risk)
		a.cash = base_cash[occ] + float((i * 11) % 300)
		a.inventory = (base_inventory[occ] as Dictionary).duplicate()
		a.state = State.IDLE
		agents.append(a)
	return agents


static func risk_profile_from_tolerance(risk: float) -> String:
	if risk < 0.4:
		return "conservative"
	if risk < 0.7:
		return "balanced"
	return "aggressive"


static func agents_to_dict(agents: Array) -> Array:
	var out: Array = []
	for a in agents:
		out.append((a as AgentData).to_dict())
	return out


static func agents_from_dict(data: Array) -> Array:
	var out: Array = []
	for d in data:
		if d is Dictionary:
			out.append(from_dict(d))
	return out
