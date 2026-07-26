extends CharacterBody2D
class_name Player

const SPEED := 500.0
const ACCELERATION := 5000.0
const JUMP_VELOCITY := -1520.0
const GRAVITY := 4000.0
const SUCK_FORCE := 3000.0
const SUCK_RANGE := Vector2(240, 120)
const BALL_SPEED := 1500.0
const HURT_INVINCIBLE_TIME := 1.5
const HOLD_TIME_LIMIT := 5.0
# 头顶倒计时进入危险区（<=2秒）后的闪烁频率（每秒次数）
const BLINK_SPEED := 4.0
const MAX_CAPTURED := 5
const VACUUM_CHARGE_TIME := 1.0
const INHALE_SFX_PATH := "res://assets/audio/Zhongkui_Inhale.mp3"
const INHALE_ENTER_SFX_PATH := "res://assets/audio/Zhongkui_Inhale_Enter.mp3"
const INHALE_OUT_SFX_PATH := "res://assets/audio/Zhongkui_Inhale_Out.mp3"
const INHALE_SFX_FADE_IN_TIME := 0.2
const INHALE_SFX_SILENT_DB := -80.0

const WORLD_LEFT := 0.0
const WORLD_RIGHT := 1920.0
const WORLD_TOP := 0.0
const WORLD_BOTTOM := 1080.0
const BODY_HALF_W := 35.0
const BODY_HEAD := 65.0
const BODY_FOOT := 75.0
const DROP_THROUGH_DISTANCE := 18.0
const DROP_THROUGH_VELOCITY := 500.0
const DROP_THROUGH_FOOT_PROBE_UP := 3.0
const DROP_THROUGH_FOOT_PROBE_DOWN := 14.0
const DROP_THROUGH_FOOT_INSET := 4.0

@onready var sprite: Sprite2D = $Sprite
@onready var collision: CollisionShape2D = $Collision
@onready var suction_area: Area2D = $SuctionArea
@onready var suction_shape: CollisionShape2D = $SuctionArea/Shape
@onready var suction_visual: Sprite2D = $SuctionVisual
@onready var hurt_box: Area2D = $HurtBox
@onready var hurt_shape: CollisionShape2D = $HurtBox/HurtShape
@onready var anim_timer: Timer = $AnimTimer
@onready var hold_warning: Label = $HoldWarning

# "吸"动作的高亮微粒特效（蓄力+正式吸气期间发射，朝葫芦口飞）
var inhale_particles: GPUParticles2D = null
var _inhale_particle_material: ParticleProcessMaterial = null
var inhale_sfx: AudioStreamPlayer = null
var inhale_enter_sfx: AudioStreamPlayer = null
var inhale_out_sfx: AudioStreamPlayer = null
var inhale_sfx_fade_timer: float = 0.0

var facing_right: bool = true
var is_vacuuming: bool = false
var is_charging_vacuum: bool = false
var vacuum_charge_timer: float = 0.0
var captured_enemies: Array = []
# 正在"飞向葫芦"动画中的敌人（不算已捕获，不能被发射；动画完成后转入 captured_enemies）
var _in_flight_enemies: Array = []
var _shoot_when_capture_ready: bool = false
var hold_timer: float = 0.0
var vacuum_armed: bool = false
var last_damage_frame: int = -1000
var invincible: bool = false
var invincible_timer: float = 0.0
var is_switching_platform: bool = false
var _death_sequence_playing: bool = false
var _death_followup_started: bool = false
var _death_anim_index: int = 0
var _death_anim_accumulator: float = 0.0
var anim_state: String = "idle"
var anim_frame: int = 0
var suction_anim_frame: int = 0
var suction_anim_timer: float = 0.0
const SUCTION_ANIM_SPEED := 0.03
const SPRAY_ANIM_SPEED := 0.045
const DUST_ANIM_SPEED := 0.045

# 每个动画状态的"每帧间隔(秒)"，未列出的状态走 AnimTimer 默认 wait_time
# walk 间隔 0.06s ≈ 16fps，比默认 0.125s/8fps 明显更快
const ANIM_FRAME_INTERVAL := {
	"walk": 0.06,
	"inhale_walk": 0.06,
	"die": 0.08,
}
var _anim_accumulator: float = 0.0

const TEX_PATHS := {
	"idle":   ["res://assets/sprites/ZhongKui/idle/ZhongKui_idle_01.png",
			   "res://assets/sprites/ZhongKui/idle/ZhongKui_idle_02.png",
			   "res://assets/sprites/ZhongKui/idle/ZhongKui_idle_03.png",
			   "res://assets/sprites/ZhongKui/idle/ZhongKui_idle_04.png",
			   "res://assets/sprites/ZhongKui/idle/ZhongKui_idle_05.png",
			   "res://assets/sprites/ZhongKui/idle/ZhongKui_idle_06.png",
			   "res://assets/sprites/ZhongKui/idle/ZhongKui_idle_07.png",
			   "res://assets/sprites/ZhongKui/idle/ZhongKui_idle_08.png"],
	"walk":   ["res://assets/sprites/ZhongKui/Walk/Zhongkui_Walk_01.png",
			   "res://assets/sprites/ZhongKui/Walk/Zhongkui_Walk_02.png",
			   "res://assets/sprites/ZhongKui/Walk/Zhongkui_Walk_03.png",
			   "res://assets/sprites/ZhongKui/Walk/Zhongkui_Walk_04.png",
			   "res://assets/sprites/ZhongKui/Walk/Zhongkui_Walk_05.png",
			   "res://assets/sprites/ZhongKui/Walk/Zhongkui_Walk_06.png",
			   "res://assets/sprites/ZhongKui/Walk/Zhongkui_Walk_07.png",
			   "res://assets/sprites/ZhongKui/Walk/Zhongkui_Walk_08.png"],
	"jump":   ["res://assets/sprites/ZhongKui/Jump/ZhongKui_Jump_01.png"],
	"fall":   ["res://assets/sprites/ZhongKui/idle/ZhongKui_idle_01.png"],
	"vacuum": ["res://assets/sprites/ZhongKui/Inhale/ZhongKui_Inhale_01.png"],
	# 吸 + 走路：钟馗抱葫芦边吸边前进时播放（地面上 + 吸气中 + 横向有速度）
	"inhale_walk": ["res://assets/sprites/ZhongKui/InhaleWalk/Zhongkui_InhaleWalk_01.png",
					"res://assets/sprites/ZhongKui/InhaleWalk/Zhongkui_InhaleWalk_02.png",
					"res://assets/sprites/ZhongKui/InhaleWalk/Zhongkui_InhaleWalk_03.png",
					"res://assets/sprites/ZhongKui/InhaleWalk/Zhongkui_InhaleWalk_04.png",
					"res://assets/sprites/ZhongKui/InhaleWalk/Zhongkui_InhaleWalk_05.png",
					"res://assets/sprites/ZhongKui/InhaleWalk/Zhongkui_InhaleWalk_06.png",
					"res://assets/sprites/ZhongKui/InhaleWalk/Zhongkui_InhaleWalk_07.png",
					"res://assets/sprites/ZhongKui/InhaleWalk/Zhongkui_InhaleWalk_08.png"],
	"shoot":  ["res://assets/sprites/ZhongKui/Inhale/ZhongKui_Inhale_01.png"],
	"hurt":   ["res://assets/sprites/ZhongKui/idle/ZhongKui_idle_01.png"],
	# 死亡动画：生命值耗尽时播放一次（不循环），共 14 帧
	"die":    ["res://assets/sprites/ZhongKui/Die/ZhongKui_Die_01.png",
			   "res://assets/sprites/ZhongKui/Die/ZhongKui_Die_02.png",
			   "res://assets/sprites/ZhongKui/Die/ZhongKui_Die_03.png",
			   "res://assets/sprites/ZhongKui/Die/ZhongKui_Die_04.png",
			   "res://assets/sprites/ZhongKui/Die/ZhongKui_Die_05.png",
			   "res://assets/sprites/ZhongKui/Die/ZhongKui_Die_06.png",
			   "res://assets/sprites/ZhongKui/Die/ZhongKui_Die_07.png",
			   "res://assets/sprites/ZhongKui/Die/ZhongKui_Die_08.png",
			   "res://assets/sprites/ZhongKui/Die/ZhongKui_Die_09.png",
			   "res://assets/sprites/ZhongKui/Die/ZhongKui_Die_10.png",
			   "res://assets/sprites/ZhongKui/Die/ZhongKui_Die_11.png",
			   "res://assets/sprites/ZhongKui/Die/ZhongKui_Die_12.png",
			   "res://assets/sprites/ZhongKui/Die/ZhongKui_Die_13.png",
			   "res://assets/sprites/ZhongKui/Die/ZhongKui_Die_14.png"],
}

const SUCTION_TEX_PATHS := [
	"res://assets/sprites/ZhongKui/InhaleEffects_a/InhaleEffects_a_01.png",
	"res://assets/sprites/ZhongKui/InhaleEffects_a/InhaleEffects_a_02.png",
	"res://assets/sprites/ZhongKui/InhaleEffects_a/InhaleEffects_a_03.png",
	"res://assets/sprites/ZhongKui/InhaleEffects_a/InhaleEffects_a_04.png",
	"res://assets/sprites/ZhongKui/InhaleEffects_a/InhaleEffects_a_05.png",
	"res://assets/sprites/ZhongKui/InhaleEffects_a/InhaleEffects_a_06.png",
	"res://assets/sprites/ZhongKui/InhaleEffects_a/InhaleEffects_a_07.png",
	"res://assets/sprites/ZhongKui/InhaleEffects_a/InhaleEffects_a_08.png",
	"res://assets/sprites/ZhongKui/InhaleEffects_a/InhaleEffects_a_09.png",
	"res://assets/sprites/ZhongKui/InhaleEffects_a/InhaleEffects_a_10.png"
]

const DUST_TEX_PATHS := [
	"res://assets/sprites/ZhongKui/Dust/ZhongKui_Dust_01.png",
	"res://assets/sprites/ZhongKui/Dust/ZhongKui_Dust_02.png",
	"res://assets/sprites/ZhongKui/Dust/ZhongKui_Dust_03.png",
	"res://assets/sprites/ZhongKui/Dust/ZhongKui_Dust_04.png",
	"res://assets/sprites/ZhongKui/Dust/ZhongKui_Dust_05.png",
	"res://assets/sprites/ZhongKui/Dust/ZhongKui_Dust_06.png"
]

const SPRAY_TEX_PATHS := [
	"res://assets/sprites/ZhongKui/Spray/ZhongKui_Spray_01.png",
	"res://assets/sprites/ZhongKui/Spray/ZhongKui_Spray_02.png",
	"res://assets/sprites/ZhongKui/Spray/ZhongKui_Spray_03.png",
	"res://assets/sprites/ZhongKui/Spray/ZhongKui_Spray_04.png",
	"res://assets/sprites/ZhongKui/Spray/ZhongKui_Spray_05.png",
	"res://assets/sprites/ZhongKui/Spray/ZhongKui_Spray_06.png"
]

var _textures := {}
var _suction_textures := []
var spray_sprite: Sprite2D = null
var _spray_textures := []
var _spray_playing: bool = false
var _spray_anim_frame: int = 0
var _spray_anim_timer: float = 0.0
var dust_sprite: Sprite2D = null
var _dust_textures := []
var _dust_playing: bool = false
var _dust_anim_frame: int = 0
var _dust_anim_timer: float = 0.0
var _landing_dust_pending: bool = false
var _dust_anchor_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	for state in TEX_PATHS.keys():
		_textures[state] = []
		for path in TEX_PATHS[state]:
			_textures[state].append(load(path))
	for path in SUCTION_TEX_PATHS:
		_suction_textures.append(load(path))
	for path in SPRAY_TEX_PATHS:
		var spray_tex := _load_texture_with_source_fallback(path)
		if spray_tex != null:
			_spray_textures.append(spray_tex)
	for path in DUST_TEX_PATHS:
		var dust_tex := _load_texture_with_source_fallback(path)
		if dust_tex != null:
			_dust_textures.append(dust_tex)
	anim_timer.timeout.connect(_on_anim_tick)
	anim_timer.start()
	hurt_box.body_entered.connect(_on_hurt_box_body_entered)
	hurt_box.area_entered.connect(_on_hurt_box_area_entered)
	suction_visual.visible = false
	suction_visual.modulate = Color(1, 1, 1, 1)
	_setup_inhale_sfx()
	_setup_inhale_enter_sfx()
	_setup_inhale_out_sfx()
	_setup_inhale_particles()
	_setup_spray_fx()
	_setup_landing_dust()
	CharTuning.tuning_changed.connect(_apply_tuning)
	_apply_tuning()

func _setup_spray_fx() -> void:
	spray_sprite = Sprite2D.new()
	spray_sprite.name = "SprayFx"
	spray_sprite.visible = false
	spray_sprite.centered = false
	spray_sprite.z_as_relative = true
	spray_sprite.z_index = sprite.z_index + 1
	add_child(spray_sprite)
	_apply_spray_tuning()

func _setup_landing_dust() -> void:
	dust_sprite = Sprite2D.new()
	dust_sprite.name = "LandingDust"
	dust_sprite.visible = false
	dust_sprite.centered = false
	dust_sprite.top_level = true
	dust_sprite.z_as_relative = true
	dust_sprite.z_index = sprite.z_index
	add_child(dust_sprite)
	move_child(dust_sprite, sprite.get_index())
	_apply_dust_tuning()

func _load_texture_with_source_fallback(path: String) -> Texture2D:
	var tex := load(path) as Texture2D
	if tex != null:
		return tex
	var image := Image.load_from_file(path)
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

func _setup_inhale_sfx() -> void:
	inhale_sfx = AudioStreamPlayer.new()
	inhale_sfx.name = "InhaleSfx"
	var stream := load(INHALE_SFX_PATH)
	if stream != null:
		stream = stream.duplicate()
		if stream is AudioStreamMP3:
			stream.loop = true
		inhale_sfx.stream = stream
	inhale_sfx.volume_db = INHALE_SFX_SILENT_DB
	add_child(inhale_sfx)

func _setup_inhale_enter_sfx() -> void:
	inhale_enter_sfx = AudioStreamPlayer.new()
	inhale_enter_sfx.name = "InhaleEnterSfx"
	inhale_enter_sfx.max_polyphony = MAX_CAPTURED
	var stream := load(INHALE_ENTER_SFX_PATH)
	if stream != null:
		stream = stream.duplicate()
		if stream is AudioStreamMP3:
			stream.loop = false
		inhale_enter_sfx.stream = stream
	add_child(inhale_enter_sfx)

func _play_inhale_enter_sfx() -> void:
	if inhale_enter_sfx == null or inhale_enter_sfx.stream == null:
		return
	inhale_enter_sfx.play()

func _setup_inhale_out_sfx() -> void:
	inhale_out_sfx = AudioStreamPlayer.new()
	inhale_out_sfx.name = "InhaleOutSfx"
	inhale_out_sfx.max_polyphony = MAX_CAPTURED
	var stream := load(INHALE_OUT_SFX_PATH)
	if stream != null:
		stream = stream.duplicate()
		if stream is AudioStreamMP3:
			stream.loop = false
		inhale_out_sfx.stream = stream
	add_child(inhale_out_sfx)

func _play_inhale_out_sfx() -> void:
	if inhale_out_sfx == null or inhale_out_sfx.stream == null:
		return
	inhale_out_sfx.play()

func _set_inhale_sfx_active(active: bool, delta: float) -> void:
	if inhale_sfx == null or inhale_sfx.stream == null:
		return
	if active:
		if not inhale_sfx.playing:
			inhale_sfx.volume_db = INHALE_SFX_SILENT_DB
			inhale_sfx_fade_timer = 0.0
			inhale_sfx.play()
		if inhale_sfx.volume_db < 0.0:
			inhale_sfx_fade_timer = minf(inhale_sfx_fade_timer + delta, INHALE_SFX_FADE_IN_TIME)
			var fade_t := inhale_sfx_fade_timer / INHALE_SFX_FADE_IN_TIME
			inhale_sfx.volume_db = lerpf(INHALE_SFX_SILENT_DB, 0.0, fade_t)
	elif inhale_sfx.playing:
		inhale_sfx.stop()
		inhale_sfx.volume_db = INHALE_SFX_SILENT_DB
		inhale_sfx_fade_timer = 0.0

# 创建高亮微粒系统：从吸气区域**远端宽带**发射，沿途**向中线汇聚**朝葫芦口飞
# 形成"远端宽 → 葫芦口窄"的锥形会聚效果
# 使用 GPUParticles2D，性能好；不指定 texture 时为内置 8×8 白方块
#
# 设计技巧：
# - GPUParticles2D 节点位置 = 葫芦口（发射器原点 = 葫芦口）
# - emission_shape_offset 把发射盒中心**偏移到远端**（远离葫芦口 suction_width 距离）
# - emission_box 高度大、X 厚度小 → 远端形成宽带
# - direction = 朝发射器（即葫芦口）方向
# - radial_accel = 负值 → 粒子被"拉回"发射器原点（葫芦口），上下 Y 偏移的粒子沿途收敛
# - 结果：远端宽 + 沿途收敛 = 锥形（远端宽，葫芦口窄）
func _setup_inhale_particles() -> void:
	inhale_particles = GPUParticles2D.new()
	inhale_particles.name = "InhaleParticles"
	inhale_particles.emitting = false
	inhale_particles.amount = 60
	inhale_particles.lifetime = 0.45
	inhale_particles.explosiveness = 0.0
	inhale_particles.randomness = 1.0
	inhale_particles.local_coords = false
	inhale_particles.preprocess = 0.0

	var mat := ParticleProcessMaterial.new()
	# 发射盒：高度大（Y 散开形成"远端宽带"），X 厚度极小（不让粒子在飞行方向上分散）
	# 实际尺寸 + offset 在 _update_inhale_particles_transform() 里按 CharTuning 同步
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(4.0, CharTuning.suction_height / 2.0, 0)
	# 飞行方向 = 朝葫芦口（默认 -X，朝右时由 _update_facing 翻转为 +X 还是 -X 由 dir_x 决定）
	mat.direction = Vector3(-1, 0, 0)
	mat.spread = 6.0  # 极小散射，方向收敛性更好
	mat.initial_velocity_min = 700.0
	mat.initial_velocity_max = 1000.0
	# 沿飞行方向加速（被吸吮的加速感）
	mat.linear_accel_min = 600.0
	mat.linear_accel_max = 1100.0
	# 径向加速：负值朝发射器原点（葫芦口）收缩 —— 让上下散开的粒子沿途汇聚到中线
	# 这是实现"锥形宽→窄"的关键参数
	mat.radial_accel_min = -1800.0
	mat.radial_accel_max = -2400.0
	mat.gravity = Vector3.ZERO
	mat.damping_min = 0.0
	mat.damping_max = 0.0
	# 缩小尺寸：3-5 px 量级（内置 8x8 白方块）
	mat.scale_min = 0.4
	mat.scale_max = 0.7
	# 寿命中渐缩到 0
	var scale_curve := Curve.new()
	scale_curve.add_point(Vector2(0.0, 1.0))
	scale_curve.add_point(Vector2(0.8, 0.6))
	scale_curve.add_point(Vector2(1.0, 0.0))
	var scale_tex := CurveTexture.new()
	scale_tex.curve = scale_curve
	mat.scale_curve = scale_tex
	# 高亮暖金 → 暖橙渐变 + 末段 alpha fade out
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.95, 0.4, 0.0))      # 起始略透明（淡入）
	grad.set_color(1, Color(1.0, 0.55, 0.15, 0.0))     # 结束透明
	grad.add_point(0.15, Color(1.0, 0.9, 0.35, 1.0))   # 早期高亮金黄
	grad.add_point(0.7,  Color(1.0, 0.7, 0.2, 0.95))   # 中段暖橙
	var grad_tex := GradientTexture1D.new()
	grad_tex.gradient = grad
	mat.color_ramp = grad_tex

	_inhale_particle_material = mat
	inhale_particles.process_material = mat
	add_child(inhale_particles)
	_update_inhale_particles_transform()

# 让粒子的"发射盒位置 + 飞行方向"跟随钟馗朝向
# - 节点 position = 葫芦口（径向加速的原点 = 葫芦口）
# - emission_shape_offset = 远端方向 suction_width 处（发射盒中心 = 远端）
# - direction = 远端→葫芦口
func _update_inhale_particles_transform() -> void:
	if inhale_particles == null:
		return
	var dir_x: float = 1.0 if facing_right else -1.0
	inhale_particles.position = Vector2(CharTuning.suction_offset_x * dir_x, CharTuning.suction_offset_y)
	if _inhale_particle_material != null:
		# 发射盒：薄宽带（X=4 极薄，Y=suction_height/2 高）放在远端
		_inhale_particle_material.emission_box_extents = Vector3(
			4.0,
			CharTuning.suction_height / 2.0,
			0
		)
		# 发射盒中心偏移：远离葫芦口 suction_width 距离（朝钟馗朝向相反方向 = 远端）
		# 钟馗朝右 (dir_x=+1) → 远端在右边 (+X)；朝左 → 远端在左边 (-X)
		_inhale_particle_material.emission_shape_offset = Vector3(
			CharTuning.suction_width * dir_x,
			0,
			0
		)
		# 飞行方向：远端→葫芦口，与远端方向相反
		# 钟馗朝右 → 远端 +X，粒子朝 -X 方向（朝葫芦口）飞
		_inhale_particle_material.direction = Vector3(-dir_x, 0, 0)

func _apply_tuning() -> void:
	sprite.scale = Vector2(CharTuning.sprite_scale, CharTuning.sprite_scale)
	sprite.position = Vector2(CharTuning.sprite_offset_x, CharTuning.sprite_offset_y)
	var body_shape := collision.shape as RectangleShape2D
	if body_shape != null:
		body_shape.size = Vector2(CharTuning.body_width, CharTuning.body_height)
	collision.position.y = CharTuning.body_offset_y
	var hurt := hurt_shape.shape as RectangleShape2D
	if hurt != null:
		hurt.size = Vector2(CharTuning.body_width, CharTuning.body_height)
	hurt_shape.position.y = CharTuning.body_offset_y
	suction_shape.position = Vector2(CharTuning.suction_offset_x, CharTuning.suction_offset_y)
	var suc_rect := suction_shape.shape as RectangleShape2D
	if suc_rect != null:
		suc_rect.size = Vector2(CharTuning.suction_width, CharTuning.suction_height)
	hold_warning.offset_top = CharTuning.hold_warning_offset_y
	hold_warning.offset_bottom = CharTuning.hold_warning_offset_y + 70.0
	_update_facing()
	_apply_spray_tuning()
	_apply_dust_tuning()
	queue_redraw()

func _apply_spray_tuning() -> void:
	if spray_sprite == null:
		return
	var s: float = maxf(0.01, CharTuning.spray_fx_scale)
	spray_sprite.scale = Vector2(s, s)
	_update_spray_transform()
	_refresh_spray_preview_visibility()

func refresh_tuning_previews() -> void:
	_refresh_spray_preview_visibility()

func _refresh_spray_preview_visibility() -> void:
	if spray_sprite == null or _spray_playing:
		return
	if _is_tuning_panel_visible() and not _spray_textures.is_empty():
		_spray_anim_frame = 0
		spray_sprite.texture = _spray_textures[0]
		_update_spray_transform()
		spray_sprite.visible = true
	else:
		spray_sprite.visible = false

func _is_tuning_panel_visible() -> bool:
	var tuning_panel = get_tree().get_first_node_in_group("tuning_panel")
	return tuning_panel != null and tuning_panel.visible

func _apply_dust_tuning() -> void:
	if dust_sprite == null:
		return
	var s: float = maxf(0.01, CharTuning.dust_fx_scale)
	dust_sprite.scale = Vector2(s, s)
	dust_sprite.modulate = Color(1, 1, 1, 0.7)
	if _dust_playing:
		_update_landing_dust_position()

func _draw() -> void:
	# Show suction area + body collision debug rects when tuning panel is open
	var tuning_panel = get_tree().get_first_node_in_group("tuning_panel")
	var panel_visible = tuning_panel != null and tuning_panel.visible
	if not panel_visible:
		return
	# Body 物理碰撞框（蓝色矩形）：实时显示 Body Width / Height / Offset Y 调参效果
	# 中心 = (0, body_offset_y)，尺寸 = body_width × body_height（局部坐标，不随朝向镜像）
	var body_w: float = CharTuning.body_width
	var body_h: float = CharTuning.body_height
	var body_y: float = CharTuning.body_offset_y
	var body_rect := Rect2(-body_w / 2.0, body_y - body_h / 2.0, body_w, body_h)
	draw_rect(body_rect, Color(0.2, 0.5, 1.0, 0.25), true)
	draw_rect(body_rect, Color(0.3, 0.6, 1.0, 0.95), false, 2.0)
	# Suction 吸气区域（青色矩形）
	var dir_x: float = 1.0 if facing_right else -1.0
	var cx: float = CharTuning.suction_offset_x * dir_x
	var cy: float = CharTuning.suction_offset_y
	var w: float = CharTuning.suction_width
	var h: float = CharTuning.suction_height
	var rect := Rect2(cx - w / 2.0, cy - h / 2.0, w, h)
	draw_rect(rect, Color(0, 1, 1, 0.35), true)
	draw_rect(rect, Color(0, 1, 1, 0.9), false, 2.0)
	# 消失点紫色十字由 $VanishMarker 子节点绘制（确保在 Sprite/SuctionVisual 之上）

func _physics_process(delta: float) -> void:
	if _death_sequence_playing:
		_tick_death_sequence(delta)
		return
	if _sync_death_sequence_with_lives():
		return
	var was_on_floor := is_on_floor()
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	var input_x := Input.get_axis("move_left", "move_right")
	if input_x != 0.0:
		# 逐渐加速到目标速度，避免快速点击时一下移动太远
		velocity.x = move_toward(velocity.x, input_x * SPEED, ACCELERATION * delta)
		facing_right = input_x > 0.0
	else:
		velocity.x = move_toward(velocity.x, 0.0, SPEED * 4.0 * delta)

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
		is_switching_platform = true
		_landing_dust_pending = true

	if Input.is_action_just_pressed("move_down"):
		_try_drop_through_platform()

	if not vacuum_armed:
		if not Input.is_action_pressed("vacuum"):
			vacuum_armed = true
		is_vacuuming = false
		is_charging_vacuum = false
		vacuum_charge_timer = 0.0
	else:
		if Input.is_action_just_pressed("vacuum"):
			_shoot_when_capture_ready = false
		var holding := Input.is_action_pressed("vacuum") and captured_enemies.size() < MAX_CAPTURED
		if holding:
			vacuum_charge_timer += delta
			if vacuum_charge_timer >= VACUUM_CHARGE_TIME:
				is_charging_vacuum = false
				is_vacuuming = true
			else:
				is_charging_vacuum = true
				is_vacuuming = false
		else:
			# 松开按键或捕获已满：重置蓄力
			is_charging_vacuum = false
			is_vacuuming = false
			vacuum_charge_timer = 0.0
		if Input.is_action_just_released("vacuum"):
			_handle_vacuum_released()


	move_and_slide()
	if _death_sequence_playing:
		return
	var landed_this_frame := not was_on_floor and is_on_floor()
	if landed_this_frame and _landing_dust_pending:
		_play_landing_dust()
		_landing_dust_pending = false
	if is_switching_platform and is_on_floor():
		is_switching_platform = false
		_damage_from_overlapping_enemy()
	_clamp_to_world()
	if _death_sequence_playing:
		return
	_update_facing()
	_apply_suction(delta)
	_tick_in_flight_enemies()
	_tick_hold_timer(delta)
	_update_animation_state()
	_tick_custom_anim(delta)
	_tick_spray_fx(delta)
	_tick_landing_dust(delta)
	_tick_invincibility(delta)
	_update_carried_enemy_position()

func _update_facing() -> void:
	sprite.flip_h = not facing_right
	var dir_x: float = 1.0 if facing_right else -1.0
	# Collision box position (independent)
	suction_shape.position.x = CharTuning.suction_offset_x * dir_x
	suction_shape.position.y = CharTuning.suction_offset_y
	# Inhale FX visual position (independent)
	suction_visual.position.x = CharTuning.inhale_fx_offset_x * dir_x
	suction_visual.position.y = CharTuning.inhale_fx_offset_y
	suction_visual.flip_h = not facing_right
	# Offset so the left edge aligns with the position
	var tex_w = 250.0  # half of 500px texture width
	suction_visual.offset.x = tex_w if facing_right else -tex_w
	suction_visual.scale = Vector2(CharTuning.inhale_fx_scale, CharTuning.inhale_fx_scale)
	# 同步高亮粒子的位置和飞行方向
	_update_inhale_particles_transform()
	_update_spray_transform()

func _update_spray_transform() -> void:
	if spray_sprite == null:
		return
	var dir_x: float = 1.0 if facing_right else -1.0
	spray_sprite.position = Vector2(CharTuning.spray_fx_offset_x * dir_x, CharTuning.spray_fx_offset_y)
	spray_sprite.flip_h = not facing_right
	if spray_sprite.texture != null:
		spray_sprite.offset = Vector2(-spray_sprite.texture.get_width() * 0.5, -spray_sprite.texture.get_height() * 0.5)

func _apply_suction(delta: float) -> void:
	# 蓄力期间或正式吸气期间都要播放视觉特效
	var fx_active := is_charging_vacuum or is_vacuuming
	suction_visual.visible = fx_active
	_set_inhale_sfx_active(fx_active, delta)
	# 高亮微粒：仅在"吸"状态发射，朝葫芦口飞
	if inhale_particles != null:
		inhale_particles.emitting = fx_active
	if not fx_active:
		suction_anim_frame = 0
		suction_anim_timer = 0.0
		return
	# Animate suction effect independently
	if not _suction_textures.is_empty():
		suction_anim_timer += delta
		if suction_anim_timer >= SUCTION_ANIM_SPEED:
			suction_anim_timer -= SUCTION_ANIM_SPEED
			suction_anim_frame = (suction_anim_frame + 1) % _suction_textures.size()
		suction_visual.texture = _suction_textures[suction_anim_frame]
	if not suction_area.monitoring:
		return
	# 吸气全程（蓄力期 + 完成期）：被吸到的敌人**完全冻结**在原地，绝不漂移。
	# 累计计满 → 立刻进入 in-flight 阶段（0.4s 自我推进飞向葫芦，与玩家是否仍按键解耦）。
	# 设计要点：
	# - 整个 1 秒期间不调用任何会改变敌人 global_position 的逻辑
	# - 避免之前"kinematic lerp 朝消失点"路径——会让敌人穿过 one-way 平台
	# - 玩家可以在 1 秒内自由移动/跳跃，敌人始终停在最初被吸到的那个点
	var dx: float = 1.0 if facing_right else -1.0
	var vanish_point: Vector2 = global_position + Vector2(
		CharTuning.vanish_point_offset_x * dx,
		CharTuning.vanish_point_offset_y
	)
	for body in suction_area.get_overlapping_bodies():
		# 跳过已捕获 / 正在飞行的敌人（in-flight 自我推进，与吸气状态解耦）
		# Boss 投射物 FireSkull 也参与吸入流程：实现了与 Enemy 同名的鸭子接口
		# （freeze_for_suction / begin_capture_flight / get_suction_capture_time / 
		#  is_captured / is_in_flight / suction_hold_timer / enemy_type），
		# 这里只需把判定从 `is Enemy` 扩展为 `is Enemy or is FireSkull` 即可。
		if not (body is Enemy or body is FireSkull) or body.is_captured or body.is_in_flight:
			continue
		if body is Enemy and body.enemy_type == Enemy.Type.FAT_DEMON_KING:
			continue
		# 冻结敌人在原地（蓄力 + 完成期都用同一套冻结逻辑）
		body.freeze_for_suction(vanish_point)
		# 计满 → 立刻起飞向葫芦（独立于玩家吸键状态）
		# 阈值按敌人类型区分：MeteorHammer=2s, RedDevil=3s, RedGhost/PalaceZombie=1s
		# 注意：begin_capture_flight 会重置 is_frozen / is_being_sucked，并接管 sprite 缩放公式
		if body.suction_hold_timer >= body.get_suction_capture_time():
			body.begin_capture_flight(vanish_point)
			_in_flight_enemies.append(body)
			break

# 每帧检查 in-flight 列表：飞行动画完成的敌人转移到 captured_enemies（已入葫芦，可发射）
func _tick_in_flight_enemies() -> void:
	if _in_flight_enemies.is_empty():
		return
	var still_flying: Array = []
	var captured_any := false
	for enemy in _in_flight_enemies:
		if not is_instance_valid(enemy):
			continue
		if enemy.is_captured:
			# 飞行动画完成（enemy._physics_process 内自动 become_captured()）
			_play_inhale_enter_sfx()
			captured_enemies.append(enemy)
			captured_any = true
		else:
			still_flying.append(enemy)
	_in_flight_enemies = still_flying
	if captured_any and _shoot_when_capture_ready and not captured_enemies.is_empty():
		var keep_waiting := not _in_flight_enemies.is_empty()
		_shoot_balls()
		_shoot_when_capture_ready = keep_waiting

func _handle_vacuum_released() -> void:
	_tick_in_flight_enemies()
	if not captured_enemies.is_empty():
		var keep_waiting := not _in_flight_enemies.is_empty()
		_shoot_balls()
		_shoot_when_capture_ready = keep_waiting
	elif not _in_flight_enemies.is_empty():
		_shoot_when_capture_ready = true
	else:
		_shoot_when_capture_ready = false

func _capture_enemy(enemy: Node) -> void:
	captured_enemies.append(enemy)
	enemy.become_captured()
	# 复位被吸时的缩放/隐藏，使敌人在被携带时正常显示
	if enemy.has_method("reset_suction_shrink"):
		enemy.reset_suction_shrink()
	is_vacuuming = false
	suction_visual.visible = false

func _shoot_balls() -> void:
	if captured_enemies.is_empty():
		return
	var ball_scene := load("res://scenes/ball.tscn") as PackedScene
	if ball_scene == null:
		push_error("Failed to load ball scene for player shot.")
		return
	_play_spray_fx()
	var dir_x: int = 1 if facing_right else -1
	var capture_count: int = captured_enemies.size()
	for i in range(captured_enemies.size()):
		var enemy = captured_enemies[i]
		if not is_instance_valid(enemy):
			continue
		var ball = ball_scene.instantiate()
		get_parent().add_child(ball)
		ball.global_position = global_position + Vector2(dir_x * (100 + i * 30), -i * 4)
		ball.launch(Vector2(dir_x, 0) * BALL_SPEED, enemy.enemy_type, capture_count)
		_play_inhale_out_sfx()
		enemy.call_deferred("queue_free")
	captured_enemies.clear()
	hold_timer = 0.0
	_shoot_when_capture_ready = false

func _tick_hold_timer(delta: float) -> void:
	# 关卡已通关（进入通关动画流程）：停止累积 hold_timer，避免动画期间葫芦持有
	# 敌人超时引爆，否则会清零生命并在动画播完后切到 GAME OVER。
	if GameState.is_level_cleared():
		hold_warning.visible = false
		return
	if captured_enemies.is_empty():
		hold_timer = 0.0
		hold_warning.visible = false
		return
	hold_timer += delta
	var remaining = HOLD_TIME_LIMIT - hold_timer
	hold_warning.visible = true
	hold_warning.text = "%d" % ceili(remaining)
	if remaining <= 2.0:
		# 进入危险区：剧烈闪烁（高频在红色与亮白之间切换，并震荡透明度）
		var t := Time.get_ticks_msec() / 1000.0
		var pulse := sin(t * BLINK_SPEED * TAU) * 0.5 + 0.5  # 0~1
		var col := Color(1, 0.2, 0.2, 1).lerp(Color(1, 1, 1, 1), pulse)
		col.a = lerp(0.35, 1.0, pulse)
		hold_warning.modulate = col
	else:
		hold_warning.modulate = Color(1, 0.8, 0.2, 1)
	if hold_timer >= HOLD_TIME_LIMIT:
		_explode()

func _explode() -> void:
	for enemy in captured_enemies:
		if is_instance_valid(enemy):
			enemy.call_deferred("queue_free")
	captured_enemies.clear()
	hold_timer = 0.0
	_shoot_when_capture_ready = false
	# 已在死亡序列中：不重复触发，避免葫芦超时与受击致死同帧叠加。
	if _death_sequence_playing:
		return
	# 葫芦引爆视为致命：清空生命（HUD 红心全灭），然后走与受击/坠落死亡完全
	# 一致的死亡序列。绝不能只设 lives=0 + 直接 goto_game_over —— 那条路径在
	# goto_game_over 被守卫（_level_cleared / _game_over_queued）拦截时会留下
	# “lives=0 但钟馗仍存活”的悬挂状态：此后 take_damage() 因 lives<=0 提前
	# return，钟馗再也不会扣命/受伤/死亡（ChapterBoss 关卡“生命耗尽却不死”Bug）。
	GameState.lives = 0
	GameState.lives_changed.emit(0)
	_play_death_sequence()

func _update_carried_enemy_position() -> void:
	# 敌人被吸入葫芦后已隐藏，不再需要更新位置
	pass

func _update_animation_state() -> void:
	if _death_sequence_playing:
		return
	var new_state: String
	if anim_state == "hurt" and invincible_timer > HURT_INVINCIBLE_TIME - 0.3:
		new_state = "hurt"
	elif not is_on_floor():
		new_state = "jump" if velocity.y < 0.0 else "fall"
	elif is_vacuuming or is_charging_vacuum:
		# 吸气中 + 地面上 + 有横向速度 → 边吸边走的专用动画
		new_state = "inhale_walk" if abs(velocity.x) > 5.0 else "vacuum"
	elif abs(velocity.x) > 5.0:
		new_state = "walk"
	else:
		new_state = "idle"
	if new_state != anim_state:
		anim_state = new_state
		anim_frame = 0
		_anim_accumulator = 0.0
		_apply_frame()

func _on_anim_tick() -> void:
	# 状态有自定义间隔时，由 _process 推进，跳过默认 Timer tick
	if ANIM_FRAME_INTERVAL.has(anim_state):
		return
	var frames = _textures.get(anim_state, [])
	if frames.is_empty():
		return
	anim_frame = (anim_frame + 1) % frames.size()
	_apply_frame()

func _tick_custom_anim(delta: float) -> void:
	if not ANIM_FRAME_INTERVAL.has(anim_state):
		_anim_accumulator = 0.0
		return
	var interval: float = ANIM_FRAME_INTERVAL[anim_state]
	_anim_accumulator += delta
	while _anim_accumulator >= interval:
		_anim_accumulator -= interval
		var frames = _textures.get(anim_state, [])
		if frames.is_empty():
			return
		anim_frame = (anim_frame + 1) % frames.size()
		_apply_frame()

func _play_spray_fx() -> void:
	if spray_sprite == null or _spray_textures.is_empty():
		return
	_spray_playing = true
	_spray_anim_frame = 0
	_spray_anim_timer = 0.0
	spray_sprite.visible = true
	_apply_spray_tuning()
	_apply_spray_frame()

func _tick_spray_fx(delta: float) -> void:
	if not _spray_playing or spray_sprite == null:
		return
	_spray_anim_timer += delta
	while _spray_anim_timer >= SPRAY_ANIM_SPEED:
		_spray_anim_timer -= SPRAY_ANIM_SPEED
		_spray_anim_frame += 1
		if _spray_anim_frame >= _spray_textures.size():
			_spray_playing = false
			_refresh_spray_preview_visibility()
			return
		_apply_spray_frame()

func _apply_spray_frame() -> void:
	if spray_sprite == null or _spray_textures.is_empty():
		return
	spray_sprite.texture = _spray_textures[_spray_anim_frame % _spray_textures.size()]
	_update_spray_transform()

func _play_landing_dust() -> void:
	if dust_sprite == null or _dust_textures.is_empty():
		return
	_dust_playing = true
	_dust_anim_frame = 0
	_dust_anim_timer = 0.0
	_dust_anchor_position = _get_foot_world_position()
	_update_landing_dust_position()
	dust_sprite.visible = true
	_apply_dust_tuning()
	_apply_dust_frame()

func _tick_landing_dust(delta: float) -> void:
	if not _dust_playing or dust_sprite == null:
		return
	_dust_anim_timer += delta
	while _dust_anim_timer >= DUST_ANIM_SPEED:
		_dust_anim_timer -= DUST_ANIM_SPEED
		_dust_anim_frame += 1
		if _dust_anim_frame >= _dust_textures.size():
			_dust_playing = false
			dust_sprite.visible = false
			return
		_apply_dust_frame()

func _apply_dust_frame() -> void:
	if dust_sprite == null or _dust_textures.is_empty():
		return
	var tex := _dust_textures[_dust_anim_frame % _dust_textures.size()] as Texture2D
	dust_sprite.texture = tex
	dust_sprite.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height())

func _update_landing_dust_position() -> void:
	if dust_sprite == null:
		return
	dust_sprite.global_position = _dust_anchor_position + Vector2(
		CharTuning.dust_fx_offset_x,
		CharTuning.dust_fx_offset_y
	)

func _get_foot_world_position() -> Vector2:
	var foot_offset_y: float = CharTuning.body_offset_y + CharTuning.body_height * 0.5
	if collision != null and collision.shape is RectangleShape2D:
		foot_offset_y = collision.position.y + (collision.shape as RectangleShape2D).size.y * 0.5
	return global_position + Vector2(0.0, foot_offset_y)

func _apply_frame() -> void:
	var frames = _textures.get(anim_state, [])
	if frames.is_empty():
		return
	sprite.texture = frames[anim_frame % frames.size()]

func take_damage() -> void:
	if _death_sequence_playing:
		return
	if _sync_death_sequence_with_lives():
		return
	if GameState.lose_life() <= 0:
		_play_death_sequence()
		return
	anim_state = "hurt"
	_apply_frame()

func ignores_boss_ghost_fire_damage() -> bool:
	return not is_on_floor()

func _tick_invincibility(delta: float) -> void:
	if not invincible:
		sprite.modulate.a = 1.0
		return
	invincible_timer -= delta
	sprite.modulate.a = 0.4 if int(invincible_timer * 10) % 2 == 0 else 1.0
	if invincible_timer <= 0.0:
		invincible = false
		sprite.modulate.a = 1.0
		hurt_box.set_deferred("monitoring", true)

func _on_hurt_box_body_entered(body: Node) -> void:
	# 钟馗处于"吸"状态时，被吸过来的敌人不会造成伤害
	if is_vacuuming:
		return
	var current_frame := Engine.get_physics_frames()
	if current_frame - last_damage_frame < 90:
		return
	if body is Enemy and not body.is_captured:
		if is_switching_platform:
			return
		# Boss 召唤的敌人出现后头 1 秒内不造成接触伤害
		if "contact_damage_delay_t" in body and body.contact_damage_delay_t > 0.0:
			return
		last_damage_frame = current_frame
		invincible = true
		invincible_timer = HURT_INVINCIBLE_TIME
		take_damage()
	# Boss 的 FireSkull 投射物撞到钟馗：扣一颗心 + FireSkull 自销毁
	# （吸气期间不应被打到——is_vacuuming 已在函数顶部 early-return；
	#  且被吸到后 is_captured/is_in_flight 期间 FireSkull 是 hide() 状态不会再触发。）
	elif body is FireSkull and not body.is_captured and not body.is_in_flight:
		last_damage_frame = current_frame
		invincible = true
		invincible_timer = HURT_INVINCIBLE_TIME
		take_damage()
		body.call_deferred("queue_free")

func _damage_from_overlapping_enemy() -> void:
	if invincible or not hurt_box.monitoring:
		return
	var current_frame := Engine.get_physics_frames()
	if current_frame - last_damage_frame < 90:
		return
	for body in hurt_box.get_overlapping_bodies():
		if body is Enemy and not body.is_captured:
			# Boss 召唤的敌人出现后头 1 秒内不造成接触伤害
			if "contact_damage_delay_t" in body and body.contact_damage_delay_t > 0.0:
				continue
			last_damage_frame = current_frame
			invincible = true
			invincible_timer = HURT_INVINCIBLE_TIME
			take_damage()
			return

func _on_hurt_box_area_entered(_area: Area2D) -> void:
	pass

func _clamp_to_world() -> void:
	if _death_sequence_playing:
		return
	# Left/Right boundaries
	if position.x < WORLD_LEFT + BODY_HALF_W:
		position.x = WORLD_LEFT + BODY_HALF_W
		if velocity.x < 0.0:
			velocity.x = 0.0
	elif position.x > WORLD_RIGHT - BODY_HALF_W:
		position.x = WORLD_RIGHT - BODY_HALF_W
		if velocity.x > 0.0:
			velocity.x = 0.0
	# Top: allow half body above screen
	if position.y < WORLD_TOP - BODY_HEAD:
		position.y = WORLD_TOP - BODY_HEAD
		if velocity.y < 0.0:
			velocity.y = 0.0
	# Bottom: falling below screen = death, respawn
	if position.y > WORLD_BOTTOM + BODY_FOOT + 50.0:
		_respawn()

func _respawn() -> void:
	if _death_sequence_playing:
		return
	if _sync_death_sequence_with_lives():
		return
	_landing_dust_pending = false
	_dust_playing = false
	if dust_sprite != null:
		dust_sprite.visible = false
	_spray_playing = false
	if spray_sprite != null:
		spray_sprite.visible = false
	var level := _get_level()
	if level != null and level.has_method("get_spawn_pos"):
		position = level.get_spawn_pos()
	else:
		position = Vector2(100, 500)
	velocity = Vector2.ZERO
	if GameState.lose_life() <= 0:
		_play_death_sequence()
		return
	invincible = true
	invincible_timer = 2.0
	hurt_box.set_deferred("monitoring", false)

func _sync_death_sequence_with_lives() -> bool:
	# 某些关卡事件/伤害链可能先把全局 lives 扣到 0，再回到 player 主循环；
	# 若这里只是 early-return，钟馗会卡在“0 命但未进入死亡序列”的悬挂状态。
	# 统一在玩家主链路里兜底同步，保证 lives 归零一定切入死亡流程。
	if GameState.lives > 0:
		return false
	_play_death_sequence()
	return true

func _get_level() -> Node:
	var parent := get_parent()
	if parent == null:
		return null
	return parent.get_parent()

func _play_death_sequence() -> void:
	if _death_sequence_playing:
		return
	_death_sequence_playing = true
	_death_followup_started = false
	_death_anim_index = 0
	_death_anim_accumulator = 0.0
	velocity = Vector2.ZERO
	invincible = false
	invincible_timer = 0.0
	is_vacuuming = false
	is_charging_vacuum = false
	vacuum_charge_timer = 0.0
	vacuum_armed = false
	_shoot_when_capture_ready = false
	_landing_dust_pending = false
	_dust_playing = false
	if dust_sprite != null:
		dust_sprite.visible = false
	_spray_playing = false
	if spray_sprite != null:
		spray_sprite.visible = false
	hold_warning.visible = false
	suction_visual.visible = false
	suction_area.monitoring = false
	hurt_box.set_deferred("monitoring", false)
	collision.set_deferred("disabled", true)
	anim_timer.stop()
	anim_state = "die"
	anim_frame = 0

	var level := _get_level()
	if level != null and level.has_method("lock_for_game_over"):
		level.lock_for_game_over()

	var frames: Array = _textures.get("die", [])
	if frames.is_empty():
		push_warning("Death animation frames not found for ZhongKui.")
		call_deferred("_start_death_followup")
		return

	sprite.texture = frames[0]

func _tick_death_sequence(delta: float) -> void:
	if not _death_sequence_playing:
		return
	var frames: Array = _textures.get("die", [])
	if frames.is_empty():
		call_deferred("_start_death_followup")
		return
	var interval: float = ANIM_FRAME_INTERVAL.get("die", 0.08)
	_death_anim_accumulator += delta
	while _death_anim_accumulator >= interval and _death_anim_index < frames.size() - 1:
		_death_anim_accumulator -= interval
		_death_anim_index += 1
		sprite.texture = frames[_death_anim_index]
	if _death_anim_index >= frames.size() - 1:
		call_deferred("_start_death_followup")

func _start_death_followup() -> void:
	if _death_followup_started:
		return
	_death_followup_started = true
	GameState.goto_game_over()

func _try_drop_through_platform() -> void:
	if not is_on_floor() and not _has_one_way_tile_underfoot():
		return
	for i in range(get_slide_collision_count()):
		var c := get_slide_collision(i)
		if _is_one_way_tile_collision(c):
			_start_drop_through_platform()
			return
	if _has_one_way_tile_underfoot():
		_start_drop_through_platform()

func _start_drop_through_platform() -> void:
	position.y += DROP_THROUGH_DISTANCE
	velocity.y = DROP_THROUGH_VELOCITY
	is_switching_platform = true
	_landing_dust_pending = true

func _is_one_way_tile_collision(c: KinematicCollision2D) -> bool:
	var collider = c.get_collider()
	if not collider is TileMapLayer:
		return false
	return _is_one_way_tile_at(collider, c.get_position() - c.get_normal())

func _has_one_way_tile_underfoot() -> bool:
	var body_shape := collision.shape as RectangleShape2D
	if body_shape == null:
		return false
	var half_w := body_shape.size.x * absf(collision.global_scale.x) * 0.5
	var foot_y := collision.global_position.y + body_shape.size.y * absf(collision.global_scale.y) * 0.5
	var probe_offsets := [0.0]
	var edge_offset = maxf(0.0, half_w - DROP_THROUGH_FOOT_INSET)
	if edge_offset > 0.0:
		probe_offsets.append(-edge_offset)
		probe_offsets.append(edge_offset)

	var space_state := get_world_2d().direct_space_state
	for offset_x in probe_offsets:
		var from := Vector2(global_position.x + float(offset_x), foot_y - DROP_THROUGH_FOOT_PROBE_UP)
		var to := Vector2(from.x, foot_y + DROP_THROUGH_FOOT_PROBE_DOWN)
		var query := PhysicsRayQueryParameters2D.create(from, to, collision_mask, [get_rid()])
		var hit := space_state.intersect_ray(query)
		if hit.is_empty():
			continue
		var collider = hit.get("collider")
		if collider is TileMapLayer and _is_one_way_tile_at(collider, hit.get("position") + Vector2.DOWN):
			return true
	return false

func _is_one_way_tile_at(tile_layer: TileMapLayer, world_pos: Vector2) -> bool:
	var tile_pos: Vector2i = tile_layer.local_to_map(tile_layer.to_local(world_pos))
	var data: TileData = tile_layer.get_cell_tile_data(tile_pos)
	if data == null:
		return false
	for polygon_index in range(data.get_collision_polygons_count(0)):
		if data.is_collision_polygon_one_way(0, polygon_index):
			return true
	return false
