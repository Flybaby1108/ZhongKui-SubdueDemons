extends Control

@export var is_victory: bool = false

@onready var title_label: Label = $Center/Title
@onready var score_label: Label = $Center/Score
@onready var hint_label: Label = $Center/Hint

func _ready() -> void:
	title_label.text = "STAGE CLEAR!" if is_victory else "GAME OVER"
	score_label.text = "FINAL SCORE: %06d" % GameState.score
	hint_label.text = "Press ENTER to play again"

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("vacuum"):
		get_viewport().set_input_as_handled()
		Input.action_release("vacuum")
		GameState.goto_main_menu()
