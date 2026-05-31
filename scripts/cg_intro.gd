extends Control

# ═══════════════════════════════════════════════════════════════════════════
# CG 开场场景控制器
#
# 播放时序：
#   [帧 1 ~ 272]  CgLayer alpha = 1.0，BgLayer 同步开始循环 StartBackground
#   [帧 273 ~ 278] CgLayer alpha 线性从 1.0 → 0.0（6 帧衰减）
#   [帧 278 播完]  alpha = 0.0，BgLayer 已完整露出，自动切换 main.tscn
#
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

@onready var bg_layer:  TextureRect       = $BgLayer
@onready var cg_layer:  TextureRect       = $CgLayer
@onready var music:     AudioStreamPlayer = $Music
@onready var skip_label: Label            = $SkipLabel

# 帧数组（同步异步加载均可；这里用同步 load，CG 279 帧 × ~200KB JPEG ≈ 50MB，
# 在 _ready 里统一加载让帧率最稳定）
var _cg_frames: Array  = []
var _bg_frames: Array  = []

var _cg_frame_idx: int   = 0     # 当前 CG 帧（0-indexed，对应 CGv1_001）
var _cg_anim_t:   float  = 0.0   # CG 帧计时累加器
var _cg_done:     bool   = false # 所有 CG 帧播完且淡出完成标志

var _bg_frame_idx: int   = 0
var _bg_anim_t:    float = 0.0

# 跳过动画（标签闪烁）
var _skip_blink_t: float = 0.0

func _ready() -> void:
	# 立即开始后台预加载 main.tscn（CG 播放 ~11s 内足以加载完毕）
	ResourceLoader.load_threaded_request(MAIN_MENU_PATH)

	# 加载 StartBackground 帧（46 帧，全部已 import，瞬间完成）
	# 这些 Texture2D 资源会被 ResourceLoader 缓存（弱引用），后续 main_menu 再
	# load() 时直接命中缓存，避免切场景瞬间重复解码导致的卡顿。
	_bg_frames = []
	for i in range(1, BG_FRAME_COUNT + 1):
		var path := "res://assets/sprites/Start/StartBackground/StartBackground_%02d.jpg" % i
		_bg_frames.append(load(path))
	if not _bg_frames.is_empty():
		bg_layer.texture = _bg_frames[0]
		# 在 CG 期间把每张 BG 都贴上 bg_layer 一次，强制 GPU 完成纹理上传 / 预热，
		# 这样切到 main_menu 时第一帧不会因首次上传 1920×1080×46 而卡顿。
		# 利用 RenderingServer 直接获取 RID，无需真的渲染。
		for tex in _bg_frames:
			if tex != null:
				# 触发底层 RID 创建（Texture2D.get_rid() 会确保 GPU 资源就绪）
				var _rid := (tex as Texture2D).get_rid()

	# 存入 autoload 共享缓存，main_menu 切场景后直接复用，零 IO 零卡顿
	GameState.shared_start_bg_frames = _bg_frames

	# 加载 CG 帧（279 帧，~50MB JPEG，同步 load）
	_cg_frames = []
	for i in range(1, CG_FRAME_COUNT + 1):
		var path := "res://assets/sprites/Start/CGv1/CGv1_%03d.jpg" % i
		_cg_frames.append(load(path))
	if not _cg_frames.is_empty():
		cg_layer.texture = _cg_frames[0]

	# 播放配乐
	if music.stream != null:
		music.play()

	# CgLayer 初始完全不透明（从第 1 帧开始全覆盖 BgLayer）
	cg_layer.modulate.a = 1.0

func _process(delta: float) -> void:
	if _cg_done:
		return

	# ── BgLayer 持续循环（始终在后面跑） ──────────────────────────
	_bg_anim_t += delta
	while _bg_anim_t >= BG_FRAME_INTERVAL:
		_bg_anim_t -= BG_FRAME_INTERVAL
		_bg_frame_idx = (_bg_frame_idx + 1) % _bg_frames.size()
		if not _bg_frames.is_empty():
			bg_layer.texture = _bg_frames[_bg_frame_idx]

	# ── CG 帧推进 ─────────────────────────────────────────────────
	_cg_anim_t += delta
	while _cg_anim_t >= CG_FRAME_INTERVAL:
		_cg_anim_t -= CG_FRAME_INTERVAL
		_cg_frame_idx += 1

		if _cg_frame_idx >= _cg_frames.size():
			# 所有帧播完 → 强制进入菜单（防止边界越界）
			_finish()
			return

		cg_layer.texture = _cg_frames[_cg_frame_idx]

		# ── 淡出计算（基于 1-indexed 帧号） ──────────────────────
		# _cg_frame_idx 是 0-indexed；帧号 = _cg_frame_idx + 1
		var frame_no := _cg_frame_idx + 1
		if frame_no >= FADE_END_FRAME:
			# frame_no = FADE_END_FRAME 时 alpha 恰好为 0 → 直接结束
			cg_layer.modulate.a = 0.0
			_finish()
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
		# 玩家按回车跳过：终止 CGv1.mp3 播放
		_finish(true)

func _finish(skipped: bool = false) -> void:
	if _cg_done:
		return
	_cg_done = true

	if skipped:
		# 跳过：立即停止 CGv1.mp3，音乐随场景释放即可
		if music != null:
			if music.playing:
				music.stop()
			# 不 reparent，cg_intro 释放时 music 节点一并被回收
	else:
		# 正常播完：把 Music 节点 reparent 到 SceneTree.root，使其脱离当前场景，
		# 不会随 cg_intro 一起被释放。播放结束后自动 queue_free。
		if music != null and music.playing:
			var root := get_tree().root
			music.get_parent().remove_child(music)
			root.add_child(music)
			music.process_mode = Node.PROCESS_MODE_ALWAYS
			# 一次性连接：mp3 播完自动清理
			if not music.finished.is_connected(music.queue_free):
				music.finished.connect(music.queue_free)
		elif music != null:
			# 如果没在播放（极端情况），直接释放
			music.queue_free()

	# 用后台已预加载的 PackedScene 切换（无磁盘读取，零卡顿）
	var packed: PackedScene = ResourceLoader.load_threaded_get(MAIN_MENU_PATH)
	if packed != null:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(MAIN_MENU_PATH)
