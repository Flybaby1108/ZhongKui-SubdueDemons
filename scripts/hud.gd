extends CanvasLayer

@onready var hearts_container: HBoxContainer = $TopBar/Hearts
@onready var stage_label: Label = $TopBar/StageLabel
@onready var time_label: Label = $TopBar/TimeLabel
@onready var coin_icon: TextureRect = $TopBar/CoinCounter/Icon
@onready var coin_digits_container: HBoxContainer = $TopBar/CoinCounter/Digits
@onready var score_label: Label = $TopBar/ScoreLabel

const HEART_FULL := preload("res://assets/sprites/ui_heart_full.png")
const HEART_EMPTY := preload("res://assets/sprites/ui_heart_empty.png")
const COIN_ICON_BASE_SIZE := Vector2(141, 150)
const COIN_DIGIT_BASE_SIZE := Vector2(40, 60)
const COIN_FLY_DURATION := 0.45
const COIN_FLY_ARC_HEIGHT := 90.0
const DIGIT_TEXTURES := [
	preload("res://assets/sprites/ui_digit_0.png"),
	preload("res://assets/sprites/ui_digit_1.png"),
	preload("res://assets/sprites/ui_digit_2.png"),
	preload("res://assets/sprites/ui_digit_3.png"),
	preload("res://assets/sprites/ui_digit_4.png"),
	preload("res://assets/sprites/ui_digit_5.png"),
	preload("res://assets/sprites/ui_digit_6.png"),
	preload("res://assets/sprites/ui_digit_7.png"),
	preload("res://assets/sprites/ui_digit_8.png"),
	preload("res://assets/sprites/ui_digit_9.png"),
]

# ===== Boss 血条 =====
# 屏幕顶部居中的红色血条。Boss spawn 时由 boss.gd 调 show_boss_bar() 出现，
# Boss take_damage() 调 update_boss_health() 同步血量并触发一次 flash 高亮，
# Boss die() 调 hide_boss_bar() 隐藏。整条血条动态在 _ready() 里建好，
# 不污染 hud.tscn 的现有 TopBar 布局。
const BOSS_BAR_WIDTH := 900.0
const BOSS_BAR_HEIGHT := 36.0
const BOSS_BAR_TOP := 110.0          # 距屏幕顶部像素，落在 TopBar 之下
const BOSS_BAR_BG_COLOR := Color(0.08, 0.05, 0.05, 0.85)
const BOSS_BAR_BORDER_COLOR := Color(0.95, 0.85, 0.55, 1.0)  # 金色边框
const BOSS_BAR_FILL_COLOR := Color(0.85, 0.15, 0.15, 1.0)    # 红色填充
const BOSS_BAR_FLASH_COLOR := Color(1.0, 1.0, 1.0, 1.0)      # 闪烁高亮色（白）
const BOSS_BAR_BORDER := 3.0

var _boss_bar_root: Control
var _boss_bar_bg: ColorRect
var _boss_bar_fill: ColorRect
var _boss_bar_label: Label
var _boss_bar_max: int = 1
var _boss_bar_cur: int = 1
var _boss_flash_tween: Tween
var _coin_fly_layer: Control
var _coin_icon_pulse_tween: Tween

func _ready() -> void:
	GameState.score_changed.connect(_on_score_changed)
	GameState.lives_changed.connect(_on_lives_changed)
	GameState.stage_changed.connect(_on_stage_changed)
	GameState.coins_changed.connect(_on_coins_changed)
	CharTuning.tuning_changed.connect(_apply_coin_tuning)
	_rebuild_hearts(GameState.lives)
	_on_score_changed(GameState.score)
	_on_stage_changed(GameState.current_stage)
	_on_coins_changed(GameState.coins)
	_apply_coin_tuning()
	_build_coin_fly_layer()
	_build_boss_bar()

func _rebuild_hearts(lives: int) -> void:
	for child in hearts_container.get_children():
		child.queue_free()
	for i in range(GameState.MAX_LIVES):
		var tex_rect = TextureRect.new()
		tex_rect.texture = HEART_FULL if i < lives else HEART_EMPTY
		tex_rect.custom_minimum_size = Vector2(80, 80)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP
		hearts_container.add_child(tex_rect)

func _on_score_changed(score: int) -> void:
	score_label.text = "SCORE %06d" % score

func _on_coins_changed(coins: int) -> void:
	for child in coin_digits_container.get_children():
		child.free()
	var text := str(max(0, coins))
	for ch in text:
		var digit := int(ch)
		var tex_rect := TextureRect.new()
		tex_rect.texture = DIGIT_TEXTURES[digit]
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		coin_digits_container.add_child(tex_rect)
	_apply_coin_tuning()

func _apply_coin_tuning() -> void:
	var icon_scale: float = max(0.01, CharTuning.coin_icon_scale)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.position = Vector2(CharTuning.coin_icon_pos_x, CharTuning.coin_icon_pos_y)
	coin_icon.custom_minimum_size = COIN_ICON_BASE_SIZE * icon_scale
	coin_icon.size = coin_icon.custom_minimum_size

	var digit_scale: float = max(0.01, CharTuning.coin_digits_scale)
	coin_digits_container.position = Vector2(CharTuning.coin_digits_pos_x, CharTuning.coin_digits_pos_y)
	for child in coin_digits_container.get_children():
		if child is TextureRect:
			child.custom_minimum_size = COIN_DIGIT_BASE_SIZE * digit_scale
			child.size = child.custom_minimum_size

func _on_lives_changed(lives: int) -> void:
	_rebuild_hearts(lives)

func _on_stage_changed(stage: int) -> void:
	stage_label.text = "STAGE %d" % stage

func update_time(time_remaining: float) -> void:
	var seconds = int(time_remaining)
	time_label.text = "TIME %02d" % seconds

func play_coin_pickup_fly(world_position: Vector2, texture: Texture2D, start_size: Vector2 = Vector2.ZERO) -> void:
	if texture == null or coin_icon == null:
		return
	if _coin_fly_layer == null:
		_build_coin_fly_layer()
	var start_pos := _world_to_screen(world_position)
	var target_size := _get_coin_icon_screen_size()
	var end_pos := _get_coin_icon_screen_center()
	if start_size == Vector2.ZERO:
		start_size = texture.get_size() * 0.4
	start_size = start_size.max(Vector2(1.0, 1.0))
	target_size = target_size.max(Vector2(1.0, 1.0))

	var fly_coin := TextureRect.new()
	fly_coin.name = "FlyingCoin"
	fly_coin.texture = texture
	fly_coin.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fly_coin.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fly_coin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly_coin.pivot_offset = start_size * 0.5
	fly_coin.size = start_size
	fly_coin.position = start_pos - fly_coin.pivot_offset
	_coin_fly_layer.add_child(fly_coin)

	var mid_pos := (start_pos + end_pos) * 0.5 + Vector2(0.0, -COIN_FLY_ARC_HEIGHT)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_method(_set_flying_coin_center.bind(fly_coin, start_pos, mid_pos, end_pos), 0.0, 1.0, COIN_FLY_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(fly_coin, "size", target_size, COIN_FLY_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(fly_coin, "pivot_offset", target_size * 0.5, COIN_FLY_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(fly_coin, "modulate:a", 0.0, 0.08).set_delay(COIN_FLY_DURATION - 0.08)
	tween.finished.connect(func() -> void:
		if is_instance_valid(fly_coin):
			fly_coin.queue_free()
		_pulse_coin_icon()
	)

func _build_coin_fly_layer() -> void:
	if _coin_fly_layer != null:
		return
	_coin_fly_layer = Control.new()
	_coin_fly_layer.name = "CoinFlyLayer"
	_coin_fly_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_coin_fly_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_coin_fly_layer)

func _world_to_screen(world_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_position

func _get_coin_icon_screen_center() -> Vector2:
	return coin_icon.get_global_rect().get_center()

func _get_coin_icon_screen_size() -> Vector2:
	return coin_icon.get_global_rect().size

func _set_flying_coin_center(t: float, fly_coin: TextureRect, start_pos: Vector2, mid_pos: Vector2, end_pos: Vector2) -> void:
	if not is_instance_valid(fly_coin):
		return
	var a := start_pos.lerp(mid_pos, t)
	var b := mid_pos.lerp(end_pos, t)
	var center := a.lerp(b, t)
	fly_coin.position = center - fly_coin.pivot_offset

func _pulse_coin_icon() -> void:
	if coin_icon == null:
		return
	if _coin_icon_pulse_tween != null and _coin_icon_pulse_tween.is_valid():
		_coin_icon_pulse_tween.kill()
	coin_icon.pivot_offset = coin_icon.size * 0.5
	coin_icon.scale = Vector2.ONE
	_coin_icon_pulse_tween = create_tween()
	_coin_icon_pulse_tween.tween_property(coin_icon, "scale", Vector2(1.16, 1.16), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_coin_icon_pulse_tween.tween_property(coin_icon, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# ===== Boss 血条相关 =====

# 在 CanvasLayer 上动态构建 BossBar 节点树。结构：
#   _boss_bar_root (Control)         —— 居中锚点容器，控制整体位置
#     ├─ _boss_bar_bg (ColorRect)    —— 深色底 + 金色"边框"（用 4 个 ColorRect 模拟）
#     ├─ _boss_bar_fill (ColorRect)  —— 红色填充，宽度按血量比例缩放
#     └─ _boss_bar_label (Label)     —— "BOSS" 标题，居中显示
func _build_boss_bar() -> void:
	_boss_bar_root = Control.new()
	_boss_bar_root.name = "BossBar"
	_boss_bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 顶部水平居中（锚到顶边中点，再用 offset 把矩形对中）
	_boss_bar_root.anchor_left = 0.5
	_boss_bar_root.anchor_right = 0.5
	_boss_bar_root.anchor_top = 0.0
	_boss_bar_root.anchor_bottom = 0.0
	_boss_bar_root.offset_left = -BOSS_BAR_WIDTH * 0.5
	_boss_bar_root.offset_right = BOSS_BAR_WIDTH * 0.5
	_boss_bar_root.offset_top = BOSS_BAR_TOP
	_boss_bar_root.offset_bottom = BOSS_BAR_TOP + BOSS_BAR_HEIGHT
	_boss_bar_root.visible = false
	add_child(_boss_bar_root)

	# 金色"边框"：用一个比内容大 BOSS_BAR_BORDER 像素的 ColorRect 作底
	var border := ColorRect.new()
	border.color = BOSS_BAR_BORDER_COLOR
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.anchor_left = 0.0
	border.anchor_right = 1.0
	border.anchor_top = 0.0
	border.anchor_bottom = 1.0
	border.offset_left = -BOSS_BAR_BORDER
	border.offset_right = BOSS_BAR_BORDER
	border.offset_top = -BOSS_BAR_BORDER
	border.offset_bottom = BOSS_BAR_BORDER
	_boss_bar_root.add_child(border)

	# 深色背景（空槽）
	_boss_bar_bg = ColorRect.new()
	_boss_bar_bg.color = BOSS_BAR_BG_COLOR
	_boss_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar_bg.anchor_left = 0.0
	_boss_bar_bg.anchor_right = 1.0
	_boss_bar_bg.anchor_top = 0.0
	_boss_bar_bg.anchor_bottom = 1.0
	_boss_bar_root.add_child(_boss_bar_bg)

	# 红色填充。靠左对齐，宽度按 cur/max 缩放（修改 anchor_right 实现）
	_boss_bar_fill = ColorRect.new()
	_boss_bar_fill.color = BOSS_BAR_FILL_COLOR
	_boss_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar_fill.anchor_left = 0.0
	_boss_bar_fill.anchor_right = 1.0
	_boss_bar_fill.anchor_top = 0.0
	_boss_bar_fill.anchor_bottom = 1.0
	_boss_bar_root.add_child(_boss_bar_fill)

	# "BOSS" 标题
	_boss_bar_label = Label.new()
	_boss_bar_label.text = "BOSS"
	_boss_bar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar_label.add_theme_font_size_override("font_size", 28)
	_boss_bar_label.add_theme_color_override("font_color", Color(1, 1, 1, 1))
	_boss_bar_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_boss_bar_label.add_theme_constant_override("outline_size", 4)
	_boss_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_boss_bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_boss_bar_label.anchor_left = 0.0
	_boss_bar_label.anchor_right = 1.0
	_boss_bar_label.anchor_top = 0.0
	_boss_bar_label.anchor_bottom = 1.0
	_boss_bar_root.add_child(_boss_bar_label)

# Boss spawn 时调用：显示血条、设定满血。
func show_boss_bar(max_health: int) -> void:
	if _boss_bar_root == null:
		return
	_boss_bar_max = max(1, max_health)
	_boss_bar_cur = _boss_bar_max
	_boss_bar_root.visible = true
	_apply_boss_fill()
	# 出现时短暂闪一下，吸引注意
	_flash_boss_bar()

# Boss take_damage 时调用：更新当前血量，并触发一次高亮快闪。
func update_boss_health(current: int) -> void:
	if _boss_bar_root == null or not _boss_bar_root.visible:
		return
	_boss_bar_cur = clamp(current, 0, _boss_bar_max)
	_apply_boss_fill()
	_flash_boss_bar()

# Boss die 时调用：隐藏血条。
func hide_boss_bar() -> void:
	if _boss_bar_root == null:
		return
	if _boss_flash_tween != null and _boss_flash_tween.is_valid():
		_boss_flash_tween.kill()
	_boss_bar_root.visible = false
	if _boss_bar_fill != null:
		_boss_bar_fill.color = BOSS_BAR_FILL_COLOR

# 把当前血量比例反映到填充条宽度上。
func _apply_boss_fill() -> void:
	if _boss_bar_fill == null:
		return
	var ratio: float = float(_boss_bar_cur) / float(_boss_bar_max)
	# 用 anchor_right 控制宽度（root 是固定 BOSS_BAR_WIDTH 宽，anchor 0..1 即比例）
	_boss_bar_fill.anchor_right = ratio
	_boss_bar_fill.offset_right = 0.0

# 受击高亮快闪：把整条血条 modulate 拉到亮白，再快速 tween 回正常色。
# 0.08s 拉亮 → 0.18s 回落，整体 ~0.26s，足够明显但不打断节奏。
func _flash_boss_bar() -> void:
	if _boss_bar_root == null:
		return
	if _boss_flash_tween != null and _boss_flash_tween.is_valid():
		_boss_flash_tween.kill()
	# 立刻把填充条切到白色高亮
	if _boss_bar_fill != null:
		_boss_bar_fill.color = BOSS_BAR_FLASH_COLOR
	# 整条 BossBar 同时做一次 modulate 脉冲（亮 → 正常）
	_boss_bar_root.modulate = Color(1.6, 1.6, 1.6, 1.0)
	_boss_flash_tween = create_tween()
	_boss_flash_tween.tween_property(_boss_bar_root, "modulate", Color(1, 1, 1, 1), 0.18)
	# 同步在 0.08s 后把填充色从白回到红
	if _boss_bar_fill != null:
		_boss_flash_tween.parallel().tween_property(_boss_bar_fill, "color", BOSS_BAR_FILL_COLOR, 0.18).set_delay(0.08)
