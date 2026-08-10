extends Node2D
## 横版像素村庄导演（阶段九横版改造）
## 构建村庄场景（地面/房屋/树/市场/天空/相机）+ 生成像素 NPC +
## 将 LLM 行动决策映射为 NPC 移动/动画，并把坐标同步回数据层。

const WORLD_W := 4160
const WORLD_H := 480
const GROUND_Y := 320.0
const CAMERA_ZOOM := 2.0
const MARKET_X := 2050.0

const WORK_SPOT := {
	"farmer": 350.0, "miner": 3880.0, "artisan": 1250.0,
	"merchant": 2100.0, "speculator": 2350.0,
}
const HOUSE_XS := [220, 520, 820, 1080, 1450, 1750, 2280, 2600, 2900, 3020, 3200, 3500, 3750, 3960, 700]

var assets := PixelAssets.new()
var npcs: Array = []
var tilemap: TileMap
var camera: Camera2D
var hud: CanvasLayer
var paused := false              # 暂停导演自主调度（测试/暂停用）
var _focus_npc: VillageNPC
var _pan_tween: Tween
var _hud_refresh := 0


func _ready() -> void:
	_build_background()
	_build_ground()
	_build_buildings()
	_build_npcs()
	_build_camera()
	_build_hud()
	SimulationLoop.tick.connect(_on_tick)
	GameLog.info("横版村庄就绪: %d 个 NPC / 世界宽 %dpx" % [npcs.size(), WORLD_W])


## ==================== 场景构建 ====================

func _build_background() -> void:
	var sky := ColorRect.new()
	sky.color = Color(0.42, 0.72, 0.96)
	sky.position = Vector2.ZERO
	sky.size = Vector2(WORLD_W, GROUND_Y + 8)
	add_child(sky)
	# 山丘
	for i in range(6):
		var hill := Sprite2D.new()
		hill.texture = assets.hill()
		hill.position = Vector2(i * 800.0 + 150.0, GROUND_Y - 28)
		hill.scale = Vector2(1.2 + float(i % 3) * 0.3, 1.0)
		add_child(hill)
	# 云（缓慢飘动）
	for i in range(8):
		var cl := Sprite2D.new()
		cl.texture = assets.cloud()
		cl.position = Vector2(randf() * WORLD_W, 30.0 + randf() * 150.0)
		cl.modulate.a = 0.75
		add_child(cl)
		var base_x := cl.position.x
		var tw := cl.create_tween()
		tw.set_loops()
		tw.tween_property(cl, "position:x", base_x + 220.0, 35.0)
		tw.tween_property(cl, "position:x", base_x, 35.0)


func _build_ground() -> void:
	tilemap = TileMap.new()
	var ts := TileSet.new()
	ts.tile_size = Vector2i(16, 16)
	var atlas_img := Image.create(64, 16, false, Image.FORMAT_RGBA8)
	var kinds := ["grass", "grass2", "path", "dirt"]
	for i in range(4):
		atlas_img.blit_rect(assets.ground_tile(kinds[i]).get_image(), Rect2i(0, 0, 16, 16), Vector2i(i * 16, 0))
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(atlas_img)
	src.texture_region_size = Vector2i(16, 16)
	for i in range(4):
		src.create_tile(Vector2i(i, 0))
	ts.add_source(src, 0)
	tilemap.tile_set = ts
	add_child(tilemap)

	var cols := int(WORLD_W / 16)
	var rows_top := int(GROUND_Y / 16)
	var rows_bottom := int(WORLD_H / 16)
	for x in range(cols):
		var is_path := x >= 118 and x <= 142
		for y in range(rows_top, rows_bottom):
			var tile := 0
			if y == rows_top:
				tile = 3 if not is_path else 2
			else:
				tile = 1 if (x + y) % 2 == 0 else 0
				if is_path:
					tile = 2
			tilemap.set_cell(0, Vector2i(x, y), 0, Vector2i(tile, 0))


func _build_buildings() -> void:
	var roof_colors := [
		Color(0.75, 0.3, 0.28), Color(0.5, 0.35, 0.7), Color(0.3, 0.55, 0.7),
		Color(0.7, 0.55, 0.25), Color(0.4, 0.7, 0.4),
	]
	for i in range(HOUSE_XS.size()):
		var sp := Sprite2D.new()
		sp.texture = assets.house(roof_colors[i % roof_colors.size()])
		sp.position = Vector2(HOUSE_XS[i], GROUND_Y)
		sp.scale = Vector2(1.6, 1.6)
		add_child(sp)
	for i in range(14):
		var sp := Sprite2D.new()
		sp.texture = assets.tree()
		var x := 120.0 + i * 290.0 + randf_range(-60.0, 60.0)
		if absf(x - MARKET_X) < 130.0:
			x += 220.0
		sp.position = Vector2(x, GROUND_Y)
		sp.scale = Vector2(1.4, 1.4)
		add_child(sp)
	var market := Sprite2D.new()
	market.texture = assets.market_stall()
	market.position = Vector2(MARKET_X, GROUND_Y)
	market.scale = Vector2(1.8, 1.8)
	add_child(market)
	# 集市招牌
	var market_sign := Sprite2D.new()
	market_sign.texture = assets.sign()
	market_sign.position = Vector2(MARKET_X - 55, GROUND_Y - 34)
	market_sign.scale = Vector2(1.3, 1.3)
	add_child(market_sign)
	# 水井
	var well := Sprite2D.new()
	well.texture = assets.well()
	well.position = Vector2(1600, GROUND_Y)
	well.scale = Vector2(1.6, 1.6)
	add_child(well)
	# 花丛
	for i in range(24):
		var fl := Sprite2D.new()
		fl.texture = assets.flower()
		fl.position = Vector2(90.0 + i * 180.0 + randf_range(-30, 30), GROUND_Y - 6)
		fl.scale = Vector2(1.4, 1.4)
		add_child(fl)


func _build_npcs() -> void:
	var st := EconomyEngine.state
	for i in range(st.agents.size()):
		var a: AgentData = st.agents[i]
		var home: float = HOUSE_XS[i % HOUSE_XS.size()]
		var work: float = float(WORK_SPOT.get(a.occupation, MARKET_X))
		if a.pos_x <= 0.0:
			a.pos_x = home
		a.pos_y = GROUND_Y - 12.0
		var npc := VillageNPC.new()
		npc.setup(a, assets.npc_sprite_frames(a.occupation), home, work)
		npc.arrived.connect(_on_npc_arrived)
		npc.selected.connect(_on_npc_selected)
		add_child(npc)
		npcs.append(npc)


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.zoom = Vector2(CAMERA_ZOOM, CAMERA_ZOOM)
	camera.limit_left = 0
	camera.limit_right = WORLD_W
	camera.limit_top = 0
	camera.limit_bottom = WORLD_H
	add_child(camera)
	camera.make_current()
	_start_pan()


func _build_hud() -> void:
	hud = load("res://Village/VillageHUD.gd").new()
	add_child(hud)


func _start_pan() -> void:
	camera.position = Vector2(400.0, 240.0)
	_pan_tween = create_tween()
	_pan_tween.set_loops()
	_pan_tween.tween_property(camera, "position:x", WORLD_W - 900.0, 70.0)
	_pan_tween.tween_property(camera, "position:x", 400.0, 70.0)


## ==================== 决策 → NPC 行动映射 ====================

func _on_tick(_idx: int, _delta: float) -> void:
	if paused:
		return
	var st := EconomyEngine.state
	for i in range(st.agents.size()):
		var a: AgentData = st.agents[i]
		if i >= npcs.size():
			break
		var npc: VillageNPC = npcs[i]
		# 空闲 NPC 按 Agent 当前状态决定去向
		if npc.state == VillageNPC.State.IDLE:
			match a.state:
				AgentData.State.WORKING:
					npc.walk_to(npc.work_x, "work")
				AgentData.State.HOARDING, AgentData.State.TRADING:
					npc.walk_to(MARKET_X, "trade")
				AgentData.State.IDLE:
					npc.walk_to(npc.home_x, "home")
		# 同步坐标回数据层（供存档/统计）
		a.pos_x = npc.position.x
		a.pos_y = npc.position.y
		a.anim = npc.sprite.animation
	_hud_refresh += 1
	if hud != null and hud.has_method("refresh"):
		hud.refresh()


func _on_npc_arrived(npc: VillageNPC, target: String) -> void:
	match target:
		"work":
			npc.do_work(5.0)
		"trade":
			npc.do_trade()
		"home", "wander":
			npc.to_idle()
	npc.agent.pos_x = npc.position.x
	npc.agent.pos_y = npc.position.y


func _on_npc_selected(npc: VillageNPC) -> void:
	_focus_npc = npc
	if _pan_tween != null and _pan_tween.is_valid():
		_pan_tween.kill()
	GameLog.info("选中市民: %s (%s) 资金%.0f" % [npc.agent.display_name, npc.agent.occupation_label(), npc.agent.cash])


## 供 HUD 对话使用：返回当前聚焦的市民 Agent（无则 null）
func focus_npc_agent() -> AgentData:
	if _focus_npc != null:
		return _focus_npc.agent
	return null


func _process(delta: float) -> void:
	if _focus_npc != null:
		camera.position.x = lerpf(camera.position.x, _focus_npc.position.x, 3.0 * delta)
		camera.position.y = lerpf(camera.position.y, _focus_npc.position.y - 120.0, 3.0 * delta)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# 点击空白处取消聚焦，恢复自动平移
		if _focus_npc != null:
			_focus_npc = null
			camera.position.y = 240.0
			_start_pan()
