class_name VillageNPC
extends CharacterBody2D
## 横版像素 NPC 实体（阶段九横版改造）
## Sprite2D(AnimatedSprite2D) + AnimationPlayer 动画状态机：
##   idle 站立 / walk 行走(上下浮动) / work 干活 / trade 交易
## 横向左右移动、按方向翻转，行动结束广播 arrived 信号。

signal arrived(npc: VillageNPC, target: String)
signal selected(npc: VillageNPC)

enum State { IDLE, WALK, WORK, TRADE }

const WALK_SPEED := 55.0
const ARRIVE_EPS := 3.0

var agent: AgentData
var state: State = State.IDLE

var target_x := 0.0
var target_name := ""
var home_x := 0.0
var work_x := 0.0
var _flip := 1.0
var _idle_timer := 0.0
var _work_left := 0.0

var sprite: AnimatedSprite2D
var anim: AnimationPlayer
var name_label: Label


func _init() -> void:
	# NPC 之间不产生碰撞阻挡（自由穿行，避免扎堆卡死）
	collision_layer = 2
	collision_mask = 0
	sprite = AnimatedSprite2D.new()
	sprite.name = "Sprite"
	add_child(sprite)
	anim = AnimationPlayer.new()
	anim.name = "Anim"
	add_child(anim)
	name_label = Label.new()
	name_label.name = "NameLabel"
	add_child(name_label)
	var col := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16, 24)
	col.shape = shape
	add_child(col)


func _ready() -> void:
	_connect_click()
	_build_animations()


## 初始化：绑定 AgentData 数据、设置外观与坐标
func setup(data: AgentData, frames: SpriteFrames, home_x: float, work_x: float) -> void:
	agent = data
	sprite.sprite_frames = frames
	sprite.animation = "idle"
	self.home_x = home_x
	self.work_x = work_x
	position.x = data.pos_x if data.pos_x > 0.0 else home_x
	position.y = data.pos_y if data.pos_y > 0.0 else 0.0
	name_label.text = "%s\n%s" % [data.display_name, data.occupation_label()]
	name_label.position = Vector2(-20, -46)
	name_label.size = Vector2(40, 30)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 9)
	# 初始站立缓冲：避免生成后立即闲逛，等导演下发首个指令
	_idle_timer = 2.0 + randf() * 3.0


## 前往目标点（横向）
func walk_to(x: float, target: String) -> void:
	target_x = x
	target_name = target
	state = State.WALK
	sprite.animation = "walk"
	anim.play("walk")


## 在原地干活（循环 work_left 秒）
func do_work(seconds: float = 4.0) -> void:
	state = State.WORK
	_work_left = seconds
	sprite.animation = "work"
	anim.play("work")


## 交易动画（短暂）
func do_trade() -> void:
	state = State.TRADE
	sprite.animation = "trade"
	anim.play("trade")
	await anim.animation_finished
	if state == State.TRADE:
		to_idle()


func to_idle() -> void:
	state = State.IDLE
	_idle_timer = 1.0 + randf() * 2.0
	sprite.animation = "idle"
	anim.play("idle")


func _physics_process(delta: float) -> void:
	match state:
		State.WALK:
			_physics_walk(delta)
		State.IDLE:
			_idle_timer -= delta
			if _idle_timer <= 0.0:
				# 闲逛：随机在 home~work 之间走动
				walk_to(_rand_between(home_x, work_x), "wander")
		State.WORK:
			_work_left -= delta
			if _work_left <= 0.0:
				to_idle()


func _physics_walk(delta: float) -> void:
	var dx := target_x - position.x
	if absf(dx) < ARRIVE_EPS:
		_arrive()
		return
	var dir := signf(dx)
	velocity.x = dir * WALK_SPEED
	move_and_slide()
	if dir != _flip:
		_flip = dir
		sprite.flip_h = dir < 0.0


func _arrive() -> void:
	velocity = Vector2.ZERO
	state = State.IDLE
	sprite.animation = "idle"
	anim.play("idle")
	arrived.emit(self, target_name)


func _rand_between(a: float, b: float) -> float:
	return minf(a, b) + randf() * absf(b - a)


## 使用 AnimationPlayer + AnimationLibrary 驱动动画：walk 时叠加上下浮动
func _build_animations() -> void:
	var lib := AnimationLibrary.new()
	lib.add_animation("walk", _bob_anim(0.5, -3.0, true))
	lib.add_animation("work", _bob_anim(1.0, -2.0, true))
	lib.add_animation("trade", _bob_anim(0.8, -4.0, false))
	lib.add_animation("idle", _bob_anim(1.0, 0.0, true))
	anim.add_animation_library("", lib)


func _bob_anim(duration: float, amplitude: float, loop: bool) -> Animation:
	var a := Animation.new()
	a.length = duration
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var t := a.add_track(Animation.TYPE_VALUE)
	a.track_set_path(t, "Sprite:position:y")
	a.track_insert_key(t, 0.0, 0.0)
	a.track_insert_key(t, duration / 2.0, amplitude)
	a.track_insert_key(t, duration, 0.0)
	return a


## 点击选中（供相机跟随 / HUD 查看状态）
func _connect_click() -> void:
	var area := Area2D.new()
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(16, 24)
	shape.shape = rect
	area.add_child(shape)
	add_child(area)
	area.input_event.connect(func(_vp, event, _idx):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			selected.emit(self)
	)
