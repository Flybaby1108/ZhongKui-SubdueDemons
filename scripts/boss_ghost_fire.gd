extends Area2D
class_name BossGhostFire

# Boss Attack3 生成的鬼火：持续循环播放，不会自行消失。
# 唯一清除方式是被玩家喷出的鬼球触碰。

const FRAME_COUNT := 15
const FRAME_INTERVAL := 0.16
const APPEAR_DURATION := 0.5
const PLAYER_SAFE_DURATION := 1.0
const FRAME_PATH_FMT := "res://assets/sprites/Enemy/Boss/Fire/Fire_%02d.png"
const PLAYER_DAMAGE_COOLDOWN_FRAMES := 90

@onready var sprite: Sprite2D = $Sprite

var _frames: Array[Texture2D] = []
var _frame_idx := 0
var _anim_t := 0.0
var _appear_t := 0.0
var _safe_t := 0.0
var _target_sprite_scale := 0.58
var _free_queued := false
var _last_player_damage_frame := -1000

func _ready() -> void:
	add_to_group("boss_ghost_fire")
	for i in range(1, FRAME_COUNT + 1):
		var tex := _load_texture_with_source_fallback(FRAME_PATH_FMT % i)
		if tex != null:
			_frames.append(tex)
	if not _frames.is_empty():
		sprite.texture = _frames[0]
		_apply_sprite_bottom_anchor()
	CharTuning.tuning_changed.connect(_apply_tuning)
	_apply_tuning()
	body_entered.connect(_on_body_entered)

func _load_texture_with_source_fallback(path: String) -> Texture2D:
	var tex := load(path) as Texture2D
	if tex != null:
		return tex
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

func _process(delta: float) -> void:
	_tick_player_safe_time(delta)
	_tick_appear(delta)
	_tick_anim(delta)
	_damage_overlapping_players()

func _tick_player_safe_time(delta: float) -> void:
	if _safe_t >= PLAYER_SAFE_DURATION:
		return
	_safe_t = min(_safe_t + delta, PLAYER_SAFE_DURATION)

func _apply_tuning() -> void:
	if sprite == null:
		return
	_target_sprite_scale = CharTuning.boss_ghost_fire_scale
	sprite.position = Vector2(
		CharTuning.boss_ghost_fire_offset_x,
		CharTuning.boss_ghost_fire_offset_y
	)
	_apply_appear_scale()

func _tick_appear(delta: float) -> void:
	if _appear_t >= APPEAR_DURATION:
		return
	_appear_t = min(_appear_t + delta, APPEAR_DURATION)
	_apply_appear_scale()

func _apply_appear_scale() -> void:
	var appear_progress := 1.0
	if APPEAR_DURATION > 0.0:
		appear_progress = clamp(_appear_t / APPEAR_DURATION, 0.0, 1.0)
	var s := _target_sprite_scale * appear_progress
	sprite.scale = Vector2(s, s)

func _apply_sprite_bottom_anchor() -> void:
	var texture := sprite.texture
	if texture == null:
		return
	sprite.centered = false
	sprite.offset = Vector2(-float(texture.get_width()) * 0.5, -float(texture.get_height()))

func _tick_anim(delta: float) -> void:
	if _frames.size() <= 1:
		return
	_anim_t += delta
	while _anim_t >= FRAME_INTERVAL:
		_anim_t -= FRAME_INTERVAL
		_frame_idx = (_frame_idx + 1) % _frames.size()
		sprite.texture = _frames[_frame_idx]
		_apply_sprite_bottom_anchor()

func _damage_overlapping_players() -> void:
	if _free_queued:
		return
	for body in get_overlapping_bodies():
		if _is_player(body):
			_try_damage_player(body)

func _on_body_entered(body: Node) -> void:
	if _free_queued:
		return
	if body != null and body.is_in_group("active_ghost_balls"):
		_queue_free_deferred()
		return
	if _is_player(body):
		_try_damage_player(body)

func _is_player(body: Node) -> bool:
	return body != null and body.is_in_group("player")

func _try_damage_player(player: Node) -> void:
	if _safe_t < PLAYER_SAFE_DURATION:
		return
	if not ("invincible" in player) or not ("invincible_timer" in player):
		return
	if player.has_method("ignores_boss_ghost_fire_damage") and player.ignores_boss_ghost_fire_damage():
		return
	if player.invincible:
		return
	var current_frame := Engine.get_physics_frames()
	if current_frame - _last_player_damage_frame < PLAYER_DAMAGE_COOLDOWN_FRAMES:
		return
	_last_player_damage_frame = current_frame
	player.invincible = true
	if "HURT_INVINCIBLE_TIME" in player:
		player.invincible_timer = player.HURT_INVINCIBLE_TIME
	if player.has_method("take_damage"):
		player.take_damage()

func _queue_free_deferred() -> void:
	if _free_queued:
		return
	_free_queued = true
	set_deferred("monitoring", false)
	call_deferred("queue_free")
