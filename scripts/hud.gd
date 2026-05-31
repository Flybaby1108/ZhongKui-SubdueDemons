extends CanvasLayer

@onready var hearts_container: HBoxContainer = $TopBar/Hearts
@onready var stage_label: Label = $TopBar/StageLabel
@onready var time_label: Label = $TopBar/TimeLabel
@onready var score_label: Label = $TopBar/ScoreLabel

const HEART_FULL := preload("res://assets/sprites/ui_heart_full.png")
const HEART_EMPTY := preload("res://assets/sprites/ui_heart_empty.png")

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

func _ready() -> void:
	GameState.score_changed.connect(_on_score_changed)
	GameState.lives_changed.connect(_on_lives_changed)
	GameState.stage_changed.connect(_on_stage_changed)
	_rebuild_hearts(GameState.lives)
	_on_score_changed(GameState.score)
	_on_stage_changed(GameState.current_stage)
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

func _on_lives_changed(lives: int) -> void:
	_rebuild_hearts(lives)

func _on_stage_changed(stage: int) -> void:
	stage_label.text = "STAGE %d" % stage

func update_time(time_remaining: float) -> void:
	var seconds = int(time_remaining)
	time_label.text = "TIME %02d" % seconds

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
