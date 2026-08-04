extends Control

## The title card the game boots into. The whole tree starts paused, so the dish
## sits frozen behind the frosted card; the first press anywhere lifts the pause
## and lets the ecosystem come to life.

var _started := false


func _ready() -> void:
	# Runs while the rest of the tree is paused, so it can catch the press that
	# starts the game -- everything else is frozen and would never see it.
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED


# _input rather than _unhandled_input: the frosted panel and its labels are
# Controls that would otherwise swallow a mouse click before it ever reached the
# unhandled pass, and "press anywhere" has to mean anywhere.
func _input(event: InputEvent) -> void:
	if _started:
		return
	if not _is_start_press(event):
		return
	_start_game()
	get_viewport().set_input_as_handled()


## A deliberate press to begin -- a key, a mouse button or a touch going down.
## Releases and mouse motion are ignored, so the button-up of the very click that
## dismisses this card can't also trip whatever it lands on underneath.
func _is_start_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventMouseButton:
		return event.pressed
	if event is InputEventScreenTouch:
		return event.pressed
	return false


func _start_game() -> void:
	_started = true
	# Unpausing is starting: the dish, the spawn clocks and the run timer were all
	# frozen behind this card and simply resume from zero the moment it lifts.
	get_tree().paused = false
	hide()
