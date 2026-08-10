class_name EconomyEvent
extends RefCounted
## 城邦随机事件系统（阶段三）
## 涵盖：天灾减产 / 丰收增产 / 外来商队入驻 / 物资禁令 / 流行消费趋势 / 工坊迭代升级。
## 触发后制造经济波动，提升仿真真实性与博弈复杂度。

enum Kind { DISASTER, HARVEST, CARAVAN, BAN, FAD, WORKSHOP }

const KIND_LABELS := {
	Kind.DISASTER: "天灾减产", Kind.HARVEST: "丰收增产", Kind.CARAVAN: "外来商队入驻",
	Kind.BAN: "物资禁令", Kind.FAD: "流行消费趋势", Kind.WORKSHOP: "工坊迭代升级",
}


## 掷事件骰。probability 0~1。未触发返回空字典 {}，否则返回事件结构：
## { kind, label, desc, effects:{ commodity, ticks, output_mult, heat_boost, volume_mult, price_limit_mult, stock_mult, stock_delta } }
static func roll(state: CityState, rng: RandomNumberGenerator, probability: float) -> Dictionary:
	if rng.randf() > probability:
		return {}
	var kind: int = Kind.values()[rng.randi_range(0, Kind.values().size() - 1)]
	return build(state, rng, kind)


static func build(state: CityState, rng: RandomNumberGenerator, kind: int) -> Dictionary:
	var cids: Array = state.commodities.keys()
	if cids.is_empty():
		return {}
	var cid: String = cids[rng.randi_range(0, cids.size() - 1)]
	var commodity: Commodity = state.commodities[cid]
	var effects := {}
	var desc := ""

	match kind:
		Kind.DISASTER:
			desc = "城邦「%s」遭受天灾，产出锐减、存量下降！" % commodity.name
			effects = {"commodity": cid, "stock_mult": 0.85, "output_mult": 0.6, "ticks": 10, "heat_boost": 0.3}
		Kind.HARVEST:
			desc = "城邦「%s」喜获丰收，产出大幅增加。" % commodity.name
			effects = {"commodity": cid, "output_mult": 1.6, "ticks": 8, "heat_boost": -0.1}
		Kind.CARAVAN:
			desc = "外来商队入驻，带来大量「%s」，市场成交活跃。" % commodity.name
			effects = {"commodity": cid, "stock_delta": commodity.total_stock * 0.12, "ticks": 5, "heat_boost": 0.2}
		Kind.BAN:
			desc = "城主颁布「%s」限购令，交易量受压制、价格波动收窄。" % commodity.name
			effects = {"commodity": cid, "volume_mult": 0.4, "ticks": 12, "price_limit_mult": 0.5}
		Kind.FAD:
			desc = "「%s」突然成为流行趋势，市场热度飙升！" % commodity.name
			effects = {"commodity": cid, "heat_boost": 0.5, "ticks": 10, "volume_mult": 2.0}
		Kind.WORKSHOP:
			desc = "城邦工坊迭代升级，「%s」产出效率提升。" % commodity.name
			effects = {"commodity": cid, "output_mult": 1.4, "ticks": 15, "heat_boost": 0.1}
		_:
			return {}

	return {"kind": int(kind), "label": KIND_LABELS.get(kind, "未知事件"), "desc": desc, "effects": effects}
