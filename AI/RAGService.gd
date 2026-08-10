extends Node
## ChromaDB 本地 RAG 向量记忆服务（阶段九存储改造）
## 通过 ChromaDB REST API (v2) 实现每 NPC 独立记忆库；未启动时自动回退内置 MemoryStore。
## 嵌入向量复用 MemoryStore.embed（零模型下载、完全离线）。

const BASE := "http://127.0.0.1:8000"
const TENANT := "default_tenant"
const DATABASE := "default_database"

var available := false

var _collection_ids: Dictionary = {}
var _pending_create: Dictionary = {}


func _ready() -> void:
	check_available()


func _coll_url(coll_id: String) -> String:
	return "%s/api/v2/tenants/%s/databases/%s/collections/%s" % [BASE, TENANT, DATABASE, coll_id]


func _collections_url() -> String:
	return "%s/api/v2/tenants/%s/databases/%s/collections" % [BASE, TENANT, DATABASE]


## 异步探活
func check_available() -> void:
	_check_async()


func _check_async() -> void:
	var http := HTTPRequest.new()
	http.timeout = 3.0
	add_child(http)
	var err := http.request("%s/api/v2/healthcheck" % BASE, [], HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		available = false
		return
	var result: Array = await http.request_completed
	http.queue_free()
	available = result.size() >= 3 and result[0] == HTTPRequest.RESULT_SUCCESS and result[1] == 200
	GameLog.info("ChromaDB %s（RAG 向量记忆）" % ("在线" if available else "不可用，回退内置 MemoryStore"))
	if available:
		_prewarm_collections()


## 预创建常用集合（city/player/所有Agent），避免运行时并发创建竞争
func _prewarm_collections() -> void:
	var names: Array = ["city", "player"]
	var st := EconomyEngine.state
	if st != null:
		for a in st.agents:
			names.append((a as AgentData).id)
	for n in names:
		var id := await ensure_collection(n)
		if not id.is_empty():
			_collection_ids[n] = id
	GameLog.info("ChromaDB 集合预创建完成: %d 个" % _collection_ids.size())


## 写入一条记忆（fire-and-forget，异步推送到 ChromaDB）
func record(npc_key: String, text: String, category: String = "", metadata: Dictionary = {}) -> void:
	if not available:
		return
	_push_async(npc_key, text, category, metadata)


func _push_async(npc_key: String, text: String, category: String, metadata: Dictionary) -> void:
	var coll_id := await ensure_collection(npc_key)
	if coll_id.is_empty():
		return
	var meta: Dictionary = metadata.duplicate()
	if not category.is_empty():
		meta["category"] = category
	var body := JSON.stringify({
		"ids": ["m%d" % Time.get_ticks_usec()],
		"embeddings": [_vec_to_array(MemoryStore.embed(text))],
		"documents": [text],
		"metadatas": [meta],
	})
	var http := HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	var err := http.request(_coll_url(coll_id) + "/add", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return
	var result: Array = await http.request_completed
	http.queue_free()
	if result.size() < 3 or result[0] != HTTPRequest.RESULT_SUCCESS:
		GameLog.warn("ChromaDB 写入失败: %s" % npc_key)


## 检索 top-k。返回 [{ text, score, metadata }]，ChromaDB 不可用时回退 MemoryStore。
func search(npc_key: String, query: String, k: int = 3) -> Array:
	if not available:
		return _fallback_search(query, k)
	var coll_id := await ensure_collection(npc_key)
	if coll_id.is_empty():
		return _fallback_search(query, k)
	var body := JSON.stringify({
		"query_embeddings": [_vec_to_array(MemoryStore.embed(query))],
		"n_results": k,
		"include": ["documents", "distances", "metadatas"],
	})
	var http := HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	var err := http.request(_coll_url(coll_id) + "/query", ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return _fallback_search(query, k)
	var result: Array = await http.request_completed
	http.queue_free()
	if result.size() < 3 or result[0] != HTTPRequest.RESULT_SUCCESS:
		return _fallback_search(query, k)
	var parsed = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if not (parsed is Dictionary):
		return _fallback_search(query, k)
	var docs: Array = parsed.get("documents", [])
	var dists: Array = parsed.get("distances", [])
	var metas: Array = parsed.get("metadatas", [])
	var out: Array = []
	if docs.size() > 0 and docs[0] is Array:
		var inner: Array = docs[0]
		var inner_d: Array = dists[0] if dists.size() > 0 and dists[0] is Array else []
		var inner_m: Array = metas[0] if metas.size() > 0 and metas[0] is Array else []
		for i in range(inner.size()):
			var score := 1.0 / (1.0 + float(inner_d[i])) if i < inner_d.size() else 0.0
			out.append({
				"text": str(inner[i]),
				"score": score,
				"metadata": inner_m[i] if i < inner_m.size() and inner_m[i] is Dictionary else {},
			})
	return out


func _fallback_search(query: String, k: int) -> Array:
	return MemoryStore.search(query, k)


## ==================== 集合管理 ====================

func ensure_collection(name: String) -> String:
	if _collection_ids.has(name):
		return _collection_ids[name]
	# 自旋锁：避免并发创建同一集合（ChromaDB 重复创建返回 409）
	while _pending_create.get(name, false):
		await get_tree().create_timer(0.2).timeout
		if _collection_ids.has(name):
			return _collection_ids[name]
	_pending_create[name] = true
	var id := await _find_collection(name)
	if id.is_empty():
		id = await _create_collection(name)
	_pending_create[name] = false
	if not id.is_empty():
		_collection_ids[name] = id
	return id


func _find_collection(name: String) -> String:
	var http := HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	var err := http.request(_collections_url(), [], HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return ""
	var result: Array = await http.request_completed
	http.queue_free()
	if result.size() < 3 or result[0] != HTTPRequest.RESULT_SUCCESS:
		return ""
	var parsed = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if not (parsed is Array):
		return ""
	for c in parsed:
		if str(c.get("name", "")) == name:
			return str(c.get("id", ""))
	return ""


func _create_collection(name: String) -> String:
	var http := HTTPRequest.new()
	http.timeout = 5.0
	add_child(http)
	var body := JSON.stringify({"name": name})
	var err := http.request(_collections_url(), ["Content-Type: application/json"], HTTPClient.METHOD_POST, body)
	if err != OK:
		http.queue_free()
		return ""
	var result: Array = await http.request_completed
	http.queue_free()
	if result.size() < 3 or result[0] != HTTPRequest.RESULT_SUCCESS:
		return ""
	var parsed = JSON.parse_string((result[3] as PackedByteArray).get_string_from_utf8())
	if parsed is Dictionary:
		return str(parsed.get("id", ""))
	return ""


func _vec_to_array(vec: PackedFloat32Array) -> Array:
	var out: Array = []
	for i in range(vec.size()):
		out.append(vec[i])
	return out
