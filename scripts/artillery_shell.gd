extends Area2D
class_name ArtilleryShell

# 胖魔王 Attack2 收招 1 秒后，从屏幕上方落下的爆竹。
# 垂直下落砸向钟馗：命中钟馗扣 1 点生命值后消失；
# 无论是否命中，下落到钟馗当前停留平台的站立面高度时也会消失。
# 爆竹消失时，在其消失位置、爆竹前层播放一段爆炸序列帧（Explode_01~10）。
# 平台本身不会消失，仅爆竹消失并播放爆炸。

const FIRECRACKER_FRAME_DIR := "res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2"
const FIRECRACKER_FRAME_PREFIX := "Firecracker_"
const FIRECRACKER_FRAME_COUNT := 2
const FIRECRACKER_FRAME_TIME := 0.16
# 炮竹下落时间很短，原始转速在实机里几乎看不出来；提高到足够肉眼可见的自转速度。
const FIRECRACKER_ROTATION_SPEED := TAU * 2.0
# 爆炸序列帧（Explode_01.png ~ Explode_10.png）所在目录与命名。
const EXPLODE_FRAME_DIR := "res://assets/sprites/Enemy/FatDemonKing/FatDemonKing_Attack2"
const EXPLODE_FRAME_PREFIX := "Explode_"
const EXPLODE_FRAME_COUNT := 10
# 爆炸序列帧每帧播放时长（秒）。
const EXPLODE_FRAME_TIME := 0.05
# 下落初速度与重力（像素/秒、像素/秒²）。在原速度基础上减慢 30%（×0.7）。
const FALL_START_SPEED := 420.0
const FALL_GRAVITY := 1540.0
const FALL_MAX_SPEED := 1680.0
# 超出屏幕下边界这么多像素后销毁（屏幕高 1080）
const WORLD_BOTTOM := 1080.0 + 200.0
# 爆炸 z_index：高于炮弹（炮弹 z_index=60），让爆炸显示在炮弹前层。
const EXPLODE_Z_INDEX := 80

@onready var sprite: Sprite2D = $Sprite

var _fall_vel: float = FALL_START_SPEED
var _free_queued: bool = false
var _visual_frames: Array = []
var _visual_frame_idx: int = 0
var _visual_frame_accum: float = 0.0
# 钟馗当前停留平台的站立面世界 Y（生成时锁定）；找不到则为 NAN（仅靠出界/命中收尾）。
var _target_platform_y: float = NAN

func _ready() -> void:
	_visual_frames = _load_firecracker_frames()
	if not _visual_frames.is_empty():
		sprite.texture = _visual_frames[0]
		sprite.rotation = randf_range(0.0, TAU)
	else:
		# 资源未导入时 load() 返回 null（Godot 需先在编辑器导入 PNG）。
		push_warning("[ArtilleryShell] 爆竹序列帧加载失败（资源未导入？）：%s/%s01~%02d.png"
			% [FIRECRACKER_FRAME_DIR, FIRECRACKER_FRAME_PREFIX, FIRECRACKER_FRAME_COUNT])
	body_entered.connect(_on_body_entered)
	CharTuning.tuning_changed.connect(_apply_tuning)
	_apply_tuning()
	_lock_target_platform_y()

func _exit_tree() -> void:
	if CharTuning.tuning_changed.is_connected(_apply_tuning):
		CharTuning.tuning_changed.disconnect(_apply_tuning)

func _apply_tuning() -> void:
	if sprite == null:
		return
	var firecracker_scale: float = maxf(0.01, CharTuning.shell_firecracker_scale)
	sprite.scale = Vector2(firecracker_scale, firecracker_scale)

# 锁定钟馗当前停留平台的站立面 Y：炮弹落到该高度时消失并爆炸。
func _lock_target_platform_y() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null or not is_instance_valid(player) or not player is Node2D:
		return
	var level := _find_level()
	if level == null or not level.has_method("find_platform_for"):
		return
	# find_platform_for 的 Y 容差（PLATFORM_Y_TOLERANCE=12）是按"脚部 Y 接近站立面"
	# 设计的，而玩家原点位于身体中心、距脚底约 body_offset_y + body_height/2 像素。
	# 若直接用玩家原点查询，Y 偏差远超容差导致返回 null，炮弹便不会在平台爆炸。
	# 因此用玩家脚底世界坐标去匹配平台。
	var query_pos := _player_foot_world_pos(player as Node2D)
	var plat = level.find_platform_for(query_pos)
	if plat != null and plat.has("top_y"):
		_target_platform_y = float(plat["top_y"])

# 估算钟馗脚底的世界坐标：原点 + 碰撞框中心偏移 + 半高。
# 优先读取碰撞框的实际尺寸/偏移；取不到则回退到 CharTuning 调参数值。
func _player_foot_world_pos(player: Node2D) -> Vector2:
	# 兜底：body_offset_y + body_height/2（CharTuning 为 autoload，必定存在）
	var foot_offset_y: float = CharTuning.body_offset_y + CharTuning.body_height * 0.5
	var col := player.get_node_or_null("Collision") as CollisionShape2D
	if col != null and col.shape is RectangleShape2D:
		foot_offset_y = col.position.y + (col.shape as RectangleShape2D).size.y * 0.5
	return player.global_position + Vector2(0.0, foot_offset_y)

# 向上查找含 find_platform_for 方法的祖先节点（即 Level）。
func _find_level() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("find_platform_for"):
			return n
		n = n.get_parent()
	# 兜底：尝试从 "level" 组取。
	var lv := get_tree().get_first_node_in_group("level")
	if lv != null and lv.has_method("find_platform_for"):
		return lv
	return null

func _process(delta: float) -> void:
	if _free_queued:
		return
	_tick_firecracker_visual(delta)
	_fall_vel = minf(FALL_MAX_SPEED, _fall_vel + FALL_GRAVITY * delta)
	global_position.y += _fall_vel * delta
	# 落到钟馗当前停留平台的站立面高度：无论是否命中钟馗都消失并爆炸。
	# 站立面 Y 在 F1 调参的 shell_explode_offset_y 基础上微调消失/爆炸高度
	# （负值=更高处提前爆炸，正值=更靠下）。
	if not is_nan(_target_platform_y):
		var explode_y := _target_platform_y + CharTuning.shell_explode_offset_y
		if global_position.y >= explode_y:
			_explode_and_free()
			return
	if global_position.y > WORLD_BOTTOM:
		_queue_free_deferred()

func _tick_firecracker_visual(delta: float) -> void:
	sprite.rotation += FIRECRACKER_ROTATION_SPEED * delta
	if _visual_frames.size() <= 1:
		return
	_visual_frame_accum += delta
	while _visual_frame_accum >= FIRECRACKER_FRAME_TIME:
		_visual_frame_accum -= FIRECRACKER_FRAME_TIME
		_visual_frame_idx = (_visual_frame_idx + 1) % _visual_frames.size()
		sprite.texture = _visual_frames[_visual_frame_idx]

func _on_body_entered(body: Node) -> void:
	if _free_queued:
		return
	# 命中钟馗：扣 1 点生命值后消失（无敌帧逻辑由 player 处理）。
	if body is Player and not body.invincible:
		body.invincible = true
		body.invincible_timer = body.HURT_INVINCIBLE_TIME
		body.take_damage()
		_explode_and_free()

# 在炮弹当前位置生成爆炸特效，然后销毁炮弹。
func _explode_and_free() -> void:
	if _free_queued:
		return
	_spawn_explosion(global_position)
	_queue_free_deferred()

# 在指定世界坐标处的炮弹前层播放一段爆炸序列帧，播完自动移除。
func _spawn_explosion(world_pos: Vector2) -> void:
	var parent_node := get_parent()
	if parent_node == null or not is_instance_valid(parent_node):
		return
	var frames := _load_explosion_frames()
	if frames.is_empty():
		push_warning("[ArtilleryShell] 爆炸序列帧加载失败（资源未导入？）：%s/%s01~%02d.png"
			% [EXPLODE_FRAME_DIR, EXPLODE_FRAME_PREFIX, EXPLODE_FRAME_COUNT])
		return
	var fx := Sprite2D.new()
	fx.name = "ArtilleryShellExplosion"
	# 爆炸美术显示位置 = 炮弹爆炸世界坐标 + F1 调参的美术 Y 偏移。
	# 该偏移仅移动爆炸序列帧的视觉位置，不影响爆炸触发判定（负值=美术更高，正值=更低）。
	fx.global_position = world_pos + Vector2(0.0, CharTuning.shell_explode_art_offset_y)
	fx.z_index = EXPLODE_Z_INDEX
	# 爆炸大小由 F1 调参 CharTuning.shell_explode_scale 控制（出厂默认 EXPLODE_SCALE）。
	var explode_scale: float = CharTuning.shell_explode_scale
	fx.scale = Vector2(explode_scale, explode_scale)
	fx.texture = frames[0]
	fx.set_script(EXPLOSION_PLAYER_SCRIPT)
	parent_node.add_child(fx)
	fx.start(frames, EXPLODE_FRAME_TIME)

func _load_explosion_frames() -> Array:
	var frames: Array = []
	for i in range(1, EXPLODE_FRAME_COUNT + 1):
		var path := "%s/%s%02d.png" % [EXPLODE_FRAME_DIR, EXPLODE_FRAME_PREFIX, i]
		var tex := _load_texture(path)
		if tex == null:
			return []
		frames.append(tex)
	return frames

func _load_firecracker_frames() -> Array:
	var frames: Array = []
	for i in range(1, FIRECRACKER_FRAME_COUNT + 1):
		var path := "%s/%s%02d.png" % [FIRECRACKER_FRAME_DIR, FIRECRACKER_FRAME_PREFIX, i]
		var tex := _load_texture(path)
		if tex == null:
			return []
		frames.append(tex)
	return frames

# 优先用 load()（依赖 .import）；失败时回退到从磁盘直接读取原始 PNG，
# 以便资源尚未在编辑器导入时仍能正常播放。
func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path, "Texture2D"):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	var img := Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	return null

func _queue_free_deferred() -> void:
	if _free_queued:
		return
	_free_queued = true
	set_deferred("monitoring", false)
	call_deferred("queue_free")

# 内嵌的爆炸序列帧播放脚本：逐帧切换，播完移除自身。
const EXPLOSION_PLAYER_SCRIPT := preload("res://scripts/artillery_shell_explosion.gd")
