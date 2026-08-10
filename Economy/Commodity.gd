class_name Commodity
extends RefCounted
## 城邦核心物资数据结构（阶段二）
## 字段覆盖：物资ID、名称、品类、初始基准价、城邦总存量、产出/消耗速率、
## 稀缺波动率、市场热度系数、单日物价波动限制。

var id: String = ""
var name: String = ""
var category: String = "survival"        # survival=生存 / industrial=工业 / trade=贸易
var base_price: float = 0.0              # 初始基准价
var current_price: float = 0.0           # 实时物价（阶段三引擎每 tick 迭代）
var total_stock: float = 0.0             # 城邦总存量
var output_rate: float = 0.0             # 产出速率（每 tick）
var consume_rate: float = 0.0            # 消耗速率（每 tick）
var scarcity_volatility: float = 0.0     # 稀缺波动率（0~1）
var heat_factor: float = 0.5             # 市场热度系数（0~1）
var daily_price_limit: float = 0.1       # 单日物价波动限制（比例，如 0.1 = ±10%）


func _init(
	p_id: String = "",
	p_name: String = "",
	p_category: String = "survival",
	p_base_price: float = 0.0,
	p_stock: float = 0.0,
	p_output: float = 0.0,
	p_consume: float = 0.0,
	p_scarcity: float = 0.0,
	p_heat: float = 0.5,
	p_limit: float = 0.1,
	p_current: float = 0.0
) -> void:
	id = p_id
	name = p_name
	category = p_category
	base_price = p_base_price
	current_price = p_base_price if p_current <= 0.0 else p_current
	total_stock = p_stock
	output_rate = p_output
	consume_rate = p_consume
	scarcity_volatility = p_scarcity
	heat_factor = p_heat
	daily_price_limit = p_limit


## 净产出（产出 - 消耗）。>0 供大于求，<0 供不应求。
func net_rate() -> float:
	return output_rate - consume_rate


func category_label() -> String:
	match category:
		"survival":
			return "生存物资"
		"industrial":
			return "工业物资"
		"trade":
			return "贸易物资"
	return category


## 默认城邦物资表：粮食/木材/矿石/药剂/工具/耗材
static func default_commodities() -> Array:
	return [
		Commodity.new("food", "粮食", "survival", 12.5, 3200.0, 80.0, 75.0, 0.08, 0.6, 0.10),
		Commodity.new("wood", "木材", "industrial", 8.2, 2100.0, 60.0, 55.0, 0.06, 0.5, 0.10),
		Commodity.new("ore", "矿石", "industrial", 15.0, 900.0, 40.0, 45.0, 0.12, 0.8, 0.15),
		Commodity.new("potion", "药剂", "survival", 32.0, 400.0, 10.0, 12.0, 0.15, 0.9, 0.20),
		Commodity.new("tool", "工具", "trade", 25.5, 300.0, 12.0, 10.0, 0.10, 0.7, 0.15),
		Commodity.new("supply", "耗材", "trade", 5.5, 1500.0, 45.0, 40.0, 0.05, 0.4, 0.08),
	]


func to_dict() -> Dictionary:
	return {
		"id": id, "name": name, "category": category,
		"base_price": base_price, "current_price": current_price,
		"total_stock": total_stock,
		"output_rate": output_rate, "consume_rate": consume_rate,
		"scarcity_volatility": scarcity_volatility,
		"heat_factor": heat_factor, "daily_price_limit": daily_price_limit,
	}


static func from_dict(d: Dictionary) -> Commodity:
	var c := Commodity.new()
	c.id = str(d.get("id", ""))
	c.name = str(d.get("name", ""))
	c.category = str(d.get("category", "survival"))
	c.base_price = float(d.get("base_price", 0.0))
	c.current_price = float(d.get("current_price", c.base_price))
	c.total_stock = float(d.get("total_stock", 0.0))
	c.output_rate = float(d.get("output_rate", 0.0))
	c.consume_rate = float(d.get("consume_rate", 0.0))
	c.scarcity_volatility = float(d.get("scarcity_volatility", 0.0))
	c.heat_factor = float(d.get("heat_factor", 0.5))
	c.daily_price_limit = float(d.get("daily_price_limit", 0.1))
	return c


static func commodities_to_dict(commodities: Dictionary) -> Dictionary:
	var out := {}
	for cid in commodities:
		out[cid] = (commodities[cid] as Commodity).to_dict()
	return out


static func commodities_from_dict(data: Dictionary) -> Dictionary:
	var out := {}
	for cid in data:
		out[cid] = from_dict(data[cid])
	return out
