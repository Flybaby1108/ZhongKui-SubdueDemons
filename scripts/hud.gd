extends CanvasLayer

@onready var hearts_container: HBoxContainer = $TopBar/Hearts
@onready var stage_label: Label = $TopBar/StageLabel
@onready var time_label: Label = $TopBar/TimeLabel
@onready var score_label: Label = $TopBar/ScoreLabel

const HEART_FULL := preload("res://assets/sprites/ui_heart_full.png")
const HEART_EMPTY := preload("res://assets/sprites/ui_heart_empty.png")

func _ready() -> void:
	GameState.score_changed.connect(_on_score_changed)
	GameState.lives_changed.connect(_on_lives_changed)
	GameState.stage_changed.connect(_on_stage_changed)
	_rebuild_hearts(GameState.lives)
	_on_score_changed(GameState.score)
	_on_stage_changed(GameState.current_stage)

func _rebuild_hearts(lives: int) -> void:
	for child in hearts_container.get_children():
		child.queue_free()
	for i in range(GameState.MAX_LIVES):
		var tex_rect = TextureRect.new()
		tex_rect.texture = HEART_FULL if i < lives else HEART_EMPTY
		tex_rect.custom_minimum_size = Vector2(80, 80)
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP
		hearts_container.add_child(tex_rect)

func _on_score_changed(score: int) -> void:
	score_label.text = "SCORE %06d" % score

func _on_lives_changed(lives: int) -> void:
	_rebuild_hearts(lives)

func _on_stage_changed(stage: int) -> void:
	stage_label.text = "STAGE %d" % stage

func update_time(time_remaining: float) -> void:
	var seconds = int(time_remaining)
	time_label.text = "TIME %02d" % seconds
