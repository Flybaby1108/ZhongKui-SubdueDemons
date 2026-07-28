extends Control

# ═══════════════════════════════════════════════════════════════════════════
# CG 开场场景控制器
#
# 播放时序：
#   [帧 1 ~ 272]  CgLayer alpha = 1.0，BgLayer 同步开始循环 StartBackground
#   [帧 273 ~ 278] CgLayer alpha 线性从 1.0 → 0.0（6 帧衰减）
#   [帧 278 播完]  alpha = 0.0，BgLayer 已完整露出，自动切换 main.tscn
#
# 音频：CGv1.mp3 播完后接 StartMusic.mp3，直到玩家按回车进入游戏时停止。
# 跳过：任意时刻按 ui_accept（回车/空格）立即停止 CGv1.mp3 并切换 main.tscn
# ═══════════════════════════════════════════════════════════════════════════

const MAIN_MENU_PATH := "res://scenes/main.tscn"

# CG 序列帧参数
const CG_FRAME_COUNT    := 279     # CGv1_001 ~ CGv1_279
const CG_FRAME_INTERVAL := 1.0 / 24.0  # 24fps，≈0.0417s/帧，总时长 ≈11.6s

# 淡出控制：从第 FADE_START_FRAME 帧开始到第 FADE_END_FRAME 帧结束，线性 alpha 1→0
const FADE_START_FRAME := 273   # 此帧及之后开始衰减（1-indexed）
const FADE_END_FRAME   := 278   # 此帧结束时 alpha = 0（1-indexed）

# StartBackground 循环参数（与 main_menu.gd 保持一致）
const BG_FRAME_COUNT    := 46
const BG_FRAME_INTERVAL := 0.05   # 20fps

@onready var bg_layer:      TextureRect       = $BgLayer
@onready var cg_layer:      TextureRect       = $CgLayer
@onready var music:         AudioStreamPlayer = $Music
@onready var skip_label:    Label             = $SkipLabel
@onready var black_overlay: ColorRect         = $BlackOverlay
@onready var start_frame:   PanelContainer    = $StartFrame
@onready var start_label:   Label             = $StartFrame/Margin/StartLabel
@onready var controls_label: Label            = $ControlsLabel

# 帧数组（同步异步加载均可；这里用同步 load，CG 279 帧 × ~200KB JPEG ≈ 50MB，
# 在 _ready 里统一加载让帧率最稳定）
var _cg_frames: Array  = []
var _bg_frames: Array  = []

var _cg_frame_idx: int   = 0     # 当前 CG 帧（0-indexed，对应 CGv1_001）
var _cg_anim_t:   float  = 0.0   # CG 帧计时累加器
var _cg_visual_done: bool = false # 所有 CG 帧播完且淡出完成标志
var _intro_audio_done: bool = false # CGv1.mp3 是否已经播完
var _cg_done:     bool   = false # 开场整体结束并开始切场景

var _bg_frame_idx: int   = 0
var _bg_anim_t:    float = 0.0

# GPU 纹理预热：用一个 1×1 离屏 TextureRect 逐帧贴上每张 BG，强制 GPU 上传。
var _warm_rect:      TextureRect = null
var _warm_idx:       int  = 0     # 下一张待预热的 BG 帧索引
var _warm_done:      bool = false # 全部 46 帧是否已预热完成
# 每个渲染帧只能可靠预热 1 张：同一帧多次给 .texture 赋值，只有最后一次会被真实
# 渲染上传。46 张在开场等待 + CG 播放（远超 46 个渲染帧）期间足以全部预热完成。

# 跳过动画（标签闪烁）
var _skip_blink_t: float = 0.0

# 开场等待：CG 播放前先显示「点击回车键进入游戏」并有节奏地闪烁，按回车后才开始播放
var _started:        bool  = false   # 是否已开始播放 CG
var _start_blink_t:  float = 0.0     # 开场提示语闪烁计时器
const START_BLINK_PERIOD := 1.0      # 闪烁周期（秒），节奏明快
const START_BLINK_MIN_ALPHA := 0.15  # 最暗
const START_BLINK_MAX_ALPHA := 1.0   # 最亮

func _ready() -> void:
	GameState.prepare_start_sequence_music()

	# 立即开始后台预加载 main.tscn（CG 播放 ~11s 内足以加载完毕）
	# 经 GameState 登记，退出时统一取回，避免未取走请求泄漏。
	GameState.request_threaded_load(MAIN_MENU_PATH)

	# 加载 StartBackground 帧（46 帧，全部已 import，瞬间完成）
	# 这些 Texture2D 资源会被 ResourceLoader 缓存（弱引用），后续 main_menu 再
	# load() 时直接命中缓存，避免切场景瞬间重复解码导致的卡顿。
	_bg_frames = []
	for i in range(1, BG_FRAME_COUNT + 1):
		var path := "res://assets/sprites/Start/StartBackground/StartBackground_%02d.jpg" % i
		_bg_frames.append(load(path))
	if not _bg_frames.is_empty():
		bg_layer.texture = _bg_frames[0]

	# 存入 autoload 共享缓存，main_menu 切场景后直接复用，零 IO 零卡顿
	GameState.shared_start_bg_frames = _bg_frames

	# GPU 纹理预热：把每张 BG 帧贴到一个 1×1 的离屏 TextureRect 上并真实渲染，
	# 强制 RenderingServer 在 CG 播放期间完成 46 张 1920×1080 纹理的 GPU 上传。
	#
	# 为什么不能用 Texture2D.get_rid() 预热：get_rid() 只创建/返回资源 RID，纹理
	# 数据的实际 GPU 上传发生在该纹理「第一次被真正渲染」时。CG 期间 BgLayer 被
	# CgLayer（alpha=1.0）完全遮挡，渲染器会裁掉被完全遮挡的绘制，BG 帧从未真正
	# 上传。结果切到 main_menu 第一轮轮播时，46 张帧才陆续首次上传 GPU，与场景
	# 初始化叠在切换瞬间，造成肉眼可见卡顿。
	#
	# 这里用一个最小尺寸、几乎不可见的 _warm_rect 在 CG 播放过程中每帧轮换贴图，
	# 让每张 BG 都被真实绘制一次，从而提前完成 GPU 上传。
	_setup_texture_warmup()

	# 加载 CG 帧（279 帧，~50MB JPEG，同步 load）
	_cg_frames = []
	for i in range(1, CG_FRAME_COUNT + 1):
		var path := "res://assets/sprites/Start/CGv1/CGv1_%03d.jpg" % i
		_cg_frames.append(load(path))
	if not _cg_frames.is_empty():
		cg_layer.texture = _cg_frames[0]

	# CgLayer 初始完全不透明（从第 1 帧开始全覆盖 BgLayer）
	cg_layer.modulate.a = 1.0

	# 开场等待：先用黑色背景遮住 CG，显示带边框的「点击回车键进入游戏」并闪烁，
	# 待玩家按回车（ui_accept）后再调用 _begin_play() 开始播放 CG 与配乐。
	black_overlay.visible = true
	start_frame.visible   = true
	start_label.visible   = true
	controls_label.visible = true
	skip_label.visible    = false

func _setup_texture_warmup() -> void:
	if _bg_frames.is_empty():
		_warm_done = true
		return
	# 1×1 像素、放在屏幕角落、几乎透明的 TextureRect。它会被真实渲染（不会被
	# 任何东西完全遮挡），因此贴上去的纹理会被 RenderingServer 真正上传到 GPU。
	_warm_rect = TextureRect.new()
	_warm_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_warm_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_warm_rect.custom_minimum_size = Vector2(1, 1)
	_warm_rect.size = Vector2(1, 1)
	_warm_rect.position = Vector2.ZERO
	# modulate.a 极低但非 0：alpha=0 时渲染器可能跳过绘制，无法触发上传。
	_warm_rect.modulate.a = 0.01
	_warm_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 置于最上层，确保不被 CgLayer / BlackOverlay 遮挡而被裁剪。
	add_child(_warm_rect)
	_warm_rect.z_index = 100
	_warm_rect.texture = _bg_frames[0]

func _process_texture_warmup() -> void:
	# 每个渲染帧把若干张 BG 帧贴到离屏 _warm_rect 上。被贴上的纹理会在本帧真实
	# 渲染中完成 GPU 上传。全部上传完毕后移除预热节点。
	if _warm_done or _warm_rect == null:
		return
	if _warm_idx >= _bg_frames.size():
		_warm_done = true
		_warm_rect.queue_free()
		_warm_rect = null
		return
	var tex = _bg_frames[_warm_idx]
	if tex != null:
		_warm_rect.texture = tex
	_warm_idx += 1

func _begin_play() -> void:
	if _started:
		return
	_started = true
	black_overlay.visible = false
	start_frame.visible   = false
	start_label.visible   = false
	controls_label.visible = false
	skip_label.visible    = true

	# 播放配乐
	if music.stream != null:
		GameState.register_intro_music_player(music)
		if not music.finished.is_connected(_on_intro_audio_finished):
			music.finished.connect(_on_intro_audio_finished)
		music.play()

func _exit_tree() -> void:
	release_cached_resources_for_quit()

func release_cached_resources_for_quit() -> void:
	# 场景销毁（含进程退出）时，若 Music 节点仍归本场景持有且正在播放，其
	# AudioStreamPlaybackMP3 会在 AudioServer 关闭前继续引用 CGv1.mp3，导致退出时
	# 报 "1 resources still in use at exit"。这里主动停止播放并解除 stream 引用，
	# 让资源引用计数及时归零。已 reparent 到 root 的情况由 GameState 统一清理。
	if is_instance_valid(music) and music.get_parent() == self:
		music.stop()
		music.stream = null

	# bg_layer / cg_layer 的 TextureRect.texture 仍指向当前显示的 1920×1080 帧。
	# 进程退出时若不主动解除，这些 Texture2D 会在 RenderingServer 关闭后仍被节点
	# 引用，触发 "Texture ... leaked N bytes" / "resources still in use at exit"。
	# 这里解除 .texture 与本地帧数组引用，让纹理引用计数及时归零。
	if is_instance_valid(bg_layer):
		bg_layer.texture = null
	if is_instance_valid(cg_layer):
		cg_layer.texture = null
	if is_instance_valid(_warm_rect):
		_warm_rect.texture = null
	# _bg_frames 与 GameState.shared_start_bg_frames 指向同一个 Array。场景切换到
	# main_menu 时不能 clear()，否则会把已预加载/预热的共享缓存清空，主菜单只能重新
	# 同步加载 46 张大图，正好卡在 CG → 开始界面的衔接帧上。
	_bg_frames = []
	_cg_frames.clear()

func _process(delta: float) -> void:
	if _cg_done:
		return

	# ── GPU 纹理预热：在开场等待 + CG 播放期间分摊完成所有 BG 帧的 GPU 上传 ──
	# 趁玩家还在看开场提示语 / CG 时把 46 张 BG 帧逐帧真实渲染上传，
	# 这样切到 main_menu 时第一轮轮播不会因首次上传而卡顿。
	_process_texture_warmup()

	# ── 开场等待阶段：CG 停在第一帧，提示语有节奏地闪烁 ──────────────
	if not _started:
		_start_blink_t += delta
		var start_phase := fmod(_start_blink_t, START_BLINK_PERIOD) / START_BLINK_PERIOD
		# 边框与文字一起按固定节奏明暗变化
		var blink := 0.5 - 0.5 * cos(start_phase * TAU)
		start_frame.modulate.a = lerp(START_BLINK_MIN_ALPHA, START_BLINK_MAX_ALPHA, blink)
		return

	# ── BgLayer 持续循环（始终在后面跑） ──────────────────────────
	_bg_anim_t += delta
	while _bg_anim_t >= BG_FRAME_INTERVAL:
		_bg_anim_t -= BG_FRAME_INTERVAL
		# 帧未加载时（_bg_frames 为空）直接跳过，避免对 0 取模崩溃。
		if _bg_frames.is_empty():
			break
		_bg_frame_idx = (_bg_frame_idx + 1) % _bg_frames.size()
		bg_layer.texture = _bg_frames[_bg_frame_idx]

	# ── CG 帧推进 ─────────────────────────────────────────────────
	if not _cg_visual_done:
		_cg_anim_t += delta
		while _cg_anim_t >= CG_FRAME_INTERVAL:
			_cg_anim_t -= CG_FRAME_INTERVAL
			var prev_idx := _cg_frame_idx
			_cg_frame_idx += 1

			if _cg_frame_idx >= _cg_frames.size():
				# 所有帧播完，等待音频也播完后再进入菜单。
				_complete_cg_visuals()
				return

			cg_layer.texture = _cg_frames[_cg_frame_idx]

			# 关键优化：CG 是单向播放、永不回头的序列。每推进一帧，就把刚刚离开
			# 显示的上一帧从数组里解除引用（置 null），让这张 1920×1080×4 ≈ 8.3MB
			# 的纹理在播放过程中被分摊回收。否则 279 帧全部驻留（≈2.3GB 显存），
			# 切场景时旧场景被一次性销毁，这 279 张大纹理的 GPU 资源同步回收会砸在
			# 切换的那一帧上，造成肉眼可见的卡顿。逐帧释放后，切场景时几乎无纹理待回收。
			if prev_idx >= 0 and prev_idx < _cg_frames.size():
				_cg_frames[prev_idx] = null

			# ── 淡出计算（基于 1-indexed 帧号） ──────────────────────
			# _cg_frame_idx 是 0-indexed；帧号 = _cg_frame_idx + 1
			var frame_no := _cg_frame_idx + 1
			if frame_no >= FADE_END_FRAME:
				# frame_no = FADE_END_FRAME 时 alpha 恰好为 0，画面结束但继续等 CG 音频。
				cg_layer.modulate.a = 0.0
				_complete_cg_visuals()
				return
			elif frame_no >= FADE_START_FRAME:
				# FADE_START_FRAME(273) ~ FADE_END_FRAME-1(277)：线性插值 1→0
				var fade_range := float(FADE_END_FRAME - FADE_START_FRAME)
				var fade_done  := float(frame_no - FADE_START_FRAME)
				cg_layer.modulate.a = 1.0 - (fade_done / fade_range)
			else:
				cg_layer.modulate.a = 1.0

	# ── "按回车跳过" 标签闪烁 ─────────────────────────────────────
	_skip_blink_t += delta
	var phase := fmod(_skip_blink_t, 1.2) / 1.2
	skip_label.modulate.a = 0.5 + 0.5 * sin(phase * TAU)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		if not _started:
			# 开场等待阶段按回车：开始播放 CG
			_begin_play()
		else:
			# CG 播放中按回车跳过：终止 CGv1.mp3 播放
			_finish(true)

func _complete_cg_visuals() -> void:
	if _cg_visual_done:
		return
	_cg_visual_done = true

	skip_label.visible = false
	if is_instance_valid(cg_layer):
		cg_layer.texture = null
	for i in range(_cg_frames.size()):
		_cg_frames[i] = null
	_cg_frames.clear()

	# CG 画面约 11.6s，CGv1.mp3 约 14.2s；线上版以前在画面结束时就切主菜单，
	# 导致主菜单音乐提前接管。这里必须等音频 finished 后再切场景。
	if _intro_audio_done or not (is_instance_valid(music) and music.playing):
		_finish()

func _on_intro_audio_finished() -> void:
	_intro_audio_done = true
	if _cg_visual_done:
		_finish()

func _finish(skipped: bool = false) -> void:
	if _cg_done:
		return
	_cg_done = true

	if skipped:
		# 跳过：立即停止 CGv1.mp3，音乐随场景释放即可
		GameState.stop_start_sequence_music()
		if is_instance_valid(music) and music.playing:
			music.stop()
	else:
		# 正常播完时，GameState 会在 CGv1.mp3 finished 后接续 StartMusic.mp3。
		if is_instance_valid(music) and not music.playing:
			music.queue_free()

	# 切场景前主动解除本场景持有的 CG 大纹理引用，避免旧场景被销毁时一次性回收
	# 剩余 CG 帧（正常播完时仅末尾几帧，跳过时可能仍有大量帧驻留）的 GPU 资源，
	# 把这部分同步回收开销从「切换那一帧」剥离出去，消除切场景卡顿。
	# BgLayer 仍指向 shared_start_bg_frames 中的帧（main_menu 复用），不在此解除。
	if not _cg_visual_done and is_instance_valid(cg_layer):
		cg_layer.texture = null
	for i in range(_cg_frames.size()):
		_cg_frames[i] = null
	_cg_frames.clear()

	# 用后台已预加载的 PackedScene 切换（无磁盘读取，零卡顿）
	var packed: PackedScene = GameState.take_threaded_load(MAIN_MENU_PATH) as PackedScene
	if packed != null:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(MAIN_MENU_PATH)
