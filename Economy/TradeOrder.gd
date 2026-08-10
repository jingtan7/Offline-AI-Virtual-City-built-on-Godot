class_name TradeOrder
extends RefCounted
## 城邦交易订单结构（阶段二）
## 字段覆盖：挂单类型、委托价格、委托数量、成交状态、挂单主体(玩家/AI Agent)、
## 挂单时间、订单有效期。

enum Type { BUY, SELL }
enum Status { PENDING, PARTIAL, FILLED, CANCELED, EXPIRED }

var id: String = ""                 # 订单ID
var order_type: Type = Type.BUY     # 挂单类型：求购/出售
var commodity_id: String = ""       # 物资ID
var price: float = 0.0              # 委托价格
var quantity: float = 0.0           # 委托数量
var filled_quantity: float = 0.0    # 已成交数量
var status: Status = Status.PENDING # 成交状态
var owner_id: String = ""           # 挂单主体ID（player 或 agent_xxxx）
var owner_kind: String = "agent"    # 挂单主体类型：player / agent
var created_at: int = 0             # 挂单时间（毫秒时间戳）
var expires_at: int = 0             # 订单有效期（绝对毫秒时间戳）


## 剩余未成交数量
func remaining() -> float:
	return maxf(0.0, quantity - filled_quantity)


## 是否仍处于可成交状态
func is_active() -> bool:
	return status == Status.PENDING or status == Status.PARTIAL


func type_label() -> String:
	return "求购" if order_type == Type.BUY else "出售"


func status_label() -> String:
	match status:
		Status.PENDING:
			return "挂单中"
		Status.PARTIAL:
			return "部分成交"
		Status.FILLED:
			return "全部成交"
		Status.CANCELED:
			return "已撤销"
		Status.EXPIRED:
			return "已过期"
	return "未知"


## 便捷构造
static func create(
	order_id: String,
	order_type: Type,
	commodity_id: String,
	price: float,
	quantity: float,
	owner_id: String,
	owner_kind: String = "agent",
	created_at: int = 0,
	valid_msec: int = 60000
) -> TradeOrder:
	var o := TradeOrder.new()
	o.id = order_id
	o.order_type = order_type
	o.commodity_id = commodity_id
	o.price = price
	o.quantity = quantity
	o.owner_id = owner_id
	o.owner_kind = owner_kind
	o.created_at = created_at
	o.expires_at = created_at + valid_msec
	return o


func to_dict() -> Dictionary:
	return {
		"id": id, "order_type": int(order_type), "commodity_id": commodity_id,
		"price": price, "quantity": quantity, "filled_quantity": filled_quantity,
		"status": int(status), "owner_id": owner_id, "owner_kind": owner_kind,
		"created_at": created_at, "expires_at": expires_at,
	}


static func from_dict(d: Dictionary) -> TradeOrder:
	var o := TradeOrder.new()
	o.id = str(d.get("id", ""))
	o.order_type = int(d.get("order_type", 0))
	o.commodity_id = str(d.get("commodity_id", ""))
	o.price = float(d.get("price", 0.0))
	o.quantity = float(d.get("quantity", 0.0))
	o.filled_quantity = float(d.get("filled_quantity", 0.0))
	o.status = int(d.get("status", 0))
	o.owner_id = str(d.get("owner_id", ""))
	o.owner_kind = str(d.get("owner_kind", "agent"))
	o.created_at = int(d.get("created_at", 0))
	o.expires_at = int(d.get("expires_at", 0))
	return o


static func orders_to_dict(orders: Array) -> Array:
	var out: Array = []
	for o in orders:
		out.append((o as TradeOrder).to_dict())
	return out


static func orders_from_dict(data: Array) -> Array:
	var out: Array = []
	for d in data:
		if d is Dictionary:
			out.append(from_dict(d))
	return out
