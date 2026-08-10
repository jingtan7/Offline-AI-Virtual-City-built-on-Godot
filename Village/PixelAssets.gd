class_name PixelAssets
extends RefCounted
## 程序化像素资源生成器（横版村庄）—— 零外部素材、完全离线
## 用 Image 逐像素生成：地面瓦片/房屋/树/市场摊位/云/山丘/像素小人分帧动画
## 所有纹理缓存复用。

const TILE := 16
const NPC_W := 16
const NPC_H := 24

var _cache: Dictionary = {}
var _rng := RandomNumberGenerator.new()

# 职业配色（对应截图紫色小人风格 + 职业差异化）
const OCCUPATION_COLORS := {
	"farmer": {"body": Color(0.35, 0.72, 0.35), "hat": Color(0.9, 0.8, 0.45)},
	"miner": {"body": Color(0.3, 0.55, 0.85), "hat": Color(0.95, 0.85, 0.3)},
	"merchant": {"body": Color(0.55, 0.35, 0.75), "hat": Color(0.75, 0.35, 0.75)},
	"artisan": {"body": Color(0.85, 0.55, 0.25), "hat": Color(0.6, 0.45, 0.3)},
	"speculator": {"body": Color(0.8, 0.3, 0.3), "hat": Color(0.15, 0.15, 0.2)},
}


func _init() -> void:
	_rng.seed = 20260810


func _new_img(w: int, h: int) -> Image:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img


func _fill(img: Image, color: Color) -> void:
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			img.set_pixel(x, y, color)


## ---------- 地面瓦片 ----------

func ground_tile(kind: String) -> ImageTexture:
	var key := "ground_" + kind
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(TILE, TILE)
	var base := Color(0.30, 0.55, 0.24)
	var speck := Color(0.36, 0.62, 0.28)
	match kind:
		"grass":
			base = Color(0.30, 0.55, 0.24)
			speck = Color(0.36, 0.62, 0.28)
		"grass2":
			base = Color(0.33, 0.58, 0.26)
			speck = Color(0.28, 0.51, 0.22)
		"path":
			base = Color(0.72, 0.62, 0.45)
			speck = Color(0.66, 0.56, 0.40)
		"dirt":
			base = Color(0.52, 0.36, 0.22)
			speck = Color(0.46, 0.31, 0.18)
	_fill(img, base)
	for i in range(8):
		img.set_pixel(_rng.randi_range(0, TILE - 1), _rng.randi_range(0, TILE - 1), speck)
	if kind == "grass" or kind == "grass2":
		for x in range(TILE):
			if _rng.randf() < 0.6:
				img.set_pixel(x, 0, Color(0.24, 0.5, 0.19))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## ---------- 房屋 ----------

func house(color_roof: Color = Color(0.75, 0.3, 0.28)) -> ImageTexture:
	var key := "house_" + color_roof.to_html()
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(48, 40)
	_fill_rect(img, 6, 18, 42, 40, Color(0.86, 0.8, 0.65))
	for gy in range(18, 40, 4):
		for gx in range(6, 42, 4):
			img.set_pixel(gx, gy, Color(0.78, 0.71, 0.56))
	for i in range(8):
		_fill_rect(img, 4 + i, 10 + i, 44 - i, 12 + i, color_roof)
	_fill_rect(img, 4, 10, 44, 12, color_roof)
	_fill_rect(img, 21, 28, 27, 40, Color(0.4, 0.28, 0.18))
	img.set_pixel(26, 34, Color(0.95, 0.85, 0.4))
	_fill_rect(img, 9, 22, 15, 27, Color(0.55, 0.8, 0.95))
	_fill_rect(img, 33, 22, 39, 27, Color(0.55, 0.8, 0.95))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## ---------- 树 ----------

func tree() -> ImageTexture:
	var key := "tree"
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(24, 36)
	_fill_rect(img, 10, 20, 14, 36, Color(0.45, 0.3, 0.16))
	_fill_circle(img, 12, 12, 9, Color(0.2, 0.48, 0.2))
	_fill_circle(img, 7, 16, 5, Color(0.26, 0.55, 0.24))
	_fill_circle(img, 17, 16, 5, Color(0.24, 0.52, 0.22))
	for i in range(10):
		img.set_pixel(_rng.randi_range(5, 19), _rng.randi_range(5, 15), Color(0.32, 0.6, 0.28))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## ---------- 市场摊位 ----------

func market_stall() -> ImageTexture:
	var key := "market"
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(40, 28)
	_fill_rect(img, 4, 14, 7, 28, Color(0.5, 0.36, 0.22))
	_fill_rect(img, 33, 14, 36, 28, Color(0.5, 0.36, 0.22))
	_fill_rect(img, 3, 14, 37, 19, Color(0.72, 0.6, 0.4))
	for i in range(5):
		var col := Color(0.85, 0.3, 0.3) if i % 2 == 0 else Color(0.95, 0.92, 0.85)
		_fill_rect(img, 0 + i * 8, 2, 8 + i * 8, 10, col)
	_fill_rect(img, 0, 10, 40, 13, Color(0.75, 0.7, 0.6))
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## ---------- 云 / 山丘 ----------

func cloud() -> ImageTexture:
	var key := "cloud"
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(48, 20)
	var c := Color(1, 1, 1, 0.85)
	_fill_circle(img, 14, 12, 6, c)
	_fill_circle(img, 24, 9, 8, c)
	_fill_circle(img, 34, 13, 6, c)
	_fill_rect(img, 10, 13, 38, 17, c)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


func hill() -> ImageTexture:
	var key := "hill"
	if _cache.has(key):
		return _cache[key]
	var img := _new_img(120, 60)
	var c := Color(0.25, 0.42, 0.22, 0.9)
	_fill_circle(img, 30, 60, 32, c)
	_fill_circle(img, 85, 60, 24, c)
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## ---------- 像素小人分帧 ----------

## 生成某职业小人某一动画帧。anim: idle/walk1/walk2/work/trade
func npc_frame(occupation: String, anim: String) -> ImageTexture:
	var key := "npc_%s_%s" % [occupation, anim]
	if _cache.has(key):
		return _cache[key]
	var colors: Dictionary = OCCUPATION_COLORS.get(occupation, OCCUPATION_COLORS["merchant"])
	var skin := Color(0.95, 0.78, 0.6)
	var body: Color = colors["body"]
	var hat: Color = colors["hat"]
	var leg := Color(0.25, 0.25, 0.3)
	var shoe := Color(0.15, 0.12, 0.1)

	var img := _new_img(NPC_W, NPC_H)
	# 腿
	match anim:
		"walk1":
			_fill_rect(img, 5, 15, 7, 22, leg)
			_fill_rect(img, 8, 15, 10, 21, leg)
			img.set_pixel(5, 22, shoe)
		"walk2":
			_fill_rect(img, 8, 15, 10, 22, leg)
			_fill_rect(img, 5, 15, 7, 21, leg)
			img.set_pixel(8, 22, shoe)
		"work":
			_fill_rect(img, 6, 15, 9, 22, leg)
			img.set_pixel(6, 22, shoe)
			img.set_pixel(9, 22, shoe)
		_:
			_fill_rect(img, 6, 15, 9, 22, leg)
			img.set_pixel(6, 22, shoe)
			img.set_pixel(9, 22, shoe)
	# 身体
	_fill_rect(img, 5, 7, 10, 15, body)
	# 手臂
	if anim == "work":
		_fill_rect(img, 2, 8, 5, 11, skin)
		_fill_rect(img, 2, 10, 4, 15, Color(0.6, 0.5, 0.35))
		_fill_rect(img, 10, 8, 13, 11, skin)
	elif anim == "trade":
		_fill_rect(img, 2, 8, 5, 10, skin)
		_fill_rect(img, 10, 8, 13, 10, skin)
	else:
		_fill_rect(img, 2, 8, 4, 12, skin)
		_fill_rect(img, 11, 8, 13, 12, skin)
	# 头
	_fill_rect(img, 6, 2, 9, 7, skin)
	# 发型/帽子
	match occupation:
		"farmer":
			_fill_rect(img, 6, 0, 9, 2, hat)
			_fill_rect(img, 5, 2, 10, 3, hat)
		"miner":
			_fill_rect(img, 6, 0, 9, 2, hat)
			img.set_pixel(9, 1, Color(1, 1, 0.8))
		"merchant":
			_fill_rect(img, 6, 0, 9, 2, hat)
			img.set_pixel(7, 0, Color(1, 0.9, 0.5))
		"artisan":
			_fill_rect(img, 6, 0, 9, 1, hat)
		"speculator":
			_fill_rect(img, 5, 0, 10, 2, hat)
			img.set_pixel(7, 1, Color(1, 0.85, 0.3))
	# 眼睛
	img.set_pixel(7, 5, Color(0.1, 0.1, 0.12))
	img.set_pixel(8, 5, Color(0.1, 0.1, 0.12))

	var tex := ImageTexture.create_from_image(img)
	_cache[key] = tex
	return tex


## 某职业的完整 SpriteFrames（idle/walk/work/trade）
func npc_sprite_frames(occupation: String) -> SpriteFrames:
	var key := "sf_" + occupation
	if _cache.has(key):
		return _cache[key]
	var sf := SpriteFrames.new()
	sf.add_animation("idle")
	sf.set_animation_speed("idle", 2.0)
	sf.add_frame("idle", npc_frame(occupation, "idle"))
	sf.add_animation("walk")
	sf.set_animation_speed("walk", 6.0)
	sf.add_frame("walk", npc_frame(occupation, "walk1"))
	sf.add_frame("walk", npc_frame(occupation, "walk2"))
	sf.add_animation("work")
	sf.set_animation_speed("work", 3.0)
	sf.add_frame("work", npc_frame(occupation, "work"))
	sf.add_animation("trade")
	sf.set_animation_speed("trade", 3.0)
	sf.add_frame("trade", npc_frame(occupation, "trade"))
	_cache[key] = sf
	return sf


## ---------- 工具方法 ----------

func _fill_rect(img: Image, x0: int, y0: int, x1: int, y1: int, color: Color) -> void:
	for y in range(y0, y1):
		for x in range(x0, x1):
			img.set_pixel(x, y, color)


func _fill_circle(img: Image, cx: int, cy: int, r: int, color: Color) -> void:
	for y in range(cy - r, cy + r + 1):
		for x in range(cx - r, cx + r + 1):
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= r * r:
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					img.set_pixel(x, y, color)
