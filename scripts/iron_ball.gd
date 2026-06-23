extends Area2D
class_name IronBall

const TEXTURE_PATH := "res://assets/sprites/Chapter3/IronBall.png"
const ROLL_SPEED := 260.0
const FALL_SPEED := 560.0
const BALL_SCALE := 0.55
const COLLISION_SIZE := 78.0
const WORLD_MARGIN := 220.0

@onready var sprite: Sprite2D = $Sprite

var _points: Array[Vector2] = []
var _segment_idx := 0
var _delay := 0.0
var _free_queued := false
# 这些值在 launch_path 时从 CharTuning 读取一次（F1 可调）；未取到则回落到常量默认。
var _roll_speed := ROLL_SPEED
var _spin_speed := 1.0
var _ball_scale := BALL_SCALE
var _track_offset_y := 0.0

func _ready() -> void:
	sprite.texture = load(TEXTURE_PATH)
	_apply_tuning()
	body_entered.connect(_on_body_entered)
	# F1 调参（美术大小 / 滚动 Y 位置 / 转速 / 滚动速度）实时同步到正在滚动的铁球。
	CharTuning.tuning_changed.connect(_apply_tuning)

func _exit_tree() -> void:
	if CharTuning.tuning_changed.is_connected(_apply_tuning):
		CharTuning.tuning_changed.disconnect(_apply_tuning)

# 从 F1 调参（CharTuning 自动加载单例）读取铁球的美术大小 / 自转速度 / 滚动速度 / 平台上滚动 Y 偏移。
func _apply_tuning() -> void:
	_ball_scale = maxf(0.01, CharTuning.fdk_ball_scale)
	_spin_speed = maxf(0.0, CharTuning.fdk_ball_spin_speed)
	_roll_speed = maxf(1.0, CharTuning.fdk_ball_roll_speed)
	_track_offset_y = CharTuning.fdk_ball_track_offset_y
	sprite.scale = Vector2(_ball_scale, _ball_scale)
	# 美术 Y 偏移：仅移动贴图视觉，使滚动时铁球贴合三层平台表面（不改变碰撞/路径坐标）。
	sprite.position.y = _track_offset_y

func launch_path(points: Array, delay: float = 0.0) -> void:
	_points.clear()
	for point in points:
		if point is Vector2:
			_points.append(point)
	_delay = maxf(0.0, delay)
	_segment_idx = 0
	if not _points.is_empty():
		global_position = _points[0]

func _process(delta: float) -> void:
	if _free_queued:
		return
	if _delay > 0.0:
		_delay = maxf(0.0, _delay - delta)
		return
	_tick_roll(delta)
	if global_position.x < -WORLD_MARGIN or global_position.x > 1920.0 + WORLD_MARGIN:
		_queue_free_deferred()

func _tick_roll(delta: float) -> void:
	if _points.size() < 2:
		return
	if _segment_idx >= _points.size() - 1:
		_queue_free_deferred()
		return
	var target := _points[_segment_idx + 1]
	var delta_pos := target - global_position
	# 竖直掉落用 FALL_SPEED；水平滚动用 F1 可调的滚动(移动)速度。
	var speed := FALL_SPEED if absf(delta_pos.y) > absf(delta_pos.x) else _roll_speed
	var step := speed * delta
	if delta_pos.length() <= step:
		global_position = target
		_segment_idx += 1
	else:
		global_position += delta_pos.normalized() * step
	# 视觉自转：方向跟随水平位移，快慢由 F1 的“转速”系数控制（与移动速度解耦）。
	var dir_x := signf(delta_pos.x)
	if dir_x != 0.0:
		sprite.rotation += dir_x * (step / maxf(COLLISION_SIZE * _ball_scale * 0.5, 1.0)) * _spin_speed

func _on_body_entered(body: Node) -> void:
	if not (body is Player):
		return
	if body.invincible:
		return
	body.invincible = true
	body.invincible_timer = body.HURT_INVINCIBLE_TIME
	body.take_damage()

func _queue_free_deferred() -> void:
	if _free_queued:
		return
	_free_queued = true
	set_deferred("monitoring", false)
	call_deferred("queue_free")
