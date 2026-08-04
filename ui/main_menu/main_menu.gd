extends Control

## The screen the game boots into: the title over a dish of cells drifting about
## on black. A press anywhere hands off to the level, which comes up paused
## behind its own title card (StartScreen) -- so the player passes through the
## card before the ecosystem actually begins.

const LEVEL_PATH := "res://scenes/level_01/level_01.tscn"

# change_scene_to_file() takes effect at the end of the frame, so without this a
# second press arriving in the same frame would queue the swap twice.
var _starting: bool = false


## Anywhere on the screen and any button or key, rather than a target to hit --
## the whole menu is the button. _unhandled_input rather than _gui_input because
## nothing here takes the mouse (every node is set to let it through), so clicks
## fall past the UI to here, and keys then arrive by exactly the same route.
func _unhandled_input(event: InputEvent) -> void:
	if _starting or not _is_press(event):
		return
	_starting = true
	get_viewport().set_input_as_handled()
	# A plain scene swap: the menu is freed and the level takes over, booting
	# frozen under StartScreen. Nothing here needs to persist.
	get_tree().change_scene_to_file(LEVEL_PATH)


## Whether this is somebody pressing something. Echoes are excluded so a held
## key reads as the one press it is, and releases are ignored so the menu cannot
## fire on the way back up from a press that began somewhere else entirely.
func _is_press(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		return event.pressed
	if event is InputEventScreenTouch:
		return event.pressed
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventJoypadButton:
		return event.pressed
	return false
