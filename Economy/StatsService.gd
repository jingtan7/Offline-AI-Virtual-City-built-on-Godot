class_name StatsService
extends RefCounted
## 城邦数据复盘统计（阶段八）
## 总资产 / 玩家收益率 / Agent 行为统计 / 行情统计。

## 城邦总资产 = 玩家(资金+库存市值) + 所有 Agent(资金+库存市值)
static func city_total_assets(state: CityState, prices: Dictionary) -> float:
	var total := state.player.cash + state.player.inventory_value(prices)
	for a in state.agents:
		total += (a as AgentData).cash
		for cid in (a as AgentData).inventory:
			total += float((a as AgentData).inventory[cid]) * float(prices.get(cid, 0.0))
	return total


## 玩家收益率（相对初始运营资金）
static func player_roi(state: CityState, prices: Dictionary) -> float:
	var cur := state.player.total_assets(prices)
	var init := maxf(0.01, state.player.initial_capital)
	return (cur - init) / init * 100.0


## Agent 行为统计
static func agent_activity(state: CityState) -> Dictionary:
	var total_trades := 0
	var llm_controlled := 0
	var by_occupation := {}
	for a in state.agents:
		total_trades += (a as AgentData).trade_history.size()
		if (a as AgentData).llm_controlled:
			llm_controlled += 1
		by_occupation[(a as AgentData).occupation] = int(by_occupation.get((a as AgentData).occupation, 0)) + 1
	return {
		"total_trades": total_trades, "llm_controlled": llm_controlled,
		"agents": state.agents.size(), "by_occupation": by_occupation,
	}


## 单物资行情统计
static func commodity_summary(state: CityState, cid: String) -> Dictionary:
	var c: Commodity = state.commodities.get(cid, null)
	if c == null:
		return {}
	var bars: Array = state.market_bars.get(cid, [])
	var high := c.current_price
	var low := c.current_price
	var sum := 0.0
	for b in bars:
		high = maxf(high, float(b.close))
		low = minf(low, float(b.close))
		sum += float(b.close)
	var avg := sum / float(maxi(1, bars.size()))
	var total_volume := 0.0
	for b in bars:
		total_volume += float(b.volume)
	return {
		"id": cid, "name": c.name, "price": c.current_price,
		"high": high, "low": low, "avg": avg, "bars": bars.size(),
		"total_volume": total_volume,
	}
