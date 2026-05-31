extends Node

signal score_changed(new_score: int)
signal lives_changed(new_lives: int)
signal stage_changed(new_stage: int)

const MAX_LIVES := 3
const MAX_STAGE := 2

var score: int = 0
var lives: int = MAX_LIVES
var current_stage: int = 1

# StartBackground 序列帧的共享缓存：cg_intro 加载完后存到这里，main_menu
# 直接复用，避免切场景时再次同步 load 造成的 1 秒卡顿。
var shared_start_bg_frames: Array = []

func reset_game() -> void:
	score = 0
	lives = MAX_LIVES
	current_stage = 1
	score_changed.emit(score)
	lives_changed.emit(lives)
	stage_changed.emit(current_stage)

func add_score(amount: int) -> void:
	score += amount
	score_changed.emit(score)

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
		lives = MAX_LIVES
		score_changed.emit(score)
		lives_changed.emit(lives)
	current_stage = n
	get_tree().change_scene_to_file("res://scenes/level_%d.tscn" % n)

func goto_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func goto_game_over() -> void:
	get_tree().change_scene_to_file("res://scenes/game_over.tscn")

func goto_victory() -> void:
	get_tree().change_scene_to_file("res://scenes/victory.tscn")
