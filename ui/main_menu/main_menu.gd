extends Control

## The screen the game boots into. "click to start" hands off to the level, which
## comes up paused behind its own title card (StartScreen) -- so the player passes
## through the title card before the ecosystem actually begins.

const LEVEL_PATH := "res://scenes/level_01/level_01.tscn"

@onready var start_button: Button = $Center/VBox/StartButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_pressed)
	# Focused so the button also answers Enter/Space, not just a click.
	start_button.grab_focus()


func _on_start_pressed() -> void:
	# A plain scene swap: the menu is freed and the level takes over, booting
	# frozen under StartScreen. Nothing here needs to persist.
	get_tree().change_scene_to_file(LEVEL_PATH)
