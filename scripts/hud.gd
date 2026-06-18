extends CanvasLayer

@onready var heart_counter: Control = $TopBar/HeartCounter
@onready var hearts_container: HBoxContainer = $TopBar/HeartCounter/Hearts
@onready var time_label: Label = $TopBar/CountdownCounter/TimeLabel
@onready var countdown_background: TextureRect = $CountdownBackground
@onready var avatar_frame: TextureRect = $AvatarFrame
@onready var coin_icon: TextureRect = $TopBar/CoinCounter/Icon
@onready var coin_digits_container: HBoxContainer = $TopBar/CoinCounter/Digits
@onready var yuanbao_icon: TextureRect = $TopBar/YuanbaoCounter/Icon
@onready var yuanbao_digits_container: HBoxContainer = $TopBar/YuanbaoCounter/Digits

const HEART_FULL := preload("res://assets/sprites/ui_heart_full.png")
const HEART_EMPTY := preload("res://assets/sprites/ui_heart_empty.png")
const FAT_DEMON_KING_FRAME := preload("res://assets/sprites/Chapter_BG/FatDemonKingFrame.png")
const BOSS_FRAME := preload("res://assets/sprites/Chapter_BG/BossFrame.png")
const HEART_BASE_SIZE := Vector2(80, 80)
const AVATAR_FRAME_BASE_SIZE := Vector2(256, 256)
const BOSS_FRAME_BASE_SIZE := Vector2(1024, 1024)
const COUNTDOWN_BG_BASE_SIZE := Vector2(248, 105)
const COIN_ICON_BASE_SIZE := Vector2(141, 150)
const YUANBAO_ICON_BASE_SIZE := Vector2(200, 128)
const COIN_DIGIT_BASE_SIZE := Vector2(40, 60)
const PICKUP_FLY_DURATION := 0.45
const PICKUP_FLY_ARC_HEIGHT := 90.0
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

# ===== Boss 头像 / 血条 =====
# Boss spawn 时由 boss.gd 调 show_boss_bar() 出现，take_damage() 调
# update_boss_health() 同步血量并触发 flash，高亮和隐藏都在这里统一处理。
const BOSS_BAR_BG_COLOR := Color(0.08, 0.05, 0.05, 0.85)
const BOSS_BAR_BORDER_COLOR := Color(0.95, 0.85, 0.55, 1.0)  # 金色边框
const BOSS_BAR_FILL_COLOR := Color(0.85, 0.15, 0.15, 1.0)    # 红色填充
const BOSS_BAR_FLASH_COLOR := Color(1.0, 1.0, 1.0, 1.0)      # 闪烁高亮色（白）
const BOSS_BAR_BORDER := 3.0
const FDK_BAR_BG_COLOR := Color(0.08, 0.05, 0.05, 0.85)
const FDK_BAR_BORDER_COLOR := Color(0.95, 0.76, 0.35, 1.0)
const FDK_BAR_FILL_COLOR := Color(0.88, 0.18, 0.12, 1.0)
const FDK_BAR_FLASH_COLOR := Color(1.0, 1.0, 1.0, 1.0)
const FDK_BAR_BORDER := 3.0

var _boss_bar_root: Control
var _boss_avatar_frame: TextureRect
var _boss_bar_fill: ColorRect
var _boss_bar_max: int = 1
var _boss_bar_cur: int = 1
var _boss_bar_active: bool = false
var _boss_flash_tween: Tween
var _fdk_hud_root: Control
var _fdk_avatar_frame: TextureRect
var _fdk_bar_root: Control
var _fdk_bar_fill: ColorRect
var _fdk_bar_max: int = 1
var _fdk_bar_cur: int = 1
var _fdk_bar_active: bool = false
var _fdk_flash_tween: Tween
var _pickup_fly_layer: Control
var _coin_icon_pulse_tween: Tween
var _yuanbao_icon_pulse_tween: Tween
var _pickup_fly_tweens: Array[Tween] = []

class PickupFlyContext:
	var fly_pickup: TextureRect
	var pulse_callback: Callable
	var tween: Tween

func _exit_tree() -> void:
	if GameState.lives_changed.is_connected(_on_lives_changed):
		GameState.lives_changed.disconnect(_on_lives_changed)
	if GameState.coins_changed.is_connected(_on_coins_changed):
		GameState.coins_changed.disconnect(_on_coins_changed)
	if GameState.yuanbao_changed.is_connected(_on_yuanbao_changed):
		GameState.yuanbao_changed.disconnect(_on_yuanbao_changed)
	if CharTuning.tuning_changed.is_connected(_apply_pickup_tuning):
		CharTuning.tuning_changed.disconnect(_apply_pickup_tuning)
	if _boss_flash_tween != null and _boss_flash_tween.is_valid():
		_boss_flash_tween.kill()
	if _fdk_flash_tween != null and _fdk_flash_tween.is_valid():
		_fdk_flash_tween.kill()
	if _coin_icon_pulse_tween != null and _coin_icon_pulse_tween.is_valid():
		_coin_icon_pulse_tween.kill()
	if _yuanbao_icon_pulse_tween != null and _yuanbao_icon_pulse_tween.is_valid():
		_yuanbao_icon_pulse_tween.kill()
	for tween in _pickup_fly_tweens:
		if tween != null and tween.is_valid():
			tween.kill()
	_pickup_fly_tweens.clear()

func _ready() -> void:
	GameState.lives_changed.connect(_on_lives_changed)
	GameState.coins_changed.connect(_on_coins_changed)
	GameState.yuanbao_changed.connect(_on_yuanbao_changed)
	CharTuning.tuning_changed.connect(_apply_pickup_tuning)
	_rebuild_hearts(GameState.lives)
	_on_coins_changed(GameState.coins)
	_on_yuanbao_changed(GameState.yuanbao)
	_apply_pickup_tuning()
	_build_pickup_fly_layer()
	_build_fat_demon_king_hud()
	_build_boss_bar()

func _rebuild_hearts(lives: int) -> void:
	for child in hearts_container.get_children():
		child.queue_free()
	var heart_scale: float = max(0.01, CharTuning.heart_scale)
	for i in range(GameState.MAX_LIVES):
		var tex_rect = TextureRect.new()
		tex_rect.texture = HEART_FULL if i < lives else HEART_EMPTY
		tex_rect.custom_minimum_size = HEART_BASE_SIZE * heart_scale
		tex_rect.size = tex_rect.custom_minimum_size
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		hearts_container.add_child(tex_rect)
	_apply_heart_tuning()

func _on_coins_changed(coins: int) -> void:
	_rebuild_digits(coin_digits_container, coins)
	_apply_pickup_tuning()

func _on_yuanbao_changed(yuanbao: int) -> void:
	_rebuild_digits(yuanbao_digits_container, yuanbao)
	_apply_pickup_tuning()

func _rebuild_digits(container: HBoxContainer, amount: int) -> void:
	for child in container.get_children():
		child.free()
	var text := str(max(0, amount))
	for ch in text:
		var digit := int(ch)
		var tex_rect := TextureRect.new()
		tex_rect.texture = DIGIT_TEXTURES[digit]
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		container.add_child(tex_rect)

func _apply_pickup_tuning() -> void:
	_apply_heart_tuning()

	var avatar_scale: float = max(0.01, CharTuning.avatar_frame_scale)
	avatar_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	avatar_frame.position = Vector2(CharTuning.avatar_frame_pos_x, CharTuning.avatar_frame_pos_y)
	avatar_frame.custom_minimum_size = AVATAR_FRAME_BASE_SIZE * avatar_scale
	avatar_frame.size = avatar_frame.custom_minimum_size
	_apply_fat_demon_king_tuning()
	_apply_boss_tuning()

	var countdown_scale: float = max(0.01, CharTuning.countdown_bg_scale)
	countdown_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	countdown_background.custom_minimum_size = COUNTDOWN_BG_BASE_SIZE * countdown_scale
	countdown_background.size = countdown_background.custom_minimum_size
	countdown_background.position = Vector2(
		CharTuning.countdown_bg_pos_x,
		CharTuning.countdown_bg_pos_y
	) - countdown_background.size * 0.5
	time_label.position = Vector2(CharTuning.countdown_digits_pos_x, CharTuning.countdown_digits_pos_y)
	time_label.scale = Vector2.ONE * max(0.01, CharTuning.countdown_digits_scale)

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

	var yuanbao_icon_scale: float = max(0.01, CharTuning.yuanbao_icon_scale)
	yuanbao_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	yuanbao_icon.position = Vector2(CharTuning.yuanbao_icon_pos_x, CharTuning.yuanbao_icon_pos_y)
	yuanbao_icon.custom_minimum_size = YUANBAO_ICON_BASE_SIZE * yuanbao_icon_scale
	yuanbao_icon.size = yuanbao_icon.custom_minimum_size

	var yuanbao_digit_scale: float = max(0.01, CharTuning.yuanbao_digits_scale)
	yuanbao_digits_container.position = Vector2(CharTuning.yuanbao_digits_pos_x, CharTuning.yuanbao_digits_pos_y)
	for child in yuanbao_digits_container.get_children():
		if child is TextureRect:
			child.custom_minimum_size = COIN_DIGIT_BASE_SIZE * yuanbao_digit_scale
			child.size = child.custom_minimum_size

func _apply_heart_tuning() -> void:
	var heart_scale: float = max(0.01, CharTuning.heart_scale)
	var heart_size := HEART_BASE_SIZE * heart_scale
	var heart_content_size := Vector2(
		heart_size.x * GameState.MAX_LIVES + hearts_container.get_theme_constant("separation") * max(0, GameState.MAX_LIVES - 1),
		heart_size.y
	)
	hearts_container.position = Vector2(CharTuning.heart_pos_x, CharTuning.heart_pos_y)
	hearts_container.custom_minimum_size = heart_content_size
	if heart_counter != null:
		heart_counter.custom_minimum_size = Vector2(
			max(280.0, max(0.0, CharTuning.heart_pos_x) + heart_content_size.x),
			max(80.0, max(0.0, CharTuning.heart_pos_y) + heart_content_size.y)
		)
	for child in hearts_container.get_children():
		if child is TextureRect:
			child.custom_minimum_size = heart_size
			child.size = child.custom_minimum_size

func _on_lives_changed(lives: int) -> void:
	_rebuild_hearts(lives)

func update_time(time_remaining: float) -> void:
	var seconds = int(time_remaining)
	time_label.text = "%02d" % seconds

func play_coin_pickup_fly(world_position: Vector2, texture: Texture2D, start_size: Vector2 = Vector2.ZERO) -> void:
	_play_pickup_fly(world_position, texture, start_size, coin_icon, Callable(self, "_pulse_coin_icon"), "FlyingCoin")

func play_yuanbao_pickup_fly(world_position: Vector2, texture: Texture2D, start_size: Vector2 = Vector2.ZERO) -> void:
	_play_pickup_fly(world_position, texture, start_size, yuanbao_icon, Callable(self, "_pulse_yuanbao_icon"), "FlyingYuanbao")

func _play_pickup_fly(world_position: Vector2, texture: Texture2D, start_size: Vector2, target_icon: TextureRect, pulse_callback: Callable, node_name: String) -> void:
	if texture == null or target_icon == null:
		return
	if _pickup_fly_layer == null:
		_build_pickup_fly_layer()
	var start_pos := _world_to_screen(world_position)
	var target_size := target_icon.get_global_rect().size
	var end_pos := target_icon.get_global_rect().get_center()
	if start_size == Vector2.ZERO:
		start_size = texture.get_size() * 0.4
	start_size = start_size.max(Vector2(1.0, 1.0))
	target_size = target_size.max(Vector2(1.0, 1.0))

	var fly_pickup := TextureRect.new()
	fly_pickup.name = node_name
	fly_pickup.texture = texture
	fly_pickup.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fly_pickup.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	fly_pickup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fly_pickup.pivot_offset = start_size * 0.5
	fly_pickup.size = start_size
	fly_pickup.position = start_pos - fly_pickup.pivot_offset
	_pickup_fly_layer.add_child(fly_pickup)

	var mid_pos := (start_pos + end_pos) * 0.5 + Vector2(0.0, -PICKUP_FLY_ARC_HEIGHT)
	var tween := create_tween()
	var context := PickupFlyContext.new()
	context.fly_pickup = fly_pickup
	context.pulse_callback = pulse_callback
	context.tween = tween
	_pickup_fly_tweens.append(tween)
	tween.set_parallel(true)
	tween.tween_method(_set_flying_pickup_center.bind(fly_pickup, start_pos, mid_pos, end_pos), 0.0, 1.0, PICKUP_FLY_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(fly_pickup, "size", target_size, PICKUP_FLY_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(fly_pickup, "pivot_offset", target_size * 0.5, PICKUP_FLY_DURATION).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(fly_pickup, "modulate:a", 0.0, 0.08).set_delay(PICKUP_FLY_DURATION - 0.08)
	tween.finished.connect(_on_pickup_fly_finished.bind(context))

func _on_pickup_fly_finished(context: PickupFlyContext) -> void:
	if context == null:
		return
	_pickup_fly_tweens.erase(context.tween)
	if is_instance_valid(context.fly_pickup):
		context.fly_pickup.queue_free()
	if context.pulse_callback.is_valid():
		context.pulse_callback.call()

func _build_pickup_fly_layer() -> void:
	if _pickup_fly_layer != null:
		return
	_pickup_fly_layer = Control.new()
	_pickup_fly_layer.name = "PickupFlyLayer"
	_pickup_fly_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pickup_fly_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_pickup_fly_layer)

func _world_to_screen(world_position: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * world_position

func _set_flying_pickup_center(t: float, fly_pickup: TextureRect, start_pos: Vector2, mid_pos: Vector2, end_pos: Vector2) -> void:
	if not is_instance_valid(fly_pickup):
		return
	var a := start_pos.lerp(mid_pos, t)
	var b := mid_pos.lerp(end_pos, t)
	var center := a.lerp(b, t)
	fly_pickup.position = center - fly_pickup.pivot_offset

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

func _pulse_yuanbao_icon() -> void:
	if yuanbao_icon == null:
		return
	if _yuanbao_icon_pulse_tween != null and _yuanbao_icon_pulse_tween.is_valid():
		_yuanbao_icon_pulse_tween.kill()
	yuanbao_icon.pivot_offset = yuanbao_icon.size * 0.5
	yuanbao_icon.scale = Vector2.ONE
	_yuanbao_icon_pulse_tween = create_tween()
	_yuanbao_icon_pulse_tween.tween_property(yuanbao_icon, "scale", Vector2(1.16, 1.16), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_yuanbao_icon_pulse_tween.tween_property(yuanbao_icon, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

# ===== Chapter3 胖魔王 HUD =====

func _build_fat_demon_king_hud() -> void:
	if _fdk_hud_root != null:
		return
	_fdk_hud_root = Control.new()
	_fdk_hud_root.name = "FatDemonKingHUD"
	_fdk_hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fdk_hud_root.visible = false
	add_child(_fdk_hud_root)

	_fdk_avatar_frame = TextureRect.new()
	_fdk_avatar_frame.name = "FatDemonKingFrame"
	_fdk_avatar_frame.texture = FAT_DEMON_KING_FRAME
	_fdk_avatar_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fdk_avatar_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_fdk_avatar_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fdk_hud_root.add_child(_fdk_avatar_frame)

	_fdk_bar_root = Control.new()
	_fdk_bar_root.name = "FatDemonKingHealthBar"
	_fdk_bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fdk_hud_root.add_child(_fdk_bar_root)

	var border := ColorRect.new()
	border.name = "Border"
	border.color = FDK_BAR_BORDER_COLOR
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	border.anchor_left = 0.0
	border.anchor_right = 1.0
	border.anchor_top = 0.0
	border.anchor_bottom = 1.0
	border.offset_left = -FDK_BAR_BORDER
	border.offset_right = FDK_BAR_BORDER
	border.offset_top = -FDK_BAR_BORDER
	border.offset_bottom = FDK_BAR_BORDER
	_fdk_bar_root.add_child(border)

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = FDK_BAR_BG_COLOR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.anchor_left = 0.0
	bg.anchor_right = 1.0
	bg.anchor_top = 0.0
	bg.anchor_bottom = 1.0
	_fdk_bar_root.add_child(bg)

	_fdk_bar_fill = ColorRect.new()
	_fdk_bar_fill.name = "Fill"
	_fdk_bar_fill.color = FDK_BAR_FILL_COLOR
	_fdk_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fdk_bar_fill.anchor_left = 0.0
	_fdk_bar_fill.anchor_right = 1.0
	_fdk_bar_fill.anchor_top = 0.0
	_fdk_bar_fill.anchor_bottom = 1.0
	_fdk_bar_root.add_child(_fdk_bar_fill)

	_apply_fat_demon_king_tuning()

func _apply_fat_demon_king_tuning() -> void:
	if _fdk_hud_root == null:
		return
	_fdk_hud_root.visible = _fdk_bar_active and GameState.current_stage == 3 and _fdk_bar_cur > 0
	var avatar_scale: float = max(0.01, CharTuning.fdk_avatar_frame_scale)
	if _fdk_avatar_frame != null:
		_fdk_avatar_frame.position = Vector2(CharTuning.fdk_avatar_frame_pos_x, CharTuning.fdk_avatar_frame_pos_y)
		_fdk_avatar_frame.custom_minimum_size = AVATAR_FRAME_BASE_SIZE * avatar_scale
		_fdk_avatar_frame.size = _fdk_avatar_frame.custom_minimum_size
	var bar_size := Vector2(
		max(1.0, CharTuning.fdk_health_bar_width),
		max(1.0, CharTuning.fdk_health_bar_height)
	)
	if _fdk_bar_root != null:
		_fdk_bar_root.position = Vector2(CharTuning.fdk_health_bar_pos_x, CharTuning.fdk_health_bar_pos_y)
		_fdk_bar_root.custom_minimum_size = bar_size
		_fdk_bar_root.size = bar_size
	_apply_fat_demon_king_fill()

func show_fat_demon_king_bar(max_health: int) -> void:
	if _fdk_hud_root == null:
		_build_fat_demon_king_hud()
	_fdk_bar_max = max(1, max_health)
	_fdk_bar_cur = _fdk_bar_max
	_fdk_bar_active = true
	_fdk_hud_root.modulate = Color.WHITE
	_apply_fat_demon_king_tuning()
	if _fdk_hud_root != null:
		_fdk_hud_root.visible = GameState.current_stage == 3

func update_fat_demon_king_health(current: int) -> void:
	if _fdk_hud_root == null:
		return
	_fdk_bar_cur = clamp(current, 0, _fdk_bar_max)
	_apply_fat_demon_king_tuning()
	_flash_fat_demon_king_bar()

func hide_fat_demon_king_bar() -> void:
	if _fdk_hud_root == null:
		return
	if _fdk_flash_tween != null and _fdk_flash_tween.is_valid():
		_fdk_flash_tween.kill()
	_fdk_bar_active = false
	_fdk_hud_root.visible = false
	if _fdk_bar_fill != null:
		_fdk_bar_fill.color = FDK_BAR_FILL_COLOR

func _apply_fat_demon_king_fill() -> void:
	if _fdk_bar_fill == null:
		return
	var ratio: float = float(_fdk_bar_cur) / float(_fdk_bar_max)
	_fdk_bar_fill.anchor_right = clamp(ratio, 0.0, 1.0)
	_fdk_bar_fill.offset_right = 0.0

func _flash_fat_demon_king_bar() -> void:
	if _fdk_hud_root == null or not _fdk_hud_root.visible:
		return
	if _fdk_flash_tween != null and _fdk_flash_tween.is_valid():
		_fdk_flash_tween.kill()
	if _fdk_bar_fill != null:
		_fdk_bar_fill.color = FDK_BAR_FLASH_COLOR
	_fdk_hud_root.modulate = Color(1.45, 1.45, 1.45, 1.0)
	_fdk_flash_tween = create_tween()
	_fdk_flash_tween.tween_property(_fdk_hud_root, "modulate", Color(1, 1, 1, 1), 0.18)
	if _fdk_bar_fill != null:
		_fdk_flash_tween.parallel().tween_property(_fdk_bar_fill, "color", FDK_BAR_FILL_COLOR, 0.18).set_delay(0.08)

# ===== Boss HUD 相关 =====

func _build_boss_bar() -> void:
	if _boss_bar_root != null:
		return
	_boss_bar_root = Control.new()
	_boss_bar_root.name = "BossHUD"
	_boss_bar_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar_root.visible = false
	add_child(_boss_bar_root)

	_boss_avatar_frame = TextureRect.new()
	_boss_avatar_frame.name = "BossFrame"
	_boss_avatar_frame.texture = BOSS_FRAME
	_boss_avatar_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_boss_avatar_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_boss_avatar_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar_root.add_child(_boss_avatar_frame)

	var bar_track := Control.new()
	bar_track.name = "BossHealthBar"
	bar_track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar_root.add_child(bar_track)

	var border := ColorRect.new()
	border.name = "Border"
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
	bar_track.add_child(border)

	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = BOSS_BAR_BG_COLOR
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.anchor_left = 0.0
	bg.anchor_right = 1.0
	bg.anchor_top = 0.0
	bg.anchor_bottom = 1.0
	bar_track.add_child(bg)

	_boss_bar_fill = ColorRect.new()
	_boss_bar_fill.name = "Fill"
	_boss_bar_fill.color = BOSS_BAR_FILL_COLOR
	_boss_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_boss_bar_fill.anchor_left = 0.0
	_boss_bar_fill.anchor_right = 1.0
	_boss_bar_fill.anchor_top = 0.0
	_boss_bar_fill.anchor_bottom = 1.0
	bar_track.add_child(_boss_bar_fill)

	_apply_boss_tuning()

func _apply_boss_tuning() -> void:
	if _boss_bar_root == null:
		return
	_boss_bar_root.visible = _boss_bar_active and GameState.current_stage == 4 and _boss_bar_cur > 0
	var avatar_scale: float = max(0.01, CharTuning.boss_avatar_frame_scale)
	if _boss_avatar_frame != null:
		_boss_avatar_frame.position = Vector2(CharTuning.boss_avatar_frame_pos_x, CharTuning.boss_avatar_frame_pos_y)
		_boss_avatar_frame.custom_minimum_size = BOSS_FRAME_BASE_SIZE * avatar_scale
		_boss_avatar_frame.size = _boss_avatar_frame.custom_minimum_size
	var bar_track := _boss_bar_root.get_node_or_null("BossHealthBar") as Control
	if bar_track != null:
		bar_track.position = Vector2(CharTuning.boss_health_bar_pos_x, CharTuning.boss_health_bar_pos_y)
		var bar_size := Vector2(
			max(1.0, CharTuning.boss_health_bar_width),
			max(1.0, CharTuning.boss_health_bar_height)
		)
		bar_track.custom_minimum_size = bar_size
		bar_track.size = bar_size
	_apply_boss_fill()

# Boss spawn 时调用：显示血条、设定满血。
func show_boss_bar(max_health: int) -> void:
	if _boss_bar_root == null:
		_build_boss_bar()
	_boss_bar_max = max(1, max_health)
	_boss_bar_cur = _boss_bar_max
	_boss_bar_active = true
	_boss_bar_root.modulate = Color.WHITE
	_apply_boss_tuning()
	_flash_boss_bar()

# Boss take_damage 时调用：更新当前血量，并触发一次高亮快闪。
func update_boss_health(current: int) -> void:
	if _boss_bar_root == null:
		return
	_boss_bar_cur = clamp(current, 0, _boss_bar_max)
	_apply_boss_tuning()
	_flash_boss_bar()

# Boss die 时调用：隐藏血条。
func hide_boss_bar() -> void:
	if _boss_bar_root == null:
		return
	if _boss_flash_tween != null and _boss_flash_tween.is_valid():
		_boss_flash_tween.kill()
	_boss_bar_active = false
	_boss_bar_root.visible = false
	if _boss_bar_fill != null:
		_boss_bar_fill.color = BOSS_BAR_FILL_COLOR

# 把当前血量比例反映到填充条宽度上。
func _apply_boss_fill() -> void:
	if _boss_bar_fill == null:
		return
	var ratio: float = float(_boss_bar_cur) / float(_boss_bar_max)
	_boss_bar_fill.anchor_right = clamp(ratio, 0.0, 1.0)
	_boss_bar_fill.offset_right = 0.0

# 受击高亮快闪：把整条血条 modulate 拉到亮白，再快速 tween 回正常色。
# 0.08s 拉亮 → 0.18s 回落，整体 ~0.26s，足够明显但不打断节奏。
func _flash_boss_bar() -> void:
	if _boss_bar_root == null or not _boss_bar_root.visible:
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
