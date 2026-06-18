extends Area2D
class_name Pickup

enum Type { APPLE, CHERRY, STAR, HEART, COIN }

@export var pickup_type: Type = Type.APPLE

# COIN 在一局游戏中永久存在（直到被玩家拾取或场景切换销毁），不再设 lifetime / fade
# COIN 序列帧动画速度（秒/帧）
const COIN_ANIM_SPEED := 0.1
const COIN_PICKUP_SFX_PATH := "res://assets/audio/Zhongkui_Inhale_CoinFalls.mp3"

# STAR (元宝) 间歇式动画：每 2 秒触发一次 4 帧序列，播完回到第 1 帧停留
const STAR_IDLE_INTERVAL := 2.0   # 两次播放之间的间隔（秒）
const STAR_ANIM_SPEED := 0.1      # 播放期间每帧间隔（秒），4 帧 × 0.1 = 0.4s 一轮

# 通用"自由落体落地"参数（COIN 和 STAR 共用）
# Pickup 是 Area2D 不响应 tile 碰撞，用 raycast 模拟落地
const FALL_GRAVITY := 1800.0
const FALL_MAX_SPEED := 1200.0
const FALL_HALF_HEIGHT := 35.0    # 道具视觉半高（200×200 × scale 0.4 ≈ 80，半高 40，留 5 缓冲)

# 哪些 Type 启用自由落体（生成时可能悬空 → 自己落到平台/地面上）
const FALLS_TO_GROUND := {
	Type.COIN: true,
	Type.STAR: true,
}

# COIN 序列帧状态
var _coin_frames: Array = []
var _coin_frame_idx: int = 0
var _coin_anim_timer: float = 0.0

# 通用落地状态（COIN 和 STAR 共用）
var _fall_vel: float = 0.0
var _landed: bool = false
var _fall_half_height: float = FALL_HALF_HEIGHT

# STAR 序列帧状态
var _star_frames: Array = []
var _star_frame_idx: int = 0
var _star_anim_timer: float = 0.0
var _star_playing: bool = false   # false = 待机停留在第 1 帧；true = 正在播放序列
var _collected: bool = false

@onready var sprite: Sprite2D = $Sprite

const VALUES := {
	Type.APPLE: 100,
	Type.CHERRY: 200,
	Type.STAR: 500,
	Type.HEART: 0,
	Type.COIN: 100,
}

# 单贴图道具的纹理路径。COIN 用单独的 FRAMES 列表
const TEX := {
	Type.APPLE:  "res://assets/sprites/prop_apple.png",
	Type.CHERRY: "res://assets/sprites/prop_cherry.png",
	# STAR 用 Yuanbao_01.png（"元宝"），由鬼球碰撞敌人掉落
	Type.STAR:   "res://assets/sprites/GeneralElements/Yuanbao/Yuanbao_01.png",
	Type.HEART:  "res://assets/sprites/prop_heart.png",
}

# 铜钱（COIN）序列帧 —— 由敌人被滚动 ball 撞死时爆出
const COIN_FRAMES := [
	"res://assets/sprites/GeneralElements/Coin/Coin_01.png",
	"res://assets/sprites/GeneralElements/Coin/Coin_02.png",
	"res://assets/sprites/GeneralElements/Coin/Coin_03.png",
	"res://assets/sprites/GeneralElements/Coin/Coin_04.png",
	"res://assets/sprites/GeneralElements/Coin/Coin_05.png",
	"res://assets/sprites/GeneralElements/Coin/Coin_06.png",
]

# 元宝（STAR）4 帧序列 —— 间歇播放，每 3 秒一次
const STAR_FRAMES := [
	"res://assets/sprites/GeneralElements/Yuanbao/Yuanbao_01.png",
	"res://assets/sprites/GeneralElements/Yuanbao/Yuanbao_02.png",
	"res://assets/sprites/GeneralElements/Yuanbao/Yuanbao_03.png",
	"res://assets/sprites/GeneralElements/Yuanbao/Yuanbao_04.png",
]

# 每个 Type 的 sprite 缩放（原占位都是 80×80，新美术资源更大需要缩小）
# 目标视觉尺寸 ≈ 80×80（与碰撞盒 60×60 + 留白匹配）
const SPRITE_SCALE := {
	Type.APPLE:  1.0,
	Type.CHERRY: 1.0,
	Type.STAR:   0.40,   # Yuanbao_*.png 200×200（之前 300×192 时是 0.27）
	Type.HEART:  1.0,
	Type.COIN:   0.40,   # Coin_*.png 200×200
}

func _ready() -> void:
	if pickup_type == Type.COIN:
		# 加载 6 张序列帧
		_coin_frames = []
		for path in COIN_FRAMES:
			_coin_frames.append(load(path))
		if not _coin_frames.is_empty():
			sprite.texture = _coin_frames[0]
	elif pickup_type == Type.STAR:
		# 加载 4 张元宝序列帧，初始停留在第 1 帧
		_star_frames = []
		for path in STAR_FRAMES:
			_star_frames.append(load(path))
		if not _star_frames.is_empty():
			sprite.texture = _star_frames[0]
		_star_frame_idx = 0
		_star_playing = false
		# 给每个元宝一个随机的初始 timer 偏移（0 到 STAR_IDLE_INTERVAL 之间）
		# → 屏幕上多个元宝的"晃动时刻"自然错开，不会整齐划一
		_star_anim_timer = randf() * STAR_IDLE_INTERVAL
	else:
		sprite.texture = load(TEX[pickup_type])
	_apply_tuning()
	CharTuning.tuning_changed.connect(_apply_tuning)
	body_entered.connect(_on_body_entered)

func _apply_tuning() -> void:
	var s: float = SPRITE_SCALE.get(pickup_type, 1.0)
	if pickup_type == Type.STAR:
		s = CharTuning.drop_yuanbao_scale
		_fall_half_height = CharTuning.drop_yuanbao_fall_half_height
	else:
		_fall_half_height = FALL_HALF_HEIGHT
	sprite.scale = Vector2(s, s)

func _process(delta: float) -> void:
	# COIN 序列帧动画（独立于 lifetime fade）
	if pickup_type == Type.COIN and not _coin_frames.is_empty():
		_coin_anim_timer += delta
		while _coin_anim_timer >= COIN_ANIM_SPEED:
			_coin_anim_timer -= COIN_ANIM_SPEED
			_coin_frame_idx = (_coin_frame_idx + 1) % _coin_frames.size()
			sprite.texture = _coin_frames[_coin_frame_idx]
	# 自由落体：COIN / STAR 都可能生成在空中，需要自己落到平台/地面上
	if FALLS_TO_GROUND.get(pickup_type, false) and not _landed:
		_tick_fall(delta)
	# STAR 间歇式动画：2 秒停留 + 一轮 4 帧播放，循环
	if pickup_type == Type.STAR and not _star_frames.is_empty():
		_tick_star_anim(delta)

# 元宝间歇式动画状态机
# 待机阶段（_star_playing=false）：停留在第 1 帧，倒计时 STAR_IDLE_INTERVAL；
# 播放阶段（_star_playing=true）：每 STAR_ANIM_SPEED 推进一帧，播完 4 帧回到待机
func _tick_star_anim(delta: float) -> void:
	_star_anim_timer += delta
	if not _star_playing:
		if _star_anim_timer >= STAR_IDLE_INTERVAL:
			_star_anim_timer -= STAR_IDLE_INTERVAL
			_star_playing = true
			_star_frame_idx = 0
			# 第 1 帧已经显示，但仍要进入循环；下面 while 会按节奏推进
		return
	# 播放阶段：按节奏推进
	while _star_anim_timer >= STAR_ANIM_SPEED:
		_star_anim_timer -= STAR_ANIM_SPEED
		_star_frame_idx += 1
		if _star_frame_idx >= _star_frames.size():
			# 一轮播完：回到第 1 帧，进入待机
			_star_frame_idx = 0
			_star_playing = false
			sprite.texture = _star_frames[0]
			_star_anim_timer = 0.0
			return
		sprite.texture = _star_frames[_star_frame_idx]

# 通用自由落体：道具在生成位置往下落，直到射线探测到 tile 地面 (collision_layer 1)
# Pickup 是 Area2D 不响应 tile 碰撞，用 raycast 模拟落地
func _tick_fall(delta: float) -> void:
	_fall_vel = min(FALL_MAX_SPEED, _fall_vel + FALL_GRAVITY * delta)
	var step: float = _fall_vel * delta
	var from: Vector2 = global_position
	var to: Vector2 = from + Vector2(0, step + _fall_half_height)
	var space := get_world_2d().direct_space_state
	var ray := PhysicsRayQueryParameters2D.create(from, to)
	ray.collision_mask = 1  # tile 地面层
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		# 没碰到地面：继续下落
		global_position.y += step
	else:
		# 碰到地面：贴在地面之上
		global_position.y = hit.position.y - _fall_half_height
		_fall_vel = 0.0
		_landed = true

func _on_body_entered(body: Node) -> void:
	if _collected or not (body is Player):
		return
	_collected = true
	set_deferred("monitoring", false)
	if pickup_type == Type.HEART:
		GameState.gain_life()
	else:
		GameState.add_score(VALUES[pickup_type])
		if pickup_type == Type.COIN:
			_play_pickup_fly_to_hud("play_coin_pickup_fly")
			GameState.add_coin()
			_play_coin_pickup_sfx()
		elif pickup_type == Type.STAR:
			_play_pickup_fly_to_hud("play_yuanbao_pickup_fly")
			GameState.add_yuanbao()
			_play_coin_pickup_sfx()
	call_deferred("queue_free")

func _play_pickup_fly_to_hud(method_name: StringName) -> void:
	var hud := _get_hud()
	if hud == null or not hud.has_method(method_name):
		return
	hud.call(method_name, global_position, sprite.texture, _get_sprite_screen_size())

func _get_hud() -> Node:
	var current := get_tree().current_scene
	if current == null:
		return null
	var hud := current.get_node_or_null("UI")
	if hud != null:
		return hud
	return current.find_child("HUD", true, false)

func _get_sprite_screen_size() -> Vector2:
	if sprite.texture == null:
		return Vector2.ZERO
	var visual_size := sprite.texture.get_size() * sprite.global_scale.abs()
	var canvas_transform := get_viewport().get_canvas_transform()
	var origin := canvas_transform * global_position
	var right := canvas_transform * (global_position + Vector2(visual_size.x, 0.0))
	var down := canvas_transform * (global_position + Vector2(0.0, visual_size.y))
	return Vector2(origin.distance_to(right), origin.distance_to(down))

func _play_coin_pickup_sfx() -> void:
	var stream := load(COIN_PICKUP_SFX_PATH)
	if stream == null:
		return
	stream = stream.duplicate()
	if stream is AudioStreamMP3:
		stream.loop = false
	var sfx_parent := get_parent()
	if sfx_parent == null:
		sfx_parent = get_tree().current_scene
	if sfx_parent == null:
		return
	var sfx := AudioStreamPlayer.new()
	sfx.name = "CoinPickupSfx"
	sfx.stream = stream
	sfx_parent.add_child(sfx)
	sfx.finished.connect(sfx.queue_free)
	sfx.play()
