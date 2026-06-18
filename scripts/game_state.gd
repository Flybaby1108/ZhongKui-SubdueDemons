extends Node

const LevelData = preload("res://scripts/level_data.gd")

signal score_changed(new_score: int)
signal lives_changed(new_lives: int)
signal stage_changed(new_stage: int)
signal coins_changed(new_coins: int)
signal yuanbao_changed(new_yuanbao: int)

const MAX_LIVES := 3
const MAX_STAGE := 4
const START_MUSIC_PATH := "res://assets/audio/StartMusic.mp3"

var score: int = 0
var coins: int = 0
var yuanbao: int = 0
var lives: int = MAX_LIVES
var current_stage: int = 1
var _allow_start_sequence_music: bool = true
var _intro_music_player: AudioStreamPlayer = null
var _start_music_player: AudioStreamPlayer = null
var _game_over_queued: bool = false
# 关卡已进入"通关"流程（_on_stage_clear 起）：置位后任何延迟触发的 goto_game_over
# 都会被忽略，避免通关动画期间玩家因 hold_timer 超时引爆 / 延迟扣血把场景切到
# game_over，覆盖掉本应跳转的下一关（典型表现：chapter3 通关动画播完后直接 GAME OVER）。
var _level_cleared: bool = false

# StartBackground 序列帧的共享缓存：cg_intro 加载完后存到这里，main_menu
# 直接复用，避免切场景时再次同步 load 造成的 1 秒卡顿。
var shared_start_bg_frames: Array = []

# 已通过 load_threaded_request 发起、但尚未被 load_threaded_get 取走的资源路径。
# 各场景统一经由 request_threaded_load / take_threaded_load 登记与注销；
# 退出时若仍有未取走的请求，其内部 RefCounted 会泄漏并触发
# "ObjectDB instances leaked at exit" 警告（典型场景：玩家在 level_1 后台
# 加载完成后、未进入游戏就直接关闭窗口）。因此退出前统一把它们取回释放。
var _pending_threaded_loads: Dictionary = {}

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
		_release_start_sequence_music()

var _quitting: bool = false

func _ready() -> void:
	# 关窗时不立即退出，改由 _handle_close_request 完成异步清理后手动 quit。
	get_tree().set_auto_accept_quit(false)

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
		tree.paused = true
		# 等待数帧让音频线程完成 AudioStreamPlayback 的释放（一帧不足以覆盖一次音频
		# 混音回调），避免 stream 资源退出竞争。
		for _i in range(8):
			await tree.process_frame
		tree.quit()

func _exit_tree() -> void:
	_drain_pending_threaded_loads()
	_clear_shared_textures()
	_release_start_sequence_music()

# 退出前释放开场序列音乐播放器。cg_intro 正常播完时会把持有 CGv1.mp3 的 Music
# 节点 reparent 到 SceneTree.root 并登记为 _intro_music_player，若玩家在其播放
# 期间关闭窗口，该节点不随任何场景释放，导致 CGv1.mp3（AudioStreamMP3）在退出时
# 被判定为 "1 resources still in use at exit"。这里主动停止并释放两个播放器。
func _release_start_sequence_music() -> void:
	# 退出阶段 SceneTree 已停止处理帧，queue_free() 的延迟释放队列不会再被 flush，
	# 因此这里必须用 free() 立即释放，并先解除 stream 引用让资源引用计数归零。
	if is_instance_valid(_intro_music_player):
		_intro_music_player.stop()
		_intro_music_player.stream = null
		_intro_music_player.free()
	_intro_music_player = null
	if is_instance_valid(_start_music_player):
		_start_music_player.stop()
		_start_music_player.stream = null
		_start_music_player.free()
	_start_music_player = null

func _clear_shared_textures() -> void:
	shared_start_bg_frames.clear()

# 关窗兜底：遍历完整场景树，解除所有可见纹理与音频 stream 引用。
# cg_intro 的 $BgLayer/$CgLayer、main_menu 的 $Background 等节点在退出时仍持有
# 当前显示的大尺寸纹理（1920×1080 StartBackground / CGv1 帧）。各场景虽已在
# _exit_tree 自行解除，但 _exit_tree 在 RenderingServer 关闭流程中触发存在竞争；
# 在 SceneTree 仍运行的关窗时刻统一清一遍，确保纹理引用计数及时归零，彻底消除
# "Texture ... leaked N bytes" 与 "resources still in use at exit"。
func _release_scene_textures() -> void:
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

# 取回一次线程加载结果，并从待取回表注销，释放其内部引用。
func take_threaded_load(path: String) -> Resource:
	_pending_threaded_loads.erase(path)
	return ResourceLoader.load_threaded_get(path)

# 退出前把所有尚未取走的线程加载请求取回，避免 RefCounted 泄漏。
func _drain_pending_threaded_loads() -> void:
	for path in _pending_threaded_loads.keys():
		# 取回即释放：无论加载是否完成，load_threaded_get 都会结束该请求。
		ResourceLoader.load_threaded_get(path)
	_pending_threaded_loads.clear()

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
	if owner == null or not is_instance_valid(owner):
		# 兜底：无有效宿主时退回 SceneTreeTimer（调用方通常会立即 await，
		# 不会长期挂起；正常路径不应走到这里）。
		return get_tree().create_timer(max(0.0, seconds)).timeout
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = max(0.001, seconds)
	timer.autostart = false
	owner.add_child(timer)
	# 超时后自动释放该 Timer 节点，避免在 owner 上无限堆积。
	timer.timeout.connect(timer.queue_free, CONNECT_DEFERRED)
	timer.start()
	return timer.timeout

func prepare_start_sequence_music() -> void:
	stop_start_sequence_music()
	_allow_start_sequence_music = true

func enable_start_sequence_music() -> void:
	_allow_start_sequence_music = true

func register_intro_music_player(player: AudioStreamPlayer) -> void:
	if player == null:
		return
	_intro_music_player = player
	_allow_start_sequence_music = true
	if not player.finished.is_connected(_on_intro_music_finished):
		player.finished.connect(_on_intro_music_finished)

func play_start_music_if_ready() -> void:
	if not _allow_start_sequence_music:
		return
	if is_instance_valid(_intro_music_player) and _intro_music_player.playing:
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
	if is_instance_valid(_intro_music_player):
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

func goto_stage(n: int) -> void:
	if n < 1 or not has_stage(n):
		return
	# 进入新关卡：复位通关守卫，使下一关的 game_over 能正常触发。
	_level_cleared = false
	if n == 1:
		_game_over_queued = false
		score = 0
		coins = 0
		yuanbao = 0
		lives = MAX_LIVES
		score_changed.emit(score)
		coins_changed.emit(coins)
		yuanbao_changed.emit(yuanbao)
		lives_changed.emit(lives)
	current_stage = n
	get_tree().change_scene_to_file(_get_stage_scene_path(n))

func _get_stage_scene_path(stage: int) -> String:
	return "res://scenes/level_%d.tscn" % stage

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
