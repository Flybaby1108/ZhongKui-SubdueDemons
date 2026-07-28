extends Node

const LevelData = preload("res://scripts/level_data.gd")

signal score_changed(new_score: int)
signal lives_changed(new_lives: int)
signal stage_changed(new_stage: int)
signal coins_changed(new_coins: int)
signal yuanbao_changed(new_yuanbao: int)

const MAX_LIVES := 5
const MAX_STAGE := 4
const START_MUSIC_PATH := "res://assets/audio/StartMusic.mp3"
const COPPER_COINS_PER_YUANBAO := 5
const REVIVE_COST_COIN_VALUE := 15
const COIN_SCORE_VALUE := 100
const YUANBAO_SCORE_VALUE := COIN_SCORE_VALUE * COPPER_COINS_PER_YUANBAO

var score: int = 0
var coins: int = 0
var yuanbao: int = 0
var lives: int = MAX_LIVES
var current_stage: int = 1
var _allow_start_sequence_music: bool = true
var _intro_music_active: bool = false
var _intro_music_player: AudioStreamPlayer = null
var _start_music_player: AudioStreamPlayer = null
# 开场 CG 配乐（CGv1.mp3）的总时长（秒）。register 时缓存，供 _process 轮询判断
# 是否真正播完用。Web 导出里 AudioStreamPlayer.finished 信号会提前 / 抖动触发，
# 单靠信号会让 StartMusic 在 CG 尾声还没播完时就抢跑，造成两段 BGM 重叠。
var _intro_music_length: float = 0.0
# 轮询到的 CG 播放进度出现回退 / playback 结束的连续帧数。Web 上 get_playback_position()
# 偶发抖动，用连续判定去抖，避免误判提前接续 StartMusic。
var _intro_music_end_grace: int = 0
var _game_over_queued: bool = false
# 关卡已进入"通关"流程（_on_stage_clear 起）：置位后任何延迟触发的 goto_game_over
# 都会被忽略，避免通关动画期间玩家因 hold_timer 超时引爆 / 延迟扣血把场景切到
# game_over，覆盖掉本应跳转的下一关（典型表现：chapter3 通关动画播完后直接 GAME OVER）。
var _level_cleared: bool = false

# StartBackground 序列帧的共享缓存：cg_intro 加载完后存到这里，main_menu
# 直接复用，避免切场景时再次同步 load 造成的 1 秒卡顿。
var shared_start_bg_frames: Array = []

# 关卡共享动画背景（Chapter_BG_01~22，1920×1080）的常驻 SpriteFrames 缓存。
# 4 个关卡的动画背景用的是同一批 22 张贴图；若内嵌在各关 .tscn 里，每次切关都会
# 卸载再重新解码/上传这 22 张（解码后约 176MB RGBA），在单线程 Web 导出
# （thread_support=false）下全部堆在切场景那一帧，造成明显卡顿。
# 改由 autoload 常驻持有一份 SpriteFrames：只在首次进关时构建一次，之后所有关卡
# 直接复用，切关不再释放/重载这批纹理。
const CHAPTER_BG_FRAME_COUNT := 22
const CHAPTER_BG_FRAME_FPS := 8.0
const CHAPTER_BG_ANIM_NAME := &"default"
var _shared_chapter_bg_frames: SpriteFrames = null

# 返回关卡共享动画背景的 SpriteFrames（首次调用时构建并常驻缓存）。
# 单线程 Web 下 load() 是同步的，但这里只在整局游戏里发生一次；之后每次切关
# 直接命中缓存，避免重复解码上传。
func get_shared_chapter_bg_frames() -> SpriteFrames:
	if _shared_chapter_bg_frames != null:
		return _shared_chapter_bg_frames
	var frames := SpriteFrames.new()
	frames.set_animation_speed(CHAPTER_BG_ANIM_NAME, CHAPTER_BG_FRAME_FPS)
	frames.set_animation_loop(CHAPTER_BG_ANIM_NAME, true)
	for i in range(1, CHAPTER_BG_FRAME_COUNT + 1):
		var path := "res://assets/sprites/Chapter_BG/Chapter_BG_%02d.jpg" % i
		var tex := load(path) as Texture2D
		if tex == null:
			push_warning("Missing Chapter_BG frame: %s" % path)
			continue
		frames.add_frame(CHAPTER_BG_ANIM_NAME, tex)
	_shared_chapter_bg_frames = frames
	return _shared_chapter_bg_frames

# 已通过 load_threaded_request 发起、但尚未被 load_threaded_get 取走的资源路径。
# 各场景统一经由 request_threaded_load / take_threaded_load 登记与注销；
# 退出时若仍有未取走的请求，其内部 RefCounted 会泄漏并触发
# "ObjectDB instances leaked at exit" 警告（典型场景：玩家在 level_1 后台
# 加载完成后、未进入游戏就直接关闭窗口）。因此退出前统一把它们取回释放。
var _pending_threaded_loads: Dictionary = {}
var _transition_resource_cache: Dictionary = {}

func _notification(what: int) -> void:
	# autoload 单例的生命周期等于整个进程。它持有的 shared_start_bg_frames
	# （46 张 1920×1080 纹理，每张 ≈8MB）若不在退出前主动释放引用，会在
	# RenderingServer 关闭后仍被引用，触发：
	#   "Texture ... leaked N bytes" 与 "N resources still in use at exit"。
	# 因此在窗口关闭 / 节点删除前清空缓存，让纹理引用计数及时归零回收。
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# 用户关窗：此时 SceneTree 仍在运行。先停止音乐并解除 stream 引用，等待数帧
		# 让音频线程把 AudioStreamPlayback 真正释放后再退出，彻底避免退出竞争导致的
		# "1 resources still in use at exit"（CGv1.mp3 / StartMusic.mp3）。
		_handle_close_request()
	elif what == NOTIFICATION_PREDELETE:
		_drain_pending_threaded_loads()
		_clear_shared_textures()
		_release_scene_textures()
		_release_start_sequence_music()
		# 兜底路径无逐帧刷新，统一在收尾再 flush 一次，覆盖场景内 BGM / 音效的 playback。
		flush_audio_thread()

var _quitting: bool = false

func _ready() -> void:
	# 关窗时不立即退出，改由 _handle_close_request 完成异步清理后手动 quit。
	get_tree().set_auto_accept_quit(false)

func _process(_delta: float) -> void:
	_poll_intro_music()

# 轮询开场 CG 配乐的真实播放进度，判断它是否已经播完，再接续开始界面 StartMusic。
#
# 为什么不只依赖 finished 信号：Web 导出下 AudioStreamPlayer.finished 会因音频线程
# 缓冲 / 解码时序而提前或抖动触发（playing 状态同样短暂不可靠），导致 StartMusic 在
# CGv1.mp3 尾声还没播完时就抢跑，两段 BGM 叠在一起。这里以「播放位置是否真的走到
# 流末尾」为准绳，只有 CG 音频确实播到结尾才切换，彻底消除重叠。
func _poll_intro_music() -> void:
	if not _intro_music_active:
		return
	if not is_instance_valid(_intro_music_player):
		# 播放器已被释放（异常路径），直接接续，避免卡在 _intro_music_active。
		_finish_intro_music()
		return

	var player := _intro_music_player
	# 时长未知（Web 上偶发拿不到）时退化为信号驱动，不在此强行判定结束。
	if _intro_music_length <= 0.0:
		return

	var pos := player.get_playback_position()
	# 播放位置走到流末尾附近（留 0.05s 余量）即视为播完。用连续 2 帧确认去抖，
	# 避免 Web 上单帧位置抖动误判。
	if pos >= _intro_music_length - 0.05:
		_intro_music_end_grace += 1
		if _intro_music_end_grace >= 2:
			_finish_intro_music()
	else:
		_intro_music_end_grace = 0

func _handle_close_request() -> void:
	if _quitting:
		return
	_quitting = true
	_drain_pending_threaded_loads()
	_clear_shared_textures()
	_release_scene_textures()
	_release_start_sequence_music()
	var tree := get_tree()
	if tree != null:
		# 不要 pause SceneTree：暂停后 AudioStreamPlayer 停止处理，反而可能让音频线程
		# 跳过对已 stop() playback 的回收，导致 8 帧后仍残留 AudioStreamPlayback。
		# 这里保持运行态逐帧 await，让主循环持续驱动 AudioServer 混音，把所有已停止的
		# playback（及其引用的 AudioStream）确定性地回收，彻底消除退出竞争导致的
		# "ObjectDB instances leaked at exit" / "resources still in use at exit"。
		for _i in range(16):
			await tree.process_frame
		tree.quit()

func _exit_tree() -> void:
	# 兜底路径：程序化 quit() / --quit-after 等不会发 NOTIFICATION_WM_CLOSE_REQUEST，
	# 不会走 _handle_close_request 的逐帧刷新。这里在 SceneTree 销毁阶段把所有还在
	# 播放的音频（开场音乐 + 当前场景内的 BGM / 音效）统一停掉并解除 stream 引用，
	# 再让音频线程把残留 playback 移除，避免 "ObjectDB instances leaked at exit"。
	_drain_pending_threaded_loads()
	_clear_shared_textures()
	_release_scene_textures()
	_release_start_sequence_music()
	# 兜底路径无逐帧刷新，统一在收尾再 flush 一次，覆盖场景内 BGM / 音效的 playback。
	flush_audio_thread()

# 退出前释放开场序列音乐播放器。cg_intro 正常播完时会把持有 CGv1.mp3 的 Music
# 节点 reparent 到 SceneTree.root 并登记为 _intro_music_player，若玩家在其播放
# 期间关闭窗口，该节点不随任何场景释放，导致 CGv1.mp3（AudioStreamMP3）在退出时
# 被判定为 "1 resources still in use at exit"。这里主动停止并释放两个播放器。
func _release_start_sequence_music() -> void:
	# 退出阶段 SceneTree 已停止处理帧，queue_free() 的延迟释放队列不会再被 flush，
	# 因此这里必须用 free() 立即释放，并先解除 stream 引用让资源引用计数归零。
	var had_player := false
	if is_instance_valid(_intro_music_player):
		_free_music_player(_intro_music_player)
		had_player = true
	_intro_music_player = null
	if is_instance_valid(_start_music_player):
		_free_music_player(_start_music_player)
		had_player = true
	_start_music_player = null
	if had_player:
		flush_audio_thread()
	_intro_music_active = false

# 退出收尾安全释放一个音乐播放器节点。
#
# 关键：关窗 / 退出流程触发本函数时，SceneTree 往往正处于"忙于增删子节点"的阶段
# （场景正在被销毁）。此时直接对仍挂在父节点下的播放器调用 free()，引擎会报：
#   "Parent node is busy adding/removing children, remove_child() can't be called"
#   "Condition 'data.parent' is true."（节点带着父节点被析构）
# 后者意味着节点未能从父节点干净摘除，其持有的 AudioStream（CGv1.mp3 /
# StartMusic.mp3）引用可能未及时归零，最终在退出时残留为
# "1 resources still in use at exit"。
#
# 这里的关键防护顺序：
#   1. 先停止播放并解除 stream 引用——无论节点最终能否立即 free，资源引用都先归零；
#   2. 若父节点正忙，无法立即 remove_child / free，则退回 queue_free()，由引擎在
#      安全时机延迟释放；节点本身（剥离 stream 后）不再持有任何资源，延迟释放无害。
func _free_music_player(player: AudioStreamPlayer) -> void:
	player.stop()
	# 第一要务：解除 stream 引用。AudioStream（CGv1.mp3 / StartMusic.mp3）的引用
	# 计数在此立即归零并回收，与节点本身能否 free 无关，从根本上消除
	# "1 resources still in use at exit"。
	player.stream = null
	var parent := player.get_parent()
	if parent == null:
		# 无父节点：可安全立即释放。
		player.free()
		return
	# 仍挂在父节点下。退出 / 关窗收尾时 SceneTree 常处于"忙于增删子节点"的阶段，
	# 此刻对带父节点调用 free() 会触发：
	#   "Parent node is busy adding/removing children, remove_child() can't be called"
	#   "Condition 'data.parent' is true."（带父析构）
	# 改用 queue_free()：它由引擎在安全时机统一摘除并释放，绝不带父析构。stream 已
	# 置空，即便延迟释放队列在极端退出竞争下未及刷新，残留的也只是一个不再持有任何
	# 资源的空节点，不会造成资源泄漏。
	player.queue_free()

# 等待音频混音线程跑完至少一次混音回调，把已 stop() 的 AudioStreamPlayback 从
# AudioServer 的播放列表中真正移除。
#
# 背景：AudioStreamPlayer.free() 只会把 playback 标记为停止并交给音频线程异步移除，
# playback（及其引用的 AudioStream）要等下一次混音步进才真正释放。退出（quit /
# _exit_tree / NOTIFICATION_PREDELETE）路径下 SceneTree 已不再 tick，混音线程若没机会
# 再跑一次，残留的 AudioStreamPlaybackMP3 + AudioStreamMP3 就会被引擎判定为
# "ObjectDB instances leaked at exit" / "resources still in use at exit"。
#
# 走 _handle_close_request 的关窗路径靠 await process_frame 让混音线程推进；但
# --quit-after / 程序化 quit() 等路径不再有帧，因此这里用一小段忙等阻塞主线程，
# 给音频线程留出 > 一个混音缓冲的时间完成移除。仅在退出收尾调用，阻塞可忽略。
#
# 供各场景在退出收尾（_exit_tree / 关窗）释放自己的 AudioStreamPlayer 后调用，
# 统一消除 BGM / 音效在退出竞争下残留的 AudioStreamPlayback 泄漏。
func flush_audio_thread() -> void:
	# 阻塞时长取输出延迟的若干倍（典型 output_latency ≈ 0.01~0.03s），并设下限，
	# 确保跨过至少一次混音回调。
	var latency := AudioServer.get_output_latency()
	var wait_ms := int(max(60.0, latency * 4.0 * 1000.0))
	# 分多次短睡，期间反复 lock/unlock 触发音频线程调度，比单次长睡更可靠。
	var elapsed := 0
	while elapsed < wait_ms:
		AudioServer.lock()
		AudioServer.unlock()
		OS.delay_msec(10)
		elapsed += 10

func _clear_shared_textures() -> void:
	shared_start_bg_frames.clear()
	# 常驻的关卡动画背景 SpriteFrames 持有 22 张 1920×1080 纹理，退出前解除引用，
	# 让纹理引用计数在 RenderingServer 关闭前归零，避免 "Texture leaked" 警告。
	_shared_chapter_bg_frames = null
	_transition_resource_cache.clear()

# 关窗兜底：遍历完整场景树，解除所有可见纹理与音频 stream 引用。
# cg_intro 的 $BgLayer/$CgLayer、main_menu 的 $Background 等节点在退出时仍持有
# 当前显示的大尺寸纹理（1920×1080 StartBackground / CGv1 帧）。各场景虽已在
# _exit_tree 自行解除，但 _exit_tree 在 RenderingServer 关闭流程中触发存在竞争；
# 在 SceneTree 仍运行的关窗时刻统一清一遍，确保纹理引用计数及时归零，彻底消除
# "Texture ... leaked N bytes" 与 "resources still in use at exit"。
func _release_scene_textures() -> void:
	# NOTIFICATION_PREDELETE 阶段 GameState（autoload）自身已离开 SceneTree，
	# 此时直接调用 get_tree() 会触发引擎报错 "Parameter 'data.tree' is null."。
	# 先用 is_inside_tree() 守卫，未在树中时 SceneTree 不可达，无需遍历。
	if not is_inside_tree():
		return
	var tree := get_tree()
	if tree == null or tree.root == null:
		return
	_strip_textures_recursive(tree.root)

func _strip_textures_recursive(node: Node) -> void:
	if node is Sprite2D:
		(node as Sprite2D).texture = null
	elif node is TextureRect:
		(node as TextureRect).texture = null
	elif node is NinePatchRect:
		(node as NinePatchRect).texture = null
	elif node is TextureButton:
		var button := node as TextureButton
		button.texture_normal = null
		button.texture_pressed = null
		button.texture_hover = null
		button.texture_disabled = null
		button.texture_focused = null
		button.texture_click_mask = null
	elif node is AnimatedSprite2D:
		(node as AnimatedSprite2D).sprite_frames = null
	elif node is AudioStreamPlayer:
		var audio := node as AudioStreamPlayer
		audio.stop()
		audio.stream = null
		audio.playing = false
	elif node is AudioStreamPlayer2D:
		var audio_2d := node as AudioStreamPlayer2D
		audio_2d.stop()
		audio_2d.stream = null
	for child in node.get_children():
		_strip_textures_recursive(child)

# 发起一次线程加载，并登记到待取回表。重复发起同一路径只登记一次。
func request_threaded_load(path: String) -> void:
	if path.is_empty():
		return
	if not _pending_threaded_loads.has(path):
		ResourceLoader.load_threaded_request(path)
		_pending_threaded_loads[path] = true

func has_pending_threaded_load(path: String) -> bool:
	return _pending_threaded_loads.has(path)

# 取回一次线程加载结果，并从待取回表注销，释放其内部引用。
func take_threaded_load(path: String) -> Resource:
	if not _pending_threaded_loads.has(path):
		return null
	_pending_threaded_loads.erase(path)
	return ResourceLoader.load_threaded_get(path)

func hold_transition_resource(path: String, res: Resource) -> void:
	if path.is_empty() or res == null:
		return
	_transition_resource_cache[path] = res

func load_transition_or_file(path: String) -> Resource:
	if _transition_resource_cache.has(path):
		return _transition_resource_cache[path]
	return load(path)

func clear_transition_resource_cache() -> void:
	_transition_resource_cache.clear()

# 退出前把所有尚未取走的线程加载请求取回，避免 RefCounted 泄漏。
func _drain_pending_threaded_loads() -> void:
	for path in _pending_threaded_loads.keys():
		# 取回即释放：无论加载是否完成，load_threaded_get 都会结束该请求。
		ResourceLoader.load_threaded_get(path)
	_pending_threaded_loads.clear()
	_transition_resource_cache.clear()

# 节点生命周期内的延迟等待，返回一次性 Timer 节点的 timeout 信号。
#
# 用于替代 get_tree().create_timer(t).timeout：后者创建的 SceneTreeTimer 是
# RefCounted，由挂起的协程（await）或已连接的回调持有；进程退出（quit）时若该
# 定时器尚未超时，引用计数无法归零，会被引擎判定为
# "ObjectDB instances leaked at exit (SceneTreeTimer ...)"。
#
# 这里改用挂在 owner 节点下的真实 Timer 节点：它随 owner 一起被释放（场景切换 /
# 退出时连同场景树销毁），不会残留 RefCounted。Timer 在 timeout 后自动 queue_free，
# 避免节点堆积。
#
# 用法：
#   await GameState.wait(self, 1.5)                 # 协程等待
#   GameState.wait(self, 1.2).connect(_on_done)     # 信号回调
func wait(owner: Node, seconds: float) -> Signal:
	if owner == null or not is_instance_valid(owner) or not owner.is_inside_tree():
		# 兜底：无有效宿主、或宿主已不在场景树（正在 / 已离开，例如协程在死亡序列中
		# 被 tree_exiting 唤醒后又重新调用 wait）。此时给宿主 add_child 的 Timer 永远
		# 不会再 timeout，挂在其上的协程会残留 RefCounted。改用 SceneTreeTimer：它由
		# 主循环驱动（关窗清理的逐帧 await 会推进并触发），不依赖已死宿主，能被回收。
		return get_tree().create_timer(max(0.0, seconds)).timeout
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = max(0.001, seconds)
	timer.autostart = false
	owner.add_child(timer)
	# 超时后自动释放该 Timer 节点，避免在 owner 上无限堆积。
	timer.timeout.connect(timer.queue_free, CONNECT_DEFERRED)
	# 关键：若 owner 在 timer 超时前离开场景树（敌人死亡 queue_free、切场景、退出），
	# 挂在 timer.timeout 上的协程将永远不会被恢复，其 GDScript 函数状态（RefCounted）
	# 会在进程退出时残留，触发非确定性的 "ObjectDB instances leaked at exit"。
	# 这里在 owner.tree_exiting 时主动把 timer.timeout 触发一次，让等待中的协程恢复
	# 并自然结束（协程内通常随即判断 is_instance_valid(self) 后返回），从而回收其状态。
	#
	# 注意：Godot 4 判定信号是否"已连接"时，对 bound Callable 只比较其基础 callable
	# （object + method），不区分 .bind() 的参数。因此若直接用
	# _emit_wait_timeout.bind(id)，同一 owner 在退出前多次调用 wait() 会因被视为
	# "已连接同一 callable" 而报 "Signal 'tree_exiting' is already connected"。
	# 这里改用 lambda：每次创建的 Callable 各不相同，不会触发重复连接检测。
	var tid := timer.get_instance_id()
	owner.tree_exiting.connect(func() -> void: _emit_wait_timeout(tid), CONNECT_ONE_SHOT)
	timer.start()
	return timer.timeout

func _emit_wait_timeout(timer_id: int) -> void:
	var timer := instance_from_id(timer_id) as Timer
	if timer == null:
		return
	# 关键：owner.tree_exiting 触发时，作为 owner 子节点的 timer 通常已不在
	# 场景树中（子节点会跟随父节点一起退 tree）。此时若再调用 timer.is_stopped()
	# 或 timer.stop()，引擎内部会访问 SceneTree 触发
	# "Parameter 'data.tree' is null." 报错。我们在这里只 emit timeout
	# 唤醒挂起的协程/回调；timer 节点会随 owner 一起被销毁，无需再 stop。
	if timer.is_inside_tree() and not timer.is_stopped():
		timer.stop()
	timer.timeout.emit()

func prepare_start_sequence_music() -> void:
	stop_start_sequence_music()
	_allow_start_sequence_music = true
	_intro_music_active = false

func enable_start_sequence_music() -> void:
	_allow_start_sequence_music = true

func register_intro_music_player(player: AudioStreamPlayer) -> void:
	if player == null:
		return
	_intro_music_player = player
	_intro_music_active = true
	_allow_start_sequence_music = true
	_intro_music_end_grace = 0
	# 缓存流总时长，供 _poll_intro_music 判定是否真正播完。
	_intro_music_length = 0.0
	if player.stream != null:
		_intro_music_length = player.stream.get_length()
	# finished 信号作为兜底触发（正常桌面端可靠）；Web 上以 _poll_intro_music
	# 的播放位置判定为主，两者最终都走 _finish_intro_music，不会重复接续。
	if not player.finished.is_connected(_on_intro_music_finished):
		player.finished.connect(_on_intro_music_finished)

func play_start_music_if_ready() -> void:
	if not _allow_start_sequence_music:
		return
	if _intro_music_active:
		return
	play_start_music()

func play_start_music() -> void:
	if not _allow_start_sequence_music:
		return
	if is_instance_valid(_start_music_player):
		if not _start_music_player.playing:
			_start_music_player.play()
		return

	var stream := load(START_MUSIC_PATH) as AudioStream
	if stream == null:
		push_warning("StartMusic.mp3 not found: %s" % START_MUSIC_PATH)
		return
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true

	_start_music_player = AudioStreamPlayer.new()
	_start_music_player.name = "StartMusic"
	_start_music_player.stream = stream
	add_child(_start_music_player)
	_start_music_player.play()

func stop_start_sequence_music() -> void:
	_allow_start_sequence_music = false
	_intro_music_active = false
	if is_instance_valid(_intro_music_player):
		if _intro_music_player.playing:
			_intro_music_player.stop()
		_intro_music_player.queue_free()
	_intro_music_player = null
	if is_instance_valid(_start_music_player):
		if _start_music_player.playing:
			_start_music_player.stop()
		_start_music_player.queue_free()
	_start_music_player = null

func _on_intro_music_finished() -> void:
	# finished 信号兜底路径。Web 上该信号可能在 CG 尾声还没播完时就抖动触发，
	# 因此这里不无条件接续 StartMusic：只有当播放位置也确认走到流末尾（或时长
	# 未知只能信任信号）时才真正结束。否则忽略这次早触发，交给 _poll_intro_music
	# 在音频真正播完时接续。
	if not _intro_music_active:
		return
	if is_instance_valid(_intro_music_player) and _intro_music_length > 0.0:
		var pos := _intro_music_player.get_playback_position()
		if pos < _intro_music_length - 0.15 and _intro_music_player.playing:
			# 明显早于结尾且仍在播放：判定为 Web 抖动误触发，忽略。
			return
	_finish_intro_music()

# 开场 CG 配乐确认播完后，释放它并接续开始界面 StartMusic。信号与轮询两条路径
# 都汇入此函数；_intro_music_active 先置 false，重复进入将被 early-return 挡住，
# 保证 StartMusic 只启动一次。
func _finish_intro_music() -> void:
	if not _intro_music_active:
		return
	_intro_music_active = false
	_intro_music_length = 0.0
	_intro_music_end_grace = 0
	if is_instance_valid(_intro_music_player):
		if _intro_music_player.playing:
			_intro_music_player.stop()
		_intro_music_player.queue_free()
	_intro_music_player = null
	play_start_music()

func mark_level_cleared() -> void:
	_level_cleared = true

func is_level_cleared() -> bool:
	return _level_cleared

func reset_game() -> void:
	_game_over_queued = false
	_level_cleared = false
	score = 0
	coins = 0
	yuanbao = 0
	lives = MAX_LIVES
	current_stage = 1
	score_changed.emit(score)
	coins_changed.emit(coins)
	yuanbao_changed.emit(yuanbao)
	lives_changed.emit(lives)
	stage_changed.emit(current_stage)

func add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)

func add_coin(amount: int = 1) -> void:
	coins += amount
	coins_changed.emit(coins)

func add_yuanbao(amount: int = 1) -> void:
	yuanbao += amount
	yuanbao_changed.emit(yuanbao)

func yuanbao_to_coin_value(amount: int = 1) -> int:
	var safe_amount: int = amount if amount > 0 else 0
	return safe_amount * COPPER_COINS_PER_YUANBAO

func currency_to_coin_value(coin_amount: int = coins, yuanbao_amount: int = yuanbao) -> int:
	var safe_coin_amount: int = coin_amount if coin_amount > 0 else 0
	return safe_coin_amount + yuanbao_to_coin_value(yuanbao_amount)

func coin_value_to_yuanbao_value(coin_value: int) -> float:
	var safe_coin_value: int = coin_value if coin_value > 0 else 0
	return float(safe_coin_value) / float(COPPER_COINS_PER_YUANBAO)

func split_coin_value(coin_value: int) -> Dictionary:
	var safe_coin_value: int = coin_value if coin_value > 0 else 0
	return {
		"yuanbao": safe_coin_value / COPPER_COINS_PER_YUANBAO,
		"coins": safe_coin_value % COPPER_COINS_PER_YUANBAO,
	}

func can_afford_coin_value(coin_value: int) -> bool:
	return currency_to_coin_value() >= max(0, coin_value)

func get_coin_value_payment(coin_value: int) -> Dictionary:
	var cost: int = max(0, coin_value)
	var paid_coins: int = min(coins, cost)
	cost -= paid_coins
	var paid_yuanbao := 0
	var change_coins := 0
	if cost > 0:
		paid_yuanbao = ceili(float(cost) / float(COPPER_COINS_PER_YUANBAO))
		change_coins = paid_yuanbao * COPPER_COINS_PER_YUANBAO - cost
	return {
		"coins": paid_coins,
		"yuanbao": paid_yuanbao,
		"change_coins": change_coins,
	}

func spend_coin_value(coin_value: int) -> bool:
	var cost: int = max(0, coin_value)
	if cost == 0:
		return true
	if currency_to_coin_value() < cost:
		return false
	var payment := get_coin_value_payment(cost)
	coins -= payment["coins"]
	yuanbao -= payment["yuanbao"]
	coins += payment["change_coins"]
	coins_changed.emit(coins)
	yuanbao_changed.emit(yuanbao)
	return true

func can_revive_from_game_over() -> bool:
	return can_afford_coin_value(REVIVE_COST_COIN_VALUE) and has_stage(current_stage)

func revive_from_game_over() -> bool:
	# 同步切场景版本（保留作兜底）。注意：Web 导出为单线程，change_scene_to_file 会在
	# 主线程同步解包关卡场景与上百张贴图，导致浏览器主线程阻塞、页面"卡住不动"。
	# 线上（GitHub Pages / Web）复活请改用 begin_revive_from_game_over + 线程加载。
	if not _consume_revive_cost():
		return false
	get_tree().change_scene_to_file(_get_stage_scene_path(current_stage))
	return true

# 扣费并复位复活相关状态，但不切场景。成功返回 true。
func _consume_revive_cost() -> bool:
	if not can_revive_from_game_over():
		return false
	if not spend_coin_value(REVIVE_COST_COIN_VALUE):
		return false
	_level_cleared = false
	_game_over_queued = false
	lives = MAX_LIVES
	lives_changed.emit(lives)
	stage_changed.emit(current_stage)
	return true

# 异步复活：扣费 + 复位状态，并发起当前关卡场景与重资源的线程加载（非阻塞）。
# 成功返回 true 后，调用方需轮询 revive_load_done() 并在完成时用
# take_revive_packed_scene() 取回 PackedScene 进行 change_scene_to_packed。
# 这样可避免 Web 单线程下同步切场景造成的卡死。
func begin_revive_from_game_over() -> bool:
	if not _consume_revive_cost():
		return false
	var scene_path := _get_stage_scene_path(current_stage)
	request_threaded_load(scene_path)
	for path in Level.get_stage_preload_resource_paths(current_stage):
		request_threaded_load(path)
	return true

# 复活场景与重资源是否全部加载完成。
func revive_load_done() -> bool:
	if not _threaded_path_done(_get_stage_scene_path(current_stage)):
		return false
	for path in Level.get_stage_preload_resource_paths(current_stage):
		if not _threaded_path_done(path):
			return false
	return true

func _threaded_path_done(path: String) -> bool:
	if not has_pending_threaded_load(path):
		return true
	var status := ResourceLoader.load_threaded_get_status(path)
	return status != ResourceLoader.THREAD_LOAD_IN_PROGRESS

# 取回复活场景的 PackedScene，并把重资源登记进过渡缓存以持有引用。
func take_revive_packed_scene() -> PackedScene:
	var scene_path := _get_stage_scene_path(current_stage)
	var packed := take_threaded_load(scene_path) as PackedScene
	for path in Level.get_stage_preload_resource_paths(current_stage):
		var res := take_threaded_load(path)
		if res != null:
			hold_transition_resource(path, res)
	return packed

func lose_life() -> int:
	lives = max(0, lives - 1)
	lives_changed.emit(lives)
	return lives

func gain_life() -> void:
	if lives < MAX_LIVES:
		lives += 1
		lives_changed.emit(lives)

func advance_stage() -> bool:
	current_stage += 1
	stage_changed.emit(current_stage)
	return has_stage(current_stage)

func has_stage(stage: int) -> bool:
	return LevelData.LEVELS.has(stage) and ResourceLoader.exists(_get_stage_scene_path(stage))

func get_final_stage() -> int:
	var final_stage := 0
	for stage in LevelData.LEVELS.keys():
		if stage is int and has_stage(stage):
			final_stage = max(final_stage, stage)
	return final_stage

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		var current_scene_path: String = ""
		if get_tree().current_scene != null:
			current_scene_path = get_tree().current_scene.scene_file_path
		if current_scene_path != "res://scenes/main.tscn":
			goto_main_menu()

func goto_stage(n: int, packed: PackedScene = null) -> void:
	if n < 1 or not has_stage(n):
		return
	# 进入新关卡：复位通关守卫与 game_over 队列守卫，使下一关的 game_over 能正常触发。
	# 注意 _game_over_queued 必须在进入「任意」新关卡时复位：它在 goto_game_over
	# 里被置位后不会自动归零，若只在 n == 1 时复位，则当玩家通关推进到第 2/3/4 关
	# （goto_stage(2..4)）时残留的 true 会让后续关卡的 goto_game_over 被第 460 行守卫
	# 直接 return —— 表现为钟馗三条命耗尽、死亡动画播完却不跳 GAME OVER，游戏仍可继续。
	_level_cleared = false
	_game_over_queued = false
	if n == 1:
		score = 0
		coins = 0
		yuanbao = 0
		lives = MAX_LIVES
		score_changed.emit(score)
		coins_changed.emit(coins)
		yuanbao_changed.emit(yuanbao)
		lives_changed.emit(lives)
	current_stage = n
	if packed != null:
		get_tree().change_scene_to_packed(packed)
	else:
		get_tree().change_scene_to_file(_get_stage_scene_path(n))

func get_stage_scene_path(stage: int) -> String:
	return "res://scenes/level_%d.tscn" % stage

func _get_stage_scene_path(stage: int) -> String:
	return get_stage_scene_path(stage)

func goto_main_menu() -> void:
	_level_cleared = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func goto_game_over() -> void:
	# 关卡已进入通关流程：忽略此时仍被延迟触发的 game_over（如葫芦持有敌人在通关
	# 动画期间 hold_timer 超时引爆、或受击延迟扣血），否则会覆盖掉通关后的关卡跳转。
	if _level_cleared:
		return
	if _game_over_queued:
		return
	_game_over_queued = true
	get_tree().change_scene_to_file("res://scenes/game_over.tscn")

func goto_victory() -> void:
	_level_cleared = false
	get_tree().change_scene_to_file("res://scenes/victory.tscn")
