extends CharacterBody2D
class_name FireSkull

# Boss Attack2 投射物：火焰骷髅头
#
# 行为概述：
# - 由 boss.gd 在 Attack2 序列帧中段从「左手法器圆环」处生成。
# - 飞行：弱追踪玩家。spawn 时锁定一个朝向玩家的初始方向，之后每帧把当前
#   速度向"指向玩家"的目标方向做小幅 lerp，避免硬追踪导致的 360° 跟焦感。
# - sprite：始终面朝画面**左侧**（flip_h = false 时素材朝右 → 设 flip_h = true）。
#   即使飞行方向有 Y 分量，朝向也不翻转——画面上始终是同一面朝左的骷髅。
# - 碰到钟馗：钟馗 take_damage()（掉一颗心）+ 自身销毁。
# - 被钟馗吸入：复用玩家现有的 SuctionArea → 葫芦 → ball 喷射流程。
#   实现上 FireSkull 提供与 Enemy 同名的"鸭子接口"方法/字段
#   （freeze_for_suction / begin_capture_flight / become_captured /
#    reset_suction_shrink / is_captured / is_in_flight / is_being_sucked /
#    suction_hold_timer / get_suction_capture_time / enemy_type）。
#   player.gd 里把 `body is Enemy` 的判断扩展为 `is Enemy or is FireSkull`，
#   其余逻辑无需感知 FireSkull 的存在。
# - 喷出（成为 ball）后：ball.gd 在 launch 时按 enemy_type == FIRE_SKULL_TYPE_ID
#   走专属贴图分支（FireSkull_*.png 帧动画继续循环播放），击中 Boss 扣 1 滴血。

# FireSkull 8 帧循环序列
const FRAMES: Array[String] = [
	"res://assets/sprites/Enemy/Boss/FireSkull/FireSkull_01.png",
	"res://assets/sprites/Enemy/Boss/FireSkull/FireSkull_02.png",
	"res://assets/sprites/Enemy/Boss/FireSkull/FireSkull_03.png",
	"res://assets/sprites/Enemy/Boss/FireSkull/FireSkull_04.png",
	"res://assets/sprites/Enemy/Boss/FireSkull/FireSkull_05.png",
	"res://assets/sprites/Enemy/Boss/FireSkull/FireSkull_06.png",
	"res://assets/sprites/Enemy/Boss/FireSkull/FireSkull_07.png",
	"res://assets/sprites/Enemy/Boss/FireSkull/FireSkull_08.png",
]

const ANIM_INTERVAL := 0.08            # 帧动画间隔（秒）
const FLY_SPEED := 460.0               # 飞行速度（像素/秒）
const TURN_RATE := 1.6                 # 弱追踪强度：每秒朝目标方向旋转的弧度上限
# sprite 视觉缩放从 CharTuning.boss_skull_scale 读取（F1 调参面板可实时调）；
# 这里保留一个兜底默认值，仅在初始化前一帧使用，正常运行下立刻被 _apply_tuning 覆盖。
const SPRITE_SCALE_FALLBACK := 0.18
const WORLD_LEFT := -160.0             # 飞出屏幕外销毁
const WORLD_RIGHT := 2080.0
const WORLD_TOP := -160.0
const WORLD_BOTTOM := 1240.0

# 用于 ball.gd 识别"这个 ball 来源是 FireSkull"，从而切到帧动画分支
const FIRE_SKULL_TYPE_ID := -1

@onready var sprite: Sprite2D = $Sprite

var _frames: Array = []
var _frame_idx: int = 0
var _anim_t: float = 0.0
var _direction: Vector2 = Vector2(-1, 0)  # 当前飞行方向（单位向量）
var _player_ref: Node2D = null

# ── 鸭子接口字段：让 player.gd 把 FireSkull 当成 Enemy 一样处理 ─────────
# enemy_type 是 ball.launch() 必须的参数；用 FIRE_SKULL_TYPE_ID 标识。
var enemy_type: int = FIRE_SKULL_TYPE_ID
var is_captured: bool = false
var is_in_flight: bool = false
var is_being_sucked: bool = false
var suction_hold_timer: float = 0.0
const SUCTION_CAPTURE_TIME := 0.0  # 瞬间吸入：一接触吸入区域立刻进入飞向葫芦阶段
const SUCTION_FLIGHT_STRETCH_MAX := 0.65
const SUCTION_FLIGHT_SQUASH_MAX := 0.28

# 内部状态：被吸入葫芦的飞行阶段
var _is_frozen: bool = false       # 蓄力期：完全冻结在原地
var _flight_t: float = 0.0
var _flight_start: Vector2 = Vector2.ZERO
var _flight_vanish: Vector2 = Vector2.ZERO
# 进入飞向葫芦阶段时锁定的 sprite 缩放基准（取自 CharTuning.boss_skull_scale），
# 用于收缩公式 scale × (1-p)。锁定后飞行中 F1 改 scale 不会让飞行动画跳变。
var _flight_base_scale: float = SPRITE_SCALE_FALLBACK
const _FLIGHT_DURATION := 0.4

# Boss 受击仅由 ball.gd 喷出阶段处理；FireSkull 自身不会撞 Boss（同阵营）
const BOSS_GROUP := "boss"

func _ready() -> void:
	# 加载帧贴图。任意一帧加载失败即整体降级（避免空 sprite 飞过去）
	for path in FRAMES:
		var t := load(path)
		if t == null:
			push_warning("[FireSkull] frame load failed: %s" % path)
			continue
		_frames.append(t)
	if _frames.is_empty():
		queue_free()
		return
	sprite.texture = _frames[0]
	# 始终面朝画面左侧。素材原图本身就是朝左，因此 flip_h 保持 false 即可；
	# 即使 _direction 在弱追踪过程中带 Y 分量、甚至略偏右，sprite 也不翻转。
	sprite.flip_h = false

	add_to_group("fire_skull")

	# 接入 F1 调参：boss_skull_scale 实时同步
	CharTuning.tuning_changed.connect(_apply_tuning)
	_apply_tuning()

# 同步 CharTuning：当前只用 boss_skull_scale 作 sprite 缩放。
# 注意：此函数不能修改 sprite 的旋转 / flip_h——飞行朝向另由 _physics_process 维护。
# 飞向葫芦阶段（is_in_flight=true）sprite.scale 由收缩公式驱动，不在此覆盖。
func _apply_tuning() -> void:
	if sprite == null:
		return
	if is_in_flight:
		return
	var s: float = CharTuning.boss_skull_scale
	sprite.scale = Vector2(s, s)

# 由 boss.gd 在生成时调用：传入玩家引用，决定初始飞行方向
func launch(player: Node2D) -> void:
	_player_ref = player
	if _player_ref != null and is_instance_valid(_player_ref):
		var to_player: Vector2 = _player_ref.global_position - global_position
		if to_player.length_squared() > 1.0:
			_direction = to_player.normalized()
		else:
			_direction = Vector2(-1, 0)
	else:
		_direction = Vector2(-1, 0)

func _physics_process(delta: float) -> void:
	_tick_anim(delta)

	# 1) 被捕获后整个节点 hide()，不再处理任何运动 / 被吸逻辑（与 Enemy 一致）
	if is_captured:
		return

	# 2) 飞向葫芦：自我推进的运动学插值，不响应任何外部物理
	if is_in_flight:
		_flight_t = min(_FLIGHT_DURATION, _flight_t + delta)
		var p: float = _flight_t / _FLIGHT_DURATION
		global_position = _flight_start.lerp(_flight_vanish, p)
		# 缩放公式以"开始飞行那一刻 CharTuning 的 scale"为基准 × (1-p)，
		# 中段额外拉伸，形成被葫芦口扯长后收进去的效果。
		var peak: float = sin(p * PI)
		var s: float = _flight_base_scale * (1.0 - p)
		sprite.scale = Vector2(
			s * (1.0 + SUCTION_FLIGHT_STRETCH_MAX * peak),
			s * (1.0 - SUCTION_FLIGHT_SQUASH_MAX * peak)
		)
		if _flight_t >= _FLIGHT_DURATION:
			is_in_flight = false
			become_captured()
		return

	# 3) 蓄力期：被钟馗吸住时完全冻结在原地，
	#    suction_hold_timer 由 player.gd 在每帧 freeze_for_suction 后由 enemy 自身累加，
	#    我们这里同样累加（player 不直接读 _is_frozen，而是在 _is_frozen=true 时累计）。
	#    与 Enemy 的实现一致：每物理帧末把 _is_frozen 重置为 false，
	#    下一帧若还在吸气区会被 player 重新置 true；脱离也保留累计进度。
	if _is_frozen:
		suction_hold_timer += delta
		velocity = Vector2.ZERO
		_is_frozen = false
		return

	# 4) 正常飞行：弱追踪玩家
	if _player_ref != null and is_instance_valid(_player_ref):
		var target_dir: Vector2 = (_player_ref.global_position - global_position)
		if target_dir.length_squared() > 1.0:
			target_dir = target_dir.normalized()
			# 用角度插值实现"每秒最多转 TURN_RATE 弧度"的弱追踪
			var current_angle: float = _direction.angle()
			var target_angle: float = target_dir.angle()
			var diff: float = wrapf(target_angle - current_angle, -PI, PI)
			var max_step: float = TURN_RATE * delta
			diff = clampf(diff, -max_step, max_step)
			_direction = Vector2.RIGHT.rotated(current_angle + diff)

	# CharacterBody2D 推进：用 velocity + move_and_slide 让物理引擎正确处理移动；
	# 但 FireSkull 不接 collision_mask（layer=4，mask=0），只穿过场景，
	# 命中由 SuctionArea / HurtBox 等 Area2D 探测。
	velocity = _direction * FLY_SPEED
	move_and_slide()

	# 5) 飞出世界边界销毁
	if global_position.x < WORLD_LEFT or global_position.x > WORLD_RIGHT \
			or global_position.y < WORLD_TOP or global_position.y > WORLD_BOTTOM:
		queue_free()

func _tick_anim(delta: float) -> void:
	if _frames.size() <= 1:
		return
	_anim_t += delta
	while _anim_t >= ANIM_INTERVAL:
		_anim_t -= ANIM_INTERVAL
		_frame_idx = (_frame_idx + 1) % _frames.size()
		sprite.texture = _frames[_frame_idx]

# ── 鸭子接口方法：与 enemy.gd 中同名方法语义对齐 ────────────────────────

func get_suction_capture_time() -> float:
	return SUCTION_CAPTURE_TIME

# 钟馗的 SuctionArea 每帧对落入其中的"敌人"调用。
# 进入冻结状态后，suction_hold_timer 在 _physics_process 中累加；
# 计满 → player.gd 调 begin_capture_flight 进入飞向葫芦阶段。
func freeze_for_suction(_vanish_world: Vector2 = Vector2.INF) -> void:
	if is_captured or is_in_flight:
		return
	_is_frozen = true

# 累计被吸满阈值后由 player.gd 调用：进入飞向葫芦的运动学阶段。
func begin_capture_flight(vanish_world: Vector2) -> void:
	if is_captured or is_in_flight:
		return
	is_in_flight = true
	_flight_t = 0.0
	_flight_start = global_position
	_flight_vanish = vanish_world
	# 锁定飞行收缩动画的缩放基准（防止飞行中 F1 改 scale 让动画跳）
	_flight_base_scale = CharTuning.boss_skull_scale
	# 飞行阶段不再被任何吸气逻辑干扰
	_is_frozen = false
	is_being_sucked = false
	# 关闭碰撞层（与 Enemy.begin_capture_flight 一致）
	collision_layer = 0

# 飞行结束 → 被纳入 captured_enemies，钟馗按吸键发射时变成 ball。
func become_captured() -> void:
	is_captured = true
	collision_layer = 0
	hide()

# 玩家 _capture_enemy 在某些路径会调（保险）；FireSkull 没有缩小流程，
# 直接复位 sprite 即可。
func reset_suction_shrink() -> void:
	if not is_captured:
		sprite.visible = true
		var s: float = CharTuning.boss_skull_scale
		sprite.scale = Vector2(s, s)
