extends Node

signal score_changed(new_score: int)
signal lives_changed(new_lives: int)
signal stage_changed(new_stage: int)
signal coins_changed(new_coins: int)

const MAX_LIVES := 3
const MAX_STAGE := 3
const START_MUSIC_PATH := "res://assets/audio/StartMusic.mp3"

var score: int = 0
var coins: int = 0
var lives: int = MAX_LIVES
var current_stage: int = 1
var _allow_start_sequence_music: bool = true
var _intro_music_player: AudioStreamPlayer = null
var _start_music_player: AudioStreamPlayer = null

# StartBackground 序列帧的共享缓存：cg_intro 加载完后存到这里，main_menu
# 直接复用，避免切场景时再次同步 load 造成的 1 秒卡顿。
var shared_start_bg_frames: Array = []

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

func reset_game() -> void:
	score = 0
	coins = 0
	lives = MAX_LIVES
	current_stage = 1
	score_changed.emit(score)
	coins_changed.emit(coins)
	lives_changed.emit(lives)
	stage_changed.emit(current_stage)

func add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)

func add_coin(amount: int = 1) -> void:
	coins += amount
	coins_changed.emit(coins)

func lose_life() -> void:
	lives -= 1
	lives_changed.emit(lives)
	if lives <= 0:
		goto_game_over()

func gain_life() -> void:
	if lives < MAX_LIVES:
		lives += 1
		lives_changed.emit(lives)

func advance_stage() -> bool:
	current_stage += 1
	stage_changed.emit(current_stage)
	return current_stage <= MAX_STAGE

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		var current_scene_path: String = ""
		if get_tree().current_scene != null:
			current_scene_path = get_tree().current_scene.scene_file_path
		if current_scene_path != "res://scenes/main.tscn":
			goto_main_menu()

func goto_stage(n: int) -> void:
	if n < 1 or n > MAX_STAGE:
		return
	if n == 1:
		score = 0
		coins = 0
		lives = MAX_LIVES
		score_changed.emit(score)
		coins_changed.emit(coins)
		lives_changed.emit(lives)
	current_stage = n
	get_tree().change_scene_to_file("res://scenes/level_%d.tscn" % n)

func goto_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func goto_game_over() -> void:
	get_tree().change_scene_to_file("res://scenes/game_over.tscn")

func goto_victory() -> void:
	get_tree().change_scene_to_file("res://scenes/victory.tscn")
