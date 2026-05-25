extends Area2D
class_name FireSeed

# 宫廷僵尸释放的绿色火种：落地后沿水平方向匀速滑行，碰到钟馗扣血并消失，
# 飞出屏幕则自动清理。两帧序列循环播放（火苗摇曳）。

const FRAMES := [
	"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_fire/PalaceZombie_fire_01.png",
	"res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_fire/PalaceZombie_fire_02.png",
]

# 视觉缩放（PNG 64×64，原大略小，按 1.0 显示约 64×64 像素）
const SPRITE_SCALE := 1.2
# 滑行水平速度（像素/秒）
const SLIDE_SPEED := 240.0
# 自由落体参数（与 pickup.gd 同步：落到 tile 平台/地面上后开始滑行）
const FALL_GRAVITY := 1800.0
const FALL_MAX_SPEED := 1200.0
const FALL_HALF_HEIGHT := 14.0  # 64 × 1.2 × 0.5 ≈ 38，但火种贴地希望底部更靠近平台，给 14 让视觉中心略高于地面
# 帧动画间隔（秒）
const ANIM_INTERVAL := 0.12
# 屏幕水平边界（与 player.gd 同步，火种滑出后销毁）
const WORLD_LEFT := -100.0
const WORLD_RIGHT := 2020.0

@onready var sprite: Sprite2D = $Sprite

var _frames: Array = []
var _frame_idx: int = 0
var _anim_timer: float = 0.0
var _direction: int = 1  # +1 朝右滑，-1 朝左
var _fall_vel: float = 0.0
var _landed: bool = false

func _ready() -> void:
	_frames = []
	for path in FRAMES:
		_frames.append(load(path))
	if not _frames.is_empty():
		sprite.texture = _frames[0]
	sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	body_entered.connect(_on_body_entered)

# 由宫廷僵尸生成时调用，设置滑行方向（+1 朝右 / -1 朝左）
func launch(dir: int) -> void:
	_direction = 1 if dir >= 0 else -1
	# 火种方向翻转：sprite.flip_h = true 时朝左
	sprite.flip_h = _direction < 0

func _process(delta: float) -> void:
	_tick_anim(delta)
	if not _landed:
		_tick_fall(delta)
	else:
		_tick_slide(delta)
	# 飞出屏幕自动销毁
	if global_position.x < WORLD_LEFT or global_position.x > WORLD_RIGHT:
		queue_free()

func _tick_anim(delta: float) -> void:
	if _frames.size() <= 1:
		return
	_anim_timer += delta
	while _anim_timer >= ANIM_INTERVAL:
		_anim_timer -= ANIM_INTERVAL
		_frame_idx = (_frame_idx + 1) % _frames.size()
		sprite.texture = _frames[_frame_idx]

# 自由落体：与 pickup.gd 中 _tick_fall 一致，用射线探测 layer 1 (tile 平台/地面)
func _tick_fall(delta: float) -> void:
	_fall_vel = min(FALL_MAX_SPEED, _fall_vel + FALL_GRAVITY * delta)
	var step: float = _fall_vel * delta
	var from: Vector2 = global_position
	var to: Vector2 = from + Vector2(0, step + FALL_HALF_HEIGHT)
	var space := get_world_2d().direct_space_state
	var ray := PhysicsRayQueryParameters2D.create(from, to)
	ray.collision_mask = 1  # tile 地面层
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		global_position.y += step
	else:
		# 贴地：火种视觉中心略高于地面
		global_position.y = hit.position.y - FALL_HALF_HEIGHT
		_fall_vel = 0.0
		_landed = true

# 沿水平方向匀速滑行；每帧用短射线检测脚下是否仍有地面，没有则继续下落
func _tick_slide(delta: float) -> void:
	global_position.x += SLIDE_SPEED * _direction * delta
	# 检测脚下是否还有平台（防止滑出平台边缘后悬空滑行）
	var from: Vector2 = global_position
	var to: Vector2 = from + Vector2(0, FALL_HALF_HEIGHT + 20.0)
	var space := get_world_2d().direct_space_state
	var ray := PhysicsRayQueryParameters2D.create(from, to)
	ray.collision_mask = 1
	var hit := space.intersect_ray(ray)
	if hit.is_empty():
		# 脱离平台 → 重新进入下落
		_landed = false
	else:
		# 持续贴地（防止平台高度不一时悬空 / 内嵌）
		global_position.y = hit.position.y - FALL_HALF_HEIGHT

func _on_body_entered(body: Node) -> void:
	# 碰到钟馗：扣血并消失（玩家在 take_damage 时已处理无敌帧，
	# 这里只在玩家可受伤时扣血，不重复处理无敌逻辑）
	if body is Player and not body.invincible:
		body.invincible = true
		body.invincible_timer = body.HURT_INVINCIBLE_TIME
		body.take_damage()
		queue_free()
