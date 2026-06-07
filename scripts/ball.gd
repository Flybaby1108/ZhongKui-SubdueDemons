extends CharacterBody2D
class_name Ball

const ROLL_TIME := 2.0
const GRAVITY := 4000.0
const ROLL_SPEED := 1500.0
# 团状翻滚每秒旋转弧度（基础值；最终方向由飞行方向决定符号）
const ROLL_SPIN_SPEED := TAU * 2.0  # 2 圈/秒
# 团状形态视觉缩放：由 CharTuning.ball_sprite_scale 控制（F1 调参面板可实时调节）

# 按 Enemy.Type enum 映射团状翻滚贴图
# 0=METEOR_HAMMER, 1=RED_GHOST, 2=RED_DEVIL, 3=PALACE_ZOMBIE
const LAUNCHED_TEX := {
	0: "res://assets/sprites/Enemy/MeteorHammer/MeteorHammer_launched/MeteorHammer_launched.png",
	1: "res://assets/sprites/Enemy/RedGhost/RedGhost_launched/RedGhost_launched.png",
	2: "res://assets/sprites/Enemy/RedDevil/RedDevil_launched/RedDevil_launched.png",
	3: "res://assets/sprites/Enemy/PalaceZombie/PalaceZombie_launched/PalaceZombie_launched.png",
}

const COLLISION_SFX_PATH := "res://assets/audio/Zhongkui_Inhale_Collision.mp3"
const PICKUP_SCENE = preload("res://scenes/pickup.tscn")

# FireSkull 喷出后的帧动画序列（FireSkull 在 ball 形态下继续循环播放原序列帧）。
# enemy_type == FireSkull.FIRE_SKULL_TYPE_ID 时启用此分支，跳过 LAUNCHED_TEX 单帧贴图。
const FIRE_SKULL_FRAMES: Array[String] = [
	"res://assets/sprites/Enemy/Boss/FireSkull/FireSkull_01.png",
	"res://assets/sprites/Enemy/Boss/FireSkull/FireSkull_02.png",
	"res://assets/sprites/Enemy/Boss/FireSkull/FireSkull_03.png",
	"res://assets/sprites/Enemy/Boss/FireSkull/FireSkull_04.png",
	"res://assets/sprites/Enemy/Boss/FireSkull/FireSkull_05.png",
	"res://assets/sprites/Enemy/Boss/FireSkull/FireSkull_06.png",
	"res://assets/sprites/Enemy/Boss/FireSkull/FireSkull_07.png",
	"res://assets/sprites/Enemy/Boss/FireSkull/FireSkull_08.png",
]
const FIRE_SKULL_ANIM_INTERVAL := 0.08
# FireSkull 在 ball 形态下不旋转翻滚（保持骷髅头始终朝同一面）；
# 视觉缩放与飞行形态共用 CharTuning.boss_skull_scale，让 F1 调参面板里
# 的 "Boss FireSkull Scale" 同时影响 Boss 释放出去的火焰骷髅 + 玩家喷出反打的形态。

var roll_timer: float = ROLL_TIME
var enemy_type: int = 0
var direction: int = 1
var capture_count: int = 1
var already_hit: Array = []
# FireSkull 专属帧动画状态（仅 enemy_type == FIRE_SKULL_TYPE_ID 时生效）
var _fs_frames: Array = []
var _fs_idx: int = 0
var _fs_t: float = 0.0
var _is_fire_skull: bool = false
var collision_sfx: AudioStreamPlayer = null

@onready var sprite: Sprite2D = $Sprite
@onready var hit_area: Area2D = $HitArea

func _ready() -> void:
	hit_area.body_entered.connect(_on_hit_body)
	_setup_collision_sfx()
	# 监听调参变化，实时同步 sprite scale
	CharTuning.tuning_changed.connect(_apply_tuning)
	print("[BALL DEBUG] _ready: hit_area.collision_mask=", hit_area.collision_mask, " hit_area.monitoring=", hit_area.monitoring, " hit_area shape valid=", hit_area.get_node("HitShape").shape != null)

func _setup_collision_sfx() -> void:
	collision_sfx = AudioStreamPlayer.new()
	collision_sfx.name = "CollisionSfx"
	collision_sfx.max_polyphony = 8
	var stream := load(COLLISION_SFX_PATH)
	if stream != null:
		stream = stream.duplicate()
		if stream is AudioStreamMP3:
			stream.loop = false
		collision_sfx.stream = stream
	add_child(collision_sfx)

func _play_enemy_hit_sfx() -> void:
	if collision_sfx == null or collision_sfx.stream == null:
		return
	var sfx_parent := get_parent()
	if sfx_parent == null:
		sfx_parent = self
	var hit_sfx := AudioStreamPlayer.new()
	hit_sfx.name = "EnemyHitSfx"
	hit_sfx.stream = collision_sfx.stream
	sfx_parent.add_child(hit_sfx)
	hit_sfx.finished.connect(hit_sfx.queue_free)
	hit_sfx.play()

func _apply_tuning() -> void:
	# FireSkull 形态：用 boss_skull_scale，不受 ball_sprite_scale 控制
	if _is_fire_skull:
		var fs_s: float = CharTuning.boss_skull_scale
		sprite.scale = Vector2(fs_s, fs_s)
		return
	var s: float = CharTuning.ball_sprite_scale
	sprite.scale = Vector2(s, s)

func launch(initial_velocity: Vector2, captured_type: int, captures: int = 1) -> void:
	velocity = initial_velocity
	enemy_type = captured_type
	direction = 1 if initial_velocity.x >= 0.0 else -1
	capture_count = clampi(captures, 1, 3)
	# FireSkull 喷出：走帧动画分支，sprite 始终朝飞行方向（不翻滚）。
	# enemy_type == FireSkull.FIRE_SKULL_TYPE_ID（-1）是 boss 投射物的特殊标识。
	if captured_type == FireSkull.FIRE_SKULL_TYPE_ID:
		_is_fire_skull = true
		_fs_frames.clear()
		for path in FIRE_SKULL_FRAMES:
			var t := load(path)
			if t != null:
				_fs_frames.append(t)
		if not _fs_frames.is_empty():
			sprite.texture = _fs_frames[0]
		# 朝飞行方向：FireSkull 素材原图**朝左**，向左飞时 flip_h = false（素材原始朝向），
		# 向右飞（被钟馗喷向 Boss 时通常 dir_x = +1，因为玩家朝右才能喷）时翻成 flip_h = true。
		sprite.flip_h = direction > 0
		sprite.rotation = 0.0
	elif LAUNCHED_TEX.has(captured_type):
		sprite.texture = load(LAUNCHED_TEX[captured_type])
		sprite.flip_h = false
		sprite.rotation = randf() * TAU
	_apply_tuning()

func _physics_process(delta: float) -> void:
	roll_timer -= delta
	if roll_timer <= 0.0:
		queue_free()
		return
	velocity.y += GRAVITY * delta
	velocity.x = ROLL_SPEED * direction
	move_and_slide()
	if is_on_wall():
		direction = -direction
		# FireSkull 撞墙翻面：sprite 朝向跟随飞行方向同步翻转
		# （素材原图朝左：向左飞 flip_h=false，向右飞 flip_h=true）
		if _is_fire_skull:
			sprite.flip_h = direction > 0
	# FireSkull 形态：推进帧动画，sprite 不旋转
	if _is_fire_skull:
		if _fs_frames.size() > 1:
			_fs_t += delta
			while _fs_t >= FIRE_SKULL_ANIM_INTERVAL:
				_fs_t -= FIRE_SKULL_ANIM_INTERVAL
				_fs_idx = (_fs_idx + 1) % _fs_frames.size()
				sprite.texture = _fs_frames[_fs_idx]
	else:
		# 团状翻滚：sprite 持续旋转，方向跟随飞行方向（右飞顺时针，左飞逆时针）
		sprite.rotation += ROLL_SPIN_SPEED * direction * delta
	_check_boss_hurt_hits()

func _on_hit_body(body: Node) -> void:
	print("[BALL DEBUG] _on_hit_body fired. body=", body, " is_Boss=", body is Boss, " is_Enemy=", body is Enemy, " body.name=", body.name if body else "<null>")
	if body is Boss and not body.dying and not already_hit.has(body):
		_try_hit_boss(body)
		return
	if body is Enemy and not body.dying and not body.is_captured and not already_hit.has(body):
		# 跳过仍处于 spawn 豁免期的召唤敌人：避免在 Boss_Attack1 召唤瞬间
		# 把刚出生的小怪当场抹掉（玩家会看到"Boss 出招了平台上没人"）。
		if "summon_invuln_t" in body and body.summon_invuln_t > 0.0:
			return
		already_hit.append(body)
		# 每个被滚动 ball 撞死的敌人只爆 1 枚铜钱
		_drop_coin(body.global_position)
		_play_enemy_hit_sfx()
		body.die()

func _drop_coin(at: Vector2) -> void:
	var parent = get_parent()
	if parent == null:
		return
	var coin = PICKUP_SCENE.instantiate()
	coin.pickup_type = Pickup.Type.COIN
	parent.add_child(coin)
	# 在敌人位置生成铜钱；铜钱自身有重力 + 地面探测，会自动落到正下方最近的平台/地面上
	# （即使敌人当时在空中、悬崖边、平台上方多层结构等情况都能正确处理）
	coin.global_position = at

func _check_boss_hurt_hits() -> void:
	for boss in get_tree().get_nodes_in_group("boss"):
		if boss is Boss:
			_try_hit_boss(boss)

func _try_hit_boss(boss: Boss) -> void:
	if boss.dying or already_hit.has(boss):
		return
	if not boss.overlaps_hurt_rect_global(_get_hit_rect_global()):
		return
	already_hit.append(boss)
	boss.take_damage(1)
	print("[BALL DEBUG] Boss damaged! HP now=", boss.health)

func _get_hit_rect_global() -> Rect2:
	var hit_shape: CollisionShape2D = hit_area.get_node("HitShape")
	var rect := Rect2(global_position, Vector2.ZERO)
	if hit_shape != null and hit_shape.shape is RectangleShape2D:
		var size: Vector2 = hit_shape.shape.size * hit_shape.global_scale.abs()
		rect = Rect2(hit_shape.global_position - size * 0.5, size)
	return rect
