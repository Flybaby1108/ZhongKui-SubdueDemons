extends Control

const STAGE_1_PATH := "res://scenes/level_1.tscn"
const GUIDE_KEY := KEY_G
const BLINK_PERIOD := 0.9  # 闪烁周期（秒）
const STAGE_PRELOAD_DELAY := 0.8  # 让菜单先稳定显示几帧，再开始预载第一关

# 背景循环播放（从 mp4 抽帧得到的 46 张 1920×1080 JPG）
# BG_FRAME_INTERVAL = 1/fps；46 帧 × 0.05 = 2.3s 一轮 (20fps)。如需改速度调此值。
const BG_FRAME_COUNT := 46
const BG_FRAME_INTERVAL := 0.05  # 20fps

# 标题：先等 TITLE_FADE_IN_DELAY 秒（背景视频先播一会），再用 TITLE_FADE_IN_DURATION 秒渐显
const TITLE_FADE_IN_DELAY := 0.5
const TITLE_FADE_IN_DURATION := 1.5

@onready var loading_bar: ProgressBar = $LoadingBar
@onready var loading_label: Label = $LoadingLabel
@onready var background: TextureRect = $Background
@onready var title: Sprite2D = $Title
@onready var guide_page: Control = $GuidePage

var _loading_done: bool = false
var _blink_t: float = 0.0
var _stage_load_requested: bool = false
var _stage_preload_t: float = 0.0
var _start_requested: bool = false

var _bg_frames: Array = []
var _bg_frame_idx: int = 0
var _bg_anim_t: float = 0.0

# 标题计时：从 0 累加；前 TITLE_FADE_IN_DELAY 秒保持透明，之后用 TITLE_FADE_IN_DURATION 秒渐显到不透明
var _title_fade_t: float = 0.0

func _ready() -> void:
	GameState.reset_game()
	GameState.enable_start_sequence_music()
	GameState.play_start_music_if_ready()
	# 优先复用 cg_intro 阶段已加载并 GPU 预热好的 BG 帧（autoload 共享缓存），
	# 避免切场景瞬间再次同步 load 46 张 1920×1080 JPG 导致的 ~1 秒卡顿。
	if not GameState.shared_start_bg_frames.is_empty():
		_bg_frames = GameState.shared_start_bg_frames
	else:
		# Fallback：直接进入主菜单（开发期跳过 CG）时仍需自己加载
		_bg_frames = []
		for i in range(1, BG_FRAME_COUNT + 1):
			var path: String = "res://assets/sprites/Start/StartBackground/StartBackground_%02d.jpg" % i
			_bg_frames.append(load(path))
	if not _bg_frames.is_empty():
		background.texture = _bg_frames[0]
	# 标题位置/大小跟随 CharTuning（F1 调参面板可实时调节）
	CharTuning.tuning_changed.connect(_apply_title_tuning)
	_apply_title_tuning()

func _exit_tree() -> void:
	release_cached_resources_for_quit()

func release_cached_resources_for_quit() -> void:
	# 进程退出时，$Background（TextureRect）的 .texture 仍指向当前显示的
	# StartBackground 帧（1920×1080，≈8MB）。若不主动解除，该 Texture2D 会在
	# RenderingServer 关闭后仍被节点引用，触发 "Texture ... leaked N bytes" /
	# "resources still in use at exit"。这里解除引用并清空本地帧数组。
	# 注意：_bg_frames 可能与 GameState.shared_start_bg_frames 是同一数组引用，
	# clear() 只解除本地变量持有；autoload 缓存由 GameState 退出流程统一清空。
	if is_instance_valid(background):
		background.texture = null
	_bg_frames = []

func _apply_title_tuning() -> void:
	if title == null:
		return
	title.position = Vector2(CharTuning.title_pos_x, CharTuning.title_pos_y)
	title.scale = Vector2(CharTuning.title_scale, CharTuning.title_scale)

func _process(delta: float) -> void:
	# 背景循环播放：按帧率推进 sprite frame，直到场景切换销毁
	if not _bg_frames.is_empty():
		_bg_anim_t += delta
		while _bg_anim_t >= BG_FRAME_INTERVAL:
			_bg_anim_t -= BG_FRAME_INTERVAL
			_bg_frame_idx = (_bg_frame_idx + 1) % _bg_frames.size()
			background.texture = _bg_frames[_bg_frame_idx]
	# 标题：前 TITLE_FADE_IN_DELAY 秒完全透明（背景视频先单独出场），
	# 之后用 TITLE_FADE_IN_DURATION 秒线性渐显到不透明
	var total: float = TITLE_FADE_IN_DELAY + TITLE_FADE_IN_DURATION
	if _title_fade_t < total:
		_title_fade_t = min(total, _title_fade_t + delta)
		var fade_progress: float = clamp((_title_fade_t - TITLE_FADE_IN_DELAY) / TITLE_FADE_IN_DURATION, 0.0, 1.0)
		title.modulate.a = fade_progress
	if not _loading_done:
		if not _stage_load_requested:
			_stage_preload_t += delta
			if _stage_preload_t < STAGE_PRELOAD_DELAY:
				return
			_request_stage_load()
		if GameState.uses_incremental_resource_loading():
			if GameState.is_threaded_load_done(STAGE_1_PATH):
				loading_bar.value = 100.0
				loading_label.text = "按回车键开始游戏 | 按G键查看新手导读"
				_loading_done = true
				if _start_requested:
					_enter_stage_one()
			else:
				loading_bar.value = 0.0
				loading_label.text = "加载中…"
			return
		var progress_arr: Array = []
		var status := ResourceLoader.load_threaded_get_status(STAGE_1_PATH, progress_arr)
		var percent: float = 0.0
		if progress_arr.size() > 0:
			percent = progress_arr[0] * 100.0
		match status:
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				loading_bar.value = percent
				loading_label.text = "加载中… %d%%" % int(percent)
			ResourceLoader.THREAD_LOAD_LOADED:
				loading_bar.value = 100.0
				loading_label.text = "按回车键开始游戏 | 按G键查看新手导读"
				_loading_done = true
				if _start_requested:
					_enter_stage_one()
			ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				loading_label.text = "加载失败"
				_loading_done = true
		return
	# 加载完成后：文字常驻 + 透明度正弦闪烁
	_blink_t += delta
	var phase: float = fmod(_blink_t, BLINK_PERIOD) / BLINK_PERIOD
	# 0..1 sin 平滑闪烁，最暗 0.3，最亮 1.0
	var alpha: float = 0.65 + 0.35 * sin(phase * TAU)
	loading_label.modulate.a = alpha

func _input(event: InputEvent) -> void:
	if guide_page.visible:
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			guide_page.visible = false
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == GUIDE_KEY:
		guide_page.visible = true
		get_viewport().set_input_as_handled()
		return
	# 回车键开始游戏（ui_accept 默认含回车）
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if not _loading_done:
			_start_requested = true
			if not _stage_load_requested:
				_request_stage_load()
			return
		_enter_stage_one()

func _request_stage_load() -> void:
	if _stage_load_requested:
		return
	_stage_load_requested = true
	loading_bar.visible = true
	loading_bar.value = 0.0
	loading_label.modulate.a = 1.0
	loading_label.text = "加载中… 0%"
	# 启动后台线程加载第一关（经 GameState 登记，退出时统一取回，避免泄漏）
	GameState.request_threaded_load(STAGE_1_PATH)

func _enter_stage_one() -> void:
	GameState.stop_start_sequence_music()
	# 优先用已预加载的 PackedScene 切换，避免再次读盘
	var packed: PackedScene = GameState.take_threaded_load(STAGE_1_PATH) as PackedScene
	if packed != null:
		GameState.current_stage = 1
		GameState.score = 0
		GameState.coins = 0
		GameState.yuanbao = 0
		GameState.lives = GameState.MAX_LIVES
		GameState.score_changed.emit(GameState.score)
		GameState.coins_changed.emit(GameState.coins)
		GameState.yuanbao_changed.emit(GameState.yuanbao)
		GameState.lives_changed.emit(GameState.lives)
		get_tree().change_scene_to_packed(packed)
	else:
		# 预加载结果丢失则回退到普通切换
		GameState.goto_stage(1)
