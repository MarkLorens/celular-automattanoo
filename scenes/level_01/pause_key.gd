extends Node

## The pause key, on a node of its own because its process_mode has to differ
## from the level's.
##
## A pausable node stops receiving input the instant the tree freezes, so a level
## that paused itself would never see the key that unpauses it. Nor can the level
## simply run while paused instead: the cells are its children, and with
## PROCESS_MODE_INHERIT they would take that setting from it and swim on straight
## through the pause. One small always-on node beside them is what leaves the
## level pausable and the key still heard.
##
## All this does is report the press. Whether the run is in any state to be
## paused is the level's business, and the level is what answers.

## Emitted on every press of `action`, whether the tree is paused or not.
signal pressed

## The input action that toggles the pause.
@export var action: StringName = &"pause_game"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed(action):
		return
	pressed.emit()
	get_viewport().set_input_as_handled()
