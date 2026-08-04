extends Control

@onready var time_label: Label = $Center/VBox/TimeLabel
@onready var restart_button: Button = $Center/VBox/RestartButton


func _ready() -> void:
	# The whole tree is paused the moment the game ends, so this screen has to be
	# the one thing that keeps running -- otherwise the Restart button never sees
	# the click that would lift the pause.
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	restart_button.pressed.connect(_on_restart_pressed)
	hide()


## Fills in the run's final time and reveals the frosted screen. The game behind
## is already frozen by the time this is called (the level pauses the tree), so
## the blur samples a still frame.
func show_result(final_time: float) -> void:
	time_label.text = _format_time(final_time)
	show()
	restart_button.grab_focus()


func _on_restart_pressed() -> void:
	# Unpause before reloading: a reloaded scene inherits the tree's paused state,
	# and one that comes back already frozen never runs a single frame.
	get_tree().paused = false
	get_tree().reload_current_scene()


## mm:ss, so a long run reads as 2:05 rather than a bare 125.
func _format_time(seconds: float) -> String:
	#var whole: int = int(seconds)
	#return "%d:%02d" % [whole / 60, whole % 60]
	return "%.2f s" % seconds
