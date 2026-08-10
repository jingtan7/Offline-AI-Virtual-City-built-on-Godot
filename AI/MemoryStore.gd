extends Node
## 本地向量记忆数据库（阶段五）—— 零依赖、纯本地、离线
## 字符 bigram 哈希 TF 向量 + 余弦相似度检索；JSON 持久化到 user://
## 承载：Agent 行为记录、城邦事件、行情动态、玩家交易习惯（自适应博弈）。
## 注意：作为 Autoload 单例使用（勿加 class_name，避免遮蔽单例名）。

const DIM := 512
const SAVE_PATH := "user://Data/memory/memory_db.json"

var memories: Array = []
var _seq := 0


func _ready() -> void:
	load_db()
	GameLog.info("记忆库就绪: %d 条记忆" % memories.size())


## 文本 → 归一化向量（确定性：同文本同向量）
func embed(text: String) -> PackedFloat32Array:
	var vec := PackedFloat32Array()
	vec.resize(DIM)
	vec.fill(0.0)
	for t in _tokenize(text):
		var idx: int = absi(hash(t)) % DIM
		vec[idx] += 1.0
	var norm := 0.0
	for i in range(DIM):
		norm += vec[i] * vec[i]
	norm = sqrt(norm)
	if norm > 0.0:
		for i in range(DIM):
			vec[i] /= norm
	return vec


func _tokenize(text: String) -> PackedStringArray:
	var clean := text.to_lower().strip_edges()
	var out := PackedStringArray()
	if clean.is_empty():
		return out
	for i in range(clean.length() - 1):
		out.append(clean.substr(i, 2))
	out.append(clean)
	return out


static func cosine(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var n := mini(a.size(), b.size())
	var dot := 0.0
	for i in range(n):
		dot += a[i] * b[i]
	return dot


## 写入一条记忆，返回记忆记录
func add_memory(text: String, category: String = "", metadata: Dictionary = {}) -> Dictionary:
	_seq += 1
	var m := {
		"id": _seq, "category": category, "text": text,
		"vector": embed(text), "metadata": metadata, "time": Time.get_ticks_msec(),
	}
	memories.append(m)
	return m


## 检索 top-k（余弦相似度）
func search(query: String, k: int = 3) -> Array:
	if memories.is_empty():
		return []
	var qv := embed(query)
	var scored: Array = []
	for m in memories:
		var s := cosine(qv, m.get("vector", PackedFloat32Array()))
		scored.append({
			"score": s, "id": m.get("id", 0), "text": m.get("text", ""),
			"category": m.get("category", ""), "metadata": m.get("metadata", {}),
		})
	scored.sort_custom(func(a, b): return float(a["score"]) > float(b["score"]))
	var out: Array = []
	for i in range(mini(k, scored.size())):
		out.append(scored[i])
	return out


## ==================== 领域记忆封装 ====================

## Agent 行为入库（RAG 决策依据）
func record_behavior(agent_id: String, action: String, cid: String, price: float, qty: float) -> void:
	var text := "%s 执行 %s 操作: %s %.1f 单位 @%.2f" % [agent_id, action, cid, qty, price]
	add_memory(text, "behavior", {"agent": agent_id, "action": action, "commodity": cid})
	RAGService.record(agent_id, text, "behavior", {"action": action, "commodity": cid})


## 城邦重大事件入库
func record_event(ev: Dictionary) -> void:
	var text := "%s: %s" % [ev.get("label", "事件"), ev.get("desc", "")]
	add_memory(text, "event", ev)
	RAGService.record("city", text, "event", ev)


## 玩家交易习惯入库（自适应博弈：Agent 可检索到城主操作习惯）
func record_player_trade(cid: String, side: String, price: float, qty: float) -> void:
	var side_cn := "买入" if side == "buy" else "卖出"
	var text := "城主 %s %s: %.1f 单位 @%.2f" % [side_cn, _commodity_label(cid), qty, price]
	add_memory(text, "player_trade", {"commodity": cid, "side": side})
	RAGService.record("player", text, "player_trade", {"commodity": cid, "side": side})


## 行情时序摘要入库（供 RAG 检索历史行情走势）
func record_market_summary(state: CityState) -> void:
	var parts: Array = []
	for cid in state.commodities:
		var c: Commodity = state.commodities[cid]
		parts.append("%s=%.1f" % [c.name, c.current_price])
	var text := "tick#%d 城邦行情: %s" % [state.tick, "、".join(parts)]
	add_memory(text, "market")
	RAGService.record("city", text, "market", {"tick": state.tick})


func _commodity_label(cid: String) -> String:
	match cid:
		"food": return "粮食"
		"wood": return "木材"
		"ore": return "矿石"
		"potion": return "药剂"
		"tool": return "工具"
		"supply": return "耗材"
	return cid


func clear() -> void:
	memories = []
	_seq = 0


## ==================== 持久化 ====================

func save_db() -> bool:
	DirAccess.make_dir_recursive_absolute("user://Data/memory")
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	var out: Array = []
	for m in memories:
		var vm: Dictionary = m.duplicate()
		vm["vector"] = _vec_to_array(m.get("vector", PackedFloat32Array()))
		out.append(vm)
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	return true


func load_db() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if not (parsed is Array):
		return
	memories = []
	var max_id := 0
	for d in parsed:
		var vm: Dictionary = (d as Dictionary).duplicate()
		vm["vector"] = _array_to_vec(vm.get("vector", []))
		memories.append(vm)
		max_id = maxi(max_id, int(vm.get("id", 0)))
	_seq = max_id


func _vec_to_array(vec: PackedFloat32Array) -> Array:
	var out: Array = []
	for i in range(vec.size()):
		out.append(vec[i])
	return out


func _array_to_vec(arr: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for x in arr:
		out.append(float(x))
	return out
