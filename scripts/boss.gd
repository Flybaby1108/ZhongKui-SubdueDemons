extends CharacterBody2D
class_name Boss

# Boss 角色（ChapterBoss 关卡）
#
# 状态：
#   IDLE    —— 22 帧呼吸循环（Boss_idle_01 ~ Boss_idle_22），AnimTimer 驱动
#   ATTACK1 —— 48 帧攻击序列（Boss_Attack1_01 ~ Boss_Attack1_48），独立计时器
#               播完一轮自动回 IDLE。攻击中段（SUMMON_FRAME_1）触发一次召唤事件：
#               在地图平台上刷 4 个**相同种类**敌人。
#   ATTACK2 —— 24 帧攻击序列（Boss_Attack2_01 ~ Boss_Attack2_24），独立计时器，
#               连续播放 ATTACK2_REPEAT 轮（默认 3 轮）。每一轮的中段
#               （FIRE_SKULL_FRAME）从 Boss 左手法器圆环处生成 1 颗 FireSkull
#               朝钟馗弱追踪飞行——三轮即先后释放 3 颗火焰骷髅。
#               与 ATTACK1 节奏不同（更长更具压迫感），美术差异化提供"换招"打击感。
#               FireSkull 撞到钟馗扣 1 颗心；可被钟馗吸入葫芦，喷出后变 ball
#               攻击 Boss 扣 1 滴血。
#   DEAD    —— 20 滴血被玩家释放的捕获物打完后死亡并通关。
#
# 召唤节奏：
#   _ready 后启动随机间隔（COOLDOWN_MIN ~ COOLDOWN_MAX 秒）的冷却计时，
#   每次 timeout 时**严格交替**使用 ATTACK1 / ATTACK2（先 Attack1，再 Attack2，
#   再 Attack1……依此类推）。整体平均 ~10s 一次招式，节奏稳定可预期。
#
# 设计：
# - **位置钉死**：Boss 不受重力、不走 move_and_slide，spawn 时 level.gd 把它放到
#   编辑器画的 BBBBBB 方块顶部中心，然后由策划/美术用 F1 面板的 offset_x / offset_y
#   做精细微调。这样关卡编辑器里画到哪儿，游戏里就稳稳站在哪儿。
# - **不接 enemy.gd 的 Type 体系**：那个体系强制要求 walk/capture/die 等帧；
#   Boss 现在只有 idle/attack 美术，硬塞会在加载或 capture 流程里崩。Boss 是关底单点，
#   独立脚本后续扩展更干净。
# - **CharTuning 接入**：sprite_scale / offset_x / offset_y 三个字段在 F1 面板里
#   可实时调，CharTuning.tuning_changed 信号连进 _apply_tuning() 实时同步。
# - **召唤敌人不计入 enemies_remaining**：通过 level.spawn_summoned_enemy() 走旁路，
#   避免 Boss 不停刷怪导致玩家无法满足通关条件。

# Boss idle 序列帧（22 帧，循环播放）
const IDLE_FRAMES: Array[String] = [
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_01.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_02.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_03.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_04.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_05.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_06.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_07.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_08.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_09.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_10.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_11.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_12.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_13.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_14.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_15.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_16.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_17.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_18.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_19.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_20.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_21.png",
	"res://assets/sprites/Enemy/Boss/Boss_idle/Boss_idle_22.png",
]

# idle 每帧间隔（秒）。22 帧 × 0.08s ≈ 1.76s 一轮
const IDLE_FRAME_INTERVAL := 0.08

# 攻击 1（48 帧，一次性播放）。0.06s/帧 → 总长 ≈2.88s，节奏适合"举手→召唤→收势"。
const ATTACK1_FRAME_COUNT := 48
const ATTACK1_FRAME_INTERVAL := 0.06
const ATTACK1_FRAME_PATH_FMT := "res://assets/sprites/Enemy/Boss/Boss_Attack1/Boss_Attack1_%02d.png"

# 攻击 2（24 帧，连续播放 ATTACK2_REPEAT 轮）。同 0.06s/帧 → 单轮总长 ≈1.44s，
# 三轮连播 ≈4.3s，比 Attack1 更具压迫感。
# 每轮序列帧的中段（FIRE_SKULL_FRAME）从 Boss 左手法器圆环位置生成 1 个 FireSkull
# 朝玩家飞——三轮连播即先后释放 3 颗火焰骷髅。
const ATTACK2_FRAME_COUNT := 24
const ATTACK2_FRAME_INTERVAL := 0.06
const ATTACK2_FRAME_PATH_FMT := "res://assets/sprites/Enemy/Boss/Boss_Attack2/Boss_Attack2_%02d.png"
# Attack2 单次施展中循环播放 Attack2 序列帧的轮数；每轮各释放 1 颗 FireSkull。
const ATTACK2_REPEAT := 3

# 攻击动画播到此帧（1-indexed）时触发一次召唤 / 投射物释放。取各自动画中段：
# 视觉上 Boss "出招"瞬间，前半段是举手蓄力、后半段是收势。
# - SUMMON_FRAME_1：Attack1 召唤小怪
# - FIRE_SKULL_FRAME：Attack2 每轮释放 1 颗 FireSkull
const SUMMON_FRAME_1 := 24  # Attack1：48 帧的中段
const FIRE_SKULL_FRAME := 12  # Attack2：24 帧的中段

# 每次召唤产出的小怪数量
const SUMMON_COUNT := 4

# 技能冷却（秒）。每次攻击结束后随机抽取，平均 ~10s。
const COOLDOWN_MIN := 7.5
const COOLDOWN_MAX := 12.5

# 可被召唤的敌人 PackedScene 列表（每次随机挑一种，召唤出 4 个相同种类）
const SUMMON_SCENES: Array[PackedScene] = [
	preload("res://scenes/enemy_meteor_hammer.tscn"),
	preload("res://scenes/enemy_red_ghost.tscn"),
	preload("res://scenes/enemy_red_devil.tscn"),
	preload("res://scenes/enemy_palace_zombie.tscn"),
]

# Attack2 释放的 FireSkull 投射物
const FIRE_SKULL_SCENE: PackedScene = preload("res://scenes/fire_skull.tscn")

enum State { IDLE, ATTACK1, ATTACK2 }

const MAX_HEALTH := 20

@onready var sprite: Sprite2D = $Sprite
@onready var anim_timer: Timer = $AnimTimer

# FireSkull 出生位置预览的覆盖层节点（运行时创建）。
#
# 它是 Boss 的兄弟级 Node2D 子节点，且在 Sprite 之后 add_child，
# 由此在 CanvasItem 渲染顺序上**位于 Sprite 之上**——保证十字标记不会被 Boss
# 美术挡住（之前画在 boss.gd 自身 _draw() 里时会被 Sprite 遮挡）。
# 脚本: scripts/boss_skull_marker.gd
const SKULL_MARKER_SCRIPT := preload("res://scripts/boss_skull_marker.gd")
var _skull_marker: Node2D = null

var _idle_frames: Array = []
var _attack1_frames: Array = []
var _attack2_frames: Array = []
var _frame_idx: int = 0
var _state: int = State.IDLE
var health: int = MAX_HEALTH
var dying: bool = false

# 攻击动画专用计时（不复用 AnimTimer，避免 idle 8-tick 节奏被攻击 6-tick 污染）
# Attack1 / Attack2 共用这两个变量：同一时刻只可能有一个攻击在播。
var _attack_anim_t: float = 0.0
var _attack_summon_done: bool = false  # 本轮攻击是否已召唤过（防止重入）

# Attack2 多轮连播状态：
# - _attack2_round_idx：当前已播完的轮数（0 ~ ATTACK2_REPEAT-1 间，最后一轮播完后回 IDLE）。
# - _attack2_skull_done：本轮的 FireSkull 是否已经投出（与 _attack_summon_done 对齐，
#   每轮 reset；保留独立变量以提升可读性，避免与 Attack1 的语义混淆）。
var _attack2_round_idx: int = 0
var _attack2_skull_done: bool = false

# 技能冷却倒计时
var _skill_t: float = 0.0

# 下一次招式索引（0 = ATTACK1，1 = ATTACK2），每次出招后翻转，实现严格交替。
# 首次出招用 ATTACK1（与原先随机机制中"50% 概率 Attack1"在玩家观感上相近，
# 同时确保两招都会出现，不会像之前那样长时间锁死在某一招上）。
var _next_attack: int = 0

func _ready() -> void:
	add_to_group("boss")
	print("[BOSS DEBUG] _ready: layer=", collision_layer, " mask=", collision_mask, " global_position=", global_position)

	# 加载 idle 帧
	for path in IDLE_FRAMES:
		_idle_frames.append(load(path))
	if _idle_frames.size() > 0:
		sprite.texture = _idle_frames[0]

	# 加载 attack1 帧。Godot 未导入的 PNG 会让 load() 返回 null（这种情况通常意味着
	# 美术拖入后没在编辑器里点过保存／没跑过 --import），过滤掉，避免后面贴成空 texture
	# 让 Boss 凭空消失。
	for i in range(1, ATTACK1_FRAME_COUNT + 1):
		var path := ATTACK1_FRAME_PATH_FMT % i
		var tex := load(path)
		if tex == null:
			push_warning("[Boss] Attack1 第 %d 帧加载失败：%s（资源未导入？）" % [i, path])
			continue
		_attack1_frames.append(tex)

	# 加载 attack2 帧（同上规则）
	for i in range(1, ATTACK2_FRAME_COUNT + 1):
		var path2 := ATTACK2_FRAME_PATH_FMT % i
		var tex2 := load(path2)
		if tex2 == null:
			push_warning("[Boss] Attack2 第 %d 帧加载失败：%s（资源未导入？）" % [i, path2])
			continue
		_attack2_frames.append(tex2)

	anim_timer.wait_time = IDLE_FRAME_INTERVAL
	anim_timer.timeout.connect(_on_anim_tick)
	anim_timer.start()

	# 接入 F1 调参：sprite scale + offset 全走 CharTuning，调好的值自动持久化
	CharTuning.tuning_changed.connect(_apply_tuning)
	_apply_tuning()

	# 启动技能冷却
	_skill_t = randf_range(COOLDOWN_MIN, COOLDOWN_MAX)

	# 创建 FireSkull 标记覆盖层。挂在 Sprite 之后（add_child 默认追加到末尾），
	# 渲染顺序自然在 Sprite 之上，不会被 Boss 美术遮挡。
	# z_as_relative + 显式 z_index 双保险——即使将来有人改了 Sprite 的 z_index，
	# marker 也会再加 1 保证仍在 Sprite 之上。
	_skull_marker = Node2D.new()
	_skull_marker.name = "SkullSpawnMarker"
	_skull_marker.set_script(SKULL_MARKER_SCRIPT)
	_skull_marker.z_as_relative = true
	_skull_marker.z_index = 1
	add_child(_skull_marker)

	# 通知 HUD 显示 Boss 血条。延迟一帧确保 level 节点树已就绪、HUD 的 _ready 已跑完。
	call_deferred("_notify_hud_show")

func _apply_tuning() -> void:
	if sprite == null:
		return
	sprite.scale = Vector2(CharTuning.boss_sprite_scale, CharTuning.boss_sprite_scale)
	sprite.position = Vector2(CharTuning.boss_sprite_offset_x, CharTuning.boss_sprite_offset_y)
	# F1 面板里调"被攻击范围"也要立即看到紫色矩形变化，触发自身重绘
	queue_redraw()

# 当前被攻击范围（HurtBox），Boss 局部坐标系下的矩形。
# 受 CharTuning.boss_hurt_offset_x/y、boss_hurt_width/height、boss_hurt_scale 五个字段控制。
# 玩家命中检测应使用此 Rect2（先转到全局坐标再做 has_point / 相交判断）。
func get_hurt_rect_local() -> Rect2:
	var s: float = CharTuning.boss_hurt_scale
	var w: float = CharTuning.boss_hurt_width * s
	var h: float = CharTuning.boss_hurt_height * s
	var cx: float = CharTuning.boss_hurt_offset_x
	var cy: float = CharTuning.boss_hurt_offset_y
	return Rect2(cx - w * 0.5, cy - h * 0.5, w, h)

func get_hurt_rect_global() -> Rect2:
	var local_rect := get_hurt_rect_local()
	return Rect2(to_global(local_rect.position), local_rect.size)

func overlaps_hurt_rect_global(global_rect: Rect2) -> bool:
	return get_hurt_rect_global().intersects(global_rect)

# 仅在 F1 调参面板可见时画出被攻击范围预览（紫色半透明矩形 + 描边 + 中心十字）。
# 不参与游戏逻辑显示，只为策划/美术调参时定位。
#
# 注意：FireSkull 出生位置的橙色十字标记**不画在这里**——它会被 Sprite 子节点遮挡。
# 那条十字现在画在 _skull_marker（scripts/boss_skull_marker.gd）这个兄弟于 Sprite
# 但在它之后 add_child 的覆盖节点上，渲染顺序保证位于 Boss 美术上层。
func _draw() -> void:
	var tuning_panel := get_tree().get_first_node_in_group("tuning_panel")
	var panel_visible: bool = tuning_panel != null and tuning_panel.visible
	if not panel_visible:
		return
	var rect := get_hurt_rect_local()
	# 紫色填充 + 描边
	draw_rect(rect, Color(0.7, 0.3, 1.0, 0.25), true)
	draw_rect(rect, Color(0.85, 0.4, 1.0, 0.95), false, 2.0)
	# 中心十字标记，方便对位
	var cx: float = CharTuning.boss_hurt_offset_x
	var cy: float = CharTuning.boss_hurt_offset_y
	var cross: float = 10.0
	var cross_col := Color(1.0, 0.5, 1.0, 0.95)
	draw_line(Vector2(cx - cross, cy), Vector2(cx + cross, cy), cross_col, 2.0)
	draw_line(Vector2(cx, cy - cross), Vector2(cx, cy + cross), cross_col, 2.0)

func _on_anim_tick() -> void:
	# AnimTimer 仅驱动 idle 循环；攻击中暂停 idle 推进
	if _state != State.IDLE:
		return
	if _idle_frames.is_empty():
		return
	_frame_idx = (_frame_idx + 1) % _idle_frames.size()
	sprite.texture = _idle_frames[_frame_idx]

func _process(delta: float) -> void:
	if dying:
		return
	# IDLE：倒数冷却 → 严格交替进入 ATTACK1 / ATTACK2
	if _state == State.IDLE:
		_skill_t -= delta
		if _skill_t <= 0.0:
			if _next_attack == 0:
				_next_attack = 1
				_enter_attack1()
			else:
				_next_attack = 0
				_enter_attack2()
		return

	# ATTACK1 / ATTACK2：累计推进帧
	if _state == State.ATTACK1:
		_tick_attack1(delta)
	elif _state == State.ATTACK2:
		_tick_attack2(delta)

func _enter_attack1() -> void:
	if _attack1_frames.is_empty():
		# 美术缺失时降级：保持 idle，重排冷却（避免无限重入）
		_skill_t = randf_range(COOLDOWN_MIN, COOLDOWN_MAX)
		return
	_state = State.ATTACK1
	_frame_idx = 0
	_attack_anim_t = 0.0
	_attack_summon_done = false
	sprite.texture = _attack1_frames[0]

func _tick_attack1(delta: float) -> void:
	_attack_anim_t += delta
	while _attack_anim_t >= ATTACK1_FRAME_INTERVAL:
		_attack_anim_t -= ATTACK1_FRAME_INTERVAL
		_frame_idx += 1

		# 触发召唤：当"即将显示"的帧号到达 SUMMON_FRAME_1 时，且本轮还没召唤过。
		# _frame_idx 自增后表示下一张要贴的纹理索引（0-indexed），+1 即 1-indexed 帧号。
		var frame_no := _frame_idx + 1
		if not _attack_summon_done and frame_no >= SUMMON_FRAME_1:
			_attack_summon_done = true
			_summon_minions()

		if _frame_idx >= _attack1_frames.size():
			_finish_attack1()
			return

		sprite.texture = _attack1_frames[_frame_idx]

func _finish_attack1() -> void:
	_state = State.IDLE
	_frame_idx = 0
	_attack_anim_t = 0.0
	if _idle_frames.size() > 0:
		sprite.texture = _idle_frames[0]
	# 重排下一次冷却
	_skill_t = randf_range(COOLDOWN_MIN, COOLDOWN_MAX)

# ── Attack2 ───────────────────────────────────────────────────────────────
# Attack2 是一招"投射物 barrage"：连续播放 ATTACK2_REPEAT 轮 24-frame 序列帧，
# 每轮的中段（FIRE_SKULL_FRAME）从 Boss 左手法器圆环位置生成 1 颗 FireSkull
# 朝玩家飞——三轮即先后释放 3 颗。
# 实现细节：
# - _enter_attack2 重置轮次计数 _attack2_round_idx = 0、清 _attack2_skull_done。
# - _tick_attack2 每物理帧累计时间推进帧索引；当 frame_no 跨过 FIRE_SKULL_FRAME
#   时（且本轮还没投过）调一次 _spawn_fire_skull()。
# - 一轮 24 帧播完不立即回 IDLE：把 _frame_idx 置 0、_attack_anim_t 置 0、
#   _attack2_skull_done 置 false，进入下一轮。播完 ATTACK2_REPEAT 轮才 _finish_attack2。
# - 三轮共用同一个 _attack_anim_t / _frame_idx / sprite.texture 状态机，
#   不与 Attack1 共时存在（State 互斥）。

func _enter_attack2() -> void:
	if _attack2_frames.is_empty():
		# 美术缺失时降级：保持 idle，重排冷却（避免无限重入）
		_skill_t = randf_range(COOLDOWN_MIN, COOLDOWN_MAX)
		return
	_state = State.ATTACK2
	_frame_idx = 0
	_attack_anim_t = 0.0
	_attack2_round_idx = 0
	_attack2_skull_done = false
	# 兼容字段：保持 _attack_summon_done 与 _attack2_skull_done 含义一致（不再使用，但不让它带脏状态）
	_attack_summon_done = false
	sprite.texture = _attack2_frames[0]

func _tick_attack2(delta: float) -> void:
	_attack_anim_t += delta
	while _attack_anim_t >= ATTACK2_FRAME_INTERVAL:
		_attack_anim_t -= ATTACK2_FRAME_INTERVAL
		_frame_idx += 1

		# 触发 FireSkull 释放：当"即将显示"的帧号跨过 FIRE_SKULL_FRAME 时，且本轮还没投过。
		var frame_no := _frame_idx + 1
		if not _attack2_skull_done and frame_no >= FIRE_SKULL_FRAME:
			_attack2_skull_done = true
			_spawn_fire_skull()

		# 单轮 24 帧播完：进入下一轮 or 收招
		if _frame_idx >= _attack2_frames.size():
			_attack2_round_idx += 1
			if _attack2_round_idx >= ATTACK2_REPEAT:
				_finish_attack2()
				return
			# 进入下一轮：复位帧索引和 spawn 标记，但不动 _attack_anim_t 累积
			# （余量自然带入下一轮，节奏不抖）
			_frame_idx = 0
			_attack2_skull_done = false
			sprite.texture = _attack2_frames[0]
			continue

		sprite.texture = _attack2_frames[_frame_idx]

func _finish_attack2() -> void:
	_state = State.IDLE
	_frame_idx = 0
	_attack_anim_t = 0.0
	_attack2_round_idx = 0
	_attack2_skull_done = false
	if _idle_frames.size() > 0:
		sprite.texture = _idle_frames[0]
	# 重排下一次冷却
	_skill_t = randf_range(COOLDOWN_MIN, COOLDOWN_MAX)

# 从 Boss 左手法器圆环位置生成 1 颗 FireSkull，朝玩家飞。
# 法器圆环在 Boss 局部坐标系下的偏移：用 CharTuning.boss_skull_spawn_offset_x/y 暴露给 F1 调参。
# Boss 在画面中通常面朝左（玩家在左侧），sprite.flip_h 默认 false（素材原图朝左）。
# 法器在 Boss "左手"——画面上仍是 Boss 视角的左手；offset_x 的方向以策划在 F1 面板里
# 实际拖动看到的位置为准（默认值已按当前美术调好）。
func _spawn_fire_skull() -> void:
	if FIRE_SKULL_SCENE == null:
		return
	var level := _find_level()
	if level == null:
		return
	var skull := FIRE_SKULL_SCENE.instantiate()
	# 把 FireSkull 挂到 level 节点下（与小怪 spawn 同一父节点），不挂在 Boss 下，
	# 否则 Boss 移动 / 缩放会影响投射物。
	level.add_child(skull)
	# 法器圆环位置 = Boss 全局位置 + 调参偏移
	var spawn_pos: Vector2 = global_position + Vector2(
		CharTuning.boss_skull_spawn_offset_x,
		CharTuning.boss_skull_spawn_offset_y
	)
	skull.global_position = spawn_pos
	# 拿到玩家引用，让 FireSkull 弱追踪
	var player: Node2D = get_tree().get_first_node_in_group("player")
	if skull.has_method("launch"):
		skull.launch(player)

# 召唤：从 level 拿到平台落点，随机挑 SUMMON_COUNT 个不同位置 + 随机一种敌人。
func _summon_minions() -> void:
	var level := _find_level()
	if level == null:
		return
	if not level.has_method("get_platform_spawn_points") or not level.has_method("spawn_summoned_enemy"):
		return

	var points: Array = level.get_platform_spawn_points()
	if points.is_empty() or SUMMON_SCENES.is_empty():
		return

	# 同种敌人
	var scene: PackedScene = SUMMON_SCENES[randi() % SUMMON_SCENES.size()]

	# 不同位置（不放回抽样）；落点不足时允许重复
	points.shuffle()
	for i in range(SUMMON_COUNT):
		var pos: Vector2 = points[i % points.size()]
		level.spawn_summoned_enemy(scene, pos)

func _find_level() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n is Level:
			return n
		n = n.get_parent()
	return null

func take_damage(amount: int = 1) -> void:
	if dying:
		return
	health = max(0, health - amount)
	# 简单受击闪白，给玩家明确反馈。
	sprite.modulate = Color(1.0, 0.35, 0.35, 1.0)
	var tween := create_tween()
	tween.tween_property(sprite, "modulate", Color.WHITE, 0.12)
	# 同步刷新顶部血条 + 触发血条高亮快闪
	var hud := _get_hud()
	if hud != null and hud.has_method("update_boss_health"):
		hud.update_boss_health(health)
	if health <= 0:
		die()

func die() -> void:
	if dying:
		return
	dying = true
	anim_timer.stop()
	# 切换到死亡贴图（单帧定格）
	var die_tex: Texture2D = load("res://assets/sprites/Enemy/Boss/Boss_Die/Boss_Die_01.png") as Texture2D
	if die_tex != null and sprite != null:
		sprite.texture = die_tex
		sprite.modulate = Color.WHITE
	# 通知 HUD 收起血条
	var hud := _get_hud()
	if hud != null and hud.has_method("hide_boss_bar"):
		hud.hide_boss_bar()
	var level := _find_level()
	if level != null and level.has_method("on_boss_defeated"):
		level.on_boss_defeated()
	# 死亡贴图停留一会再移除节点，避免瞬间消失
	var t := get_tree().create_timer(1.2)
	t.timeout.connect(func() -> void:
		if is_instance_valid(self):
			queue_free()
	)

# 通过 level.ui 拿到 HUD（CanvasLayer）。HUD 上挂着 hud.gd，提供 show/update/hide_boss_bar 三个方法。
func _get_hud() -> Node:
	var level := _find_level()
	if level == null:
		return null
	if "ui" in level:
		return level.ui
	return null

# spawn 后第一次出现：显示血条 + 设满血。
func _notify_hud_show() -> void:
	var hud := _get_hud()
	if hud != null and hud.has_method("show_boss_bar"):
		hud.show_boss_bar(MAX_HEALTH)

# 不实现 _physics_process —— Boss 钉死在 spawn 位置，不受重力影响。
# velocity 始终为 0，position 由 level.gd 在 spawn 时一次性设定。
