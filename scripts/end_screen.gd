extends Control

@export var is_victory: bool = false

const END_EFFECT_PATH := "res://assets/audio/EndEffect.mp3"
const GAME_OVER_SFX_PATH := "res://assets/audio/GameOver.mp3"
const BRIBERY_IMAGE_PATH := "res://assets/sprites/bribery/Bribery.jpg"
const BRIBERY_TEXT_PATH := "res://assets/sprites/bribery/Bribery_Text.png"
const BRIBERY_FADE_IN_TIME := 1.0
const BRIBERY_TEXT_FADE_IN_TIME := 2.0

@onready var title_label: Label = $Center/Title
@onready var score_label: Label = $Center/Score
@onready var hint_label: Label = $Center/Hint

var _end_effect_player: AudioStreamPlayer = null
var _bribery_background: TextureRect = null
var _bribery_title_image: TextureRect = null
var _bribery_fade_overlay: ColorRect = null
var _bribery_fade_tween: Tween = null
var _bribery_title_tween: Tween = null
var _showing_bribery_offer: bool = false

func _ready() -> void:
	if not is_victory and GameState.can_revive_from_game_over():
		_showing_bribery_offer = true
		_setup_bribery_offer()
		return

	title_label.text = "STAGE CLEAR!" if is_victory else "GAME OVER"
	score_label.text = "FINAL SCORE: %06d" % GameState.score
	_update_hint_text()

	# GAME OVER 界面播放失败音效，胜利界面播放结算音乐
	if not is_victory:
		var go_stream := load(GAME_OVER_SFX_PATH) as AudioStream
		if go_stream == null:
			push_warning("GameOver.mp3 not found: %s" % GAME_OVER_SFX_PATH)
			return
		_end_effect_player = AudioStreamPlayer.new()
		_end_effect_player.name = "GameOverSFX"
		_end_effect_player.stream = go_stream
		add_child(_end_effect_player)
		_end_effect_player.play()
		return

	var stream := load(END_EFFECT_PATH) as AudioStream
	if stream == null:
		push_warning("EndEffect.mp3 not found: %s" % END_EFFECT_PATH)
		return

	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true

	_end_effect_player = AudioStreamPlayer.new()
	_end_effect_player.name = "EndEffectBGM"
	_end_effect_player.stream = stream
	add_child(_end_effect_player)
	_end_effect_player.play()

func _input(event: InputEvent) -> void:
	if _showing_bribery_offer:
		if event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
			Input.action_release("ui_accept")
			GameState.revive_from_game_over()
		elif event.is_action_pressed("ui_cancel") or _is_escape_pressed(event):
			get_viewport().set_input_as_handled()
			GameState.goto_main_menu()
		return

	if event.is_action_pressed("vacuum") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		Input.action_release("vacuum")
		Input.action_release("ui_accept")
		if not is_victory and GameState.revive_from_game_over():
			return
		GameState.goto_main_menu()

func _setup_bribery_offer() -> void:
	_bribery_background = TextureRect.new()
	_bribery_background.name = "BriberyBackground"
	_bribery_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bribery_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bribery_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bribery_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bribery_texture := load(BRIBERY_IMAGE_PATH) as Texture2D
	if bribery_texture != null:
		_bribery_background.texture = bribery_texture
	else:
		push_warning("Bribery image not found: %s" % BRIBERY_IMAGE_PATH)
	add_child(_bribery_background)
	move_child(_bribery_background, 0)

	_bribery_title_image = TextureRect.new()
	_bribery_title_image.name = "BriberyTitleImage"
	_bribery_title_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bribery_title_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_bribery_title_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bribery_title_image.modulate.a = 0.0
	var title_texture := load(BRIBERY_TEXT_PATH) as Texture2D
	if title_texture != null:
		_bribery_title_image.texture = title_texture
	else:
		push_warning("Bribery title image not found: %s" % BRIBERY_TEXT_PATH)
	add_child(_bribery_title_image)
	move_child(_bribery_title_image, 1)
	_apply_bribery_title_tuning()
	if not CharTuning.tuning_changed.is_connected(_apply_bribery_title_tuning):
		CharTuning.tuning_changed.connect(_apply_bribery_title_tuning)
	if not CharTuning.tuning_changed.is_connected(_apply_bribery_prompt_tuning):
		CharTuning.tuning_changed.connect(_apply_bribery_prompt_tuning)

	var center := $Center as VBoxContainer
	center.add_theme_constant_override("separation", 28)

	title_label.visible = false

	var payment := GameState.get_coin_value_payment(GameState.REVIVE_COST_COIN_VALUE)
	score_label.text = "是否愿意支付%d枚铜钱+%d个元宝，买通门卫，放你从当前关卡重新开始？" % [payment["coins"], payment["yuanbao"]]
	score_label.visible = false
	_style_bribery_label(score_label, Color(1.0, 0.96, 0.78, 1.0), 4)

	hint_label.text = "是：按 ENTER    否：按 ESC"
	hint_label.visible = false
	hint_label.add_theme_font_size_override("font_size", 38)
	_style_bribery_label(hint_label, Color(0.96, 0.92, 0.82, 1.0), 3)
	_apply_bribery_prompt_tuning()
	_start_bribery_fade_in()

func _start_bribery_fade_in() -> void:
	_bribery_fade_overlay = ColorRect.new()
	_bribery_fade_overlay.name = "BriberyFadeOverlay"
	_bribery_fade_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bribery_fade_overlay.color = Color.BLACK
	_bribery_fade_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bribery_fade_overlay)
	_bribery_fade_tween = create_tween()
	_bribery_fade_tween.tween_property(_bribery_fade_overlay, "modulate:a", 0.0, BRIBERY_FADE_IN_TIME)
	_bribery_fade_tween.tween_callback(_finish_bribery_fade_in)

func _finish_bribery_fade_in() -> void:
	if is_instance_valid(_bribery_fade_overlay):
		_bribery_fade_overlay.queue_free()
	_bribery_fade_overlay = null
	_bribery_fade_tween = null
	_start_bribery_title_fade_in()

func _start_bribery_title_fade_in() -> void:
	if not is_instance_valid(_bribery_title_image):
		return
	if _bribery_title_tween != null and _bribery_title_tween.is_valid():
		_bribery_title_tween.kill()
	_bribery_title_image.modulate.a = 0.0
	_bribery_title_tween = create_tween()
	_bribery_title_tween.tween_property(_bribery_title_image, "modulate:a", 1.0, BRIBERY_TEXT_FADE_IN_TIME)
	_bribery_title_tween.tween_callback(_show_bribery_prompt)

func _show_bribery_prompt() -> void:
	if is_instance_valid(score_label):
		score_label.visible = true
	if is_instance_valid(hint_label):
		hint_label.visible = true
	_bribery_title_tween = null

func _apply_bribery_title_tuning() -> void:
	if not is_instance_valid(_bribery_title_image):
		return
	var title_texture := _bribery_title_image.texture
	var base_size := Vector2(447.0, 800.0)
	if title_texture != null:
		base_size = title_texture.get_size()
	var title_scale: float = max(0.01, CharTuning.bribery_title_scale)
	_bribery_title_image.position = Vector2(
		CharTuning.bribery_title_pos_x,
		CharTuning.bribery_title_pos_y
	)
	_bribery_title_image.custom_minimum_size = base_size * title_scale
	_bribery_title_image.size = _bribery_title_image.custom_minimum_size

func _apply_bribery_prompt_tuning() -> void:
	if not is_instance_valid(score_label):
		return
	var center := $Center as VBoxContainer
	center.anchor_left = 0.0
	center.anchor_top = 0.0
	center.anchor_right = 0.0
	center.anchor_bottom = 0.0
	center.offset_left = CharTuning.bribery_prompt_pos_x
	center.offset_top = CharTuning.bribery_prompt_pos_y
	center.offset_right = CharTuning.bribery_prompt_pos_x + 760.0
	center.offset_bottom = CharTuning.bribery_prompt_pos_y + 260.0
	score_label.add_theme_font_size_override(
		"font_size",
		int(round(max(1.0, CharTuning.bribery_prompt_font_size)))
	)

func _style_bribery_label(label: Label, color: Color, shadow_size: int) -> void:
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.86))
	label.add_theme_constant_override("shadow_offset_x", shadow_size)
	label.add_theme_constant_override("shadow_offset_y", shadow_size)

func _is_escape_pressed(event: InputEvent) -> bool:
	return event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE

func _update_hint_text() -> void:
	if is_victory:
		hint_label.text = "Press ENTER to return to menu"
		return
	var cost := GameState.REVIVE_COST_COIN_VALUE
	var value := GameState.currency_to_coin_value()
	if GameState.can_revive_from_game_over():
		hint_label.text = "Press ENTER to spend %d coins and retry Chapter%d" % [cost, GameState.current_stage]
	else:
		hint_label.text = "Need %d coins to retry (you have %d). Press ENTER to return" % [cost, value]

func _exit_tree() -> void:
	# 退出（含进程关闭）时若播放器仍在播放，其 AudioStreamPlaybackMP3 会在 AudioServer
	# 关闭前继续引用 GameOver.mp3 / EndEffect.mp3，触发
	# "ObjectDB instances leaked at exit" / "resources still in use at exit"。
	# 退出路径下 SceneTree 已不再 tick，queue_free 的延迟队列不会被 flush，因此用
	# free() 立即释放，并先解除 stream 引用让资源引用计数归零。退出竞争由 GameState
	# 统一的关窗清理（_handle_close_request 的逐帧 await）兜底刷新音频线程。
	if is_instance_valid(_end_effect_player):
		_end_effect_player.stop()
		_end_effect_player.stream = null
		_end_effect_player.free()
	_end_effect_player = null
	if is_instance_valid(_bribery_background):
		_bribery_background.texture = null
	_bribery_background = null
	if CharTuning.tuning_changed.is_connected(_apply_bribery_title_tuning):
		CharTuning.tuning_changed.disconnect(_apply_bribery_title_tuning)
	if CharTuning.tuning_changed.is_connected(_apply_bribery_prompt_tuning):
		CharTuning.tuning_changed.disconnect(_apply_bribery_prompt_tuning)
	if _bribery_title_tween != null and _bribery_title_tween.is_valid():
		_bribery_title_tween.kill()
	_bribery_title_tween = null
	if is_instance_valid(_bribery_title_image):
		_bribery_title_image.texture = null
		_bribery_title_image.queue_free()
	_bribery_title_image = null
	if _bribery_fade_tween != null and _bribery_fade_tween.is_valid():
		_bribery_fade_tween.kill()
	_bribery_fade_tween = null
	if is_instance_valid(_bribery_fade_overlay):
		_bribery_fade_overlay.queue_free()
	_bribery_fade_overlay = null
