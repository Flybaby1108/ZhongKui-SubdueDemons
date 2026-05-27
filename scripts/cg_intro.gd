extends Node2D

# ═══════════════════════════════════════════════════════════════════════════
# CG 开场场景控制器
#
# 播放时序：
#   [帧 1 ~ 272]  CgLayer alpha = 1.0，BgLayer 同步开始循环 StartBackground
#   [帧 273 ~ 278] CgLayer alpha 线性从 1.0 → 0.0（6 帧衰减）
#   [帧 278 播完]  alpha = 0.0，BgLayer 已完整露出，自动切换 main.tscn
#
# 跳过：任意时刻按 ui_accept（回车/空格）立即切换 main.tscn
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
	# 加载 StartBackground 帧（46 帧，全部已 import，瞬间完成）
	_bg_frames = []
	for i in range(1, BG_FRAME_COUNT + 1):
		var path := "res://assets/sprites/Start/StartBackground/StartBackground_%02d.jpg" % i
		_bg_frames.append(load(path))
	if not _bg_frames.is_empty():
		bg_layer.texture = _bg_frames[0]

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
		_finish()

func _finish() -> void:
	if _cg_done:
		return
	_cg_done = true
	if music.playing:
		music.stop()
	get_tree().change_scene_to_file(MAIN_MENU_PATH)
