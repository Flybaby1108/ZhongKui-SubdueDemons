extends Control

@export var is_victory: bool = false

const END_EFFECT_PATH := "res://assets/audio/EndEffect.mp3"
const FAIL_SFX_PATH := "res://assets/audio/Fail.mp3"
const FAIL_BACKGROUND_PATH := "res://assets/sprites/Fail/Fail_Background.jpg"
const FAIL_WORD_PATH := "res://assets/sprites/Fail/Fail_Word.png"
const FAIL_WORD_DELAY_TIME := 1.0
const FAIL_WORD_FADE_IN_TIME := 2.0
const FAIL_AUTO_BLACK_TIME := 4.0
const FAIL_BLACK_FADE_OUT_TIME := 1.0
const BRIBERY_IMAGE_PATH := "res://assets/sprites/bribery/Bribery.jpg"
const BRIBERY_TEXT_PATH := "res://assets/sprites/bribery/Bribery_Text.png"
const BRIBERY_LAUGHTER_SFX_PATH := "res://assets/audio/Bribery_Laughter.mp3"
const BRIBERY_COIN_SFX_PATH := "res://assets/audio/Bribery_Coin.mp3"
const BRIBERY_FADE_IN_TIME := 1.0
const BRIBERY_TEXT_FADE_IN_TIME := 2.0

@onready var title_label: Label = $Center/Title
@onready var score_label: Label = $Center/Score
@onready var hint_label: Label = $Center/Hint

var _end_effect_player: AudioStreamPlayer = null
var _fail_background: TextureRect = null
var _fail_word_image: TextureRect = null
var _fail_black_overlay: ColorRect = null
var _fail_sequence_tween: Tween = null
var _fail_word_tween: Tween = null
var _fail_black_tween: Tween = null
var _bribery_background: TextureRect = null
var _bribery_title_image: TextureRect = null
var _bribery_fade_overlay: ColorRect = null
var _bribery_fade_tween: Tween = null
var _bribery_title_tween: Tween = null
var _bribery_laughter_player: AudioStreamPlayer = null
var _bribery_coin_player: AudioStreamPlayer = null
var _showing_fail_screen: bool = false
var _showing_bribery_offer: bool = false
var _bribery_accepting: bool = false
var _returning_to_menu: bool = false
# 复活中：已扣费并发起线程加载关卡场景，正在 _process 里轮询加载完成后再切场景。
# Web 单线程下若同步 change_scene_to_file 会阻塞主线程导致页面卡死，故改为异步。
var _reviving: bool = false
# 复活等待的累计时长（秒）：达到上限即使音效/加载未完成也强制切场景，防止卡在复活界面。
var _revive_wait_t: float = 0.0
const REVIVE_MAX_WAIT_TIME := 6.0

func _ready() -> void:
	# 默认关闭 _process，仅在发起异步复活后开启轮询，避免无谓的每帧调用。
	set_process(false)
	if not is_victory and GameState.can_revive_from_game_over():
		_showing_bribery_offer = true
		_setup_bribery_offer()
		return

	title_label.text = "STAGE CLEAR!" if is_victory else "GAME OVER"
	score_label.text = "FINAL SCORE: %06d" % GameState.score
	_update_hint_text()

	# Fail_Background 界面播放失败音效，胜利界面播放结算音乐
	if not is_victory:
		_setup_fail_screen()
		var fail_stream := load(FAIL_SFX_PATH) as AudioStream
		if fail_stream == null:
			push_warning("Fail.mp3 not found: %s" % FAIL_SFX_PATH)
			return
		_end_effect_player = AudioStreamPlayer.new()
		_end_effect_player.name = "FailSFX"
		_end_effect_player.stream = fail_stream
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
		if _bribery_accepting:
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_accept"):
			get_viewport().set_input_as_handled()
			Input.action_release("ui_accept")
			_accept_bribery_offer()
		elif event.is_action_pressed("ui_cancel") or _is_escape_pressed(event):
			get_viewport().set_input_as_handled()
			GameState.goto_main_menu()
		return

	if _showing_fail_screen:
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") or _is_escape_pressed(event):
			get_viewport().set_input_as_handled()
			Input.action_release("ui_accept")
			Input.action_release("ui_cancel")
			_return_to_main_menu_from_fail()
		return

	if _reviving:
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("vacuum") or event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		Input.action_release("vacuum")
		Input.action_release("ui_accept")
		if not is_victory and _begin_revive():
			return
		GameState.goto_main_menu()

func _setup_fail_screen() -> void:
	_showing_fail_screen = true
	var center := $Center as VBoxContainer
	center.visible = false

	_fail_background = TextureRect.new()
	_fail_background.name = "FailBackground"
	_fail_background.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fail_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fail_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_fail_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var background_texture := load(FAIL_BACKGROUND_PATH) as Texture2D
	if background_texture != null:
		_fail_background.texture = background_texture
	else:
		push_warning("Fail background not found: %s" % FAIL_BACKGROUND_PATH)
	add_child(_fail_background)
	move_child(_fail_background, 0)

	_fail_word_image = TextureRect.new()
	_fail_word_image.name = "FailWord"
	_fail_word_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fail_word_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_fail_word_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fail_word_image.modulate.a = 0.0
	var word_texture := load(FAIL_WORD_PATH) as Texture2D
	if word_texture != null:
		_fail_word_image.texture = word_texture
	else:
		push_warning("Fail word image not found: %s" % FAIL_WORD_PATH)
	add_child(_fail_word_image)
	move_child(_fail_word_image, 1)
	_apply_fail_word_tuning()
	if not CharTuning.tuning_changed.is_connected(_apply_fail_word_tuning):
		CharTuning.tuning_changed.connect(_apply_fail_word_tuning)

	_start_fail_sequence()

func _start_fail_sequence() -> void:
	if _fail_sequence_tween != null and _fail_sequence_tween.is_valid():
		_fail_sequence_tween.kill()
	_fail_sequence_tween = create_tween()
	_fail_sequence_tween.tween_interval(FAIL_WORD_DELAY_TIME)
	_fail_sequence_tween.tween_callback(_start_fail_word_fade_in)
	_fail_sequence_tween.tween_interval(max(0.0, FAIL_AUTO_BLACK_TIME - FAIL_WORD_DELAY_TIME))
	_fail_sequence_tween.tween_callback(_start_fail_black_fade_out)

func _start_fail_word_fade_in() -> void:
	if _returning_to_menu or not is_instance_valid(_fail_word_image):
		return
	if _fail_word_tween != null and _fail_word_tween.is_valid():
		_fail_word_tween.kill()
	_fail_word_image.modulate.a = 0.0
	_fail_word_tween = create_tween()
	_fail_word_tween.set_trans(Tween.TRANS_SINE)
	_fail_word_tween.set_ease(Tween.EASE_OUT)
	_fail_word_tween.tween_property(_fail_word_image, "modulate:a", 1.0, FAIL_WORD_FADE_IN_TIME)

func _start_fail_black_fade_out() -> void:
	if _returning_to_menu:
		return
	_fail_black_overlay = ColorRect.new()
	_fail_black_overlay.name = "FailBlackOverlay"
	_fail_black_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fail_black_overlay.color = Color.BLACK
	_fail_black_overlay.modulate.a = 0.0
	_fail_black_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fail_black_overlay)
	move_child(_fail_black_overlay, get_child_count() - 1)

	_fail_black_tween = create_tween()
	_fail_black_tween.set_trans(Tween.TRANS_SINE)
	_fail_black_tween.set_ease(Tween.EASE_IN_OUT)
	_fail_black_tween.tween_property(_fail_black_overlay, "modulate:a", 1.0, FAIL_BLACK_FADE_OUT_TIME)
	_fail_black_tween.tween_callback(_return_to_main_menu_from_fail)

func _return_to_main_menu_from_fail() -> void:
	if _returning_to_menu:
		return
	_returning_to_menu = true
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
	_setup_bribery_sfx()
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
	_play_bribery_laughter_sfx()
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

func _setup_bribery_sfx() -> void:
	_bribery_laughter_player = _create_bribery_sfx_player(BRIBERY_LAUGHTER_SFX_PATH, "BriberyLaughterSfx")
	_bribery_coin_player = _create_bribery_sfx_player(BRIBERY_COIN_SFX_PATH, "BriberyCoinSfx")

func _create_bribery_sfx_player(path: String, player_name: String) -> AudioStreamPlayer:
	var loaded_stream := load(path) as AudioStream
	if loaded_stream == null:
		push_warning("%s not found: %s" % [player_name, path])
		return null
	var stream := loaded_stream.duplicate() as AudioStream
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = false
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	add_child(player)
	return player

func _play_bribery_laughter_sfx() -> void:
	if _bribery_laughter_player == null or _bribery_laughter_player.stream == null:
		return
	_bribery_laughter_player.play()

func _accept_bribery_offer() -> void:
	if _bribery_accepting:
		return
	_bribery_accepting = true
	if _bribery_coin_player != null and _bribery_coin_player.stream != null:
		_bribery_coin_player.play()
	call_deferred("_finish_bribery_acceptance")

func _finish_bribery_acceptance() -> void:
	if not is_inside_tree():
		return
	if _begin_revive():
		return
	_bribery_accepting = false
	_update_hint_text()

# 发起异步复活：扣费 + 线程加载关卡场景。成功后进入 _reviving 轮询态，
# 由 _process 在加载完成时用 change_scene_to_packed 切场景。避免 Web 单线程卡死。
func _begin_revive() -> bool:
	if _reviving:
		return true
	if not GameState.begin_revive_from_game_over():
		return false
	_reviving = true
	_revive_wait_t = 0.0
	set_process(true)
	return true

func _process(delta: float) -> void:
	if not _reviving:
		return
	_revive_wait_t += delta
	# 关卡后台加载完成后，还需等 Bribery_Coin.mp3 播完再切场景，否则 end_screen 被
	# 销毁会打断音效（异步加载太快导致音效几乎没出声）。到达等待上限则强制切场景兜底。
	if _revive_wait_t < REVIVE_MAX_WAIT_TIME:
		if not GameState.revive_load_done():
			return
		if not _bribery_coin_sfx_done():
			return
	_reviving = false
	set_process(false)
	var packed := GameState.take_revive_packed_scene()
	if packed != null:
		get_tree().change_scene_to_packed(packed)
	else:
		# 线程加载结果异常丢失：兜底同步切场景（极少发生）。
		get_tree().change_scene_to_file(GameState.get_stage_scene_path(GameState.current_stage))

# Bribery_Coin.mp3 是否已播放结束（或本就没有播放器 / 没在播放）。
func _bribery_coin_sfx_done() -> bool:
	if _bribery_coin_player == null or not is_instance_valid(_bribery_coin_player):
		return true
	return not _bribery_coin_player.playing

func _apply_fail_word_tuning() -> void:
	if not is_instance_valid(_fail_word_image):
		return
	var word_texture := _fail_word_image.texture
	var base_size := Vector2(875.0, 699.0)
	if word_texture != null:
		base_size = word_texture.get_size()
	var word_scale: float = max(0.01, CharTuning.fail_word_scale)
	_fail_word_image.position = Vector2(
		CharTuning.fail_word_pos_x,
		CharTuning.fail_word_pos_y
	)
	_fail_word_image.custom_minimum_size = base_size * word_scale
	_fail_word_image.size = _fail_word_image.custom_minimum_size

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
	# 关闭前继续引用 Fail.mp3 / EndEffect.mp3，触发
	# "ObjectDB instances leaked at exit" / "resources still in use at exit"。
	# 退出路径下 SceneTree 已不再 tick，queue_free 的延迟队列不会被 flush，因此用
	# free() 立即释放，并先解除 stream 引用让资源引用计数归零。退出竞争由 GameState
	# 统一的关窗清理（_handle_close_request 的逐帧 await）兜底刷新音频线程。
	if is_instance_valid(_end_effect_player):
		_end_effect_player.stop()
		_end_effect_player.stream = null
		_end_effect_player.free()
	_end_effect_player = null
	if is_instance_valid(_fail_background):
		_fail_background.texture = null
	_fail_background = null
	if is_instance_valid(_fail_word_image):
		_fail_word_image.texture = null
	_fail_word_image = null
	if is_instance_valid(_fail_black_overlay):
		_fail_black_overlay.queue_free()
	_fail_black_overlay = null
	if _fail_sequence_tween != null and _fail_sequence_tween.is_valid():
		_fail_sequence_tween.kill()
	_fail_sequence_tween = null
	if _fail_word_tween != null and _fail_word_tween.is_valid():
		_fail_word_tween.kill()
	_fail_word_tween = null
	if _fail_black_tween != null and _fail_black_tween.is_valid():
		_fail_black_tween.kill()
	_fail_black_tween = null
	if CharTuning.tuning_changed.is_connected(_apply_fail_word_tuning):
		CharTuning.tuning_changed.disconnect(_apply_fail_word_tuning)
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
	if is_instance_valid(_bribery_laughter_player):
		_bribery_laughter_player.stop()
		_bribery_laughter_player.stream = null
		_bribery_laughter_player.free()
	_bribery_laughter_player = null
	if is_instance_valid(_bribery_coin_player):
		_bribery_coin_player.stop()
		_bribery_coin_player.stream = null
		_bribery_coin_player.free()
	_bribery_coin_player = null
