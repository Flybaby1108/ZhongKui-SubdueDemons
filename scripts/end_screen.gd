extends Control

@export var is_victory: bool = false

const END_EFFECT_PATH := "res://assets/audio/EndEffect.mp3"
const GAME_OVER_SFX_PATH := "res://assets/audio/GameOver.mp3"

@onready var title_label: Label = $Center/Title
@onready var score_label: Label = $Center/Score
@onready var hint_label: Label = $Center/Hint

var _end_effect_player: AudioStreamPlayer = null

func _ready() -> void:
	title_label.text = "STAGE CLEAR!" if is_victory else "GAME OVER"
	score_label.text = "FINAL SCORE: %06d" % GameState.score
	hint_label.text = "Press ENTER to play again"

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
	if event.is_action_pressed("vacuum"):
		get_viewport().set_input_as_handled()
		Input.action_release("vacuum")
		GameState.goto_main_menu()

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
